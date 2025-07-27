--[[
* UI Functions Module
* Shared functions for JobBinds UI components
* Copyright (c) 2025 Seekey
--]]

require('common');
local blocked_keybinds = require('blocked_keybinds');

local ui_functions = {};

-- ============================================================================
-- PATH AND FILE UTILITIES
-- ============================================================================

-- Function to get scripts folder path
function ui_functions.get_scripts_path()
    return string.format('%s/scripts', AshitaCore:GetInstallPath())
end

-- Function to ensure directory exists
local function ensure_directory_exists(path)
    local ok, err = pcall(function()
        AshitaCore:GetChatManager():QueueCommand(1, string.format('/mkdir "%s"', path))
    end)
    return ok
end

-- ============================================================================
-- MACRO FILENAME GENERATION
-- ============================================================================

-- Helper: Generate macro filename based on profile + modifiers + key
function ui_functions.get_macro_filename(profile_base, key, shift, alt, ctrl)
    if not profile_base or not key then
        return ''
    end
    profile_base = profile_base:gsub('%.txt$', '')
    local mod = ''
    if ctrl then mod = mod .. '^' end
    if alt then mod = mod .. '!' end
    if shift then mod = mod .. '+' end
    return string.format('%s_%s%s.txt', profile_base, mod, key)
end

-- Helper: Rename macro script file if the filename changes
function ui_functions.rename_macro_file(old_name, new_name)
    if old_name == new_name then return end
    local scripts_path = ui_functions.get_scripts_path()
    local old_path = string.format('%s/%s', scripts_path, old_name)
    local new_path = string.format('%s/%s', scripts_path, new_name)
    local file = io.open(old_path, 'r')
    if file then
        file:close()
        -- Only rename if new doesn't already exist
        local newfile = io.open(new_path, 'r')
        if not newfile then
            local ok, err = pcall(function() os.rename(old_path, new_path) end)
            return ok
        else
            newfile:close()
        end
    end
    return false
end

-- ============================================================================
-- VALIDATION FUNCTIONS
-- ============================================================================

-- Function to validate key binding and set error message
function ui_functions.validate_key_binding(binding_key, shift_modifier, alt_modifier, ctrl_modifier)
    if binding_key == '' then
        return true, ''
    end
    
    local modifiers = {}
    if shift_modifier then table.insert(modifiers, 'Shift') end
    if alt_modifier then table.insert(modifiers, 'Alt') end
    if ctrl_modifier then table.insert(modifiers, 'Ctrl') end
    local modifier_string = table.concat(modifiers, '+')
    
    local is_blocked, error_msg = blocked_keybinds.is_combination_blocked(binding_key, modifier_string)
    if is_blocked then
        local message = error_msg or blocked_keybinds.get_block_reason(binding_key, modifier_string)
        return false, message
    end
    
    return true, ''
end

-- ============================================================================
-- BIND COMMAND GENERATION
-- ============================================================================

-- Function to generate bind command string from binding data
function ui_functions.generate_bind_command(binding)
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
    
    return string.format('/bind %s %s', key_part, command)
end

-- Function to generate binding suffix for display
function ui_functions.generate_binding_suffix(shift_modifier, alt_modifier, ctrl_modifier)
    local suffix = ''
    if ctrl_modifier then suffix = suffix .. '^' end
    if alt_modifier then suffix = suffix .. '!' end
    if shift_modifier then suffix = suffix .. '+' end
    return suffix
end

-- ============================================================================
-- PROFILE FILE OPERATIONS
-- ============================================================================

-- Function to save bindings back to profile file
function ui_functions.save_bindings_to_profile(current_bindings, current_profile_path, debug_mode)
    if not current_profile_path then
        if debug_mode then
            print('[JobBinds] No profile path available for saving')
        end
        return false
    end
    
    local file = io.open(current_profile_path, 'w')
    if not file then
        if debug_mode then
            print('[JobBinds] Could not open profile file for writing: ' .. current_profile_path)
        end
        return false
    end
    
    -- Write all bindings
    for _, binding in ipairs(current_bindings) do
        local bind_command = ui_functions.generate_bind_command(binding)
        file:write(bind_command .. '\n')
        if debug_mode then
            print('[JobBinds] Wrote binding: ' .. bind_command)
        end
    end
    
    file:close()
    
    if debug_mode then
        print('[JobBinds] Saved ' .. #current_bindings .. ' bindings to: ' .. current_profile_path)
    end
    
    return true
end

-- Function to parse a bind command line
function ui_functions.parse_bind_line(line)
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
        local macro_path = string.format('%s/%s', ui_functions.get_scripts_path(), exec_file)
        if not macro_path:match('%.txt$') then
            macro_path = macro_path .. '.txt'
        end
        
        local macro_file = io.open(macro_path, 'r')
        if macro_file then
            macro_content = macro_file:read('*all') or ''
            macro_file:close()
        end
    end
    
    -- Parse modifiers and key
    local key = modifiers_key
    local modifiers = {}
    
    -- Check for modifiers (order matters for parsing)
    if key:match('^%^') then
        table.insert(modifiers, 'Ctrl')
        key = key:sub(2)
    end
    if key:match('^!') then
        table.insert(modifiers, 'Alt')
        key = key:sub(2)
    end
    if key:match('^%+') then
        table.insert(modifiers, 'Shift')
        key = key:sub(2)
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
function ui_functions.load_bindings_from_profile(profile_path, debug_mode)
    local current_bindings = {} -- Clear existing bindings
    
    if not profile_path then
        if debug_mode then
            print('[JobBinds] No profile path provided')
        end
        return current_bindings
    end
    
    local file = io.open(profile_path, 'r')
    if not file then
        if debug_mode then
            print('[JobBinds] Could not open profile file: ' .. profile_path)
        end
        return current_bindings
    end
    
    local line_count = 0
    local bind_count = 0
    
    for line in file:lines() do
        line_count = line_count + 1
        line = line:match('^%s*(.-)%s*$') -- Trim whitespace
        
        if line:match('^/bind%s+') then
            local binding = ui_functions.parse_bind_line(line)
            if binding then
                table.insert(current_bindings, binding)
                bind_count = bind_count + 1
                if debug_mode then
                    print('[JobBinds] Parsed binding: ' .. binding.key .. 
                          (binding.modifiers ~= '' and (' (' .. binding.modifiers .. ')') or '') .. 
                          ' -> ' .. binding.command .. 
                          (binding.is_macro and ' [MACRO]' or ''))
                end
            else
                if debug_mode then
                    print('[JobBinds] Failed to parse bind line: ' .. line)
                end
            end
        end
    end
    
    file:close()
    
    if debug_mode then
        print('[JobBinds] Loaded ' .. bind_count .. ' bindings from ' .. line_count .. ' lines in: ' .. profile_path)
    end
    
    return current_bindings
end

-- ============================================================================
-- MACRO FILE OPERATIONS
-- ============================================================================

-- Function to generate profile name for macros
function ui_functions.generate_profile_name()
    local ok, party = pcall(function() return AshitaCore:GetMemoryManager():GetParty() end)
    if not ok or not party then
        return 'unknown'
    end
    
    local okj, job = pcall(function() return party:GetMemberMainJob(0) end)
    local oksj, subjob = pcall(function() return party:GetMemberSubJob(0) end)
    
    if not okj or not oksj then
        return 'unknown'
    end
    
    local job_names = {
        [1] = 'WAR', [2] = 'MNK', [3] = 'WHM', [4] = 'BLM', [5] = 'RDM', [6] = 'THF',
        [7] = 'PLD', [8] = 'DRK', [9] = 'BST', [10] = 'BRD', [11] = 'RNG', [12] = 'SAM',
        [13] = 'NIN', [14] = 'DRG', [15] = 'SMN', [16] = 'BLU', [17] = 'COR', [18] = 'PUP',
        [19] = 'DNC', [20] = 'SCH', [21] = 'GEO', [22] = 'RUN'
    }
    
    local job_name = job_names[job] or 'UNK'
    local subjob_name = job_names[subjob] or 'UNK'
    
    return string.format('%s_%s', job_name, subjob_name)
end

-- Function to create macro file
function ui_functions.create_macro_file(macro_name, content, existing_command)
    local scripts_path = ui_functions.get_scripts_path()
    ensure_directory_exists(scripts_path)
    
    local macro_path = string.format('%s/%s', scripts_path, macro_name)
    if not macro_path:match('%.txt$') then
        macro_path = macro_path .. '.txt'
    end
    
    -- Check if we need to handle existing commands that aren't exec commands
    if existing_command and existing_command ~= '' and not existing_command:match('^/exec%s+') then
        -- If there's an existing non-exec command, prepend it to the macro content
        if content and content ~= '' then
            content = existing_command .. '\n' .. content
        else
            content = existing_command
        end
    end
    
    local file = io.open(macro_path, 'w')
    if file then
        file:write(content or '')
        file:close()
        return true
    end
    
    return false
end

-- ============================================================================
-- BINDING MANAGEMENT FUNCTIONS
-- ============================================================================

-- Function to save current binding
function ui_functions.save_current_binding(binding_data, current_bindings, current_profile_path, debug_mode)
    -- Validate inputs
    if binding_data.key == '' then
        return false, 'Please select a key'
    end
    
    if binding_data.command == '' and not binding_data.is_macro then
        return false, 'Please enter a command'
    end
    
    if binding_data.is_macro and binding_data.macro_text == '' then
        return false, 'Please enter macro content'
    end
    
    -- Build modifiers string
    local modifiers = {}
    if binding_data.shift_modifier then table.insert(modifiers, 'Shift') end
    if binding_data.alt_modifier then table.insert(modifiers, 'Alt') end
    if binding_data.ctrl_modifier then table.insert(modifiers, 'Ctrl') end
    local modifier_string = table.concat(modifiers, '+')
    
    -- Check if key+modifiers are blocked
    local is_valid, error_msg = ui_functions.validate_key_binding(binding_data.key, 
                                                                  binding_data.shift_modifier,
                                                                  binding_data.alt_modifier,
                                                                  binding_data.ctrl_modifier)
    if not is_valid then
        return false, error_msg
    end
    
    -- Create new binding
    local new_binding = {
        key = binding_data.key,
        modifiers = modifier_string,
        command = binding_data.command,
        is_macro = binding_data.is_macro
    }
    
    -- Handle macro
    if binding_data.is_macro then
        -- Extract profile name from path
        local profile_base = 'profile'
        if current_profile_path then
            profile_base = current_profile_path:match('([^/\\]+)%.txt$') or 'profile'
        end
        
        -- Generate macro filename
        local macro_filename = ui_functions.get_macro_filename(profile_base, 
                                                               binding_data.key, 
                                                               binding_data.shift_modifier, 
                                                               binding_data.alt_modifier, 
                                                               binding_data.ctrl_modifier)
        
        -- Save macro content to file
        if not ui_functions.create_macro_file(macro_filename, binding_data.macro_text) then
            return false, 'Failed to save macro file'
        end
        
        -- Set command to exec the macro
        new_binding.command = '/exec ' .. macro_filename
    end
    
    -- Remove existing binding for this key+modifiers combination
    for i = #current_bindings, 1, -1 do
        local binding = current_bindings[i]
        if binding.key == new_binding.key and binding.modifiers == new_binding.modifiers then
            table.remove(current_bindings, i)
            break
        end
    end
    
    -- Add new binding
    table.insert(current_bindings, new_binding)
    
    -- Save to file
    if ui_functions.save_bindings_to_profile(current_bindings, current_profile_path, debug_mode) then
        -- Apply binding immediately
        local bind_command = ui_functions.generate_bind_command(new_binding)
        AshitaCore:GetChatManager():QueueCommand(1, bind_command)
        return true, ''
    else
        return false, 'Failed to save profile'
    end
end

-- Function to delete current binding
function ui_functions.delete_current_binding(binding_data, current_bindings, current_profile_path, debug_mode)
    if binding_data.key == '' then
        return false, 'Please select a key'
    end
    
    -- Build modifiers string
    local modifiers = {}
    if binding_data.shift_modifier then table.insert(modifiers, 'Shift') end
    if binding_data.alt_modifier then table.insert(modifiers, 'Alt') end
    if binding_data.ctrl_modifier then table.insert(modifiers, 'Ctrl') end
    local modifier_string = table.concat(modifiers, '+')
    
    -- Find and remove binding
    local found = false
    for i = #current_bindings, 1, -1 do
        local binding = current_bindings[i]
        if binding.key == binding_data.key and binding.modifiers == modifier_string then
            -- Handle macro file deletion
            if binding.is_macro and binding.command:match('^/exec%s+(.+)$') then
                local macro_name = binding.command:match('^/exec%s+(.+)$')
                local macro_path = string.format('%s/%s', ui_functions.get_scripts_path(), macro_name)
                if not macro_path:match('%.txt$') then
                    macro_path = macro_path .. '.txt'
                end
                os.remove(macro_path)
            end
            
            table.remove(current_bindings, i)
            found = true
            break
        end
    end
    
    if not found then
        return false, 'No binding found for this key combination'
    end
    
    -- Save to file
    if ui_functions.save_bindings_to_profile(current_bindings, current_profile_path, debug_mode) then
        -- Unbind the key
        local key_part = binding_data.key
        if binding_data.ctrl_modifier then key_part = '^' .. key_part end
        if binding_data.alt_modifier then key_part = '!' .. key_part end
        if binding_data.shift_modifier then key_part = '+' .. key_part end
        
        AshitaCore:GetChatManager():QueueCommand(1, '/unbind ' .. key_part)
        return true, ''
    else
        return false, 'Failed to save profile'
    end
end

return ui_functions;
