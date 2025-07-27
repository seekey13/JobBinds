require('common');
local imgui = require('imgui');
local vk_codes = require('vk_codes');
local blocked_keybinds = require('blocked_keybinds');

-- UI state variables
local keyboard_ui = {};
keyboard_ui.is_open = { false };
keyboard_ui.selected_binding = -1;
keyboard_ui.binding_key = { '' };
keyboard_ui.shift_modifier = { false };
keyboard_ui.alt_modifier = { false };
keyboard_ui.ctrl_modifier = { false };
keyboard_ui.command_text = { '' };
keyboard_ui.is_macro = { false };
keyboard_ui.macro_text = { '' };
keyboard_ui.current_profile = 'No Profile Loaded';
keyboard_ui.is_binding = false;
keyboard_ui.debug_mode = false;
keyboard_ui.error_message = '';

-- Current bindings loaded from profile file
local current_bindings = {};
local current_profile_path = nil;

-- Virtual keyboard layout definition
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
}

-- Function to render a virtual keyboard button
local function render_key_button(key, width)
    if key == '' then
        -- Spacer
        imgui.SameLine();
        imgui.Dummy({ width, 30 });
        return false
    end
    
    local clicked = false
    
    -- Check if this key is blocked
    local is_blocked = blocked_keybinds.blocked[key:upper()] or false
    
    -- Check if this key is bound
    local is_bound = false
    for _, binding in ipairs(current_bindings) do
        if binding.key:upper() == key:upper() then
            is_bound = true
            break
        end
    end
    
    -- Determine if we need to push custom colors
    local push_colors = false
    local push_alpha = false
    
    -- Style the button based on status: blocked > selected > bound > normal
    if is_blocked then
        -- Blocked keys: dark red/disabled appearance
        imgui.PushStyleColor(ImGuiCol_Button, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.5);
        push_colors = true
        push_alpha = true
    elseif keyboard_ui.binding_key[1] ~= '' and keyboard_ui.binding_key[1]:upper() == key:upper() then
        -- Selected key: default ImGui styling (matching New/Save/Delete buttons)
        -- No custom styling - uses default ImGui button colors
        push_colors = false
    elseif is_bound then
        -- Bound keys: green
        imgui.PushStyleColor(ImGuiCol_Button, { 0.2, 0.8, 0.2, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.3, 0.9, 0.3, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.1, 0.7, 0.1, 1.0 });
        push_colors = true
    else
        -- Normal keys: gray
        imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.2, 0.2, 0.2, 1.0 });
        push_colors = true
    end
    
    -- Only allow clicking if not blocked
    local button_clicked = false
    if is_blocked then
        -- Disabled button - still render but don't handle clicks
        imgui.Button(key, { width, 30 });
    else
        button_clicked = imgui.Button(key, { width, 30 });
    end
    
    if button_clicked then
        -- Handle key click - for now just visual feedback
        keyboard_ui.binding_key[1] = key:upper();
        keyboard_ui.error_message = '';
        clicked = true
    end
    
    -- Pop style colors only if we pushed them
    if push_colors then
        imgui.PopStyleColor(3);
    end
    if push_alpha then
        imgui.PopStyleVar();
    end
    
    return clicked
end

-- Function to render the virtual keyboard
local function render_virtual_keyboard()
    for row_index, row in ipairs(keyboard_layout) do
        local first_key = true
        for _, key_data in ipairs(row) do
            local key = key_data[1]
            local width = key_data[2]
            
            if not first_key then
                imgui.SameLine();
            end
            first_key = false
            
            render_key_button(key, width)
        end
    end
end

-- Helper: Generate macro filename based on profile + modifiers + key
local function get_macro_filename(profile_base, key, shift, alt, ctrl)
    profile_base = profile_base:gsub('%.txt$', '')
    local mod = ''
    if ctrl then mod = mod .. '^' end
    if alt then mod = mod .. '!' end
    if shift then mod = mod .. '+' end
    return string.format('%s_%s%s.txt', profile_base, mod, key)
end

-- Function to validate key binding and set error message
local function validate_key_binding()
    keyboard_ui.error_message = ''
    
    if keyboard_ui.binding_key[1] == '' then
        return true
    end
    
    local modifiers = {}
    if keyboard_ui.shift_modifier[1] then table.insert(modifiers, 'Shift') end
    if keyboard_ui.alt_modifier[1] then table.insert(modifiers, 'Alt') end
    if keyboard_ui.ctrl_modifier[1] then table.insert(modifiers, 'Ctrl') end
    local modifier_string = table.concat(modifiers, '+')
    
    local is_blocked, error_msg = blocked_keybinds.is_combination_blocked(keyboard_ui.binding_key[1], modifier_string)
    if is_blocked then
        keyboard_ui.error_message = error_msg or blocked_keybinds.get_block_reason(keyboard_ui.binding_key[1], modifier_string)
        return false
    end
    
    return true
end

-- Function to generate bind command string from binding data
local function generate_bind_command(binding)
    local key_part = binding.key
    
    if binding.modifiers and binding.modifiers ~= '' then
        for modifier in binding.modifiers:gmatch('[^+]+') do
            if modifier == 'Ctrl' then
                key_part = '^' .. key_part
            elseif modifier == 'Alt' then
                key_part = '!' .. key_part
            elseif modifier == 'Shift' then
                key_part = '+' .. key_part
            end
        end
    end
    
    local command = binding.command
    if command:sub(1, 1) ~= '/' then
        command = '/' .. command
    end
    
    return string.format('/bind %s "%s"', key_part, command)
end

-- Function to render the binding editor (right side content from config_ui)
local function render_binding_editor()
    if imgui.Button('New', { 86, 0 }) then
        keyboard_ui.selected_binding = -1;
        keyboard_ui.binding_key[1] = '';
        keyboard_ui.shift_modifier[1] = false;
        keyboard_ui.alt_modifier[1] = false;
        keyboard_ui.ctrl_modifier[1] = false;
        keyboard_ui.command_text[1] = '';
        keyboard_ui.is_macro[1] = false;
        keyboard_ui.macro_text[1] = '';
        keyboard_ui.is_binding = false;
        keyboard_ui.error_message = '';
    end
    
    imgui.SameLine();
    
    if imgui.Button('Save', { 86, 0 }) then
        -- For now, just show a message since this is non-functional
        print('[JobBinds-KB] Save button clicked (non-functional UI)')
    end
    
    imgui.SameLine();
    
    if imgui.Button('Delete', { 86, 0 }) then
        -- For now, just show a message since this is non-functional
        print('[JobBinds-KB] Delete button clicked (non-functional UI)')
    end
    
    imgui.SameLine();
    if imgui.Checkbox('Ctrl', keyboard_ui.ctrl_modifier) then
        validate_key_binding();
    end
    
    imgui.SameLine();
    if imgui.Checkbox('Alt', keyboard_ui.alt_modifier) then
        validate_key_binding();
    end
    
    imgui.SameLine();
    if imgui.Checkbox('Shift', keyboard_ui.shift_modifier) then
        validate_key_binding();
    end
    
    if keyboard_ui.error_message ~= '' then
        imgui.Spacing();
        imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.3, 0.3, 1.0 });
        imgui.Text('Error: ' .. keyboard_ui.error_message);
        imgui.PopStyleColor();
    end
    
    imgui.Spacing();
    imgui.Spacing();
    
    imgui.Text('Command:');
    imgui.SameLine();
    
    if keyboard_ui.is_macro[1] then
        imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.6);
    end
    
    imgui.SetNextItemWidth(330);
    imgui.InputText('##command_text', keyboard_ui.command_text, 256, keyboard_ui.is_macro[1] and ImGuiInputTextFlags_ReadOnly or ImGuiInputTextFlags_None);
    
    if keyboard_ui.is_macro[1] then
        imgui.PopStyleVar();
    end
    
    imgui.SameLine();
    imgui.Checkbox('Macro', keyboard_ui.is_macro);
    
    if keyboard_ui.is_macro[1] then
        imgui.Spacing();
        imgui.InputTextMultiline('##macro_text', keyboard_ui.macro_text, 2048, { -1, 200 });
    end
    
    -- Key binding detection (simplified for demo)
    if keyboard_ui.is_binding then
        for key_code = 1, 255 do
            local ok, is_pressed = pcall(function() return imgui.IsKeyPressed(key_code) end)
            if ok and is_pressed then
                local key_name = vk_codes.get_key_name(key_code);
                if vk_codes.is_known_key(key_code) then
                    keyboard_ui.binding_key[1] = key_name;
                    keyboard_ui.is_binding = false;
                    validate_key_binding();
                    if keyboard_ui.debug_mode then
                        print('[JobBinds-KB] Detected key: ' .. key_name .. ' (code: ' .. key_code .. ')');
                    end
                else
                    keyboard_ui.binding_key[1] = 'KEY_' .. key_code;
                    keyboard_ui.is_binding = false;
                    validate_key_binding();
                    if keyboard_ui.debug_mode then
                        print('[JobBinds-KB] Detected unknown key code: ' .. key_code);
                    end
                end
                break;
            end
        end
        local ok, is_pressed = pcall(function() return imgui.IsKeyPressed(27) end)
        if ok and is_pressed then
            keyboard_ui.is_binding = false;
            if keyboard_ui.debug_mode then
                print('[JobBinds-KB] Escape pressed, canceling binding');
            end
        end
    end
end

-- Main render function
function keyboard_ui.render()
    if not keyboard_ui.is_open[1] then
        return
    end

    -- Set window size and flags
    imgui.SetNextWindowSize({ 508, -1 });
    
    if imgui.Begin('JobBinds Keyboard Interface', keyboard_ui.is_open, ImGuiWindowFlags_None) then
        -- Virtual keyboard on top
        render_virtual_keyboard();
        
        -- Horizontal divider
        imgui.Separator();
        
        -- Binding editor on bottom
        render_binding_editor();
    end
    imgui.End();
end

function keyboard_ui.show()
    keyboard_ui.is_open[1] = true;
end

function keyboard_ui.hide()
    keyboard_ui.is_open[1] = false;
end

function keyboard_ui.toggle()
    keyboard_ui.is_open[1] = not keyboard_ui.is_open[1];
end

function keyboard_ui.set_current_profile(profile_name)
    keyboard_ui.current_profile = profile_name or 'No Profile Loaded';
end

function keyboard_ui.load_bindings(bindings)
    current_bindings = bindings or {};
end

function keyboard_ui.set_debug_mode(enabled)
    keyboard_ui.debug_mode = enabled;
end

return keyboard_ui;
