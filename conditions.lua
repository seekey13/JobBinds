--[[
* JobBinds hotbar conditions: when a bar shows. A bar shows while every one of
* its conditions holds, and always with none.
*
*     { kind = 'tp',   op = '>=', value = 1000 }   TP at least 1000 ('<': below)
*     { kind = 'hpp',  op = '<',  value = 50 }     HP% below 50
*     { kind = 'mpp',  op = '>=', value = 30 }     MP% at least 30
*     { kind = 'ctrl', is = true }                 Ctrl held (also 'alt', 'shift')
*     { kind = 'engaged', is = false }             not engaged
*     { kind = 'buff', name = 'Haste', is = false } Haste missing
*
* KINDS is read by the editor too, so a kind is described in one place.
--]]

local conditions = {};

conditions.KINDS = {
    { kind = 'tp',      label = 'TP',      type = 'number', lo = 0, hi = 3000, default = 1000 },
    { kind = 'hpp',     label = 'HP%',     type = 'number', lo = 0, hi = 100,  default = 50 },
    { kind = 'mpp',     label = 'MP%',     type = 'number', lo = 0, hi = 100,  default = 50 },
    { kind = 'ctrl',    label = 'Ctrl',    type = 'flag',   states = { 'Held', 'Not held' } },
    { kind = 'alt',     label = 'Alt',     type = 'flag',   states = { 'Held', 'Not held' } },
    { kind = 'shift',   label = 'Shift',   type = 'flag',   states = { 'Held', 'Not held' } },
    { kind = 'engaged', label = 'Engaged', type = 'flag',   states = { 'Engaged', 'Not engaged' } },
    { kind = 'buff',    label = 'Buff',    type = 'buff',   states = { 'Up', 'Missing' } },
};
conditions.OPS = { 'At least', 'Below' }; -- a number kind's two ways, '>=' and '<'

conditions.by_kind = {};
for _, k in ipairs(conditions.KINDS) do
    conditions.by_kind[k.kind] = k;
end

local function trim(text)
    return (tostring(text):match('^%s*(.-)%s*$'));
end

-- A new condition of a kind, as the editor adds it
function conditions.new(kind)
    local k = conditions.by_kind[kind];
    if not k then
        return nil;
    end
    if k.type == 'number' then
        return { kind = kind, op = '>=', value = k.default };
    elseif k.type == 'buff' then
        return { kind = kind, name = '', is = true };
    end
    return { kind = kind, is = true };
end

-- A condition read from the file, made whole; nil when it can't be.
function conditions.clean(c)
    if type(c) ~= 'table' then
        return nil;
    end
    local k = conditions.by_kind[c.kind];
    if not k then
        return nil;
    end
    if k.type == 'number' then
        local v = tonumber(c.value) or k.default;
        v = math.min(math.max(math.floor(v + 0.5), k.lo), k.hi);
        return { kind = c.kind, op = c.op == '<' and '<' or '>=', value = v };
    elseif k.type == 'buff' then
        return { kind = c.kind, name = type(c.name) == 'string' and trim(c.name) or '', is = c.is ~= false };
    end
    return { kind = c.kind, is = c.is ~= false };
end

-- Status names ----------------------------------------------------------------

local status_index = nil; -- lower-case name -> { id, ... }

-- Every status id with this name (several share one), or nil.
function conditions.status_ids(name)
    if not status_index then
        status_index = {};
        pcall(function ()
            local rm = AshitaCore:GetResourceManager();
            for id = 0, 1023 do
                local en = rm:GetString('buffs.names', id, 2); -- 2: English
                if type(en) == 'string' and en ~= '' then
                    local key = en:lower();
                    status_index[key] = status_index[key] or {};
                    table.insert(status_index[key], id);
                end
            end
        end);
    end
    return name and status_index[trim(name):lower()] or nil;
end

-- The game, read once a frame -------------------------------------------------

local VK = { ctrl = 0x11, alt = 0x12, shift = 0x10 };

local key_state = nil;
do
    local ok, ffi = pcall(require, 'ffi');
    if ok then
        pcall(ffi.cdef, 'short __stdcall GetKeyState(int nVirtKey);');
        key_state = function (vk) return ffi.C.GetKeyState(vk) < 0; end;
    end
end

local function key_down(name)
    if key_state then
        local ok, down = pcall(key_state, VK[name]);
        if ok then
            return down;
        end
    end
    -- ImGui's idea of it, when Win32 can't be asked
    local ok, down = pcall(function ()
        local io = require('imgui').GetIO();
        local v = io[name == 'ctrl' and 'KeyCtrl' or name == 'alt' and 'KeyAlt' or 'KeyShift'];
        return v == true or v == 1;
    end);
    return ok and down or false;
end

local function party()
    return AshitaCore:GetMemoryManager():GetParty();
end

-- How each value a condition asks about is read. A value that can't be read is nil.
local readers = {
    tp = function () return party():GetMemberTP(0); end,
    hpp = function () return party():GetMemberHPPercent(0); end,
    mpp = function () return party():GetMemberMPPercent(0); end,
    ctrl = function () return key_down('ctrl'); end,
    alt = function () return key_down('alt'); end,
    shift = function () return key_down('shift'); end,
    engaged = function ()
        local mm = AshitaCore:GetMemoryManager();
        return mm:GetEntity():GetStatus(mm:GetParty():GetMemberTargetIndex(0)) == 1;
    end,
    buffs = function ()
        local set = {};
        for _, id in pairs(AshitaCore:GetMemoryManager():GetPlayer():GetBuffs()) do
            if id and id >= 0 and id ~= 255 then
                set[id] = true;
            end
        end
        return set;
    end,
};

-- This frame's game. Each value is read the first time a condition asks for
-- it, so only what some bar uses is read.
function conditions.snapshot()
    return setmetatable({}, { __index = function (snap, name)
        local reader = readers[name];
        if not reader then
            return nil;
        end
        local ok, v = pcall(reader);
        v = ok and v or false;
        rawset(snap, name, v);
        return v;
    end });
end

-- Testing ---------------------------------------------------------------------

function conditions.test(c, snap)
    local k = conditions.by_kind[c.kind];
    if not k then
        return true;
    end
    if k.type == 'number' then
        local v = tonumber(snap[c.kind]);
        if v == nil then
            return false;
        end
        if c.op == '<' then
            return v < c.value;
        end
        return v >= c.value;
    elseif k.type == 'flag' then
        return (snap[c.kind] == true) == (c.is ~= false);
    end
    -- buff: up when any status of that name is on; an unknown name is never up
    local up = false;
    local ids = conditions.status_ids(c.name);
    local buffs = snap.buffs or {};
    for _, id in ipairs(ids or {}) do
        if buffs[id] then
            up = true;
            break;
        end
    end
    return up == (c.is ~= false);
end

-- True when every condition holds (and with none).
function conditions.met(list, snap)
    for _, c in ipairs(list or {}) do
        if not conditions.test(c, snap) then
            return false;
        end
    end
    return true;
end

-- 'TP at least 1000', 'Ctrl held', 'Haste missing'
function conditions.describe(c)
    local k = conditions.by_kind[c.kind];
    if not k then
        return '?';
    end
    if k.type == 'number' then
        return ('%s %s %d'):format(k.label, c.op == '<' and 'below' or 'at least', c.value);
    elseif k.type == 'buff' then
        return ('%s %s'):format(c.name ~= '' and c.name or 'Buff', c.is ~= false and 'up' or 'missing');
    elseif c.kind == 'engaged' then
        return c.is ~= false and 'Engaged' or 'Not engaged';
    end
    return ('%s %s'):format(k.label, c.is ~= false and 'held' or 'not held');
end

return conditions;
