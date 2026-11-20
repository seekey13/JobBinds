--[[
* Offline tests for the hotbars: no game needed. From the addon's folder:
*
*     luajit tests/hotbar_test.lua
*
* The game and ImGui are stubbed. The pure parts (recasts, conditions, the
* hotbar file) are tested directly; the window's Hotbars page and the bars on
* screen are driven through a fake ImGui that clicks, types and drags, to catch
* errors in code that otherwise only runs in game.
--]]

package.path = './?.lua;' .. package.path;
package.preload['common'] = function () return true; end

local TMP = (os.getenv('TEMP') or os.getenv('TMP') or '.') .. '\\jobbinds_hotbar_test';
os.execute('mkdir "' .. TMP .. '" 2>nul');

-- The game ------------------------------------------------------------------------

local ABILITIES = {
    [1]   = { Name = { 'Combo' }, Type = 3, RecastTimerId = 0 },   -- a weapon skill: no recast
    [547] = { Name = { 'Provoke' }, Type = 1, RecastTimerId = 5 },
    [558] = { Name = { 'Shield Bash' }, Type = 1, RecastTimerId = 73 },
    [600] = { Name = { 'Sentinel' }, Type = 1, RecastTimerId = 75 },
};
local SPELLS = { [21] = { Name = { 'Holy' } }, [112] = { Name = { 'Flash' } }, [320] = { Name = { 'Raiton: Ichi' } } };
local BUFFS = { [33] = 'Haste', [580] = 'Haste', [65] = 'Sneak Attack' };

local game = {
    tp = 1200, hpp = 80, mpp = 50, status = 1, buffs = { 33, 255, 255 },
    abilities = {},  -- slot -> { id, timer (1/60 s) }
    spells = {},     -- spell id -> timer (1/60 s)
    sent = {},       -- commands queued
};

AshitaCore = {
    GetInstallPath = function () return TMP; end,
    GetResourceManager = function ()
        return {
            GetAbilityById = function (_, id) return ABILITIES[id]; end,
            GetSpellById = function (_, id) return SPELLS[id]; end,
            GetString = function (_, _, id) return BUFFS[id]; end,
        };
    end,
    GetChatManager = function ()
        return { QueueCommand = function (_, _, command) game.sent[#game.sent + 1] = command; end };
    end,
    GetMemoryManager = function ()
        return {
            GetPlayer = function ()
                return {
                    GetLoginStatus = function () return 2; end,
                    GetIsZoning = function () return 0; end,
                    GetMainJob = function () return 7; end,
                    GetBuffs = function () return game.buffs; end,
                };
            end,
            GetParty = function ()
                return {
                    GetMemberTP = function () return game.tp; end,
                    GetMemberHPPercent = function () return game.hpp; end,
                    GetMemberMPPercent = function () return game.mpp; end,
                    GetMemberTargetIndex = function () return 1; end,
                };
            end,
            GetEntity = function () return { GetStatus = function () return game.status; end }; end,
            GetRecast = function ()
                return {
                    GetAbilityTimerId = function (_, i) return game.abilities[i] and game.abilities[i].id or 0; end,
                    GetAbilityTimer = function (_, i) return game.abilities[i] and game.abilities[i].timer or 0; end,
                    GetSpellTimer = function (_, id) return game.spells[id] or 0; end,
                };
            end,
        };
    end,
};
ashita = { fs = { create_dir = function () end, exists = function () return true; end } };

-- ImGui: anything not here does nothing. The script below says which control
-- is clicked, pressed (held), dragged or typed into on the next frame.
local input = {};
local last_id = nil;
local dl = setmetatable({}, { __index = function () return function () end; end });
setmetatable(_G, { __index = function (_, name)
    if type(name) == 'string' and name:match('^ImGui') then
        return 0;
    end
end });
package.preload['imgui'] = function ()
    return setmetatable({
        GetWindowDrawList = function () return dl; end,
        CalcTextSize = function (s) return #s * 7, 14; end,
        GetFontSize = function () return 14; end,
        GetFont = function () return 'font'; end,
        GetIO = function () return { DisplaySize = { x = 1920, y = 1080 } }; end,
        GetCursorScreenPos = function () return 100, 100; end,
        Begin = function () return true; end,
        BeginTooltip = function () return true; end,
        InvisibleButton = function (id) last_id = id; return input.click == id; end,
        IsItemHovered = function () return input.hover == last_id; end,
        IsItemActive = function () return input.hold == last_id or input.drag == last_id; end,
        IsItemActivated = function () return input.drag == last_id; end,
        GetMouseDragDelta = function () return input.delta and input.delta[1] or 0, input.delta and input.delta[2] or 0; end,
        IsMouseDown = function () return input.hold ~= nil or input.drag ~= nil; end,
        IsAnyItemActive = function () return input.hold ~= nil or input.drag ~= nil; end,
        InputText = function (id, buf)
            last_id = id;
            if input.type and input.type[1] == id then
                buf[1] = input.type[2];
                return true;
            end
            return false;
        end,
    }, { __index = function () return function () end; end });
end

-- The tests -----------------------------------------------------------------------

local passed, failed = 0, 0;
local function check(name, ok, detail)
    if ok then
        passed = passed + 1;
    else
        failed = failed + 1;
        print('FAIL ' .. name .. (detail and (': ' .. detail) or ''));
    end
end
local function eq(name, got, want)
    check(name, got == want, ('got %s, want %s'):format(tostring(got), tostring(want)));
end

local recasts = require('recasts');
local conditions = require('conditions');
local profiles = require('profiles');
local hotbars = require('hotbars');
hotbars.path = TMP .. '\\hotbars.lua';

-- recasts.parse and from_lines, on lines like those in the profiles
do
    local kind, name = recasts.parse('/ma Flash <t>');
    eq('parse unquoted spell kind', kind, 'ma');
    eq('parse unquoted spell name', name, 'Flash');
    kind, name = recasts.parse('/ja "Shield Bash" <t>');
    eq('parse quoted ability', name, 'Shield Bash');
    eq('parse quoted ability kind', kind, 'ja');
    eq('parse another character\'s command', recasts.parse('/mst Butt /ws "Raging Fists" <t>'), nil);
    kind, name = recasts.parse('/up Raiton <t>');
    eq('parse upcast is a label', kind, 'label');
    eq('parse upcast name', name, 'Raiton');
    _, name = recasts.parse('/ma Utsusemi: Ni <me>');
    eq('parse name with a colon', name, 'Utsusemi: Ni');
    eq('parse wait', recasts.parse('/wait 1.1'), nil);

    local list, label = recasts.from_lines({ '/ma Flash <t>', '/wait 1.1', '/ja Provoke <t>' });
    eq('from_lines finds two', #list, 2);
    eq('from_lines spell first', list[1] and list[1].kind .. list[1].id, 'ma112');
    eq('from_lines ability by timer id', list[2] and list[2].kind .. list[2].id, 'ja5');
    eq('from_lines label', label, 'Flash');

    list = recasts.from_lines({ '/MA flash <t>' });
    eq('from_lines ignores case', list[1] and list[1].name, 'Flash');

    list, label = recasts.from_lines({ '/mst Butt /ws "Raging Fists" <t>' });
    eq('from_lines skips another character', #list, 0);
    eq('from_lines label falls back to the command', label, '/mst Butt /ws "Raging Fists" <t>');

    list, label = recasts.from_lines({ '/ws "Vorpal Blade" <t>' });
    eq('weapon skill has no recast', #list, 0);
    eq('weapon skill label', label, 'Vorpal Blade');

    _, label = recasts.from_lines({ '/wait 2', '/ja "Shield Bash" <t>' });
    eq('label skips waits', label, 'Shield Bash');
    _, label = recasts.from_lines({ '/up Raiton <t>' });
    eq('upcast label', label, 'Raiton');

    list = recasts.from_lines({ '/ja Provoke <t>', '/ja Provoke <t>' });
    eq('from_lines counts a recast once', #list, 1);
    eq('weapon skill not found as an ability', recasts.find('ja', 'Combo'), nil);

    local found = recasts.search('pro', 5);
    eq('search finds Provoke', found[1] and found[1].name, 'Provoke');
    found = recasts.search('S', 5);
    eq('search: starts-with first', found[1] and found[1].name, 'Sentinel');
    eq('search: then the next', found[2] and found[2].name, 'Shield Bash');
    eq('search empty', #recasts.search('  ', 5), 0);

    eq('format seconds', recasts.format(42), '42');
    eq('format minutes', recasts.format(75), '1:15');
    eq('format rounds up', recasts.format(41.2), '42');
end

-- recasts.state: the fade's share comes from the most seen
do
    game.abilities = { [0] = { id = 0, timer = 0 }, [3] = { id = 5, timer = 600 }, [4] = { id = 0, timer = 100 } };
    game.spells = { [112] = 900 };
    recasts.frame();
    local left, frac = recasts.state({ kind = 'ja', id = 5 });
    eq('ability seconds', left, 10);
    eq('ability share at start', frac, 1);
    left = recasts.state({ kind = 'ja', id = 0 });
    eq('an empty slot is not the one-hour', left, 0);
    left = recasts.state({ kind = 'ma', id = 112 });
    eq('spell seconds', left, 15);

    game.abilities[3].timer = 300;
    recasts.frame();
    left, frac = recasts.state({ kind = 'ja', id = 5 });
    eq('ability half way', frac, 0.5);

    -- a recast first asked about part way through still knows its start
    game.abilities[5] = { id = 73, timer = 1200 };
    recasts.frame();
    game.abilities[5].timer = 300;
    recasts.frame();
    left, frac = recasts.state({ kind = 'ja', id = 73 });
    eq('ability seen before it was asked about', frac, 0.25);
    game.abilities[5] = nil;
    game.abilities[3].timer = 0;
    recasts.frame();
    left, frac = recasts.state({ kind = 'ja', id = 5 });
    eq('ability ready', left, 0);
    eq('ability ready share', frac, 0);
end

-- conditions.met
do
    eq('none always shows', conditions.met({}, {}), true);
    local tp = { { kind = 'tp', op = '>=', value = 1000 } };
    eq('tp under', conditions.met(tp, { tp = 999 }), false);
    eq('tp at', conditions.met(tp, { tp = 1000 }), true);
    eq('tp below', conditions.met({ { kind = 'tp', op = '<', value = 1000 } }, { tp = 999 }), true);
    eq('tp unread', conditions.met(tp, {}), false);
    eq('ctrl held', conditions.met({ { kind = 'ctrl', is = true } }, { ctrl = true }), true);
    eq('ctrl not held, held', conditions.met({ { kind = 'ctrl', is = false } }, { ctrl = true }), false);
    eq('ctrl not held', conditions.met({ { kind = 'ctrl', is = false } }, { ctrl = false }), true);
    eq('engaged', conditions.met({ { kind = 'engaged', is = true } }, { engaged = true }), true);
    eq('not engaged', conditions.met({ { kind = 'engaged', is = false } }, { engaged = true }), false);

    local haste = { { kind = 'buff', name = 'haste', is = true } };
    eq('buff up', conditions.met(haste, { buffs = { [33] = true } }), true);
    eq('buff up by its other id', conditions.met(haste, { buffs = { [580] = true } }), true);
    eq('buff not up', conditions.met(haste, { buffs = {} }), false);
    eq('buff missing', conditions.met({ { kind = 'buff', name = 'Haste', is = false } }, { buffs = {} }), true);
    eq('unknown buff never up', conditions.met({ { kind = 'buff', name = 'Hastee', is = true } }, { buffs = { [33] = true } }), false);
    eq('unknown buff always missing', conditions.met({ { kind = 'buff', name = 'Hastee', is = false } }, { buffs = {} }), true);
    eq('all must hold', conditions.met({ tp[1], { kind = 'ctrl', is = true } }, { tp = 1500, ctrl = false }), false);

    eq('clean clamps', conditions.clean({ kind = 'tp', value = 5000 }).value, 3000);
    eq('clean drops unknown kind', conditions.clean({ kind = 'nope' }), nil);
    eq('clean trims buff', conditions.clean({ kind = 'buff', name = '  Haste ' }).name, 'Haste');

    -- the live snapshot, from the stubbed game
    game.buffs = { 33, 255 };
    local snap = conditions.snapshot();
    eq('snapshot tp', snap.tp, 1200);
    eq('snapshot engaged', snap.engaged, true);
    eq('snapshot buffs', snap.buffs[33], true);
    eq('snapshot buffs ignores empty', snap.buffs[255], nil);
    eq('snapshot unknown', snap.nothing, nil);
end

-- The hotbar file
local function S(n) return math.floor(n + 0.5); end
do
    os.remove(hotbars.path);
    eq('load without a file', hotbars.load(), true);
    eq('no bars', #hotbars.list(), 0);

    eq('new bar index', hotbars.new_bar(1920, 1080, S), 1);
    local bar = hotbars.list()[1];
    eq('new bar slots', #bar.slots, 10);
    eq('new bar first key', bar.slots[1].key, '1');
    eq('new bar last key', bar.slots[10].key, '0');
    eq('new bar centred', bar.x, (1920 - (10 * 44 + 9 * 4)) / 2);
    eq('new bar key text', bar.key_text, hotbars.DEFAULT_KEY_TEXT);
    eq('new bar label text', bar.label_text, hotbars.DEFAULT_LABEL_TEXT);
    hotbars.new_bar(1920, 1080, S);
    eq('second bar on shift', hotbars.list()[2].slots[1].key, '+1');
    eq('second bar above the first', hotbars.list()[2].y < bar.y, true);
    hotbars.new_bar(1920, 1080, S);
    eq('third bar empty', hotbars.list()[3].slots[1].key, nil);
    eq('names differ', hotbars.list()[3].name, 'Bar 3');

    bar.conditions = { { kind = 'tp', op = '>=', value = 1000 }, { kind = 'buff', name = 'Haste', is = false } };
    bar.slots[2].label = 'Holy "quoted"';
    bar.slots[2].recasts = { { kind = 'ma', id = 21, name = 'Holy' } };
    bar.slots[3].recasts = {};
    bar.key_text, bar.label_text = 14, 18;
    local ok, err = hotbars.save();
    eq('save', ok, true);
    check('save error', ok, err);

    eq('reload', hotbars.load(), true);
    local list = hotbars.list();
    eq('bars read back', #list, 3);
    bar = list[1];
    eq('name read back', bar.name, 'Bar 1');
    eq('x read back', bar.x, (1920 - (10 * 44 + 9 * 4)) / 2);
    eq('key text read back', bar.key_text, 14);
    eq('label text read back', bar.label_text, 18);
    eq('conditions read back', #bar.conditions, 2);
    eq('buff missing read back', bar.conditions[2].is, false);
    eq('label with quotes read back', bar.slots[2].label, 'Holy "quoted"');
    eq('recast read back', bar.slots[2].recasts[1].id, 21);
    eq('no recasts read back', bar.slots[3].recasts and #bar.slots[3].recasts, 0);
    eq('auto recasts read back', bar.slots[1].recasts, nil);
    eq('empty slots read back', list[3].slots[10] ~= nil, true);

    hotbars.set_count(bar, 4);
    eq('one row stays one row (fewer)', bar.columns, 4);
    hotbars.set_count(bar, 12);
    eq('one row stays one row (more)', bar.columns, 12);
    bar.columns = 5;
    hotbars.set_count(bar, 20);
    eq('a grid keeps its columns', bar.columns, 5);
    eq('slots added', #bar.slots, 20);
    hotbars.set_count(bar, 3);
    eq('columns no more than slots', bar.columns, 3);

    hotbars.edit.bar = 3;
    hotbars.remove(3);
    eq('removed', #hotbars.list(), 2);
    eq('edit moves off a removed bar', hotbars.edit.bar, 2);
end

local function write(text)
    local file = assert(io.open(hotbars.path, 'w'));
    file:write(text);
    file:close();
end
local function read()
    local file = assert(io.open(hotbars.path, 'r'));
    local text = file:read('*a');
    file:close();
    return text;
end

-- Bad values are cleaned up
do
    write([[return {
        { name = '', x = 'abc', size = 500, columns = 0, key_text = 999, label_text = 'big',
          conditions = { { kind = 'nope' }, { kind = 'tp', value = 99999 } },
          slots = { { key = '  ^q ' }, 'junk', { recasts = { { kind = 'xx', id = 1 }, { kind = 'ja', id = '5' } } } } },
        'not a bar',
    }]]);
    eq('bad file loads', hotbars.load(), true);
    local bar = hotbars.list()[1];
    eq('one bar from bad file', #hotbars.list(), 1);
    eq('empty name filled in', bar.name, 'Bar 1');
    eq('bad x defaulted', bar.x, 100);
    eq('size clamped', bar.size, hotbars.MAX_SIZE);
    eq('columns clamped', bar.columns, 1);
    eq('key text clamped', bar.key_text, hotbars.MAX_TEXT);
    eq('bad label text defaulted', bar.label_text, hotbars.DEFAULT_LABEL_TEXT);
    eq('unknown condition dropped', #bar.conditions, 1);
    eq('condition value clamped', bar.conditions[1].value, 3000);
    eq('key cleaned', bar.slots[1].key, '^Q');
    eq('junk slot emptied', next(bar.slots[2]), nil);
    eq('bad recast dropped', #bar.slots[3].recasts, 1);
    eq('recast id as number', bar.slots[3].recasts[1].id, 5);
end

-- A file that can't be read is never written over
do
    write('return {');
    local ok = hotbars.load();
    eq('broken file reported', ok, false);
    check('broken file says so', hotbars.error ~= nil);
    hotbars.new_bar(1920, 1080, S);
    eq('broken file not saved over', (hotbars.save()), false);
    eq('broken file left alone', read(), 'return {');

    write('return { { name = tostring(os) } }');
    eq('file can reach nothing', (hotbars.load()), false);
end

-- engine.press runs a key's binding
local engine = require('engine');
local scope = { id = 'PLD_WAR', label = 'PLD/WAR' };
local bindings = {
    { id = '1', key = '1', lines = { '/ma Holy <t>' }, scope = scope },
    { id = 'G', key = 'G', lines = { '/ma Flash <t>', '/wait 1.1', '/ja Provoke <t>' }, scope = scope },
};
do
    engine.apply(bindings);
    game.sent = {};
    eq('press a bound key', engine.press('1'), true);
    eq('press sends its command', game.sent[1], '/ma Holy <t>');
    eq('press an unbound key', engine.press('2'), false);
end

-- The window and the bars, driven through the fake ImGui
do
    os.remove(hotbars.path);
    hotbars.load();
    hotbars.edit.bar, hotbars.edit.slot = 1, nil;
    local style = require('style');
    local hotbar_ui = require('hotbar_ui');
    local keyboard_ui = require('keyboard_ui');
    keyboard_ui.set_context(profiles.scopes('PLD', 'WAR'), bindings, function () end);
    hotbar_ui.set_bindings(bindings);
    keyboard_ui.open('hotbars');

    -- One frame as jobbinds.lua draws it, with this input
    local function frame(name, given)
        input = given or {};
        local ok, err = pcall(function ()
            style.frame();
            recasts.frame();
            hotbar_ui.render(keyboard_ui.editing_hotbars());
            keyboard_ui.render();
            style.tooltips();
        end);
        check('frame: ' .. name, ok, err);
    end

    frame('empty page');
    frame('new bar', { click = '##jb_bar_new' });
    local bar = hotbars.list()[1];
    eq('new bar made', bar ~= nil, true);
    frame('page with a bar');
    eq('first slot picked', hotbars.edit.slot, 1);

    frame('type a key', { type = { '##jb_slot_key', 'g' } });
    eq('key typed', bar.slots[1].key, 'G');
    frame('hover the key note', { hover = '##jb_slot_runs' });
    frame('type a label', { type = { '##jb_slot_label', 'Enmity' } });
    eq('label typed', bar.slots[1].label, 'Enmity');
    frame('clear the label', { type = { '##jb_slot_label', '  ' } });
    eq('label back to auto', bar.slots[1].label, nil);

    frame('add tp', { click = '##jb_add_tp' });
    eq('tp added', bar.conditions[1] and bar.conditions[1].kind, 'tp');
    frame('tp value', { type = { '##jb_cond_1_v', '1500' } });
    eq('tp value typed', bar.conditions[1].value, 1500);
    frame('tp below', { click = '##jb_cond_1_2' });
    eq('tp op flipped', bar.conditions[1].op, '<');
    frame('add buff', { click = '##jb_add_buff' });
    frame('buff name', { type = { '##jb_cond_2_v', 'Hastee' } });
    frame('page with an unknown buff');
    frame('buff name fixed', { type = { '##jb_cond_2_v', 'haste' } });
    eq('buff typed', bar.conditions[2].name, 'haste');
    frame('remove tp', { click = '##jb_cond_1_x' });
    eq('tp removed', #bar.conditions, 1);
    eq('buff kept', bar.conditions[1].kind, 'buff');

    frame('search', { type = { '##jb_slot_search', 'sent' } });
    frame('search shows matches', { hover = '##jb_match_1' });
    frame('pick a match', { click = '##jb_match_1' });
    local names = {};
    for _, rc in ipairs(bar.slots[1].recasts or {}) do
        names[#names + 1] = rc.name;
    end
    eq('auto recasts kept, match added', table.concat(names, ','), 'Flash,Provoke,Sentinel');
    frame('remove a recast', { click = '##jb_rc_1' });
    eq('recast removed', #bar.slots[1].recasts, 2);
    frame('none', { click = '##jb_rc_none' });
    eq('none picked', #bar.slots[1].recasts, 0);
    frame('auto', { click = '##jb_rc_auto' });
    eq('auto picked', bar.slots[1].recasts, nil);

    frame('more slots', { hold = '##jb_bar_count_up' });
    eq('slot added', #bar.slots, 11);
    eq('still one row', bar.columns, 11);
    frame('release');
    frame('fewer columns', { hold = '##jb_bar_cols_dn' });
    eq('columns down', bar.columns, 10);
    frame('release');
    frame('bigger', { hold = '##jb_bar_size_up' });
    eq('size up by two', bar.size, 46);
    frame('release');
    frame('bigger key', { hold = '##jb_bar_key_text_up' });
    eq('key text up', bar.key_text, hotbars.DEFAULT_KEY_TEXT + 1);
    frame('release');
    frame('smaller label', { hold = '##jb_bar_label_text_dn' });
    eq('label text down', bar.label_text, hotbars.DEFAULT_LABEL_TEXT - 1);
    frame('release');
    bar.label_text = hotbars.MAX_TEXT; -- a two-line label this tall falls back to one line
    bar.slots[2].label = 'Shield Bash';
    frame('huge label');
    bar.slots[2].label = nil;
    frame('next slot', { hold = '##jb_slot_step_up' });
    eq('slot two picked', hotbars.edit.slot, 2);
    frame('release');
    frame('rename', { type = { '##jb_bar_name', 'Main' } });
    eq('renamed', bar.name, 'Main');

    -- On screen, in the editor: pick a slot, drag the tab
    frame('pick slot 3 on screen', { click = '##jb_slot_1_3' });
    eq('slot three picked', hotbars.edit.slot, 3);
    local x, y = bar.x, bar.y;
    frame('drag the tab', { drag = '##jb_bar_tab_1', delta = { 50, -20 } });
    eq('dragged right', bar.x, x + 50);
    eq('dragged up', bar.y, y - 20);
    frame('drag off the screen', { drag = '##jb_bar_tab_1', delta = { -5000, -5000 } });
    eq('kept on screen x', bar.x, 0);
    eq('kept on screen y', bar.y, 0);
    frame('release');
    frame('tab under a bar at the top', { hover = '##jb_bar_tab_1' });
    frame('clear slot', { click = '##jb_slot_clear' });
    eq('slot cleared', next(bar.slots[3]), nil);

    -- Recasts running, a hidden bar, a second bar
    game.abilities = { [3] = { id = 5, timer = 600 } };
    game.spells = { [112] = 300 };
    frame('slot cooling down');
    frame('hover a cooling slot', { hover = '##jb_slot_1_1' });
    game.abilities = {};
    game.spells = {};
    frame('slot ready again');
    frame('new bar again', { click = '##jb_bar_new' });
    eq('second bar', #hotbars.list(), 2);
    eq('second bar picked', hotbars.edit.bar, 2);
    frame('pick bar one', { click = '##jb_bars_1' });
    eq('bar one picked', hotbars.edit.bar, 1);

    -- Outside the editor: the bar shows by its conditions, and clicks run
    keyboard_ui.is_open[1] = false;
    game.buffs = { 255 };
    bar.conditions[1].is = true; -- Haste up: not now
    frame('hidden bar');
    game.buffs = { 33 };
    engine.apply(bindings);
    game.sent = {};
    frame('click a slot', { click = '##jb_slot_1_1' });
    eq('slot ran its key', game.sent[1], '/ma Flash <t>');
    frame('hover a slot', { hover = '##jb_slot_1_1' });
    frame('hover an empty slot', { hover = '##jb_slot_1_3' });

    -- Delete asks once
    keyboard_ui.open('hotbars');
    frame('delete once', { click = '##jb_bar_delete' });
    eq('not deleted yet', #hotbars.list(), 2);
    frame('delete again', { click = '##jb_bar_delete' });
    eq('deleted', #hotbars.list(), 1);

    -- Many bars: the picker steps through them
    for _ = 1, 8 do
        hotbars.new_bar(1920, 1080, S);
    end
    frame('many bars');
    frame('keys page', { click = '##jb_page_1' });
    eq('keys page', keyboard_ui.page, 'keys');
    frame('keys page drawn');

    -- Saved once idle
    input = {};
    hotbars.save_if_idle();
    eq('saved when idle', hotbars.is_dirty(), false);
    eq('saved bars read back', (hotbars.load()) and #hotbars.list(), 9);
end

os.remove(hotbars.path);
print(('%d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
