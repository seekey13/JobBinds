require('common');
local imgui = require('imgui');
local vk_codes = require('vk_codes');
local blocked_keybinds = require('blocked_keybinds');
local ui_functions = require('ui_functions');

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
config_ui.error_message = ''; -- Error message for blocked keys

-- Current bindings loaded from profile file
local current_bindings = {};
local current_profile_path = nil; -- Track the current profile file path

-- Helper: Generate macro filename based on profile + modifiers + key
local function get_macro_filename(profile_base, key, shift, alt, ctrl)
    return ui_functions.get_macro_filename(profile_base, key, shift, alt, ctrl)
end

-- Helper: Rename macro script file if the filename changes
local function rename_macro_file(old_name, new_name)
    if old_name == new_name then return end
    local scripts_path = get_scripts_path()
    local old_path = string.format('%s/%s', scripts_path, old_name)
    local new_path = string.format('%s/%s', scripts_path, new_name)
    local file = io.open(old_path, 'r')
    if file then
        file:close()
        -- Only rename if new doesn't already exist
        local newfile = io.open(new_path, 'r')
        if not newfile then
            local ok, err = pcall(function() os.rename(old_path, new_path) end)
            if config_ui.debug_mode then
                if ok then
                    print('[JobBinds] Renamed macro file: ' .. old_path .. ' -> ' .. new_path)
                else
                    print('[JobBinds] Failed to rename macro file: ' .. (err or '?'))
                end
            end
        elseif newfile then
            newfile:close()
        end
    end
end

-- Function to validate key binding and set error message
local function validate_key_binding()
    config_ui.error_message = '' -- Clear previous errors
    
    if config_ui.binding_key[1] == '' then
        return true -- No key selected yet, no error
    end
    
    -- Build modifiers string for validation
    local modifiers = {}
    if config_ui.shift_modifier[1] then table.insert(modifiers, 'Shift') end
    if config_ui.alt_modifier[1] then table.insert(modifiers, 'Alt') end
    if config_ui.ctrl_modifier[1] then table.insert(modifiers, 'Ctrl') end
    local modifier_string = table.concat(modifiers, '+')
    
    -- Use shared validation function
    local is_valid, error_msg = ui_functions.validate_key_binding(config_ui.binding_key[1], modifier_string)
    if not is_valid then
        config_ui.error_message = error_msg
        return false
    end
    
    return true
end

-- Function to generate bind command string from binding data
local function generate_bind_command(binding)
    return ui_functions.generate_bind_command(binding)
end

-- Function to generate binding suffix from current UI state
local function generate_binding_suffix()
    return ui_functions.generate_binding_suffix(config_ui.shift_modifier[1], config_ui.alt_modifier[1], config_ui.ctrl_modifier[1])
end

-- Function to get scripts folder path
function get_scripts_path()
    return ui_functions.get_scripts_path()
end

-- Function to generate profile name based on current jobs
local function generate_profile_name()
    return ui_functions.generate_profile_name()
end

-- Function to create macro file with content
local function create_macro_file(macro_name, content, existing_command)
    return ui_functions.create_macro_file(macro_name, content, existing_command, config_ui.debug_mode)
end

-- Function to save bindings back to profile file
local function save_bindings_to_profile()
    return ui_functions.save_bindings_to_profile(current_bindings, current_profile_path, config_ui.debug_mode)
end

-- Function to parse a bind command line
local function parse_bind_line(line)
    return ui_functions.parse_bind_line(line, config_ui.debug_mode)
end

-- Function to load bindings from profile file
local function load_bindings_from_profile(profile_path)
    local bindings, path = ui_functions.load_bindings_from_profile(profile_path, config_ui.debug_mode)
    current_bindings = bindings
    current_profile_path = path
end

-- Instantly updates macro command and filename in UI when modifiers/key change
local function update_macro_command_and_filename(create_file, existing_command)
    if not config_ui.is_macro[1] then return end
    local profile_base = config_ui.current_profile
    if not profile_base or profile_base == 'No Profile Loaded' then
        profile_base = generate_profile_name()
    else
        profile_base = profile_base:gsub('%.txt$', '')
    end
    local macro_name = get_macro_filename(
        profile_base,
        config_ui.binding_key[1],
        config_ui.shift_modifier[1],
        config_ui.alt_modifier[1],
        config_ui.ctrl_modifier[1]
    )
    config_ui.command_text[1] = '/exec ' .. macro_name:gsub('%.txt$', '')
    
    -- If create_file is true, create the macro file
    if create_file then
        local success, updated_content = create_macro_file(macro_name:gsub('%.txt$', ''), config_ui.macro_text[1], existing_command)
        if success then
            config_ui.macro_text[1] = updated_content
            if config_ui.debug_mode then
                print('[JobBinds] Generated macro command: ' .. config_ui.command_text[1])
            end
        else
            if config_ui.debug_mode then
                print('[JobBinds] Failed to create macro file for: ' .. macro_name)
            end
        end
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
        if imgui.BeginChild('bindings_list', { 0, -1 }, true) then
            for i, binding in ipairs(current_bindings) do
                local label = string.format('%s%s%s -> %s', 
                    binding.modifiers ~= '' and binding.modifiers .. '+' or '',
                    binding.key,
                    string.rep(' ', math.max(1, 3 - string.len(binding.modifiers) - string.len(binding.key))),
                    binding.command);
                
                if imgui.Selectable(label, config_ui.selected_binding == i) then
                    config_ui.selected_binding = i;
                    config_ui.error_message = ''; -- Clear any error messages
                    -- Populate the edit fields with selected binding data
                    config_ui.binding_key[1] = string.upper(binding.key);
                    config_ui.shift_modifier[1] = string.find(binding.modifiers, 'Shift') ~= nil;
                    config_ui.alt_modifier[1] = string.find(binding.modifiers, 'Alt') ~= nil;
                    config_ui.ctrl_modifier[1] = string.find(binding.modifiers, 'Ctrl') ~= nil;
                    config_ui.command_text[1] = binding.command;
                    config_ui.is_macro[1] = binding.is_macro or false;
                    config_ui.macro_text[1] = binding.macro_content or '';
                    -- Track previous macro settings for renaming
                    binding.prev_key = binding.key
                    binding.prev_modifiers = binding.modifiers
                    binding.prev_shift = config_ui.shift_modifier[1]
                    binding.prev_alt = config_ui.alt_modifier[1]
                    binding.prev_ctrl = config_ui.ctrl_modifier[1]
                    validate_key_binding();
                end
            end
        end
        imgui.EndChild();
        
        imgui.NextColumn();
        imgui.Separator();
        
        if imgui.Button('New', { 80, 0 }) then
            config_ui.selected_binding = -1;
            config_ui.binding_key[1] = '';
            config_ui.shift_modifier[1] = false;
            config_ui.alt_modifier[1] = false;
            config_ui.ctrl_modifier[1] = false;
            config_ui.command_text[1] = '';
            config_ui.is_macro[1] = false;
            config_ui.macro_text[1] = '';
            config_ui.is_binding = false;
            config_ui.error_message = '';
        end
        
        imgui.SameLine();
        
        if imgui.Button('Save', { 80, 0 }) then
            if not validate_key_binding() then
                if config_ui.debug_mode then
                    print('[JobBinds] Save blocked: ' .. config_ui.error_message)
                end
            elseif config_ui.binding_key[1] ~= '' and config_ui.command_text[1] ~= '' then
                if not current_profile_path or config_ui.current_profile == 'No Profile Loaded' then
                    local profile_name = generate_profile_name()
                    local scripts_path = get_scripts_path()
                    current_profile_path = string.format('%s/%s.txt', scripts_path, profile_name)
                    config_ui.current_profile = profile_name .. '.txt'
                    -- Directory creation is handled by ui_functions when needed
                    if config_ui.debug_mode then
                        print('[JobBinds] Creating new profile in scripts folder: ' .. current_profile_path)
                    end
                    if #current_bindings == 0 then
                        current_bindings = {}
                    end
                end
                
                local old_key_part = nil
                local binding = nil
                
                if config_ui.selected_binding > 0 and config_ui.selected_binding <= #current_bindings then
                    binding = current_bindings[config_ui.selected_binding]
                    local old_bind_command = generate_bind_command(binding)
                    old_key_part = old_bind_command:match('/bind%s+([!@#%^+%w]+)')
                else
                    binding = {}
                    table.insert(current_bindings, binding)
                    config_ui.selected_binding = #current_bindings
                    if config_ui.debug_mode then
                        print('[JobBinds] Creating new binding')
                    end
                end
                
                binding.key = config_ui.binding_key[1]:upper()
                local modifiers = {}
                if config_ui.shift_modifier[1] then table.insert(modifiers, 'Shift') end
                if config_ui.alt_modifier[1] then table.insert(modifiers, 'Alt') end
                if config_ui.ctrl_modifier[1] then table.insert(modifiers, 'Ctrl') end
                binding.modifiers = table.concat(modifiers, '+')
                binding.command = config_ui.command_text[1]
                binding.is_macro = config_ui.is_macro[1]
                binding.macro_content = config_ui.macro_text[1]
                
                -- If this is a macro binding, update the macro file and possibly rename
                if binding.is_macro and binding.command:match('^/exec%s+(.+)$') then
                    local macro_name = binding.command:match('^/exec%s+(.+)$')
                    macro_name = macro_name:gsub('%.txt$', '') .. '.txt'
                    local old_macro_name = nil
                    if binding.old_macro_name then
                        old_macro_name = binding.old_macro_name
                    elseif binding.prev_key and binding.prev_modifiers then
                        local old_profile_base = config_ui.current_profile:gsub('%.txt$', '')
                        old_macro_name = get_macro_filename(
                            old_profile_base,
                            binding.prev_key,
                            binding.prev_shift,
                            binding.prev_alt,
                            binding.prev_ctrl
                        )
                    end
                    if old_macro_name and old_macro_name ~= macro_name then
                        rename_macro_file(old_macro_name, macro_name)
                    end
                    local success, updated_content = create_macro_file(macro_name:gsub('%.txt$', ''), config_ui.macro_text[1], nil)
                    binding.old_macro_name = macro_name
                end
                
                local new_bind_command = generate_bind_command(binding)
                local new_key_part = new_bind_command:match('/bind%s+([!@#%^+%w]+)')
                
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
                
                if save_bindings_to_profile() then
                    print('[JobBinds] Profile saved successfully')
                else
                    print('[JobBinds] Failed to save profile')
                end
            elseif config_ui.binding_key[1] == '' or config_ui.command_text[1] == '' then
                config_ui.error_message = 'Missing key or command'
                if config_ui.debug_mode then
                    print('[JobBinds] Cannot save: missing key or command')
                end
            end
        end
        
        imgui.SameLine();
        
        if imgui.Button('Delete', { 80, 0 }) then
            if config_ui.selected_binding > 0 and config_ui.selected_binding <= #current_bindings then
                local binding = current_bindings[config_ui.selected_binding]
                local bind_command = generate_bind_command(binding)
                local key_part = bind_command:match('/bind%s+([!@#%^+%w]+)')
                if key_part then
                    local unbind_command = '/unbind ' .. key_part
                    local ok = pcall(function()
                        AshitaCore:GetChatManager():QueueCommand(-1, unbind_command)
                    end)
                    if config_ui.debug_mode then
                        print('[JobBinds] Executed: ' .. unbind_command .. (ok and ' [SUCCESS]' or ' [FAILED]'))
                    end
                end
                if binding.is_macro and binding.command:match('^/exec%s+(.+)$') then
                    local macro_name = binding.command:match('^/exec%s+(.+)$')
                    local scripts_path = get_scripts_path()
                    local macro_file_path = string.format('%s/%s.txt', scripts_path, macro_name)
                    local delete_ok = pcall(function()
                        os.remove(macro_file_path)
                    end)
                    if config_ui.debug_mode then
                        if delete_ok then
                            print('[JobBinds] Deleted macro file: ' .. macro_file_path)
                        else
                            print('[JobBinds] Failed to delete macro file: ' .. macro_file_path)
                        end
                    end
                end
                table.remove(current_bindings, config_ui.selected_binding)
                config_ui.selected_binding = -1
                config_ui.binding_key[1] = ''
                config_ui.shift_modifier[1] = false
                config_ui.alt_modifier[1] = false
                config_ui.ctrl_modifier[1] = false
                config_ui.command_text[1] = ''
                config_ui.is_macro[1] = false
                config_ui.macro_text[1] = ''
                config_ui.is_binding = false
                if save_bindings_to_profile() then
                    print('[JobBinds] Binding deleted and profile saved successfully')
                else
                    print('[JobBinds] Failed to save profile after deletion')
                end
            else
                print('[JobBinds] No binding selected for deletion')
            end
        end
        
        imgui.Spacing();
        imgui.Spacing();
        
        if imgui.Button(config_ui.is_binding and 'Press Key...' or 'Bind', { 60, 0 }) then
            config_ui.is_binding = not config_ui.is_binding;
        end
        
        imgui.SameLine();
        local display_key = config_ui.binding_key[1] ~= '' and config_ui.binding_key[1] or '(none)';
        imgui.Text('Key: ' .. display_key);
        
        imgui.SameLine();
        if imgui.Checkbox('Ctrl', config_ui.ctrl_modifier) then
            validate_key_binding();
            update_macro_command_and_filename();
        end
        
        imgui.SameLine();
        if imgui.Checkbox('Alt', config_ui.alt_modifier) then
            validate_key_binding();
            update_macro_command_and_filename();
        end
        
        imgui.SameLine();
        if imgui.Checkbox('Shift', config_ui.shift_modifier) then
            validate_key_binding();
            update_macro_command_and_filename();
        end
        
        if config_ui.error_message ~= '' then
            imgui.Spacing();
            imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.3, 0.3, 1.0 });
            imgui.Text('Error: ' .. config_ui.error_message);
            imgui.PopStyleColor();
        end
        
        imgui.Spacing();
        imgui.Spacing();
        
        imgui.Text('Command:');
        imgui.SameLine();
        
        if config_ui.is_macro[1] then
            imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.6);
        end
        
        imgui.SetNextItemWidth(200);
        imgui.InputText('##command_text', config_ui.command_text, 256, config_ui.is_macro[1] and ImGuiInputTextFlags_ReadOnly or ImGuiInputTextFlags_None);
        
        if config_ui.is_macro[1] then
            imgui.PopStyleVar();
        end
        
        imgui.SameLine();
        local prev_macro_state = config_ui.is_macro[1]
        imgui.Checkbox('Macro', config_ui.is_macro);
        
        -- If macro checkbox was just checked, generate exec command and create macro file
        if config_ui.is_macro[1] and not prev_macro_state then
            local existing_command = config_ui.command_text[1]
            update_macro_command_and_filename(true, existing_command)
        end
        
        if config_ui.is_macro[1] then
            imgui.Spacing();
            imgui.InputTextMultiline('##macro_text', config_ui.macro_text, 2048, { -1, -1 });
        end
        
        if config_ui.is_binding then
            for key_code = 1, 255 do
                local ok, is_pressed = pcall(function() return imgui.IsKeyPressed(key_code) end)
                if ok and is_pressed then
                    local key_name = vk_codes.get_key_name(key_code);
                    if vk_codes.is_known_key(key_code) then
                        config_ui.binding_key[1] = key_name;
                        config_ui.is_binding = false;
                        validate_key_binding();
                        update_macro_command_and_filename();
                        if config_ui.debug_mode then
                            print('[JobBinds] Detected key: ' .. key_name .. ' (code: ' .. key_code .. ')');
                        end
                    else
                        config_ui.binding_key[1] = 'KEY_' .. key_code;
                        config_ui.is_binding = false;
                        validate_key_binding();
                        update_macro_command_and_filename();
                        if config_ui.debug_mode then
                            print('[JobBinds] Detected unknown key code: ' .. key_code);
                        end
                    end
                    break;
                end
            end
            local ok, is_pressed = pcall(function() return imgui.IsKeyPressed(27) end)
            if ok and is_pressed then
                config_ui.is_binding = false;
                if config_ui.debug_mode then
                    print('[JobBinds] Escape pressed, canceling binding');
                end
            end
        end
        
        imgui.Columns(1);
    end
    imgui.End();
end

function config_ui.show()
    config_ui.is_open[1] = true;
end

function config_ui.hide()
    config_ui.is_open[1] = false;
end

function config_ui.toggle()
    config_ui.is_open[1] = not config_ui.is_open[1];
end

function config_ui.set_current_profile(profile_name)
    config_ui.current_profile = profile_name or 'No Profile Loaded';
end

function config_ui.load_profile(profile_path)
    load_bindings_from_profile(profile_path);
end

function config_ui.set_debug_mode(enabled)
    config_ui.debug_mode = enabled;
end

return config_ui;
