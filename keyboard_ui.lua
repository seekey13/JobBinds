--[[
* JobBinds window: a visual keyboard to pick a key, and an editor for what the
* key runs (alone, and with Ctrl, Alt or Shift) in one of the profiles that
* apply to the current job.
--]]

require('common');
local imgui = require('imgui');
local blocked_keybinds = require('blocked_keybinds');
local profiles = require('profiles');

local keyboard_ui = {};
keyboard_ui.is_open = { false };

-- Virtual keyboard layout definition: { label, width }
local keyboard_layout = {
    -- Row 1: Number row
    {
        {'`', 26}, {'1', 26}, {'2', 26}, {'3', 26}, {'4', 26}, {'5', 26}, {'6', 26},
        {'7', 26}, {'8', 26}, {'9', 26}, {'0', 26}, {'-', 26}, {'=', 26}, {'<--', 51}
    },
    -- Row 2: QWERTY row
    {
        {'TAB', 38}, {'Q', 26}, {'W', 26}, {'E', 26}, {'R', 26}, {'T', 26}, {'Y', 26},
        {'U', 26}, {'I', 26}, {'O', 26}, {'P', 26}, {'[', 26}, {']', 26}, {'\\', 38}
    },
    -- Row 3: ASDF row
    {
        {'CAPS', 51}, {'A', 26}, {'S', 26}, {'D', 26}, {'F', 26}, {'G', 26}, {'H', 26},
        {'J', 26}, {'K', 26}, {'L', 26}, {';', 26}, {"'", 26}, {'ENTER', 58}
    },
    -- Row 4: ZXCV row
    {
        {'SHIFT', 64}, {'Z', 26}, {'X', 26}, {'C', 26}, {'V', 26}, {'B', 26}, {'N', 26},
        {'M', 26}, {',', 26}, {'.', 26}, {'/', 26}, {'SHIFT', 78}
    }
};

-- The editor's rows: the key alone and with each modifier.
local rows = {
    { prefix = '',  modifier = '',      text = { '' }, multi = { false } },
    { prefix = '^', modifier = 'Ctrl',  text = { '' }, multi = { false } },
    { prefix = '!', modifier = 'Alt',   text = { '' }, multi = { false } },
    { prefix = '+', modifier = 'Shift', text = { '' }, multi = { false } },
};

local LABEL_X   = 136; -- where the command fields start
local COMMAND_W = 330;

local selected_key = '';   -- the key being edited ('' for none)
local scopes = {};         -- the profiles that apply now, lowest priority first
local scope_index = 1;     -- the one being edited
local scope_ids = '';
local bound = {};          -- chord id -> the binding in force
local bound_keys = {};     -- key -> its bindings in force
local on_changed = nil;    -- called after a profile is saved
local error_message = '';

-- ImGui's text calls take a printf format
local function plain(text)
    return (text:gsub('%%', '%%%%'));
end

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

-- Function to render a virtual keyboard button
local function render_key_button(key, width)
    local is_blocked = blocked_keybinds.blocked[key] or false;
    local bindings = bound_keys[key];

    -- Style the button based on status: blocked > selected > bound > normal
    local pushed_colors = true;
    if is_blocked then
        -- Blocked keys: dark red/disabled appearance
        imgui.PushStyleColor(ImGuiCol_Button, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.5);
    elseif selected_key == key then
        -- Selected key: green
        imgui.PushStyleColor(ImGuiCol_Button, { 0.1, 0.6, 0.1, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.15, 0.7, 0.15, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.08, 0.5, 0.08, 1.0 });
    elseif bindings then
        -- Bound keys: default ImGui button colors
        pushed_colors = false;
    else
        -- Normal keys: gray
        imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.2, 0.2, 0.2, 1.0 });
    end

    local clicked = imgui.Button(key, { width, 30 });

    if pushed_colors then
        imgui.PopStyleColor(3);
    end
    if is_blocked then
        imgui.PopStyleVar();
    end

    -- Show what the key runs on hover
    if bindings and not is_blocked and imgui.IsItemHovered() then
        local lines = {};
        for _, binding in ipairs(bindings) do
            local combo = (binding.ctrl and 'Ctrl + ' or '') .. (binding.alt and 'Alt + ' or '')
                .. (binding.shift and 'Shift + ' or '') .. binding.key;
            lines[#lines + 1] = ('%s  [%s]  %s'):format(combo, binding.scope.label, describe(binding));
        end
        imgui.SetTooltip(plain(table.concat(lines, '\n')));
    end

    if clicked and not is_blocked then
        selected_key = key;
        load_rows();
    end
end

-- Function to render the virtual keyboard
local function render_virtual_keyboard()
    for _, row in ipairs(keyboard_layout) do
        for i, key_data in ipairs(row) do
            if i > 1 then
                imgui.SameLine();
            end
            render_key_button(key_data[1], key_data[2]);
        end
    end
end

-- Which profile the editor works on
local function render_scope_picker()
    imgui.Text('Profile');
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Each profile applies to the jobs it names.\nWhen two bind the same key, the one further right wins.');
    end
    for i, scope in ipairs(scopes) do
        imgui.SameLine();
        if imgui.RadioButton(scope.label, i == scope_index) then
            scope_index = i;
            load_rows();
        end
    end
end

local function render_binding_row(row, label)
    local scope = scopes[scope_index];

    imgui.Text(label);
    imgui.SameLine();

    imgui.SetCursorPosX(112);
    if imgui.Button('X##clear_' .. row.modifier, { 20, 0 }) then
        row.text[1] = '';
        row.multi[1] = false;
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Clear binding');
    end
    imgui.SameLine();

    -- Several commands never collapse back into the one-line field
    if row.text[1]:find('\n', 1, true) then
        row.multi[1] = true;
    end

    imgui.SetCursorPosX(LABEL_X);
    if row.multi[1] then
        imgui.InputTextMultiline('##cmd_' .. row.modifier, row.text, 2048, { COMMAND_W, 100 });
    else
        imgui.SetNextItemWidth(COMMAND_W);
        imgui.InputText('##cmd_' .. row.modifier, row.text, 2048, ImGuiInputTextFlags_None);
    end
    imgui.SameLine();
    imgui.Checkbox('##macro_' .. row.modifier, row.multi);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Macro: several commands, one per line.\n/wait 2 on its own line pauses for 2 seconds.');
    end

    -- Say so when another profile decides what this key runs
    local binding = bound[row.prefix .. selected_key];
    if binding and binding.scope.id ~= scope.id then
        imgui.SetCursorPosX(LABEL_X);
        local what = row.text[1] == '' and 'From' or 'Overridden by';
        imgui.TextDisabled(plain(('%s %s: %s'):format(what, binding.scope.label, describe(binding))));
    end
end

-- Function to render the binding editor
local function render_binding_editor()
    if selected_key == '' then
        imgui.Spacing();
        imgui.Spacing();
        imgui.Text('Click a button on the keyboard to apply a key binding');
        imgui.Spacing();
        imgui.Spacing();
        return;
    end

    imgui.Text('Binding');
    imgui.SameLine();
    imgui.SetCursorPosX(LABEL_X);
    imgui.Text('Command');
    imgui.SameLine();
    imgui.SetCursorPosX(LABEL_X + COMMAND_W - 16);
    imgui.Text('Macro');
    imgui.Spacing();

    for _, row in ipairs(rows) do
        if row_allowed(row) then
            render_binding_row(row, row.modifier == '' and selected_key or ('+ ' .. row.modifier));
            imgui.Spacing();
        end
    end

    imgui.Separator();
    imgui.Spacing();

    if imgui.Button('Save', { 120, 0 }) then
        save_rows(false);
    end
    imgui.SameLine();
    if imgui.Button('Delete', { 120, 0 }) then
        save_rows(true);
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Remove this key\'s bindings from the selected profile');
    end

    if error_message ~= '' then
        imgui.TextColored({ 1.0, 0.3, 0.3, 1.0 }, plain(error_message));
    end
end

-- Main render function
function keyboard_ui.render()
    if not keyboard_ui.is_open[1] then
        return;
    end

    if imgui.Begin('JobBinds', keyboard_ui.is_open, ImGuiWindowFlags_AlwaysAutoResize) then
        render_virtual_keyboard();
        imgui.Separator();
        render_scope_picker();
        imgui.Separator();
        render_binding_editor();
    end
    imgui.End();
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
        -- another job: start on its most specific profile
        scope_ids = ids;
        scope_index = #new_scopes;
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
