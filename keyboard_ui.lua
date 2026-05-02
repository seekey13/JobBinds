require('common');
local imgui = require('imgui');
local vk_codes = require('vk_codes');
local blocked_keybinds = require('blocked_keybinds');
local ui_functions = require('ui_functions');

-- UI state variables
local keyboard_ui = {};
keyboard_ui.is_open = { false };
keyboard_ui.selected_binding = -1;
keyboard_ui.binding_key = { '' };

-- Separate state for each modifier combination
keyboard_ui.command_text_none = { '' };
keyboard_ui.is_macro_none = { false };
keyboard_ui.macro_text_none = { '' };

keyboard_ui.command_text_ctrl = { '' };
keyboard_ui.is_macro_ctrl = { false };
keyboard_ui.macro_text_ctrl = { '' };

keyboard_ui.command_text_alt = { '' };
keyboard_ui.is_macro_alt = { false };
keyboard_ui.macro_text_alt = { '' };

keyboard_ui.command_text_shift = { '' };
keyboard_ui.is_macro_shift = { false };
keyboard_ui.macro_text_shift = { '' };

-- Script list state
keyboard_ui.available_scripts = {};
keyboard_ui.selected_script_index = { 0 };
keyboard_ui.last_scripts_refresh = 0;

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

-- Function to refresh the list of available script files
local function refresh_scripts_list()
    keyboard_ui.available_scripts = {};
    local scripts_path = ui_functions.get_scripts_path();
    
    -- Helper function to check if file is a job binding profile (JOB_JOB.txt format)
    local function is_job_binding_file(filename)
        return filename:match('^[A-Z][A-Z][A-Z]_[A-Z][A-Z][A-Z]%.txt$') ~= nil;
    end
    
    -- Use Lua's lfs library if available, otherwise use a simple file list
    local ok, lfs = pcall(require, 'lfs');
    if ok then
        -- Use lfs to list directory
        for file in lfs.dir(scripts_path) do
            if file:match('%.txt$') and not is_job_binding_file(file) then
                table.insert(keyboard_ui.available_scripts, file);
            end
        end
    else
        -- Fallback: Try to execute dir command and parse output
        -- This is Windows-specific
        local handle = io.popen('dir "' .. scripts_path .. '\\*.txt" /B 2>nul');
        if handle then
            for file in handle:lines() do
                if file:match('%.txt$') and not is_job_binding_file(file) then
                    table.insert(keyboard_ui.available_scripts, file);
                end
            end
            handle:close();
        end
    end
    
    -- Sort alphabetically
    table.sort(keyboard_ui.available_scripts);
    keyboard_ui.last_scripts_refresh = os.time();
end

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
        -- Bound keys: green (darker)
        imgui.PushStyleColor(ImGuiCol_Button, { 0.1, 0.6, 0.1, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.15, 0.7, 0.15, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.08, 0.5, 0.08, 1.0 });
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
        -- Handle key click - populate UI with existing bindings for all modifier combinations
        keyboard_ui.binding_key[1] = key:upper();
        keyboard_ui.error_message = '';
        
        -- Helper function to load binding data for a specific modifier combination
        local function load_modifier_binding(has_ctrl, has_alt, has_shift)
            local cmd_text, is_macro, macro_text
            
            -- Find existing binding for this key+modifier combination
            local existing_binding = nil
            for _, binding in ipairs(current_bindings) do
                if binding.key:upper() == key:upper() then
                    local modifiers = binding.modifiers or ''
                    local bind_has_ctrl = modifiers:find('Ctrl') ~= nil
                    local bind_has_alt = modifiers:find('Alt') ~= nil
                    local bind_has_shift = modifiers:find('Shift') ~= nil
                    
                    if bind_has_ctrl == has_ctrl and bind_has_alt == has_alt and bind_has_shift == has_shift then
                        existing_binding = binding
                        break
                    end
                end
            end
            
            if existing_binding then
                cmd_text = existing_binding.command or ''
                is_macro = existing_binding.is_macro or false
                macro_text = ''
                
                -- Load macro content if it's a macro
                if existing_binding.is_macro and existing_binding.command:match('^/exec%s+(.+)$') then
                    local macro_name = existing_binding.command:match('^/exec%s+(.+)$')
                    local macro_path = string.format('%s/%s', ui_functions.get_scripts_path(), macro_name)
                    if not macro_path:match('%.txt$') then
                        macro_path = macro_path .. '.txt'
                    end
                    
                    local macro_file = io.open(macro_path, 'r')
                    if macro_file then
                        macro_text = macro_file:read('*all') or ''
                        macro_file:close()
                    end
                    
                    -- Set command to just the macro name for display
                    cmd_text = macro_name:gsub('%.txt$', '')
                end
            else
                -- No binding exists for this combination
                cmd_text = ''
                is_macro = false
                macro_text = ''
            end
            
            return cmd_text, is_macro, macro_text
        end
        
        -- Load all 4 modifier combinations
        keyboard_ui.command_text_none[1], keyboard_ui.is_macro_none[1], keyboard_ui.macro_text_none[1] = 
            load_modifier_binding(false, false, false)
        
        -- Check if modifier combinations are valid for this key before loading
        local is_valid_ctrl, _ = ui_functions.validate_key_binding(key:upper(), false, false, true)
        local is_valid_alt, _ = ui_functions.validate_key_binding(key:upper(), false, true, false)
        local is_valid_shift, _ = ui_functions.validate_key_binding(key:upper(), true, false, false)
        
        if is_valid_ctrl then
            keyboard_ui.command_text_ctrl[1], keyboard_ui.is_macro_ctrl[1], keyboard_ui.macro_text_ctrl[1] = 
                load_modifier_binding(true, false, false)
        else
            keyboard_ui.command_text_ctrl[1] = ''
            keyboard_ui.is_macro_ctrl[1] = false
            keyboard_ui.macro_text_ctrl[1] = ''
        end
        
        if is_valid_alt then
            keyboard_ui.command_text_alt[1], keyboard_ui.is_macro_alt[1], keyboard_ui.macro_text_alt[1] = 
                load_modifier_binding(false, true, false)
        else
            keyboard_ui.command_text_alt[1] = ''
            keyboard_ui.is_macro_alt[1] = false
            keyboard_ui.macro_text_alt[1] = ''
        end
        
        if is_valid_shift then
            keyboard_ui.command_text_shift[1], keyboard_ui.is_macro_shift[1], keyboard_ui.macro_text_shift[1] = 
                load_modifier_binding(false, false, true)
        else
            keyboard_ui.command_text_shift[1] = ''
            keyboard_ui.is_macro_shift[1] = false
            keyboard_ui.macro_text_shift[1] = ''
        end
        
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

-- Function to save current bindings for all modifier combinations
local function save_current_binding()
    if keyboard_ui.binding_key[1] == '' then
        keyboard_ui.error_message = 'No key selected'
        return false
    end
    
    local all_success = true
    local last_error = ''
    
    -- Helper function to save a single modifier combination
    local function save_modifier_binding(cmd_text, is_macro, macro_text, has_ctrl, has_alt, has_shift)
        -- Skip if no command is set
        if cmd_text == '' then
            return true
        end
        
        local binding_data = {
            key = keyboard_ui.binding_key[1],
            command = cmd_text,
            is_macro = is_macro,
            macro_text = macro_text,
            shift_modifier = has_shift,
            alt_modifier = has_alt,
            ctrl_modifier = has_ctrl
        }
        
        local success, error_msg = ui_functions.save_current_binding(binding_data, current_bindings, current_profile_path, keyboard_ui.debug_mode)
        if not success then
            last_error = error_msg
            return false
        end
        return true
    end
    
    -- Check which modifier combinations are valid for this key
    local is_valid_ctrl, _ = ui_functions.validate_key_binding(keyboard_ui.binding_key[1], false, false, true)
    local is_valid_alt, _ = ui_functions.validate_key_binding(keyboard_ui.binding_key[1], false, true, false)
    local is_valid_shift, _ = ui_functions.validate_key_binding(keyboard_ui.binding_key[1], true, false, false)
    
    -- Save all 4 modifier combinations (only if valid)
    if not save_modifier_binding(keyboard_ui.command_text_none[1], keyboard_ui.is_macro_none[1], 
                                  keyboard_ui.macro_text_none[1], false, false, false) then
        all_success = false
    end
    
    if is_valid_ctrl then
        if not save_modifier_binding(keyboard_ui.command_text_ctrl[1], keyboard_ui.is_macro_ctrl[1], 
                                      keyboard_ui.macro_text_ctrl[1], true, false, false) then
            all_success = false
        end
    end
    
    if is_valid_alt then
        if not save_modifier_binding(keyboard_ui.command_text_alt[1], keyboard_ui.is_macro_alt[1], 
                                      keyboard_ui.macro_text_alt[1], false, true, false) then
            all_success = false
        end
    end
    
    if is_valid_shift then
        if not save_modifier_binding(keyboard_ui.command_text_shift[1], keyboard_ui.is_macro_shift[1], 
                                      keyboard_ui.macro_text_shift[1], false, false, true) then
            all_success = false
        end
    end
    
    if not all_success then
        keyboard_ui.error_message = last_error
        return false
    end
    
    keyboard_ui.error_message = ''
    return true
end

-- Function to delete current bindings for all modifier combinations
local function delete_current_binding()
    if keyboard_ui.binding_key[1] == '' then
        keyboard_ui.error_message = 'No key selected'
        return false
    end
    
    local all_success = true
    local last_error = ''
    
    -- Helper function to delete a single modifier combination
    local function delete_modifier_binding(has_ctrl, has_alt, has_shift)
        local binding_data = {
            key = keyboard_ui.binding_key[1],
            shift_modifier = has_shift,
            alt_modifier = has_alt,
            ctrl_modifier = has_ctrl
        }
        
        local success, error_msg = ui_functions.delete_current_binding(binding_data, current_bindings, current_profile_path, keyboard_ui.debug_mode)
        if not success then
            last_error = error_msg
            return false
        end
        return true
    end
    
    -- Delete all 4 modifier combinations
    delete_modifier_binding(false, false, false)
    delete_modifier_binding(true, false, false)
    delete_modifier_binding(false, true, false)
    delete_modifier_binding(false, false, true)
    
    -- Clear UI
    keyboard_ui.binding_key[1] = ''
    keyboard_ui.command_text_none[1] = ''
    keyboard_ui.macro_text_none[1] = ''
    keyboard_ui.is_macro_none[1] = false
    keyboard_ui.command_text_ctrl[1] = ''
    keyboard_ui.macro_text_ctrl[1] = ''
    keyboard_ui.is_macro_ctrl[1] = false
    keyboard_ui.command_text_alt[1] = ''
    keyboard_ui.macro_text_alt[1] = ''
    keyboard_ui.is_macro_alt[1] = false
    keyboard_ui.command_text_shift[1] = ''
    keyboard_ui.macro_text_shift[1] = ''
    keyboard_ui.is_macro_shift[1] = false
    keyboard_ui.error_message = ''
    return true
end

-- Function to render the binding editor (right side content from config_ui)
local function render_binding_editor()
    -- Helper function to render a single modifier binding row
    local function render_binding_row(label, cmd_text, is_macro, macro_text, label_width)
        imgui.Text(label);
        imgui.SameLine();
        
        -- Align to the label width
        imgui.SetCursorPosX(label_width);
        
        -- Command text field (always editable, used for filename when macro mode)
        imgui.SetNextItemWidth(330); -- Align Command Text Width
        imgui.InputText('##cmd_' .. label, cmd_text, 256, ImGuiInputTextFlags_None);
        
        imgui.SameLine();
        
        -- Macro checkbox
        if imgui.Checkbox('##macro_' .. label, is_macro) then
            if is_macro[1] then
                -- Switching to macro mode
                -- Try to load existing macro content if filename is specified
                if cmd_text[1] ~= '' then
                    local macro_filename = cmd_text[1];
                    if not macro_filename:match('%.txt$') then
                        macro_filename = macro_filename .. '.txt';
                    end
                    local macro_path = string.format('%s/%s', ui_functions.get_scripts_path(), macro_filename);
                    local macro_file = io.open(macro_path, 'r');
                    if macro_file then
                        macro_text[1] = macro_file:read('*all') or '';
                        macro_file:close();
                    end
                end
            else
                -- Switching to command mode
                macro_text[1] = '';
            end
        end
        
        -- Show macro text editor if in macro mode
        if is_macro[1] then
            -- Refresh scripts list if needed (every 5 seconds)
            if os.time() - keyboard_ui.last_scripts_refresh > 5 then
                refresh_scripts_list();
            end
            
            -- Create a horizontal layout: script list on left, macro text on right
            -- Script list on the left
            imgui.BeginChild('##scripts_child_' .. label, { 120, 100 }, true);
            for i, script_name in ipairs(keyboard_ui.available_scripts) do
                local is_selected = (keyboard_ui.selected_script_index[1] == i);
                -- Display name without .txt extension
                local display_name = script_name:gsub('%.txt$', '');
                if imgui.Selectable(display_name, is_selected) then
                    keyboard_ui.selected_script_index[1] = i;
                    -- Load the selected script into the macro text field
                    local script_path = string.format('%s/%s', ui_functions.get_scripts_path(), script_name);
                    local script_file = io.open(script_path, 'r');
                    if script_file then
                        macro_text[1] = script_file:read('*all') or '';
                        script_file:close();
                        -- Also set the command text to the script name (without .txt)
                        cmd_text[1] = script_name:gsub('%.txt$', '');
                    end
                end
            end
            imgui.EndChild();
            
            imgui.SameLine();
            
            -- Macro text editor on the right
            imgui.SetNextItemWidth(400);
            imgui.InputTextMultiline('##macro_' .. label .. '_text', macro_text, 2048, { 362, 100 }); -- Align Macro Text Width
        end
    end
    
    -- Calculate label width for alignment
    local label_width = 136 -- Align Label Width
    
    -- Show prompt if no key is selected
    if keyboard_ui.binding_key[1] == '' then
        imgui.Spacing();
        imgui.Spacing();
        imgui.Text('Click a button on the keyboard to apply a key binding');
        imgui.Spacing();
        imgui.Spacing();
        return
    end
    
    -- Check which modifier combinations are valid for the selected key
    local show_none = true -- Always show base key
    local show_ctrl = false
    local show_alt = false
    local show_shift = false
    
    local is_valid_ctrl, _ = ui_functions.validate_key_binding(keyboard_ui.binding_key[1], false, false, true)
    local is_valid_alt, _ = ui_functions.validate_key_binding(keyboard_ui.binding_key[1], false, true, false)
    local is_valid_shift, _ = ui_functions.validate_key_binding(keyboard_ui.binding_key[1], true, false, false)
    
    show_ctrl = is_valid_ctrl
    show_alt = is_valid_alt
    show_shift = is_valid_shift
    
    -- Render the 4 binding rows with "Macro" header
    imgui.Text('Command:');
    imgui.SameLine();
    imgui.SetCursorPosX(label_width + 314); -- Align Macro Text
    imgui.Text('Macro');
    
    imgui.Spacing();
    
    -- [KEY]
    if show_none then
        render_binding_row(keyboard_ui.binding_key[1], 
                           keyboard_ui.command_text_none, 
                           keyboard_ui.is_macro_none, 
                           keyboard_ui.macro_text_none, 
                           label_width);
        imgui.Spacing();
    end
    
    -- + Ctrl
    if show_ctrl then
        render_binding_row('+ Ctrl', 
                           keyboard_ui.command_text_ctrl, 
                           keyboard_ui.is_macro_ctrl, 
                           keyboard_ui.macro_text_ctrl, 
                           label_width);
        imgui.Spacing();
    end
    
    -- + Alt
    if show_alt then
        render_binding_row('+ Alt', 
                           keyboard_ui.command_text_alt, 
                           keyboard_ui.is_macro_alt, 
                           keyboard_ui.macro_text_alt, 
                           label_width);
        imgui.Spacing();
    end
    
    -- + Shift
    if show_shift then
        render_binding_row('+ Shift', 
                           keyboard_ui.command_text_shift, 
                           keyboard_ui.is_macro_shift, 
                           keyboard_ui.macro_text_shift, 
                           label_width);
        imgui.Spacing();
    end
    
    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();
    
    -- Save and Delete buttons at the bottom
    if imgui.Button('Save', { 120, 0 }) then
        if save_current_binding() then
            print('[JobBinds-KB] Bindings saved successfully')
        else
            print('[JobBinds-KB] Failed to save bindings')
        end
    end
    
    imgui.SameLine();
    
    if imgui.Button('Delete', { 120, 0 }) then
        if delete_current_binding() then
            print('[JobBinds-KB] Bindings deleted successfully')
        else
            print('[JobBinds-KB] Failed to delete bindings')
        end
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
                    if keyboard_ui.debug_mode then
                        print('[JobBinds-KB] Detected key: ' .. key_name .. ' (code: ' .. key_code .. ')');
                    end
                else
                    keyboard_ui.binding_key[1] = 'KEY_' .. key_code;
                    keyboard_ui.is_binding = false;
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

    -- Window automatically sizes to content
    if imgui.Begin('JobBinds Keyboard Interface', keyboard_ui.is_open, ImGuiWindowFlags_AlwaysAutoResize) then
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
    -- Refresh scripts list when showing UI
    if keyboard_ui.last_scripts_refresh == 0 then
        refresh_scripts_list();
    end
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

function keyboard_ui.load_profile(profile_path)
    current_bindings = ui_functions.load_bindings_from_profile(profile_path, keyboard_ui.debug_mode);
    current_profile_path = profile_path;
end

function keyboard_ui.load_bindings(bindings)
    current_bindings = bindings or {};
end

function keyboard_ui.set_debug_mode(enabled)
    keyboard_ui.debug_mode = enabled;
end

return keyboard_ui;
