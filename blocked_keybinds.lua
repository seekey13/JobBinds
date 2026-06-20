-- Blocked key configurations for JobBinds addon
-- These define which keys cannot be used for bindings to protect essential game functions

local M = {}

-- Keys that are completely blocked and cannot be bound in any context
M.blocked = {
    ['A'] = true,
    ['D'] = true,
    ['F'] = true,
    ['H'] = true,
    ['I'] = true,
    ['J'] = true,
    ['K'] = true,
    ['L'] = true,
    ['N'] = true,
    ['R'] = true,
    ['S'] = true,
    ['V'] = true,
    ['W'] = true,
    ['Y'] = true,
    [','] = true,
    ['.'] = true,
    ['/'] = true,
    ['-'] = true,
    ['UP'] = true,
    ['DOWN'] = true,
    ['LEFT'] = true,
    ['RIGHT'] = true,
    ['F1'] = true,
    ['F2'] = true,
    ['F3'] = true,
    ['F4'] = true,
    ['F5'] = true,
    ['F6'] = true,
    ['F7'] = true,
    ['F8'] = true,
    ['F9'] = true,
    ['F10'] = true,
    ['F11'] = true,
    ['F12'] = true,
    ['ESCAPE'] = true,
    ['ESC'] = true,
    ['BACKSPACE'] = true,
    ['<--'] = true,
    ['TAB'] = true,
    ['ENTER'] = true,
    ['SPACE'] = true,
    ['PRINTSCREEN'] = true,
    ['CAPS'] = true,
    ['CAPSLOCK'] = true,
    ['LCTRL'] = true,
    ['RCTRL'] = true,
    ['CTRL'] = true,
    ['LSHIFT'] = true,
    ['RSHIFT'] = true,
    ['SHIFT'] = true,
    ['LALT'] = true,
    ['RALT'] = true,
    ['ALT'] = true,
    ['LWIN'] = true,
    ['RWIN'] = true,
    ['WIN'] = true,
    ['PAGEUP'] = true,
    ['PAGEDOWN'] = true,
    ['INSERT'] = true,
    ['HOME'] = true,
    ['END'] = true,
}

-- Keys that can be used alone or with Shift, but not with Ctrl or Alt
M.blocked_with_modifiers = {
    ['B'] = true,
    ['E'] = true,
    ['M'] = true,
    ['Q'] = true,
    ['T'] = true,
    ['U'] = true,
    ['X'] = true,
    ['0'] = true,
    ['1'] = true,
    ['2'] = true,
    ['3'] = true,
    ['4'] = true,
    ['5'] = true,
    ['6'] = true,
    ['7'] = true,
    ['8'] = true,
    ['9'] = true,
}

-- Function to check if a key is blocked
function M.is_key_blocked(key)
    if not key then return false end
    return M.blocked[key:upper()] == true
end

-- Function to check if a key combination is blocked
function M.is_combination_blocked(key, modifiers)
    if not key then return false end
    
    local base_key = key:upper()
    
    -- Check if base key is completely blocked
    if M.is_key_blocked(base_key) then
        return true, string.format("Key '%s' is protected and cannot be rebound", base_key)
    end
    
    -- Check for restricted modifier combinations
    if M.blocked_with_modifiers[base_key] and modifiers then
        local mod_string = modifiers:upper()
        
        -- Block Ctrl combinations for restricted keys
        if mod_string:find('CTRL') then
            return true, string.format("'%s' cannot be used with Ctrl modifier", base_key)
        end
        
        -- Block Alt combinations for restricted keys
        if mod_string:find('ALT') then
            return true, string.format("'%s' cannot be used with Alt modifier", base_key)
        end
    end
    
    -- Special cases for certain combinations that should always be blocked
    if modifiers then
        local mod_string = modifiers:upper()
        
        -- Block Alt+F4 (close application)
        if base_key == 'F4' and mod_string:find('ALT') then
            return true, "Alt+F4 is protected (closes application)"
        end
        
        -- Block Ctrl+Alt+Delete equivalent combinations
        if mod_string:find('CTRL') and mod_string:find('ALT') and base_key == 'DELETE' then
            return true, "Ctrl+Alt+Delete combination is protected"
        end
        
        -- Block Windows key combinations
        if mod_string:find('WIN') then
            return true, "Windows key combinations are protected"
        end
    end
    
    return false, nil
end


return M
