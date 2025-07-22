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

-- Current bindings loaded from profile file
local current_bindings = {};
local current_profile_path = nil; -- Track the current profile file path

-- Function to generate bind command string from binding data
local function generate_bind_command(binding)
    local key_part = binding.key
    local modifiers = {}
    
    -- Parse modifiers back to FFXI format
    if binding.modifiers and binding.modifiers ~= '' then
        for modifier in binding.modifiers:gmatch('[^+]+') do
            if modifier == 'Ctrl' then
                key_part = '^' .. key_part
            elseif modifier == 'Alt' then
                key_part = '!' .. key_part
            elseif modifier == 'Shift' then
                key_part = '@' .. key_part
            elseif modifier == 'Win' then
                key_part = '#' .. key_part
            end
        end
    end
    
    return string.format('/bind %s %s', key_part, binding.command)
end

-- Function to save bindings back to profile file
local function save_bindings_to_profile()
    if not current_profile_path then
        if config_ui.debug_mode then
            print('[JobBinds] No profile path available for saving')
        end
        return false
    end
    
    local file = io.open(current_profile_path, 'w')
    if not file then
        if config_ui.debug_mode then
            print('[JobBinds] Could not open profile file for writing: ' .. current_profile_path)
        end
        return false
    end
    
    -- Write all bindings
    for _, binding in ipairs(current_bindings) do
        local bind_command = generate_bind_command(binding)
        file:write(bind_command .. '\n')
        if config_ui.debug_mode then
            print('[JobBinds] Wrote binding: ' .. bind_command)
        end
    end
    
    file:close()
    
    if config_ui.debug_mode then
        print('[JobBinds] Saved ' .. #current_bindings .. ' bindings to: ' .. current_profile_path)
    end
    
    return true
end

-- Function to parse a bind command line
local function parse_bind_line(line)
    -- Pattern to match: /bind [modifiers+]key "command" or /bind [modifiers+]key command
    local modifiers_key, command = line:match('^/bind%s+([!@#%^+%w]+)%s+(.+)$')
    if not modifiers_key or not command then
        return nil
    end
    
    -- Remove quotes from command if present
    command = command:match('^"(.*)"$') or command
    
    -- Check if this is a macro (exec command)
    local is_macro = false
    local macro_content = ''
    local exec_file = command:match('^/exec%s+(.+)$')
    if exec_file then
        is_macro = true
        -- Load macro file content
        local macro_path = string.format('%s/scripts/%s', AshitaCore:GetInstallPath(), exec_file)
        if not macro_path:match('%.txt$') then
            macro_path = macro_path .. '.txt'
        end
        
        local macro_file = io.open(macro_path, 'r')
        if macro_file then
            macro_content = macro_file:read('*all')
            macro_file:close()
            if config_ui.debug_mode then
                print('[JobBinds] Loaded macro content from: ' .. macro_path)
            end
        else
            if config_ui.debug_mode then
                print('[JobBinds] Could not load macro file: ' .. macro_path)
            end
            macro_content = '-- Macro file not found: ' .. macro_path
        end
    end
    
    -- Parse modifiers and key
    local modifiers = {}
    local key = modifiers_key
    
    -- Check for modifier prefixes
    if key:match('^%^') then
        table.insert(modifiers, 'Ctrl')
        key = key:sub(2)
    end
    if key:match('^!') then
        table.insert(modifiers, 'Alt')
        key = key:sub(2)
    end
    if key:match('^@') then
        table.insert(modifiers, 'Shift')
        key = key:sub(2)
    end
    if key:match('^#') then
        table.insert(modifiers, 'Win')
        key = key:sub(2)
    end
    
    -- Check for + notation (Ctrl+F1, Alt+F2, etc.)
    local parts = {}
    for part in key:gmatch('[^+]+') do
        table.insert(parts, part)
    end
    
    if #parts > 1 then
        key = parts[#parts] -- Last part is the actual key
        for i = 1, #parts - 1 do
            local mod = parts[i]:lower()
            if mod == 'ctrl' then
                table.insert(modifiers, 'Ctrl')
            elseif mod == 'alt' then
                table.insert(modifiers, 'Alt')
            elseif mod == 'shift' then
                table.insert(modifiers, 'Shift')
            end
        end
    end
    
    return {
        key = key:upper(),
        modifiers = table.concat(modifiers, '+'),
        command = command,
        is_macro = is_macro,
        macro_content = macro_content
    }
end

-- Function to load bindings from profile file
local function load_bindings_from_profile(profile_path)
    if config_ui.debug_mode then
        print('[JobBinds] Loading bindings from: ' .. (profile_path or 'nil'))
    end
    
    current_bindings = {} -- Clear existing bindings
    current_profile_path = profile_path -- Store the profile path for saving
    
    if not profile_path then
        if config_ui.debug_mode then
            print('[JobBinds] No profile path provided')
        end
        return
    end
    
    local file = io.open(profile_path, 'r')
    if not file then
        if config_ui.debug_mode then
            print('[JobBinds] Could not open profile file: ' .. profile_path)
        end
        return
    end
    
    local line_count = 0
    local bind_count = 0
    
    for line in file:lines() do
        line_count = line_count + 1
        line = line:match('^%s*(.-)%s*$') -- Trim whitespace
        
        if line:match('^/bind%s+') then
            local binding = parse_bind_line(line)
            if binding then
                table.insert(current_bindings, binding)
                bind_count = bind_count + 1
                if config_ui.debug_mode then
                    print('[JobBinds] Parsed binding: ' .. binding.key .. 
                          (binding.modifiers ~= '' and (' (' .. binding.modifiers .. ')') or '') .. 
                          ' -> ' .. binding.command .. 
                          (binding.is_macro and ' [MACRO]' or ''))
                end
            else
                if config_ui.debug_mode then
                    print('[JobBinds] Failed to parse bind line: ' .. line)
                end
            end
        end
    end
    
    file:close()
    
    if config_ui.debug_mode then
        print('[JobBinds] Loaded ' .. bind_count .. ' bindings from ' .. line_count .. ' lines')
    end
end

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
            for i, binding in ipairs(current_bindings) do
                local label = string.format('%s%s%s -> %s', 
                    binding.modifiers ~= '' and binding.modifiers .. '+' or '',
                    binding.key,
                    string.rep(' ', math.max(1, 3 - string.len(binding.modifiers) - string.len(binding.key))),
                    binding.command);
                
                if imgui.Selectable(label, config_ui.selected_binding == i) then
                    config_ui.selected_binding = i;
                    -- Populate the edit fields with selected binding data
                    config_ui.binding_key[1] = string.upper(binding.key);
                    config_ui.shift_modifier[1] = string.find(binding.modifiers, 'Shift') ~= nil;
                    config_ui.alt_modifier[1] = string.find(binding.modifiers, 'Alt') ~= nil;
                    config_ui.ctrl_modifier[1] = string.find(binding.modifiers, 'Ctrl') ~= nil;
                    config_ui.command_text[1] = binding.command;
                    config_ui.is_macro[1] = binding.is_macro or false;
                    config_ui.macro_text[1] = binding.macro_content or '';
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
            -- Check if we have valid data to save
            if config_ui.binding_key[1] ~= '' and config_ui.command_text[1] ~= '' then
                local old_key_part = nil
                local binding = nil
                
                if config_ui.selected_binding > 0 and config_ui.selected_binding <= #current_bindings then
                    -- Updating existing binding
                    binding = current_bindings[config_ui.selected_binding]
                    local old_bind_command = generate_bind_command(binding)
                    old_key_part = old_bind_command:match('/bind%s+([!@#%^+%w]+)')
                else
                    -- Creating new binding
                    binding = {}
                    table.insert(current_bindings, binding)
                    config_ui.selected_binding = #current_bindings
                    if config_ui.debug_mode then
                        print('[JobBinds] Creating new binding')
                    end
                end
                
                -- Update binding with current editor values
                binding.key = config_ui.binding_key[1]:upper()
                
                -- Build modifiers string
                local modifiers = {}
                if config_ui.shift_modifier[1] then table.insert(modifiers, 'Shift') end
                if config_ui.alt_modifier[1] then table.insert(modifiers, 'Alt') end
                if config_ui.ctrl_modifier[1] then table.insert(modifiers, 'Ctrl') end
                binding.modifiers = table.concat(modifiers, '+')
                
                binding.command = config_ui.command_text[1]
                binding.is_macro = config_ui.is_macro[1]
                binding.macro_content = config_ui.macro_text[1]
                
                -- Generate new bind command
                local new_bind_command = generate_bind_command(binding)
                local new_key_part = new_bind_command:match('/bind%s+([!@#%^+%w]+)')
                
                -- Apply changes in-game: unbind old key (if updating), bind new key
                if old_key_part and old_key_part ~= new_key_part then
                    local unbind_command = '/unbind ' .. old_key_part
                    local ok = pcall(function()
                        AshitaCore:GetChatManager():QueueCommand(-1, unbind_command)
                    end)
                    if config_ui.debug_mode then
                        print('[JobBinds] Executed: ' .. unbind_command .. (ok and ' [SUCCESS]' or ' [FAILED]'))
                    end
                end
                
                if new_key_part then
                    local ok = pcall(function()
                        AshitaCore:GetChatManager():QueueCommand(-1, new_bind_command)
                    end)
                    if config_ui.debug_mode then
                        print('[JobBinds] Executed: ' .. new_bind_command .. (ok and ' [SUCCESS]' or ' [FAILED]'))
                    end
                end
                
                if config_ui.debug_mode then
                    print('[JobBinds] ' .. (old_key_part and 'Updated' or 'Created') .. ' binding: ' .. binding.key .. 
                          (binding.modifiers ~= '' and (' (' .. binding.modifiers .. ')') or '') .. 
                          ' -> ' .. binding.command)
                end
                
                -- Save all bindings to file
                if save_bindings_to_profile() then
                    print('[JobBinds] Profile saved successfully')
                else
                    print('[JobBinds] Failed to save profile')
                end
            else
                print('[JobBinds] Cannot save: missing key or command')
            end
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
        
        -- Store previous macro state to detect changes
        local prev_macro_state = config_ui.is_macro[1]
        imgui.Checkbox('Macro', config_ui.is_macro);
        
        -- If macro checkbox was just checked, generate exec command
        if config_ui.is_macro[1] and not prev_macro_state then
            -- Generate exec command based on current profile and binding
            local profile_base = config_ui.current_profile
            if profile_base and profile_base ~= 'No Profile Loaded' then
                -- Remove .txt extension if present
                profile_base = profile_base:gsub('%.txt$', '')
                
                -- Generate binding suffix from key and modifiers
                local binding_suffix = ''
                if config_ui.binding_key[1] ~= '' then
                    local key_part = config_ui.binding_key[1]
                    
                    -- Add modifier prefixes
                    if config_ui.shift_modifier[1] then
                        binding_suffix = 'S' .. binding_suffix
                    end
                    if config_ui.alt_modifier[1] then
                        binding_suffix = 'A' .. binding_suffix
                    end
                    if config_ui.ctrl_modifier[1] then
                        binding_suffix = 'C' .. binding_suffix
                    end
                    
                    -- Add key name
                    binding_suffix = binding_suffix .. key_part
                else
                    binding_suffix = 'R' -- Default suffix if no key selected
                end
                
                -- Generate the exec command
                local exec_command = string.format('/exec %s_%s', profile_base, binding_suffix)
                config_ui.command_text[1] = exec_command
                
                if config_ui.debug_mode then
                    print('[JobBinds] Generated macro command: ' .. exec_command)
                end
            else
                config_ui.command_text[1] = '/exec PROFILE_R'
                if config_ui.debug_mode then
                    print('[JobBinds] No profile loaded, using default macro command')
                end
            end
        end
        
        -- Show multiline text field if macro is enabled
        if config_ui.is_macro[1] then
            imgui.Spacing();
            imgui.InputTextMultiline('##macro_text', config_ui.macro_text, 2048, { -1, -1 }); -- -1 width means full column width
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

-- Function to load profile and update bindings
function config_ui.load_profile(profile_path)
    load_bindings_from_profile(profile_path);
end

-- Function to set debug mode state
function config_ui.set_debug_mode(enabled)
    config_ui.debug_mode = enabled;
end

return config_ui;
