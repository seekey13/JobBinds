--[[
* JobBinds
* Automatically loads keybind profile scripts based on current job and subjob.
* Copyright (c) 2025 Seekey

* This addon is designed for Ashita v4.
--]]

addon.name      = 'JobBinds';
addon.author    = 'Seekey';
addon.version   = '0.6';
addon.desc      = 'Automatically loads keybind profile scripts based on current job/subjob.';
addon.link      = 'https://github.com/seekey13/jobbinds';

require('common');
local chat = require('chat')
local config_ui = require('config_ui');
local keyboard_ui = require('keyboard_ui');
local blocked_keybinds = require('blocked_keybinds');

-- Use the blocked_keybinds module for consistency
local KEY_BLACKLIST = blocked_keybinds.blocked;

-- Custom print functions for categorized output.
local function printf(fmt, ...)  print(chat.header(addon.name) .. chat.message(fmt:format(...))) end
local function warnf(fmt, ...)   print(chat.header(addon.name) .. chat.warning(fmt:format(...))) end
local function errorf(fmt, ...)  print(chat.header(addon.name) .. chat.error  (fmt:format(...))) end
local function debugf(fmt, ...) 
    if debug_mode then
        print(chat.header(addon.name) .. chat.message('[DEBUG] ' .. fmt:format(...))) 
    end
end

-- Holds the last loaded job/subjob profile info
local last_job = nil
local last_subjob = nil
local last_profile_keys = {}

-- Debug mode flag (off by default)
local debug_mode = false

-- Helper: Get current job and subjob
local function get_current_jobs()
    local ok, party = pcall(function() return AshitaCore:GetMemoryManager():GetParty() end)
    if not ok or not party then
        errorf('Failed to get party info for job detection.')
        return nil, nil
    end
    local okj, job = pcall(function() return party:GetMemberMainJob(0) end)
    local oksj, subjob = pcall(function() return party:GetMemberSubJob(0) end)
    if not okj or not oksj then
        errorf('Failed to get job/subjob from party object.')
        return nil, nil
    end
    debugf('Current jobs detected: Main=%d, Sub=%d', job, subjob)
    return job, subjob
end

-- Helper: Get job/subjob short names (WAR, NIN, etc.)
local function get_job_shortname(jobid)
    local ok, name = pcall(function() return AshitaCore:GetResourceManager():GetString('jobs.names_abbr', jobid) end)
    if ok and name then
        return name:upper()
    end
    return tostring(jobid)
end

-- Helper: Build profile filename (e.g., WAR_NIN.txt)
local function get_profile_filename(jobid, subjobid)
    local job = get_job_shortname(jobid)
    local subjob = get_job_shortname(subjobid)
    return string.format('%s_%s.txt', job, subjob)
end

-- Helper: Full path to profile
local function get_profile_path(jobid, subjobid)
    local filename = get_profile_filename(jobid, subjobid)
    return string.format('%s/scripts/%s', AshitaCore:GetInstallPath(), filename)
end

-- Helper: Read profile keys from .txt file
local function read_profile_keys(profile_path)
    debugf('Reading profile keys from: %s', profile_path)
    local ok, lines = pcall(function() return io.lines(profile_path) end)
    if not ok or not lines then
        debugf('Failed to read profile file: %s', profile_path)
        return nil
    end
    local keys = {}
    for line in lines do
        local b = line:match('^/bind%s+([!@#%^+%w]+)')
        if b and not KEY_BLACKLIST[b] then
            keys[#keys+1] = b
            debugf('Found bindable key: %s', b)
        elseif b and KEY_BLACKLIST[b] then
            debugf('Skipped blacklisted key: %s', b)
        end
    end
    debugf('Total keys found: %d', #keys)
    return keys
end

-- Unbind previous job profile keys
local function unload_profile(keys)
    if not keys then 
        debugf('No keys to unbind')
        return 
    end
    debugf('Unbinding %d keys', #keys)
    for _, key in ipairs(keys) do
        if not KEY_BLACKLIST[key] then
            debugf('Unbinding key: %s', key)
            local ok = pcall(function()
                AshitaCore:GetChatManager():QueueCommand(-1, string.format('/unbind %s', key))
            end)
            if not ok then
                errorf("Failed to unbind key: %s", key)
            end
        else
            debugf('Skipped unbinding blacklisted key: %s', key)
        end
    end
    printf('Previous job/subjob binds unloaded.')
end

-- Helper: Get safe job name for display (handles nil values)
local function get_safe_job_name(jobid)
    return jobid and get_job_shortname(jobid) or 'nil'
end

-- Helper: Update config UI with profile information
local function update_config_ui(profile_filename, profile_path)
    config_ui.set_current_profile(profile_filename)
    config_ui.load_profile(profile_path)
end

-- Load new profile via /exec
local function load_profile(jobid, subjobid)
    local profile_path = get_profile_path(jobid, subjobid)
    local profile_filename = get_profile_filename(jobid, subjobid)
    debugf('Attempting to load profile: %s', profile_path)
    
    -- Ensure file exists
    local file = io.open(profile_path, "r")
    if not file then
        errorf('Profile %s not found.', profile_path)
        debugf('Profile file does not exist at: %s', profile_path)
        return false
    end
    file:close()
    debugf('Profile file exists, executing: %s', profile_filename)
    
    local ok = pcall(function()
        AshitaCore:GetChatManager():QueueCommand(-1, string.format('/exec %s', profile_filename))
    end)
    if ok then
        printf('Loaded jobbinds profile: %s', profile_filename)
        -- Update the config UI with the current profile
        update_config_ui(profile_filename, profile_path)
        debugf('Successfully loaded and updated UI with profile: %s', profile_filename)
        return true
    else
        errorf('Failed to load profile: %s', profile_filename)
        return false
    end
end

-- Helper: Load profile and track keys for future unload
local function load_and_track_profile(jobid, subjobid)
    local loaded = load_profile(jobid, subjobid)
    if loaded then
        last_profile_keys = read_profile_keys(get_profile_path(jobid, subjobid))
    end
    return loaded
end

-- Handle job change logic
local function handle_job_change()
    local jobid, subjobid = get_current_jobs()
    if not jobid or not subjobid then return end
    if jobid == last_job and subjobid == last_subjob then
        return
    end
    
    printf('Job change detected: %s/%s -> %s/%s', 
           get_safe_job_name(last_job),
           get_safe_job_name(last_subjob),
           get_safe_job_name(jobid), 
           get_safe_job_name(subjobid))
    
    -- Unload previous profile
    unload_profile(last_profile_keys)
    -- Clear the config UI profile name and bindings
    update_config_ui(nil, nil)
    
    -- Update job tracking
    last_job, last_subjob = jobid, subjobid
    last_profile_keys = nil

    -- Load new profile immediately
    load_and_track_profile(jobid, subjobid)
end

-- Initial load event
ashita.events.register('load', 'jobbinds_load', function()
    -- Populate initial job/subjob and load profile
    local jobid, subjobid = get_current_jobs()
    last_job, last_subjob = jobid, subjobid
    if jobid and subjobid then
        load_and_track_profile(jobid, subjobid)
    end
end)

-- Listen for job/subjob change packets (0x1B, 0x44 most common for job change)
ashita.events.register('packet_in', 'jobbinds_packet_in', function(e)
    -- 0x1B = job info, 0x44 = character update, 0x1A = party update; all candidates
    if (e.id == 0x1B or e.id == 0x44 or e.id == 0x1A) then
        debugf('Received packet 0x%02X, scheduling job change check', e.id)
        ashita.tasks.once(0.5, function()
            handle_job_change()
        end)
    end
end)

-- On zone change (optional: could unload/reload profile, but FFXI job changes are not zone-based)
-- You could hook 0x0A (zone enter) if needed.

-- Command handler for /jobbinds
ashita.events.register('command', 'jobbinds_command', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/jobbinds' then
        return
    end
    
    e.blocked = true
    
    if #args == 1 then
        -- No additional arguments, show the config UI
        config_ui.show()
        printf('Opening JobBinds configuration window.')
    elseif #args == 2 and args[2]:lower() == 'debug' then
        -- Toggle debug mode
        debug_mode = not debug_mode
        config_ui.set_debug_mode(debug_mode)  -- Update UI debug mode
        keyboard_ui.set_debug_mode(debug_mode)  -- Update keyboard UI debug mode
        printf('Debug mode %s.', debug_mode and 'enabled' or 'disabled')
        if debug_mode then
            debugf('Debug information will now be displayed.')
            debugf('Current state: last_job=%s, last_subjob=%s', 
                   get_safe_job_name(last_job),
                   get_safe_job_name(last_subjob))
            debugf('Profile keys tracked: %d', last_profile_keys and #last_profile_keys or 0)
        end
    elseif #args == 2 and args[2]:lower() == 'kb' then
        -- Show the keyboard UI
        keyboard_ui.show()
        printf('Opening JobBinds keyboard interface.')
    else
        -- Handle unknown commands
        printf('Usage: /jobbinds [debug|kb]')
        printf('  /jobbinds       - Open configuration window')
        printf('  /jobbinds debug - Toggle debug information')
        printf('  /jobbinds kb    - Open keyboard interface')
    end
end)

-- Render loop for ImGui
ashita.events.register('d3d_present', 'jobbinds_render', function()
    config_ui.render()
    keyboard_ui.render()
end)

-- For future: Add a /jobbinds debug command, or more options.

-- Startup message
printf('JobBinds v%s by %s loaded. Profiles will auto-load on job/subjob change.', addon.version, addon.author)
