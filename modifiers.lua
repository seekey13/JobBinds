--[[
* Modifier helpers for JobBinds
* Single source of truth for Ctrl/Alt/Shift <-> ^/!/+ conversions.
--]]

local modifiers = {}

-- Canonical order: Ctrl, Alt, Shift (matches Ashita /bind prefix order ^!+)
modifiers.ORDER = { 'Ctrl', 'Alt', 'Shift' }

-- Name -> single-char prefix used by Ashita's /bind command
modifiers.PREFIX = {
    Ctrl  = '^',
    Alt   = '!',
    Shift = '+',
}

-- Build the "Ctrl+Alt+Shift" style string from boolean flags.
function modifiers.string_from_flags(ctrl, alt, shift)
    local parts = {}
    if ctrl  then parts[#parts + 1] = 'Ctrl'  end
    if alt   then parts[#parts + 1] = 'Alt'   end
    if shift then parts[#parts + 1] = 'Shift' end
    return table.concat(parts, '+')
end

-- Build the "^!+" style prefix used in /bind commands and macro filenames.
function modifiers.prefix_from_flags(ctrl, alt, shift)
    local s = ''
    if ctrl  then s = s .. modifiers.PREFIX.Ctrl  end
    if alt   then s = s .. modifiers.PREFIX.Alt   end
    if shift then s = s .. modifiers.PREFIX.Shift end
    return s
end

-- Build the prefix from a "Ctrl+Alt+Shift" style string (case-insensitive).
function modifiers.prefix_from_string(mod_string)
    if not mod_string or mod_string == '' then return '' end
    local up = mod_string:upper()
    return modifiers.prefix_from_flags(
        up:find('CTRL')  ~= nil,
        up:find('ALT')   ~= nil,
        up:find('SHIFT') ~= nil
    )
end

-- Parse leading ^!+ prefix off a key string. Returns key, ctrl, alt, shift.
function modifiers.strip_prefix(key)
    local ctrl, alt, shift = false, false, false
    while true do
        local c = key:sub(1, 1)
        if     c == '^' then ctrl  = true; key = key:sub(2)
        elseif c == '!' then alt   = true; key = key:sub(2)
        elseif c == '+' then shift = true; key = key:sub(2)
        else break end
    end
    return key, ctrl, alt, shift
end

-- Convert a "Ctrl+Alt+Shift" style string into boolean flags.
function modifiers.flags_from_string(mod_string)
    if not mod_string or mod_string == '' then
        return false, false, false
    end
    local up = mod_string:upper()
    return up:find('CTRL')  ~= nil,
           up:find('ALT')   ~= nil,
           up:find('SHIFT') ~= nil
end

return modifiers
