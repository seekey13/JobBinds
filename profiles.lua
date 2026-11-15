--[[
* JobBinds profiles: where bindings live on disk and how they stack.
*
* A profile is one text file in config/addons/jobbinds/. A key on its own line,
* then the commands it runs indented beneath it:
*
*     ^1
*         /ma "Cure" <me>
*     +Q
*         /ja "Sneak Attack" <me>
*         /wait 1
*         /ws "Viper Bite" <t>
*
* Key prefixes: ^ Ctrl, ! Alt, + Shift. Lines starting with # are comments.
*
* Four profiles apply to a job combination, later ones winning a shared key:
*     SUB_NIN.txt    any main job with /NIN
*     BLM.txt        BLM with any subjob
*     BLM_NIN.txt    exactly BLM/NIN
*     ALL.txt        global: every job, overriding the job profiles
--]]

require('common');
local blocked_keybinds = require('blocked_keybinds');

local profiles = {};

local install = (AshitaCore:GetInstallPath():gsub('[\\/]+$', ''));
profiles.dir = install .. '\\config\\addons\\jobbinds';
profiles.scripts_dir = install .. '\\scripts';

local cache = {}; -- profile id -> { [chord id] = { command, ... } }

-- Other names for the keys the keyboard shows as DEL and INS
local KEY_ALIASES = { DELETE = 'DEL', INSERT = 'INS' };

local function trim(text)
    return (text:match('^%s*(.-)%s*$'));
end

function profiles.path(id)
    return profiles.dir .. '\\' .. id .. '.txt';
end

-- '+^q' -> { id = '^+Q', key = 'Q', ctrl = true, alt = false, shift = true }
function profiles.parse_chord(text)
    local prefix, key = text:match('^([%^!+]*)(.+)$');
    if not key then
        return nil;
    end
    key = key:upper();
    local chord = {
        key   = KEY_ALIASES[key] or key,
        ctrl  = prefix:find('^', 1, true) ~= nil,
        alt   = prefix:find('!', 1, true) ~= nil,
        shift = prefix:find('+', 1, true) ~= nil,
    };
    chord.id = (chord.ctrl and '^' or '') .. (chord.alt and '!' or '') .. (chord.shift and '+' or '') .. chord.key;
    return chord;
end

function profiles.is_blocked(chord)
    local mods = {};
    if chord.ctrl then mods[#mods + 1] = 'Ctrl'; end
    if chord.alt then mods[#mods + 1] = 'Alt'; end
    if chord.shift then mods[#mods + 1] = 'Shift'; end
    return (blocked_keybinds.is_combination_blocked(chord.key, table.concat(mods, '+'))) == true;
end

-- The profile's bindings, read from disk the first time it's asked for.
function profiles.layer(id)
    if cache[id] then
        return cache[id];
    end
    local layer = {};
    local file = io.open(profiles.path(id), 'r');
    if file then
        local lines = nil;
        for line in file:lines() do
            line = line:gsub('\r$', '');
            if line:match('^%s') then
                local command = trim(line);
                if lines and command ~= '' then
                    lines[#lines + 1] = command;
                end
            elseif line ~= '' and line:sub(1, 1) ~= '#' then
                local chord = profiles.parse_chord(trim(line));
                lines = nil;
                if chord then
                    lines = {};
                    layer[chord.id] = lines;
                end
            end
        end
        file:close();
        for chord_id, commands in pairs(layer) do
            if #commands == 0 then
                layer[chord_id] = nil;
            end
        end
    end
    cache[id] = layer;
    return layer;
end

-- Set (or with no commands, remove) one key's binding. Not written until save().
function profiles.set(id, chord_id, commands)
    profiles.layer(id)[chord_id] = (commands and #commands > 0) and commands or nil;
end

function profiles.save(id)
    local layer = profiles.layer(id);
    local ids = {};
    for chord_id in pairs(layer) do
        ids[#ids + 1] = chord_id;
    end
    table.sort(ids);

    local path = profiles.path(id);
    if #ids == 0 then
        os.remove(path);
        return true;
    end

    ashita.fs.create_dir(profiles.dir);
    local file, err = io.open(path, 'w');
    if not file then
        return false, err;
    end
    file:write('# JobBinds profile: ', id, '\n');
    file:write('# A key (^ Ctrl, ! Alt, + Shift), then the commands it runs indented beneath it.\n\n');
    for _, chord_id in ipairs(ids) do
        file:write(chord_id, '\n');
        for _, command in ipairs(layer[chord_id]) do
            file:write('    ', command, '\n');
        end
    end
    file:close();
    return true;
end

-- Forget what was read, so hand edits to the files are picked up.
function profiles.reload()
    cache = {};
end

-- The profiles that apply to a job combination, lowest priority first.
-- main and sub are job abbreviations, or nil.
function profiles.scopes(main, sub)
    local scopes = {};
    if sub then
        scopes[#scopes + 1] = { id = 'SUB_' .. sub, label = 'Any/' .. sub };
    end
    if main then
        scopes[#scopes + 1] = { id = main, label = main .. '/Any' };
    end
    if main and sub then
        scopes[#scopes + 1] = { id = main .. '_' .. sub, label = main .. '/' .. sub };
    end
    scopes[#scopes + 1] = { id = 'ALL', label = 'Global' };
    return scopes;
end

-- The bindings in force for those scopes: one per key, from the highest
-- priority profile that binds it. Protected keys are left out.
function profiles.effective(scopes)
    local by_id = {};
    for _, scope in ipairs(scopes) do
        for chord_id, commands in pairs(profiles.layer(scope.id)) do
            local chord = profiles.parse_chord(chord_id);
            if chord and not profiles.is_blocked(chord) then
                chord.lines = commands;
                chord.scope = scope;
                by_id[chord.id] = chord;
            end
        end
    end
    local list = {};
    for _, chord in pairs(by_id) do
        list[#list + 1] = chord;
    end
    table.sort(list, function (a, b) return a.id < b.id; end);
    return list;
end

return profiles;
