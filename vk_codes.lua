--[[
* Windows Virtual Key Codes (VK Codes) Reference
* Used by Ashita's ImGui implementation for key detection
* Based on Microsoft Windows API Virtual-Key Codes
* https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
--]]

local vk_codes = {};

-- Windows Virtual Key Code to Key Name mapping
vk_codes.key_mappings = {

    -- Control keys
    [8] = 'Backspace',   -- BACKSPACE key
    [9] = 'Tab',         -- TAB key
    [13] = 'Enter',      -- ENTER key
    [16] = 'Shift',      -- SHIFT key
    [17] = 'Ctrl',       -- CTRL key
    [18] = 'Alt',        -- ALT key
    [19] = 'Pause',      -- PAUSE key
    [20] = 'CapsLock',   -- CAPS LOCK key
    [27] = 'Escape',     -- ESC key
    [32] = 'Space',      -- SPACEBAR
    [33] = 'PageUp',     -- PAGE UP key
    [34] = 'PageDown',   -- PAGE DOWN key
    [35] = 'End',        -- END key
    [36] = 'Home',       -- HOME key
    
    -- Arrow keys
    [37] = 'Left',       -- LEFT ARROW key
    [38] = 'Up',         -- UP ARROW key
    [39] = 'Right',      -- RIGHT ARROW key
    [40] = 'Down',       -- DOWN ARROW key
    
    -- Edit keys
    [45] = 'Insert',     -- INS key
    [46] = 'Delete',     -- DEL key
    
    -- Number keys (top row)
    [48] = '0', [49] = '1', [50] = '2', [51] = '3', [52] = '4',
    [53] = '5', [54] = '6', [55] = '7', [56] = '8', [57] = '9',
    
    -- Letter keys A-Z
    [65] = 'A', [66] = 'B', [67] = 'C', [68] = 'D', [69] = 'E', [70] = 'F',
    [71] = 'G', [72] = 'H', [73] = 'I', [74] = 'J', [75] = 'K', [76] = 'L',
    [77] = 'M', [78] = 'N', [79] = 'O', [80] = 'P', [81] = 'Q', [82] = 'R',
    [83] = 'S', [84] = 'T', [85] = 'U', [86] = 'V', [87] = 'W', [88] = 'X',
    [89] = 'Y', [90] = 'Z',
    
    -- Windows keys
    [91] = 'LWin',       -- Left Windows key
    [92] = 'RWin',       -- Right Windows key
    [93] = 'Apps',       -- Applications key
    
    -- Numeric keypad
    [96] = 'Numpad0', [97] = 'Numpad1', [98] = 'Numpad2', [99] = 'Numpad3', [100] = 'Numpad4',
    [101] = 'Numpad5', [102] = 'Numpad6', [103] = 'Numpad7', [104] = 'Numpad8', [105] = 'Numpad9',
    [106] = 'Multiply',  -- Multiply key (*)
    [107] = 'Add',       -- Add key (+)
    [109] = 'Subtract',  -- Subtract key (-)
    [110] = 'Decimal',   -- Decimal key (.)
    [111] = 'Divide',    -- Divide key (/)
    
    -- Function keys F1-F24
    [112] = 'F1', [113] = 'F2', [114] = 'F3', [115] = 'F4', [116] = 'F5', [117] = 'F6',
    [118] = 'F7', [119] = 'F8', [120] = 'F9', [121] = 'F10', [122] = 'F11', [123] = 'F12',
    [124] = 'F13', [125] = 'F14', [126] = 'F15', [127] = 'F16', [128] = 'F17', [129] = 'F18',
    [130] = 'F19', [131] = 'F20', [132] = 'F21', [133] = 'F22', [134] = 'F23', [135] = 'F24',
    
    -- Lock keys
    [144] = 'NumLock',   -- NUM LOCK key
    [145] = 'ScrollLock', -- SCROLL LOCK key
    
    -- Shift keys (left/right specific)
    [160] = 'LShift',    -- Left SHIFT key
    [161] = 'RShift',    -- Right SHIFT key
    [162] = 'LCtrl',     -- Left CONTROL key
    [163] = 'RCtrl',     -- Right CONTROL key
    [164] = 'LAlt',      -- Left ALT key
    [165] = 'RAlt',      -- Right ALT key
    
    -- Symbol keys (US QWERTY layout)
    [186] = ';',         -- Semicolon key
    [187] = '=',         -- Equals key
    [188] = ',',         -- Comma key
    [189] = '-',         -- Minus key
    [190] = '.',         -- Period key
    [191] = '/',         -- Forward slash key
    [192] = '`',         -- Grave accent key
    [219] = '[',         -- Left bracket key
    [220] = '\\',        -- Backslash key
    [221] = ']',         -- Right bracket key
    [222] = "'",         -- Apostrophe key
};

-- Reverse lookup: Key Name to VK Code
vk_codes.name_to_code = {};
for code, name in pairs(vk_codes.key_mappings) do
    vk_codes.name_to_code[name] = code;
end

-- Function to get key name from VK code
function vk_codes.get_key_name(vk_code)
    return vk_codes.key_mappings[vk_code] or ('KEY_' .. vk_code);
end

-- Function to get VK code from key name
function vk_codes.get_vk_code(key_name)
    return vk_codes.name_to_code[key_name];
end

-- Function to check if a VK code is a known key
function vk_codes.is_known_key(vk_code)
    return vk_codes.key_mappings[vk_code] ~= nil;
end

-- Function to get all available keys (for UI dropdowns, etc.)
function vk_codes.get_all_keys()
    local keys = {};
    for _, name in pairs(vk_codes.key_mappings) do
        table.insert(keys, name);
    end
    table.sort(keys);
    return keys;
end

return vk_codes;
