require('common');
local chat = require('chat');
local imgui = require('imgui');
local vk_codes = require('vk_codes');
local blocked_keybinds = require('blocked_keybinds');
local ui_functions = require('ui_functions');

-- Custom print functions
local function printf(fmt, ...) print(chat.header('JobBinds') .. chat.message(fmt:format(...))) end
local function errorf(fmt, ...) print(chat.header('JobBinds') .. chat.error(fmt:format(...))) end

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
keyboard_ui.global = { false };

-- Current bindings loaded from profile files
local current_bindings = {};  -- Job-specific bindings
local global_bindings = {};   -- Global bindings from JobBinds.txt
local combined_bindings = {}; -- Merged bindings (global overrides job-specific)
local current_profile_path = nil;
local global_profile_path = nil;

-- ============================================================================
-- GLOBAL BINDINGS HELPER FUNCTIONS (Must be defined early for use in render functions)
-- ============================================================================

-- Helper: Get path to global bindings file (JobBinds.txt)
local function get_global_bindings_path()
    return string.format('%s/scripts/JobBinds.txt', AshitaCore:GetInstallPath());
end

-- Helper: Ensure global bindings file exists
local function ensure_global_bindings_file()
    local global_path = get_global_bindings_path();
    local file = io.open(global_path, 'r');
    if not file then
        -- Create empty global bindings file
        file = io.open(global_path, 'w');
        if file then
            file:write('# JobBinds Global Bindings\n');
            file:write('\n');
            file:close();
        end
    else
        file:close();
    end
end

-- Helper: Load global bindings from JobBinds.txt
local function load_global_bindings()
    ensure_global_bindings_file();
    local global_path = get_global_bindings_path();
    local bindings = ui_functions.load_bindings_from_profile(global_path, keyboard_ui.debug_mode);
    
    -- Mark all bindings as global
    for _, binding in ipairs(bindings) do
        binding.is_global = true;
    end
    
    return bindings;
end

-- Helper: Check if any global binding exists on a key (any modifier combination)
local function has_global_binding_on_key(key)
    for _, binding in ipairs(global_bindings) do
        if binding.key:upper() == key:upper() then
            return true;
        end
    end
    return false;
end

-- Helper: Merge global and job-specific bindings (global overrides job-specific)
local function merge_bindings()
    local merged = {};
    local added_keys = {}; -- Track key+modifier combinations
    
    -- Add global bindings first (they take precedence)
    for _, binding in ipairs(global_bindings) do
        local key_id = binding.key:upper() .. '|' .. (binding.modifiers or '');
        binding.is_global = true; -- Ensure global flag is set
        merged[#merged + 1] = binding;
        added_keys[key_id] = true;
    end
    
    -- Add job-specific bindings that don't conflict with global
    for _, binding in ipairs(current_bindings) do
        local key_id = binding.key:upper() .. '|' .. (binding.modifiers or '');
        if not added_keys[key_id] then
            binding.is_global = false; -- Explicitly ensure job-specific bindings are NOT global
            merged[#merged + 1] = binding;
            added_keys[key_id] = true;
        end
    end
    
    return merged;
end

-- ============================================================================
-- KEYBOARD LAYOUT AND UI FUNCTIONS
-- ============================================================================

-- Virtual keyboard layout definition
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
}

-- Function to validate filename doesn't contain invalid characters
local function has_invalid_filename_chars(filename)
    if not filename or filename == '' then
        return false
    end
    -- Check for Windows invalid filename characters: \ / : * ? " < > | and spaces
    return filename:match('[\\/:*?"<>| ]') ~= nil
end

-- Function to refresh the list of available script files
local function refresh_scripts_list()
    keyboard_ui.available_scripts = {};
    local scripts_path = ui_functions.get_scripts_path();
    
    -- Helper function to check if file is a job binding profile (JOB_JOB.txt format)
    local function is_job_binding_file(filename)
        return filename:match('^[A-Z][A-Z][A-Z]_[A-Z][A-Z][A-Z]%.txt$') ~= nil;
    end
    
    -- Helper function to check if file should be ignored
    local function is_ignored_file(filename)
        local lower = filename:lower();
        return lower == 'default.txt' or lower == 'launcher.txt' or lower == 'jobbinds.txt';
    end
    
    -- Use Lua's lfs library if available, otherwise use a simple file list
    local ok, lfs = pcall(require, 'lfs');
    if ok then
        -- Use lfs to list directory (wrapped in pcall to handle missing directory)
        local dir_ok, dir_iter, dir_obj = pcall(lfs.dir, scripts_path);
        if dir_ok and dir_iter then
            for file in dir_iter, dir_obj do
                if file:match('%.txt$') and not is_job_binding_file(file) and not is_ignored_file(file) then
                    table.insert(keyboard_ui.available_scripts, file);
                end
            end
        end
    else
        -- Fallback: Try to execute dir command and parse output
        -- This is Windows-specific
        local handle = io.popen('dir "' .. scripts_path .. '\\*.txt" /B 2>nul');
        if handle then
            for file in handle:lines() do
                if file:match('%.txt$') and not is_job_binding_file(file) and not is_ignored_file(file) then
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
    
    -- Check if this key is bound (check combined bindings)
    local is_bound = false
    local is_global_bound = false
    local binding_count = 0
    local global_binding_count = 0
    
    for _, binding in ipairs(combined_bindings) do
        if binding.key:upper() == key:upper() then
            is_bound = true
            binding_count = binding_count + 1
            -- Check if ANY binding on this key is global
            -- If so, all bindings on the key should be global (per requirements)
            if binding.is_global == true then  -- Explicit check for true value
                is_global_bound = true
                global_binding_count = global_binding_count + 1
            end
        end
    end
    
    -- Additional safety: double-check global status against global_bindings array
    if is_global_bound then
        local confirmed_global = false
        for _, global_binding in ipairs(global_bindings) do
            if global_binding.key:upper() == key:upper() then
                confirmed_global = true
                break
            end
        end
        if not confirmed_global then
            errorf('[BUG] Key %s marked as global but not in global_bindings', key)
            is_global_bound = false  -- Correct the error
        end
    end
    
    -- Debug: If we have mixed global/job bindings, that's a bug
    if binding_count > 0 and global_binding_count > 0 and global_binding_count < binding_count then
        errorf('[BUG] Key %s has mixed bindings: %d total, %d global', key, binding_count, global_binding_count)
    end
    
    -- Style the button based on status: blocked > selected > global > bound > normal
    -- Push colors, render button, pop colors immediately to prevent leaks
    local button_clicked = false
    local colors_pushed = 0  -- Track number of colors pushed
    
    if is_blocked then
        -- Blocked keys: dark red/disabled appearance
        imgui.PushStyleColor(ImGuiCol_Button, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.5);
        colors_pushed = 3
        button_clicked = imgui.Button(key, { width, 30 });
        imgui.PopStyleVar();
        imgui.PopStyleColor(3);
        colors_pushed = 0
    elseif keyboard_ui.binding_key[1] ~= '' and keyboard_ui.binding_key[1]:upper() == key:upper() then
        -- Selected key: green (active binding being edited)
        imgui.PushStyleColor(ImGuiCol_Button, { 0.1, 0.6, 0.1, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.15, 0.7, 0.15, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.08, 0.5, 0.08, 1.0 });
        colors_pushed = 3
        button_clicked = imgui.Button(key, { width, 30 });
        imgui.PopStyleColor(3);
        colors_pushed = 0
    elseif is_global_bound then
        -- Global bound keys: blue
        imgui.PushStyleColor(ImGuiCol_Button, { 0.1, 0.3, 0.7, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.15, 0.4, 0.8, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.08, 0.25, 0.6, 1.0 });
        colors_pushed = 3
        button_clicked = imgui.Button(key, { width, 30 });
        imgui.PopStyleColor(3);
        colors_pushed = 0
    elseif is_bound then
        -- Bound keys: default ImGui styling (standard red button color)
        button_clicked = imgui.Button(key, { width, 30 });
    else
        -- Normal keys: gray
        imgui.PushStyleColor(ImGuiCol_Button, { 0.3, 0.3, 0.3, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.4, 0.4, 1.0 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.2, 0.2, 0.2, 1.0 });
        colors_pushed = 3
        button_clicked = imgui.Button(key, { width, 30 });
        imgui.PopStyleColor(3);
        colors_pushed = 0
    end
    
    -- Safety check: ensure no styles are leaked
    if colors_pushed > 0 then
        errorf('[STYLE LEAK] %d colors still pushed after rendering key %s', colors_pushed, key);
        imgui.PopStyleColor(colors_pushed);
    end
    
    -- Show tooltip on hover if key has bindings
    if is_bound and imgui.IsItemHovered() then
        local tooltip_lines = {};
        for _, binding in ipairs(combined_bindings) do
            if binding.key:upper() == key:upper() then
                local modifier_text = binding.modifiers ~= '' and (binding.modifiers .. ' + ') or '';
                local global_marker = binding.is_global and ' [GLOBAL]' or '';
                table.insert(tooltip_lines, modifier_text .. binding.key .. ': ' .. binding.command .. global_marker);
            end
        end
        if #tooltip_lines > 0 then
            imgui.SetTooltip(table.concat(tooltip_lines, '\n'));
        end
    end
    
    if button_clicked then
        -- Use pcall to ensure style pop happens even if there's an error
        local success, err = pcall(function()
            -- Handle key click - populate UI with existing bindings for all modifier combinations
            keyboard_ui.binding_key[1] = key:upper();
            keyboard_ui.error_message = '';
            
            -- Helper function to load binding data for a specific modifier combination
            local function load_modifier_binding(has_ctrl, has_alt, has_shift)
                local cmd_text, is_macro, macro_text
                
                -- Find existing binding for this key+modifier combination (check combined bindings)
                local existing_binding = nil
                for _, binding in ipairs(combined_bindings) do
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
            
            -- Set Global checkbox based on whether key has any global bindings
            keyboard_ui.global[1] = has_global_binding_on_key(key:upper());
        end)
        
        if not success then
            -- Log error but don't crash
            errorf('Error handling key click: %s', tostring(err))
        end
        
        clicked = true
    end
    
    return clicked
end

-- Function to render the virtual keyboard
local function render_virtual_keyboard()
    -- Get the initial style color stack depth (if available)
    local initial_stack_depth = 0
    
    for row_index, row in ipairs(keyboard_layout) do
        local first_key = true
        for _, key_data in ipairs(row) do
            local key = key_data[1]
            local width = key_data[2]
            
            if not first_key then
                imgui.SameLine();
            end
            first_key = false
            
            -- Render each key button
            render_key_button(key, width)
        end
    end
    
    -- Ensure no style colors are left on the stack after rendering keyboard
    -- This is a safety check - all keys should pop their own colors
    -- Note: ImGui doesn't provide a way to check stack depth in Lua, so we rely on
    -- the per-key safety checks in render_key_button
end

-- Function to save current bindings for all modifier combinations
local function save_current_binding()
    if keyboard_ui.binding_key[1] == '' then
        keyboard_ui.error_message = 'No key selected'
        return false
    end
    
    -- Check if trying to save job-specific binding on a key with global bindings
    if not keyboard_ui.global[1] and has_global_binding_on_key(keyboard_ui.binding_key[1]) then
        keyboard_ui.error_message = 'Cannot create job-specific binding: Key has global binding(s)';
        errorf('Cannot create job-specific binding on %s: Key has global binding(s)', keyboard_ui.binding_key[1]);
        return false;
    end
    
    local all_success = true
    local last_error = ''
    
    -- Determine which profile path and binding array to use
    local target_profile_path = keyboard_ui.global[1] and global_profile_path or current_profile_path;
    local target_bindings = keyboard_ui.global[1] and global_bindings or current_bindings;
    
    -- Helper function to save a single modifier combination
    local function save_modifier_binding(cmd_text, is_macro, macro_text, has_ctrl, has_alt, has_shift)
        local binding_data = {
            key = keyboard_ui.binding_key[1],
            command = cmd_text,
            is_macro = is_macro,
            macro_text = macro_text,
            shift_modifier = has_shift,
            alt_modifier = has_alt,
            ctrl_modifier = has_ctrl,
            is_global = keyboard_ui.global[1]
        }
        
        -- If no command is set, delete the binding instead of saving
        if cmd_text == '' then
            local success, error_msg = ui_functions.delete_current_binding(binding_data, target_bindings, target_profile_path, keyboard_ui.debug_mode)
            -- If no binding was found, that's okay (nothing to delete)
            if not success and error_msg ~= 'No binding found for this key combination' then
                last_error = error_msg
                return false
            end
            return true
        end
        
        local success, error_msg = ui_functions.save_current_binding(binding_data, target_bindings, target_profile_path, keyboard_ui.debug_mode)
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
    
    -- Update the appropriate binding array
    if keyboard_ui.global[1] then
        global_bindings = target_bindings;
    else
        current_bindings = target_bindings;
    end
    
    -- Re-merge bindings
    combined_bindings = merge_bindings();
    
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
    
    -- Determine which profile path and binding array to use
    local target_profile_path = keyboard_ui.global[1] and global_profile_path or current_profile_path;
    local target_bindings = keyboard_ui.global[1] and global_bindings or current_bindings;
    
    -- Helper function to delete a single modifier combination
    local function delete_modifier_binding(has_ctrl, has_alt, has_shift)
        local binding_data = {
            key = keyboard_ui.binding_key[1],
            shift_modifier = has_shift,
            alt_modifier = has_alt,
            ctrl_modifier = has_ctrl,
            is_global = keyboard_ui.global[1]
        }
        
        local success, error_msg = ui_functions.delete_current_binding(binding_data, target_bindings, target_profile_path, keyboard_ui.debug_mode)
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
    
    -- Update the appropriate binding array
    if keyboard_ui.global[1] then
        global_bindings = target_bindings;
    else
        current_bindings = target_bindings;
    end
    
    -- Re-merge bindings
    combined_bindings = merge_bindings();
    
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
        
        -- Clear button aligned at fixed position
        imgui.SetCursorPosX(112); -- Align Clear Button
        if imgui.Button('X##clear_' .. label, { 20, 0 }) then
            cmd_text[1] = '';
            is_macro[1] = false;
            macro_text[1] = '';
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Clear binding');
        end
        imgui.SameLine();
        
        -- Align to the label width
        imgui.SetCursorPosX(label_width);
        
        -- Check for invalid filename characters when in macro mode
        local has_invalid_chars = is_macro[1] and has_invalid_filename_chars(cmd_text[1]);
        
        -- Set text color to red if invalid characters in macro mode
        if has_invalid_chars then
            imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.3, 0.3, 1.0 });
        end
        
        -- Command text field (always editable, used for filename when macro mode)
        imgui.SetNextItemWidth(389); -- Align Command Text Width
        imgui.InputText('##cmd_' .. label, cmd_text, 256, ImGuiInputTextFlags_None);
        
        -- Show tooltip if invalid characters detected
        if has_invalid_chars and imgui.IsItemHovered() then
            imgui.SetTooltip('A file name can\'t contain any of the following characters:\n\\ / : * ? " < > | or spaces');
        end
        
        if has_invalid_chars then
            imgui.PopStyleColor();
        end
        
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
            imgui.InputTextMultiline('##macro_' .. label .. '_text', macro_text, 2048, { 421, 100 }); -- Align Macro Text Width
        end
    end
    
    -- Calculate label width for alignment
    local label_width = 136 -- Align Label Width
    
    -- Show prompt if no key is selected
    if keyboard_ui.binding_key[1] == '' then
        imgui.Spacing();
        imgui.Text('Click a button on the keyboard to apply a key binding');
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
    
    -- Render the 4 binding rows with headers
    imgui.Spacing();
    imgui.Text('Binding');
    imgui.SameLine();
    imgui.SetCursorPosX(135); -- Above the X button
    imgui.Text('Command');
    imgui.SameLine();
    imgui.SetCursorPosX(label_width + 373); -- Align Macro Text
    imgui.Text('Macro');
    
    imgui.Spacing();
    
    -- [KEY]
    if show_none then
        render_binding_row(keyboard_ui.binding_key[1]..'    ', 
                           keyboard_ui.command_text_none, 
                           keyboard_ui.is_macro_none, 
                           keyboard_ui.macro_text_none, 
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
    
    imgui.Spacing();
    
    -- Check if any macro bindings have invalid filename characters
    local has_any_invalid = false;
    if keyboard_ui.is_macro_none[1] and has_invalid_filename_chars(keyboard_ui.command_text_none[1]) then
        has_any_invalid = true;
    end
    if keyboard_ui.is_macro_ctrl[1] and has_invalid_filename_chars(keyboard_ui.command_text_ctrl[1]) then
        has_any_invalid = true;
    end
    if keyboard_ui.is_macro_alt[1] and has_invalid_filename_chars(keyboard_ui.command_text_alt[1]) then
        has_any_invalid = true;
    end
    if keyboard_ui.is_macro_shift[1] and has_invalid_filename_chars(keyboard_ui.command_text_shift[1]) then
        has_any_invalid = true;
    end
    
    -- Disable and gray out Save button if invalid characters detected
    if has_any_invalid then
        imgui.PushStyleColor(ImGuiCol_Button, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.4, 0.1, 0.1, 0.6 });
        imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.5);
    end
    
    -- Save and Delete buttons at the bottom
    local save_clicked = imgui.Button('Save', { 120, 0 });
    
    -- Show tooltip on disabled Save button
    if has_any_invalid and imgui.IsItemHovered() then
        imgui.SetTooltip('A file name can\'t contain any of the following characters:\n\\ / : * ? " < > | or spaces');
    end
    
    if has_any_invalid then
        imgui.PopStyleVar();
        imgui.PopStyleColor(3);
    end
    
    if save_clicked and not has_any_invalid then
        if save_current_binding() then
            printf('Bindings saved successfully')
        else
            errorf('Failed to save bindings')
        end
    end
    
    imgui.SameLine();
    
    if imgui.Button('Delete', { 120, 0 }) then
        if delete_current_binding() then
            printf('Bindings deleted successfully')
        else
            errorf('Failed to delete bindings')
        end
    end
    
    imgui.SameLine();
    imgui.Checkbox('Global', keyboard_ui.global);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Save binding to JobBinds.txt (global across all jobs).\nGlobal bindings override job-specific bindings.\nKeys with global bindings cannot have job-specific bindings.');
    end
    
    -- Display current profile/job combination
    imgui.SameLine();
    imgui.Dummy({ 128, 0 }); -- Move right 116px
    imgui.SameLine();
    local profile_display = keyboard_ui.current_profile or 'No Profile Loaded';
    -- Convert WAR_NIN.txt format to WAR/NIN display
    profile_display = profile_display:gsub('%.txt$', ''):gsub('_', '/');
    imgui.Text(profile_display);
    
    -- Display error message if present
    if keyboard_ui.error_message ~= '' then
        imgui.Spacing();
        imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.3, 0.3, 1.0 });
        imgui.Text(keyboard_ui.error_message);
        imgui.PopStyleColor();
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
                        printf('[DEBUG] Detected key: %s (code: %d)', key_name, key_code);
                    end
                else
                    keyboard_ui.binding_key[1] = 'KEY_' .. key_code;
                    keyboard_ui.is_binding = false;
                    if keyboard_ui.debug_mode then
                        printf('[DEBUG] Detected unknown key code: %d', key_code);
                    end
                end
                break;
            end
        end
        local ok, is_pressed = pcall(function() return imgui.IsKeyPressed(27) end)
        if ok and is_pressed then
            keyboard_ui.is_binding = false;
            if keyboard_ui.debug_mode then
                printf('[DEBUG] Escape pressed, canceling binding');
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
    if imgui.Begin('JobBinds', keyboard_ui.is_open, ImGuiWindowFlags_AlwaysAutoResize) then
        -- Virtual keyboard on top
        render_virtual_keyboard();
        
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
    -- Load job-specific bindings
    current_bindings = ui_functions.load_bindings_from_profile(profile_path, keyboard_ui.debug_mode);
    
    -- Ensure job-specific bindings are NOT marked as global
    for _, binding in ipairs(current_bindings) do
        binding.is_global = false;
    end
    
    current_profile_path = profile_path;
    
    -- Load global bindings
    global_bindings = load_global_bindings();
    global_profile_path = get_global_bindings_path();
    
    -- Merge bindings (global overrides job-specific)
    combined_bindings = merge_bindings();
    
    -- Debug: Count global vs total bindings
    if keyboard_ui.debug_mode then
        local global_count = 0;
        for _, binding in ipairs(combined_bindings) do
            if binding.is_global then
                global_count = global_count + 1;
            end
        end
        printf('[DEBUG] Bindings loaded - Total: %d, Global: %d, Job-specific: %d', 
               #combined_bindings, global_count, #combined_bindings - global_count);
    end
end

function keyboard_ui.load_bindings(bindings)
    current_bindings = bindings or {};
    
    -- Ensure job-specific bindings are NOT marked as global
    for _, binding in ipairs(current_bindings) do
        binding.is_global = false;
    end
    
    -- Also reload global bindings and merge
    global_bindings = load_global_bindings();
    combined_bindings = merge_bindings();
end

function keyboard_ui.set_debug_mode(enabled)
    keyboard_ui.debug_mode = enabled;
end

-- Get global bindings path (for external access)
function keyboard_ui.get_global_bindings_path()
    return get_global_bindings_path();
end

-- Check if key has global binding (for external access)
function keyboard_ui.has_global_binding_on_key(key)
    return has_global_binding_on_key(key);
end

return keyboard_ui;
