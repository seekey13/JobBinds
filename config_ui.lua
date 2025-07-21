require('common');
local imgui = require('imgui');
local vk_codes = require('vk_codes');

-- UI state variables
local config_ui = {};
config_ui.is_open = { false };
config_ui.selected_binding = -1;
config_ui.binding_key = { '' };
config_ui.shift_modifier = { false };
config_ui.alt_modifier = { false };
config_ui.ctrl_modifier = { false };
config_ui.command_text = { '' };
config_ui.is_macro = { false };
config_ui.macro_text = { '' };
config_ui.current_profile = 'No Profile Loaded';
config_ui.is_binding = false; -- Track if we're currently capturing a key
config_ui.debug_mode = false; -- Debug mode flag, controlled by main addon

-- Sample bindings for UI testing (will be replaced with actual data later)
local sample_bindings = {
    { key = 'F1', modifiers = '', command = '/ja "Cure" <t>' },
    { key = 'F2', modifiers = 'Ctrl', command = '/ja "Protect" <me>' },
    { key = 'F3', modifiers = 'Alt', command = '/ja "Shell" <me>' },
    { key = 'F4', modifiers = 'Shift', command = '/ja "Haste" <t>' },
    { key = '1', modifiers = 'Ctrl+Alt', command = '/ws "Fast Blade" <t>' },
};

-- Function to render the config window
function config_ui.render()
    if not config_ui.is_open[1] then
        return;
    end

    -- Set window size and flags
    imgui.SetNextWindowSize({ 600, 400 }, ImGuiCond_FirstUseEver);
    
    if imgui.Begin('JobBinds Configuration', config_ui.is_open, ImGuiWindowFlags_None) then
        -- Create two columns
        imgui.Columns(2, 'main_columns', true);
        
        -- Column headers on the same line
        imgui.Text(string.format('Current Bindings: %s', config_ui.current_profile));
        imgui.NextColumn();
        imgui.Text('Binding Editor');
        imgui.NextColumn();
        
        -- Left column: Current bindings list
        -- Create a child window for the bindings list with scrolling
        if imgui.BeginChild('bindings_list', { 0, -1 }, true) then
            for i, binding in ipairs(sample_bindings) do
                local label = string.format('%s%s%s -> %s', 
                    binding.modifiers ~= '' and binding.modifiers .. '+' or '',
                    binding.key,
                    string.rep(' ', math.max(1, 15 - string.len(binding.modifiers) - string.len(binding.key))),
                    binding.command);
                
                if imgui.Selectable(label, config_ui.selected_binding == i) then
                    config_ui.selected_binding = i;
                    -- Populate the edit fields with selected binding data
                    config_ui.binding_key[1] = string.upper(binding.key);
                    config_ui.shift_modifier[1] = string.find(binding.modifiers, 'Shift') ~= nil;
                    config_ui.alt_modifier[1] = string.find(binding.modifiers, 'Alt') ~= nil;
                    config_ui.ctrl_modifier[1] = string.find(binding.modifiers, 'Ctrl') ~= nil;
                    config_ui.command_text[1] = binding.command;
                    config_ui.is_macro[1] = false; -- Default to single command for now
                    config_ui.macro_text[1] = '';
                end
            end
        end
        imgui.EndChild();
        
        -- Move to right column
        imgui.NextColumn();
        
        -- Right column: Controls
        imgui.Separator();
        
        -- Button row: New, Save, and Delete
        if imgui.Button('New', { 80, 0 }) then
            -- TODO: Add new binding logic
            config_ui.selected_binding = -1;
            config_ui.binding_key[1] = '';
            config_ui.shift_modifier[1] = false;
            config_ui.alt_modifier[1] = false;
            config_ui.ctrl_modifier[1] = false;
            config_ui.command_text[1] = '';
            config_ui.is_macro[1] = false;
            config_ui.macro_text[1] = '';
            config_ui.is_binding = false;
        end
        
        imgui.SameLine();
        
        if imgui.Button('Save', { 80, 0 }) then
            -- TODO: Add save binding logic
        end
        
        imgui.SameLine();
        
        if imgui.Button('Delete', { 80, 0 }) then
            -- TODO: Add delete binding logic
            if config_ui.selected_binding > 0 then
                -- Logic to delete selected binding
            end
        end
        
        imgui.Spacing();
        imgui.Spacing();
        
        -- Binding Key input with modifiers on the same line
        if imgui.Button(config_ui.is_binding and 'Press Key...' or 'Bind', { 60, 0 }) then
            config_ui.is_binding = not config_ui.is_binding;
        end
        
        imgui.SameLine();
        
        -- Display the detected key
        local display_key = config_ui.binding_key[1] ~= '' and config_ui.binding_key[1] or '(none)';
        imgui.Text('Key: ' .. display_key);
        
        imgui.SameLine();
        imgui.Checkbox('Shift', config_ui.shift_modifier);
        
        imgui.SameLine();
        imgui.Checkbox('Alt', config_ui.alt_modifier);
        
        imgui.SameLine();
        imgui.Checkbox('Ctrl', config_ui.ctrl_modifier);
        
        imgui.Spacing();
        imgui.Spacing();
        
        -- Command text field with macro checkbox on the same line
        imgui.Text('Command:');
        imgui.SameLine();
        
        -- Disable the text field if macro mode is enabled
        if config_ui.is_macro[1] then
            imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.6);
        end
        
        imgui.SetNextItemWidth(200);
        imgui.InputText('##command_text', config_ui.command_text, 256, config_ui.is_macro[1] and ImGuiInputTextFlags_ReadOnly or ImGuiInputTextFlags_None);
        
        if config_ui.is_macro[1] then
            imgui.PopStyleVar();
        end
        
        imgui.SameLine();
        imgui.Checkbox('Macro', config_ui.is_macro);
        
        -- Show multiline text field if macro is enabled
        if config_ui.is_macro[1] then
            imgui.Spacing();
            imgui.InputTextMultiline('##macro_text', config_ui.macro_text, 2048, { -1, 100 }); -- -1 width means full column width
        end
        
        -- Key detection logic
        if config_ui.is_binding then
            -- Test all possible key codes
            for key_code = 1, 255 do
                local ok, is_pressed = pcall(function() return imgui.IsKeyPressed(key_code) end)
                if ok and is_pressed then
                    local key_name = vk_codes.get_key_name(key_code);
                    
                    if vk_codes.is_known_key(key_code) then
                        config_ui.binding_key[1] = key_name;
                        config_ui.is_binding = false;
                        if config_ui.debug_mode then
                            print('[JobBinds] Detected key: ' .. key_name .. ' (code: ' .. key_code .. ')');
                        end
                    else
                        -- Unknown key, store as raw code for debugging
                        config_ui.binding_key[1] = 'KEY_' .. key_code;
                        config_ui.is_binding = false;
                        if config_ui.debug_mode then
                            print('[JobBinds] Detected unknown key code: ' .. key_code);
                        end
                    end
                    break;
                end
            end
            
            -- Cancel binding on Escape
            local ok, is_pressed = pcall(function() return imgui.IsKeyPressed(27) end)
            if ok and is_pressed then
                config_ui.is_binding = false;
                if config_ui.debug_mode then
                    print('[JobBinds] Escape pressed, canceling binding');
                end
            end
        end
        
        imgui.Columns(1); -- Reset columns
    end
    imgui.End();
end

-- Function to show the config window
function config_ui.show()
    config_ui.is_open[1] = true;
end

-- Function to hide the config window
function config_ui.hide()
    config_ui.is_open[1] = false;
end

-- Function to toggle the config window
function config_ui.toggle()
    config_ui.is_open[1] = not config_ui.is_open[1];
end

-- Function to set the current profile name
function config_ui.set_current_profile(profile_name)
    config_ui.current_profile = profile_name or 'No Profile Loaded';
end

-- Function to set debug mode state
function config_ui.set_debug_mode(enabled)
    config_ui.debug_mode = enabled;
end

return config_ui;
