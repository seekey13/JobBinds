--[[
* JobBinds recasts: how long an ability or spell has left before it can be used
* again, finding them by name, and what a binding's commands use.
*
* A recast is { kind = 'ja', id = <the ability's recast timer id>, name = 'Provoke' }
* or { kind = 'ma', id = <the spell id>, name = 'Flash' }. Pet commands count as
* 'ja': they have ability timers too.
--]]

local recasts = {};

-- Ability types that have no recast of their own: weapon skill, trait, monstrosity
local NO_RECAST = { [3] = true, [4] = true, [20] = true };

-- Commands, by their name in a binding: 'ja' and 'ma' use a recast; 'label'
-- names something worth showing on a slot but has no recast to show.
local ACTIONS = {
    ja = 'ja', jobability = 'ja', pet = 'ja',
    ma = 'ma', magic = 'ma', nin = 'ma', ninjutsu = 'ma', song = 'ma', sing = 'ma',
    ws = 'label', weaponskill = 'label', item = 'label', up = 'label',
};

local function trim(text)
    return (text:match('^%s*(.-)%s*$'));
end

-- The names ------------------------------------------------------------------

local index = nil; -- { list = { entry, ... } sorted by name, ja = { [lower name] = entry }, ma = { ... } }

local function add(kind, id, name)
    if type(name) ~= 'string' or name == '' or name == '.' or type(id) ~= 'number' then
        return;
    end
    local lower = name:lower();
    if index[kind][lower] then
        return; -- the first of a name stands for it
    end
    local entry = { kind = kind, id = id, name = name, lower = lower };
    index[kind][lower] = entry;
    index.list[#index.list + 1] = entry;
end

-- Every ability and spell, read from the client the first time one is asked for
local function build()
    if index then
        return index;
    end
    index = { list = {}, ja = {}, ma = {} };
    pcall(function ()
        local rm = AshitaCore:GetResourceManager();
        for id = 1, 2047 do
            local a = rm:GetAbilityById(id);
            if a and not NO_RECAST[a.Type] then
                add('ja', a.RecastTimerId, a.Name and a.Name[1]);
            end
        end
        for id = 1, 1023 do
            local s = rm:GetSpellById(id);
            if s then
                add('ma', id, s.Name and s.Name[1]);
            end
        end
    end);
    table.sort(index.list, function (a, b)
        if a.lower ~= b.lower then
            return a.lower < b.lower;
        end
        return a.kind < b.kind;
    end);
    return index;
end

-- The recast for an ability ('ja') or spell ('ma') of this name, or nil
function recasts.find(kind, name)
    local entry = build()[kind][trim(name):lower()];
    return entry and { kind = entry.kind, id = entry.id, name = entry.name } or nil;
end

-- Up to n recasts whose names hold text: those starting with it first.
function recasts.search(text, n)
    text = trim(text or ''):lower();
    if text == '' then
        return {};
    end
    local starts, within = {}, {};
    for _, entry in ipairs(build().list) do
        local at = entry.lower:find(text, 1, true);
        if at == 1 then
            starts[#starts + 1] = entry;
        elseif at then
            within[#within + 1] = entry;
        end
    end
    local out = {};
    for _, list in ipairs({ starts, within }) do
        for _, entry in ipairs(list) do
            if #out >= (n or 5) then
                return out;
            end
            out[#out + 1] = { kind = entry.kind, id = entry.id, name = entry.name };
        end
    end
    return out;
end

-- A binding's commands -------------------------------------------------------

-- '/ma Flash <t>' -> 'ma', 'Flash'; '/ja "Shield Bash" <t>' -> 'ja', 'Shield Bash';
-- '/ws "Savage Blade" <t>' -> 'label', 'Savage Blade'. nil for anything else,
-- including a command sent to another character ('/mst Butt /ws ...').
function recasts.parse(line)
    local command, rest = tostring(line):match('^%s*/(%a+)%s+(.-)%s*$');
    local kind = command and ACTIONS[command:lower()];
    if not kind then
        return nil;
    end
    local name = rest:match('^"([^"]+)"') or rest:match("^'([^']+)'") or rest:match('^([^<]-)%s*<') or rest;
    name = trim(name);
    if name == '' then
        return nil;
    end
    return kind, name;
end

-- What a binding's commands use, and a label for them: the recasts of every
-- ability and spell they use, and the first thing they name (or else the
-- first command that isn't a wait).
function recasts.from_lines(lines)
    local list, seen, label, first = {}, {}, nil, nil;
    for _, line in ipairs(lines or {}) do
        if not first and not line:lower():match('^%s*/wait') then
            first = line;
        end
        local kind, name = recasts.parse(line);
        if kind then
            label = label or name;
            if kind ~= 'label' then
                local rc = recasts.find(kind, name);
                if rc and not seen[rc.kind .. rc.id] then
                    seen[rc.kind .. rc.id] = true;
                    list[#list + 1] = rc;
                end
            end
        end
    end
    return list, label or first or '';
end

-- The timers -----------------------------------------------------------------

local ability_left = {}; -- recast timer id -> seconds, this frame
local spell_left = {};   -- spell id -> seconds, read this frame
local recast_mm = nil;   -- the client's recast timers, this frame
local longest = {};      -- 'ja12' -> the most seconds seen since that recast started

-- Once a frame: the ability timers, all at once. Spells are read as asked for.
-- Every running ability's longest is kept here, so a bar that shows part way
-- through a recast (one shown while Ctrl is held) still fades from the start.
function recasts.frame()
    ability_left, spell_left, recast_mm = {}, {}, nil;
    local ok, r = pcall(function () return AshitaCore:GetMemoryManager():GetRecast(); end);
    if not ok or not r then
        return;
    end
    recast_mm = r;
    pcall(function ()
        for i = 0, 31 do
            local id, timer = r:GetAbilityTimerId(i), r:GetAbilityTimer(i);
            -- slot 0 is the one-hour ability, whose id is 0; elsewhere 0 is an empty slot
            if (id ~= 0 or i == 0) and timer > 0 then
                ability_left[id] = math.max(ability_left[id] or 0, timer / 60);
            end
        end
    end);
    for key in pairs(longest) do
        local id = tonumber(key:match('^ja(%d+)$'));
        if id and not ability_left[id] then
            longest[key] = nil;
        end
    end
    for id, left in pairs(ability_left) do
        longest['ja' .. id] = math.max(longest['ja' .. id] or 0, left);
    end
end

-- Seconds left on a recast, 0 when it's ready
function recasts.left(rc)
    if rc.kind == 'ja' then
        return ability_left[rc.id] or 0;
    end
    local left = spell_left[rc.id];
    if left == nil then
        left = 0;
        if recast_mm then
            local ok, timer = pcall(recast_mm.GetSpellTimer, recast_mm, rc.id);
            if ok and tonumber(timer) then
                left = timer / 60;
            end
        end
        spell_left[rc.id] = left;
    end
    return left;
end

-- Seconds left, and the share of the recast still to go (1 when it has just
-- been used). The whole recast is the most seen since it started, so no table
-- of recast lengths is needed.
function recasts.state(rc)
    local key = rc.kind .. rc.id;
    local left = recasts.left(rc);
    if left <= 0 then
        longest[key] = nil;
        return 0, 0;
    end
    local whole = longest[key];
    if not whole or left > whole then
        whole = left;
        longest[key] = whole;
    end
    return left, left / whole;
end

-- 42 -> '42', 75 -> '1:15', 3600 -> '60:00'
function recasts.format(seconds)
    local s = math.ceil(seconds);
    if s < 60 then
        return tostring(s);
    end
    return ('%d:%02d'):format(math.floor(s / 60), s % 60);
end

return recasts;
