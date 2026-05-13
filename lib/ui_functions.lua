--[[
* UI Functions Module
* Shared functions for JobBinds UI components
* Copyright (c) 2025 Seekey
--]]

require('common');
local blocked_keybinds = require('lib.blocked_keybinds');
local modifiers = require('lib.modifiers');
local log = require('lib.log');

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
    local ok = pcall(function()
        AshitaCore:GetChatManager():QueueCommand(1, string.format('/mkdir "%s"', path))
    end)
    return ok
end

-- ============================================================================
-- VALIDATION FUNCTIONS
-- ============================================================================

-- Function to validate key binding and set error message
function ui_functions.validate_key_binding(binding_key, shift_modifier, alt_modifier, ctrl_modifier)
    if binding_key == '' then
        return true, ''
    end

    local modifier_string = modifiers.string_from_flags(ctrl_modifier, alt_modifier, shift_modifier)
    local is_blocked, error_msg = blocked_keybinds.is_combination_blocked(binding_key, modifier_string)
    if is_blocked then
        return false, error_msg or ''
    end

    return true, ''
end

-- ============================================================================
-- BIND COMMAND GENERATION
-- ============================================================================

-- Function to generate bind command string from binding data
function ui_functions.generate_bind_command(binding)
    local key_part = modifiers.prefix_from_string(binding.modifiers) .. binding.key

    local command = binding.command
    if command:sub(1, 1) ~= '/' then
        command = '/' .. command
    end

    return string.format('/bind %s %s', key_part, command)
end

-- ============================================================================
-- PROFILE FILE OPERATIONS
-- ============================================================================

-- Function to save bindings back to profile file
function ui_functions.save_bindings_to_profile(current_bindings, current_profile_path)
    if not current_profile_path then
        log.debugf('No profile path available for saving')
        return false
    end

    local file = io.open(current_profile_path, 'w')
    if not file then
        log.debugf('Could not open profile file for writing: %s', current_profile_path)
        return false
    end

    for _, binding in ipairs(current_bindings) do
        local bind_command = ui_functions.generate_bind_command(binding)
        file:write(bind_command .. '\n')
        log.debugf('Wrote binding: %s', bind_command)
    end

    file:close()
    log.debugf('Saved %d bindings to: %s', #current_bindings, current_profile_path)
    return true
end

-- Function to parse a bind command line
function ui_functions.parse_bind_line(line)
    -- Match: /bind <key-with-prefix> <command...>
    local modifiers_key, command = line:match('^/bind%s+(%S+)%s+(.+)$')
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

    -- Strip ^!+ prefix into modifier flags
    local key, ctrl, alt, shift = modifiers.strip_prefix(modifiers_key)

    return {
        key           = key:upper(),
        modifiers     = modifiers.string_from_flags(ctrl, alt, shift),
        command       = command,
        is_macro      = is_macro,
        macro_content = macro_content,
    }
end

-- Function to load bindings from profile file
function ui_functions.load_bindings_from_profile(profile_path)
    local current_bindings = {}

    if not profile_path then
        log.debugf('No profile path provided')
        return current_bindings
    end

    local file = io.open(profile_path, 'r')
    if not file then
        log.debugf('Could not open profile file: %s', profile_path)
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
                log.debugf('Parsed binding: %s%s -> %s%s',
                    binding.key,
                    binding.modifiers ~= '' and (' (' .. binding.modifiers .. ')') or '',
                    binding.command,
                    binding.is_macro and ' [MACRO]' or '')
            else
                log.debugf('Failed to parse bind line: %s', line)
            end
        end
    end

    file:close()
    log.debugf('Loaded %d bindings from %d lines in: %s', bind_count, line_count, profile_path)

    return current_bindings
end

-- ============================================================================
-- MACRO FILE OPERATIONS
-- ============================================================================

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
function ui_functions.save_current_binding(binding_data, current_bindings, current_profile_path)
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

    -- Build modifier string
    local modifier_string = modifiers.string_from_flags(
        binding_data.ctrl_modifier,
        binding_data.alt_modifier,
        binding_data.shift_modifier
    )

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
        key       = binding_data.key,
        modifiers = modifier_string,
        command   = binding_data.command,
        is_macro  = binding_data.is_macro,
        is_global = binding_data.is_global or false,
    }

    -- Handle macro
    if binding_data.is_macro then
        local macro_filename = binding_data.command
        if not macro_filename or macro_filename == '' then
            return false, 'Please enter a macro filename'
        end
        if not macro_filename:match('%.txt$') then
            macro_filename = macro_filename .. '.txt'
        end

        if not ui_functions.create_macro_file(macro_filename, binding_data.macro_text) then
            return false, 'Failed to save macro file'
        end

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

    table.insert(current_bindings, new_binding)

    if ui_functions.save_bindings_to_profile(current_bindings, current_profile_path) then
        local bind_command = ui_functions.generate_bind_command(new_binding)
        AshitaCore:GetChatManager():QueueCommand(1, bind_command)
        return true, ''
    else
        return false, 'Failed to save profile'
    end
end

-- Function to delete current binding
function ui_functions.delete_current_binding(binding_data, current_bindings, current_profile_path)
    if binding_data.key == '' then
        return false, 'Please select a key'
    end

    local modifier_string = modifiers.string_from_flags(
        binding_data.ctrl_modifier,
        binding_data.alt_modifier,
        binding_data.shift_modifier
    )

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

    if ui_functions.save_bindings_to_profile(current_bindings, current_profile_path) then
        local key_part = modifiers.prefix_from_flags(
            binding_data.ctrl_modifier,
            binding_data.alt_modifier,
            binding_data.shift_modifier
        ) .. binding_data.key
        AshitaCore:GetChatManager():QueueCommand(1, '/unbind ' .. key_part)
        return true, ''
    else
        return false, 'Failed to save profile'
    end
end

return ui_functions;
