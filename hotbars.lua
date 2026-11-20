--[[
* JobBinds hotbars: the bars, and the file they're kept in
* (config/addons/jobbinds/hotbars.lua, shared by every character, as the
* profiles are).
*
*     return {
*         { name = 'Main', x = 760, y = 940, columns = 10, size = 44, key_text = 10, label_text = 11,
*           conditions = { { kind = 'tp', op = '>=', value = 1000 } },
*           slots = { { key = '1', jobs = { PLD_WAR = { label = 'Holy' }, NIN_WAR = { recasts = {} } } },
*                     { key = 'G' }, {} } },
*     }
*
* A slot points at a key, and shows only on jobs that key is bound for. Its
* label and recasts are taken from what the key runs for the current job,
* unless the slot sets them for that job/subjob under jobs: a label left out
* means that, and so do recasts left out. recasts = {} shows none.
*
* The slots are #slots; columns of them make a row. x and y are the bar's top
* left in screen pixels; size is a slot's side, and key_text and label_text the
* sizes of its key and label, before the window's scale.
--]]

local profiles = require('profiles');
local conditions = require('conditions');

local hotbars = {};

hotbars.path = profiles.dir .. '\\hotbars.lua';
hotbars.MAX_SLOTS = 40;
hotbars.MIN_SIZE, hotbars.MAX_SIZE, hotbars.DEFAULT_SIZE = 28, 80, 44;
-- The text on a bar's slots, in pixels before the scale: the key in the corner, and the label
hotbars.MIN_TEXT, hotbars.MAX_TEXT = 6, 32;
hotbars.DEFAULT_KEY_TEXT, hotbars.DEFAULT_LABEL_TEXT = 10, 11;
hotbars.GAP = 4; -- between slots, before the scale

-- The bar and slot being edited on the window's Hotbars page. Here so the bars
-- on screen and the page share it.
hotbars.edit = { bar = 1, slot = nil };
hotbars.error = nil; -- why the file couldn't be read or written, for the page to say

local bars = {};
local dirty = false;
local unreadable = nil; -- a file that couldn't be read is never written over
local retry_at = 0;

local function num(v, lo, hi, fallback)
    v = tonumber(v);
    if v == nil or v ~= v then
        return fallback;
    end
    return math.min(math.max(math.floor(v + 0.5), lo), hi);
end

local function text(v)
    return type(v) == 'string' and v or nil;
end

-- Reading ---------------------------------------------------------------------

local function clean_recasts(list)
    if type(list) ~= 'table' then
        return nil; -- auto
    end
    local out = {};
    for _, rc in ipairs(list) do
        if type(rc) == 'table' and (rc.kind == 'ja' or rc.kind == 'ma') and tonumber(rc.id) then
            out[#out + 1] = { kind = rc.kind, id = math.floor(tonumber(rc.id)), name = text(rc.name) or '' };
        end
    end
    return out;
end

-- A slot's label and recasts for each job/subjob ('PLD_WAR'), those that set something
local function clean_jobs(jobs)
    if type(jobs) ~= 'table' then
        return nil;
    end
    local out = nil;
    for job, own in pairs(jobs) do
        if type(job) == 'string' and job:match('^%u+_%u+$') and type(own) == 'table' then
            local entry = {
                label = (text(own.label) and own.label ~= '') and own.label or nil,
                recasts = clean_recasts(own.recasts),
            };
            if entry.label or entry.recasts then
                out = out or {};
                out[job] = entry;
            end
        end
    end
    return out;
end

local function clean_slot(s)
    local slot = {};
    if type(s) ~= 'table' then
        return slot;
    end
    local chord = text(s.key) and profiles.parse_chord(s.key:match('^%s*(.-)%s*$'));
    slot.key = chord and chord.id or nil;
    slot.jobs = clean_jobs(s.jobs); -- (2.1's first label and recasts, for every job, are left behind)
    return slot;
end

local function clean_bar(b, n)
    if type(b) ~= 'table' then
        return nil;
    end
    local bar = {
        name = (text(b.name) and b.name ~= '') and b.name or ('Bar ' .. n),
        x = num(b.x, -10000, 10000, 100),
        y = num(b.y, -10000, 10000, 100),
        size = num(b.size, hotbars.MIN_SIZE, hotbars.MAX_SIZE, hotbars.DEFAULT_SIZE),
        key_text = num(b.key_text, hotbars.MIN_TEXT, hotbars.MAX_TEXT, hotbars.DEFAULT_KEY_TEXT),
        label_text = num(b.label_text, hotbars.MIN_TEXT, hotbars.MAX_TEXT, hotbars.DEFAULT_LABEL_TEXT),
        conditions = {},
        slots = {},
    };
    if type(b.conditions) == 'table' then
        for _, c in ipairs(b.conditions) do
            bar.conditions[#bar.conditions + 1] = conditions.clean(c);
        end
    end
    local count = type(b.slots) == 'table' and math.min(hotbars.MAX_SLOTS, table.maxn(b.slots)) or 0;
    for i = 1, math.max(1, count) do
        bar.slots[i] = clean_slot(type(b.slots) == 'table' and b.slots[i] or nil);
    end
    bar.columns = num(b.columns, 1, #bar.slots, #bar.slots);
    return bar;
end

-- Read the file. False and why when it couldn't be: the bars are then empty,
-- and the file is left alone until it reads.
function hotbars.load()
    bars, dirty, unreadable, hotbars.error = {}, false, nil, nil;
    local file = io.open(hotbars.path, 'r');
    if not file then
        return true; -- none yet
    end
    local source = file:read('*a');
    file:close();

    local chunk, err = loadstring(source, '=hotbars.lua');
    local ok, data = false, err;
    if chunk then
        setfenv(chunk, {}); -- only a table: it can reach nothing
        ok, data = pcall(chunk);
    end
    if not ok or type(data) ~= 'table' then
        unreadable = ('hotbars.lua could not be read (%s). Fix or remove it, then /jb reload.'):format(
            ok and 'it does not return a table' or tostring(data));
        hotbars.error = unreadable;
        return false, unreadable;
    end
    for _, b in ipairs(data) do
        bars[#bars + 1] = clean_bar(b, #bars + 1);
    end
    return true;
end

hotbars.reload = hotbars.load;

-- Writing ---------------------------------------------------------------------

-- Keys in this order, the rest sorted after them
local ORDER = { name = 1, x = 2, y = 3, columns = 4, size = 5, key_text = 6, label_text = 7, key = 8, label = 9,
    kind = 10, op = 11, value = 12, is = 13, id = 14, conditions = 20, slots = 21, recasts = 22, jobs = 23 };

local function scalar(v)
    if type(v) == 'string' then
        return ('%q'):format(v);
    end
    return tostring(v);
end

-- A table as Lua: tables of plain values on one line, the rest one entry a line
local function serialize(t, indent)
    local keys, nested = {}, false;
    for k, v in pairs(t) do
        if type(k) ~= 'number' then
            keys[#keys + 1] = k;
        end
        nested = nested or type(v) == 'table';
    end
    table.sort(keys, function (a, b)
        local oa, ob = ORDER[a] or 99, ORDER[b] or 99;
        if oa ~= ob then
            return oa < ob;
        end
        return tostring(a) < tostring(b);
    end);

    local parts = {};
    local function value(v)
        return type(v) == 'table' and serialize(v, indent .. '    ') or scalar(v);
    end
    for _, k in ipairs(keys) do
        local name = tostring(k):match('^[%a_][%w_]*$') and k or ('[' .. scalar(k) .. ']');
        parts[#parts + 1] = name .. ' = ' .. value(t[k]);
    end
    for i = 1, #t do
        parts[#parts + 1] = value(t[i]);
    end
    if #parts == 0 then
        return '{}';
    end
    if not nested then
        return '{ ' .. table.concat(parts, ', ') .. ' }';
    end
    local inner = indent .. '    ';
    return '{\n' .. inner .. table.concat(parts, ',\n' .. inner) .. ',\n' .. indent .. '}';
end

function hotbars.save()
    if unreadable then
        return false, unreadable;
    end
    ashita.fs.create_dir(profiles.dir);
    local file, err = io.open(hotbars.path, 'w');
    if not file then
        return false, err;
    end
    file:write('-- JobBinds hotbars, edited in the window (/jb bars). After editing by hand: /jb reload\n');
    file:write('return ', serialize(bars, ''), '\n');
    file:close();
    dirty = false;
    return true;
end

function hotbars.mark_dirty()
    dirty = true;
end

function hotbars.is_dirty()
    return dirty;
end

-- Save a change once nothing is being dragged or typed, so a drag is written
-- once, at its end. A failed save is tried again every few seconds.
function hotbars.save_if_idle()
    if not dirty or os.clock() < retry_at then
        return;
    end
    local imgui = require('imgui');
    if imgui.IsMouseDown(0) or imgui.IsAnyItemActive() then
        return;
    end
    local ok, err = hotbars.save();
    hotbars.error = (not ok) and (unreadable or ('Could not save hotbars.lua: ' .. tostring(err))) or nil;
    if not ok then
        retry_at = os.clock() + 5;
    end
end

-- The bars --------------------------------------------------------------------

function hotbars.list()
    return bars;
end

-- Jobs ------------------------------------------------------------------------

-- 'PLD', 'WAR' -> 'PLD_WAR'; no subjob is NON. nil without a main job.
function hotbars.job_key(main, sub)
    return main and (main .. '_' .. (sub or 'NON')) or nil;
end

-- 'PLD_WAR' -> 'PLD/WAR'
function hotbars.job_label(job)
    return job and (job:gsub('_', '/')) or '';
end

-- A slot's own label and recasts on a job/subjob: { label, recasts }, or nil.
-- With create, made when it isn't there yet.
function hotbars.for_job(slot, job, create)
    if not job then
        return nil;
    end
    local own = slot.jobs and slot.jobs[job];
    if not own and create then
        slot.jobs = slot.jobs or {};
        own = {};
        slot.jobs[job] = own;
    end
    return own;
end

-- Forget a job's settings once they set nothing
function hotbars.prune(slot, job)
    local own = slot.jobs and slot.jobs[job];
    if own and own.label == nil and own.recasts == nil then
        slot.jobs[job] = nil;
    end
    if slot.jobs and next(slot.jobs) == nil then
        slot.jobs = nil;
    end
end

-- A bar's shape in screen pixels: a slot's side, the gap, columns, rows, width, height
function hotbars.metrics(bar, S)
    local slot, gap = S(bar.size), S(hotbars.GAP);
    local columns = math.max(1, math.min(bar.columns, #bar.slots));
    local rows = math.ceil(#bar.slots / columns);
    return slot, gap, columns, rows, columns * slot + (columns - 1) * gap, rows * slot + (rows - 1) * gap;
end

-- The keys a new bar starts on: 1 to 0, then Shift+1 to Shift+0 (the number
-- keys take no Ctrl or Alt), then none.
local function fresh_keys()
    local used = {};
    for _, bar in ipairs(bars) do
        for _, slot in ipairs(bar.slots) do
            if slot.key then
                used[slot.key] = true;
            end
        end
    end
    for _, prefix in ipairs({ '', '+' }) do
        if not used[prefix .. '1'] then
            return prefix;
        end
    end
    return nil;
end

-- A new bar of ten slots in a row, centred near the bottom of the screen and
-- above the bars already there. Returns its index.
function hotbars.new_bar(screen_w, screen_h, S)
    local names = {};
    for _, bar in ipairs(bars) do
        names[bar.name] = true;
    end
    local n = #bars + 1;
    while names['Bar ' .. n] do
        n = n + 1;
    end

    local bar = { name = 'Bar ' .. n, size = hotbars.DEFAULT_SIZE, columns = 10,
        key_text = hotbars.DEFAULT_KEY_TEXT, label_text = hotbars.DEFAULT_LABEL_TEXT, conditions = {}, slots = {} };
    local prefix = fresh_keys();
    for i = 1, 10 do
        bar.slots[i] = prefix and { key = prefix .. (i % 10) } or {};
    end
    local _, _, _, _, w, h = hotbars.metrics(bar, S);
    bar.x = math.floor((screen_w - w) / 2 + 0.5);
    bar.y = math.max(0, math.floor(screen_h * 0.82 - h - #bars * (h + S(40)) + 0.5));

    bars[#bars + 1] = bar;
    dirty = true;
    return #bars;
end

function hotbars.remove(i)
    if not bars[i] then
        return;
    end
    table.remove(bars, i);
    hotbars.edit.bar = math.max(1, math.min(hotbars.edit.bar, #bars));
    hotbars.edit.slot = nil;
    dirty = true;
end

-- Give a bar n slots. A bar in one row stays in one row.
function hotbars.set_count(bar, n)
    n = math.max(1, math.min(hotbars.MAX_SLOTS, n));
    local one_row = bar.columns >= #bar.slots;
    for i = #bar.slots + 1, n do
        bar.slots[i] = {};
    end
    for i = #bar.slots, n + 1, -1 do
        bar.slots[i] = nil;
    end
    bar.columns = one_row and n or math.min(bar.columns, n);
    if hotbars.edit.slot and hotbars.edit.slot > n then
        hotbars.edit.slot = n;
    end
    dirty = true;
end

return hotbars;
