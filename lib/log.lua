--[[
* Logging module for JobBinds
* Centralizes printf/warnf/errorf/debugf and the debug_mode flag.
--]]

local chat = require('chat')

local log = {}

local addon_name = 'JobBinds'
local debug_mode = false

local function emit(formatter, fmt, ...)
    print(chat.header(addon_name) .. formatter(fmt:format(...)))
end

function log.set_addon_name(name)
    addon_name = name or addon_name
end

function log.set_debug(enabled)
    debug_mode = enabled and true or false
end

function log.is_debug()
    return debug_mode
end

function log.printf(fmt, ...)
    emit(chat.message, fmt, ...)
end

function log.warnf(fmt, ...)
    emit(chat.warning, fmt, ...)
end

function log.errorf(fmt, ...)
    emit(chat.error, fmt, ...)
end

function log.debugf(fmt, ...)
    if debug_mode then
        emit(chat.message, '[DEBUG] ' .. fmt, ...)
    end
end

return log
