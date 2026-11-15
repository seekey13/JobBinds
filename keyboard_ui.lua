--[[
* JobBinds window: a visual keyboard to pick a key, and an editor for what the
* key runs (alone, and with Ctrl, Alt or Shift) in one of the profiles that
* apply to the current job. Drawn in the VanaCore style (style.lua).
--]]

require('common');
local imgui = require('imgui');
local blocked_keybinds = require('blocked_keybinds');
local profiles = require('profiles');
local style = require('style');

local P, S, mix = style.P, style.S, style.mix;

local keyboard_ui = {};
keyboard_ui.is_open = { false };

-- Virtual keyboard layout definition: { label, width }. Each row's last key is
-- the Ins/Del/Home/End column; the one before it is stretched to meet it.
local keyboard_layout = {
    -- Row 1: Number row
    {
        {'`', 26}, {'1', 26}, {'2', 26}, {'3', 26}, {'4', 26}, {'5', 26}, {'6', 26},
        {'7', 26}, {'8', 26}, {'9', 26}, {'0', 26}, {'-', 26}, {'=', 26}, {'<--', 51}, {'INS', 51}
    },
    -- Row 2: QWERTY row
    {
        {'TAB', 38}, {'Q', 26}, {'W', 26}, {'E', 26}, {'R', 26}, {'T', 26}, {'Y', 26},
        {'U', 26}, {'I', 26}, {'O', 26}, {'P', 26}, {'[', 26}, {']', 26}, {'\\', 38}, {'DEL', 51}
    },
    -- Row 3: ASDF row
    {
        {'CAPS', 51}, {'A', 26}, {'S', 26}, {'D', 26}, {'F', 26}, {'G', 26}, {'H', 26},
        {'J', 26}, {'K', 26}, {'L', 26}, {';', 26}, {"'", 26}, {'ENTER', 58}, {'HOME', 51}
    },
    -- Row 4: ZXCV row
    {
        {'SHIFT', 64}, {'Z', 26}, {'X', 26}, {'C', 26}, {'V', 26}, {'B', 26}, {'N', 26},
        {'M', 26}, {',', 26}, {'.', 26}, {'/', 26}, {'SHIFT', 78}, {'END', 51}
    }
};

-- The editor's rows: the key alone and with each modifier.
local rows = {
    { prefix = '',  modifier = '',      text = { '' }, multi = { false } },
    { prefix = '^', modifier = 'Ctrl',  text = { '' }, multi = { false } },
    { prefix = '!', modifier = 'Alt',   text = { '' }, multi = { false } },
    { prefix = '+', modifier = 'Shift', text = { '' }, multi = { false } },
};

-- Layout, in unscaled pixels (style.S scales each one)
local MARGIN    = 6;    -- round the panel, room for its shadow
local PAD       = 18;   -- the panel's left and right padding
local INNER_W   = 540;  -- the keyboard's width, and every row's
local TITLE_H   = 36;
local KEY_H     = 28;
local KEY_GAP   = 6;
local NAV_GAP   = 12;   -- before the Ins/Del/Home/End column
local BLOCK_GAP = 14;   -- above and below the keyboard
local PROFILE_H = 40;
local HINT_H    = 64;   -- the editor with no key picked
local HEAD_H    = 30;   -- the editor's heading
local ROW_H     = 32;   -- a one-line binding
local FIELD_H   = 26;
local MULTI_H   = 100;  -- a macro's field
local NOTE_H    = 18;   -- "From Global: ..." under a field
local FIELD_X   = 122;  -- where the command fields start
local FOOT_H    = 46;   -- Save and Delete

local selected_key = '';   -- the key being edited ('' for none)
local scopes = {};         -- the profiles that apply now, lowest priority first
local scope_index = 1;     -- the one being edited
local scope_ids = '';
local bound = {};          -- chord id -> the binding in force
local bound_keys = {};     -- key -> its bindings in force
local on_changed = nil;    -- called after a profile is saved
local error_message = '';

local function row_allowed(row)
    return not blocked_keybinds.is_combination_blocked(selected_key, row.modifier);
end

local function describe(binding)
    local first = binding.lines[1] or '';
    return #binding.lines > 1 and (first .. ' ...') or first;
end

-- Fill the editor from the profile being edited.
local function load_rows()
    local layer = scopes[scope_index] and profiles.layer(scopes[scope_index].id) or {};
    for _, row in ipairs(rows) do
        local lines = selected_key ~= '' and layer[row.prefix .. selected_key] or {};
        row.text[1] = table.concat(lines, '\n');
        row.multi[1] = #lines > 1;
    end
    error_message = '';
end

-- Write the editor's rows (or with clear, nothing) to the profile being edited.
local function save_rows(clear)
    local scope = scopes[scope_index];
    if selected_key == '' or not scope then
        return;
    end
    for _, row in ipairs(rows) do
        if row_allowed(row) then
            local lines = {};
            if not clear then
                for line in row.text[1]:gmatch('[^\r\n]+') do
                    line = line:match('^%s*(.-)%s*$');
                    if line ~= '' then
                        lines[#lines + 1] = line;
                    end
                end
            end
            profiles.set(scope.id, row.prefix .. selected_key, lines);
        end
    end
    local ok, err = profiles.save(scope.id);
    if on_changed then
        on_changed(); -- rebinds the keys and comes back through set_context
    end
    error_message = ok and '' or ('Could not save ' .. scope.id .. '.txt: ' .. tostring(err));
end

-- One key: sunken while unbound, a raised keycap while bound, in the accent
-- while it is the one being edited, faded while the game keeps it.
local function draw_key(dl, id, key, x, y, w, h)
    local usable = not blocked_keybinds.blocked[key];
    local bindings = usable and bound_keys[key] or nil;
    local hovered, clicked = style.hit(id, x, y, w, h);

    local picked = style.ease(id .. '.picked', usable and selected_key == key and 1 or 0);
    local lit = style.ease(id .. '.lit', usable and hovered and 1 or 0, 22);
    local alpha = usable and 1 or 0.4;
    local face = bindings and P.seg or P.well;
    local edge = bindings and mix(P.seg, P.white, 0.12) or P.well_edge;
    local ink = not usable and P.faint or bindings and P.text or P.dim;

    style.fill(dl, x, y, w, h, mix(face, P.accent_bg, picked), S(4), alpha);
    style.outline(dl, x, y, w, h, mix(mix(edge, P.accent_lo, lit), P.accent, picked), S(4), alpha);
    if lit > 0.01 then
        style.fill(dl, x, y, w, h, '#FFFFFF', S(4), 0.05 * lit);
    end
    style.text_centred(dl, x + w / 2, y + h / 2, key, mix(mix(ink, P.text, lit), P.white, picked),
        style.fonts.text, S(style.SMALL), alpha);

    -- Show what the key runs on hover
    if bindings and hovered then
        local lines = {};
        for _, binding in ipairs(bindings) do
            local combo = (binding.ctrl and 'Ctrl + ' or '') .. (binding.alt and 'Alt + ' or '')
                .. (binding.shift and 'Shift + ' or '') .. binding.key;
            lines[#lines + 1] = ('%s  [%s]  %s'):format(combo, binding.scope.label, describe(binding));
        end
        style.tooltip(table.concat(lines, '\n'));
    end

    if clicked and usable then
        selected_key = key;
        load_rows();
    end
end

-- The keyboard, w wide: every row ends at the same right edge
local function draw_keyboard(dl, x, y, w)
    local gap, h = S(KEY_GAP), S(KEY_H);
    for r, row in ipairs(keyboard_layout) do
        local nav = row[#row];
        local nav_x = x + w - S(nav[2]);
        local at = x;
        for i = 1, #row - 1 do
            local key = row[i];
            -- the last key before the Ins/Del/Home/End column takes what is left
            local key_w = i == #row - 1 and (nav_x - S(NAV_GAP) - at) or S(key[2]);
            draw_key(dl, ('##jb_key_%d_%d'):format(r, i), key[1], at, y, key_w, h);
            at = at + key_w + gap;
        end
        draw_key(dl, ('##jb_key_%d_%d'):format(r, #row), nav[1], nav_x, y, S(nav[2]), h);
        y = y + h + gap;
    end
end

local function keyboard_height()
    return #keyboard_layout * S(KEY_H) + (#keyboard_layout - 1) * S(KEY_GAP);
end

-- Which profile the editor works on
local function draw_scope_picker(dl, x, y, right)
    local cy = y + S(PROFILE_H) / 2;
    local px = S(style.BODY);
    style.text_mid(dl, x, cy, 'Profile', P.text, style.fonts.text, px);
    style.hit('##jb_profile_label', x, cy - S(11), style.measure('Profile', style.fonts.text, px), S(22));
    style.tip('Each profile applies to the jobs it names.\nWhen two bind the same key, the one further right wins.');

    local labels = {};
    for i, scope in ipairs(scopes) do
        labels[i] = scope.label;
    end
    if #labels == 0 then
        return;
    end
    local total = style.segments_width(labels);
    local index, changed = style.segments('##jb_scope', right - total, cy, labels, scope_index);
    if changed then
        scope_index = index;
        load_rows();
    end
end

-- What the editor will draw for the key picked, and how tall it is: the
-- window's size is set before it is drawn. nil with no key picked.
local function plan_editor()
    if selected_key == '' then
        return nil, S(HINT_H);
    end
    local scope = scopes[scope_index];
    local plan = { key = selected_key };
    local height = S(6) + S(HEAD_H);
    for _, row in ipairs(rows) do
        if row_allowed(row) then
            -- Several commands never collapse back into the one-line field
            if row.text[1]:find('\n', 1, true) then
                row.multi[1] = true;
            end
            local item = { row = row, multi = row.multi[1], h = row.multi[1] and S(MULTI_H) + S(6) or S(ROW_H) };

            -- Say so when another profile decides what this key runs
            local binding = bound[row.prefix .. selected_key];
            if scope and binding and binding.scope.id ~= scope.id then
                local what = row.text[1] == '' and 'From' or 'Overridden by';
                item.note = ('%s %s: %s'):format(what, binding.scope.label, describe(binding));
                item.h = item.h + S(NOTE_H);
            end
            plan[#plan + 1] = item;
            height = height + item.h;
        end
    end
    return plan, height + S(8) + S(FOOT_H);
end

-- One binding: its keys, the command, a cross to clear it, the Macro toggle
local function draw_binding_row(dl, item, key, x, y, right)
    local row = item.row;
    local cy = y + S(ROW_H) / 2;

    local at = x;
    if row.modifier ~= '' then
        local px = S(style.SMALL);
        at = at + style.keycap(dl, at, cy, row.modifier) + S(5);
        style.text_mid(dl, at, cy, '+', P.faint, style.fonts.text, px);
        at = at + style.measure('+', style.fonts.text, px) + S(5);
    end
    style.keycap(dl, at, cy, key);

    local chip_w, cross = style.chip_width('Macro'), S(20);
    local field_x = x + S(FIELD_X);
    local field_w = right - chip_w - S(8) - cross - S(4) - field_x;
    local field_h = item.multi and S(MULTI_H) or S(FIELD_H);
    style.field('##cmd_' .. row.modifier, field_x, cy - S(FIELD_H) / 2, field_w, field_h, row.text, 2048, item.multi);

    if style.cross('##clear_' .. row.modifier, field_x + field_w + S(4) + cross / 2, cy, cross) then
        row.text[1] = '';
        row.multi[1] = false;
    end
    style.tip('Clear binding');

    if style.chip('##macro_' .. row.modifier, right - chip_w, cy, 'Macro', item.multi) then
        row.multi[1] = not row.multi[1];
    end
    style.tip('Macro: several commands, one per line.\n/wait 2 on its own line pauses for 2 seconds.');

    if item.note then
        local font, px = style.fonts.base, imgui.GetFontSize();
        style.text_mid(dl, field_x + S(2), y + item.h - S(NOTE_H) / 2 - S(2),
            style.fit(item.note, field_w - S(4), font, px), P.dim, font, px);
    end
end

-- The editor for the key picked: a heading, its bindings, Save and Delete
local function draw_editor(dl, plan, x, y, right, panel_x, panel_right)
    if not plan then
        style.text_centred(dl, (x + right) / 2, y + S(HINT_H) / 2, 'Click a key on the keyboard to bind it',
            P.dim, style.fonts.text, S(style.BODY - 1));
        return;
    end

    -- Heading: spaced capitals in teal, then a hairline
    y = y + S(6);
    local cy = y + S(HEAD_H) / 2;
    local title_w = style.text_spaced(dl, x, cy, 'BINDINGS', P.teal, style.fonts.semi_italic, S(style.SMALL),
        math.max(1, S(1.2)));
    style.line(dl, x + title_w + S(10), cy, right, cy, P.line);
    y = y + S(HEAD_H);

    for _, item in ipairs(plan) do
        draw_binding_row(dl, item, plan.key, x, y, right);
        y = y + item.h;
    end

    y = y + S(8);
    style.line(dl, panel_x, y, panel_right, y, P.border);
    cy = y + S(FOOT_H) / 2;

    local save_w = math.max(S(84), style.button_width('Save'));
    local delete_w = math.max(S(84), style.button_width('Delete'));
    local delete_x = right - save_w - S(8) - delete_w;
    if style.button('##jb_delete', delete_x, cy, 'Delete', 'danger', delete_w) then
        save_rows(true);
    end
    style.tip('Remove this key\'s bindings from the selected profile');
    if style.button('##jb_save', right - save_w, cy, 'Save', 'accent', save_w) then
        save_rows(false);
    end

    if error_message ~= '' then
        local font, px = style.fonts.base, imgui.GetFontSize();
        local room = delete_x - S(12) - x;
        style.text_mid(dl, x, cy, style.fit(error_message, room, font, px), P.rose, font, px);
        style.hit('##jb_error', x, cy - S(11), room, S(22));
        style.tip(error_message);
    end
end

-- The panel (ImGui draws none of it), then everything in it
local function draw_window(plan, pw, ph)
    local m, pad = S(MARGIN), S(PAD);
    local x, y = imgui.GetCursorScreenPos();
    x, y = x + m, y + m;
    local dl = imgui.GetWindowDrawList();
    style.fill(dl, x - 1, y, pw + 2, ph + 2, '#000000', S(6), 0.35); -- its shadow
    style.fill(dl, x, y, pw, ph, P.bg, S(5));
    style.outline(dl, x, y, pw, ph, P.border, S(5));

    -- Title bar
    local cy = y + S(TITLE_H) / 2;
    style.text_mid(dl, x + pad, cy, 'JobBinds', P.white, style.fonts.semi, S(style.BODY));
    local box = S(21);
    if style.cross('##jb_close', x + pw - pad - box / 2 + S(4), cy, box) then
        keyboard_ui.is_open[1] = false;
    end
    style.tip('Close');
    style.line(dl, x, y + S(TITLE_H), x + pw, y + S(TITLE_H), P.border);

    local left, right = x + pad, x + pw - pad;
    y = y + S(TITLE_H) + S(BLOCK_GAP);
    draw_keyboard(dl, left, y, right - left);
    y = y + keyboard_height() + S(BLOCK_GAP);

    style.line(dl, x, y, x + pw, y, P.border);
    draw_scope_picker(dl, left, y, right);
    y = y + S(PROFILE_H);
    style.line(dl, x, y, x + pw, y, P.border);

    draw_editor(dl, plan, left, y, right, x, x + pw);
end

local WINDOW_FLAGS = ImGuiWindowFlags_NoTitleBar + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_NoScrollbar
    + ImGuiWindowFlags_NoScrollWithMouse + ImGuiWindowFlags_NoCollapse + ImGuiWindowFlags_NoBackground
    + ImGuiWindowFlags_NoNavInputs; -- NoNavInputs: Tab is the game's (target cycling), not ImGui's

-- Main render function
function keyboard_ui.render()
    if not keyboard_ui.is_open[1] then
        return;
    end

    style.frame();
    local plan, editor_h = plan_editor();
    local m, pw = S(MARGIN), S(INNER_W) + S(PAD) * 2;
    local ph = S(TITLE_H) + S(BLOCK_GAP) + keyboard_height() + S(BLOCK_GAP) + S(PROFILE_H) + editor_h;

    local screen_w, screen_h = style.screen();
    imgui.SetNextWindowPos({ screen_w / 2, screen_h / 2 }, ImGuiCond_FirstUseEver, { 0.5, 0.5 });
    imgui.SetNextWindowSize({ pw + m * 2, ph + m * 2 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 });

    -- An error while drawing must still reach End: ImGui asserts on a window left open
    local ok, err = true, nil;
    if imgui.Begin('JobBinds', keyboard_ui.is_open, WINDOW_FLAGS) then
        ok, err = pcall(draw_window, plan, pw, ph);
    end
    imgui.End();
    imgui.PopStyleVar(3);
    style.tooltips();

    if not ok then
        keyboard_ui.is_open[1] = false; -- not drawn again until /jb reopens it
        error(err, 0);
    end
end

-- Segoe UI for the window. From Ashita's load event: ImGui 1.81 takes no font mid-frame.
function keyboard_ui.load()
    style.load();
end

function keyboard_ui.toggle()
    keyboard_ui.is_open[1] = not keyboard_ui.is_open[1];
end

-- The profiles that apply now and the bindings in force. changed() is called
-- after the window saves a profile.
function keyboard_ui.set_context(new_scopes, bindings, changed)
    local ids = {};
    for i, scope in ipairs(new_scopes) do
        ids[i] = scope.id;
    end
    ids = table.concat(ids, ' ');
    if ids ~= scope_ids then
        -- another job: start on its exact job/subjob profile (Global comes last)
        scope_ids = ids;
        scope_index = math.max(1, #new_scopes - 1);
    end
    scopes = new_scopes;
    on_changed = changed;

    bound, bound_keys = {}, {};
    for _, binding in ipairs(bindings) do
        bound[binding.id] = binding;
        bound_keys[binding.key] = bound_keys[binding.key] or {};
        table.insert(bound_keys[binding.key], binding);
    end
    load_rows();
end

return keyboard_ui;
