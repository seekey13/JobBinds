--[[
* JobBinds
* Automatically loads keybind profile scripts based on current job and subjob.
* Copyright (c) 2025 Seekey
* https://github.com/seekey13/jobbinds
*
* Version: 0.1
* Author: Seekey
* Desc  : Binds management per job/subjob. Unbinds previous profile, loads new profile after delay on job change.
*         Key blacklist enforced. Profiles are .txt scripts in Ashita/scripts. No fallback/default profile.
*
* This addon is designed for Ashita v4.
--]]

addon.name      = 'JobBinds';
addon.author    = 'Seekey';
addon.version   = '0.1';
addon.desc      = 'Automatically loads keybind profile scripts based on current job/subjob.';
addon.link      = 'https://github.com/seekey13/jobbinds';

require('common');

-- Blacklist keys (cannot be bound/unbound by this addon)
local KEY_BLACKLIST = {
    ['W'] = true,
    ['A'] = true,
    ['S'] = true,
    ['D'] = true,
    ['F'] = true,
    ['V'] = true,
}

-- Helper functions for printing
local function printf(fmt, ...)  print(string.format('[JobBinds] ' .. fmt, ...)) end
local function errorf(fmt, ...) print(string.format('[JobBinds] ERROR: ' .. fmt, ...)) end

-- Holds the last loaded job/subjob profile info
local last_job = nil
local last_subjob = nil
local last_profile_keys = {}
local jobbinds_delay = 10 -- seconds delay after job/subjob change

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
    local ok, lines = pcall(function() return io.lines(profile_path) end)
    if not ok or not lines then
        return nil
    end
    local keys = {}
    for line in lines do
        local b = line:match('^/bind%s+([!@#%^+%w]+)')
        if b and not KEY_BLACKLIST[b] then
            keys[#keys+1] = b
        end
    end
    return keys
end

-- Unbind previous job profile keys
local function unload_profile(keys)
    if not keys then return end
    for _, key in ipairs(keys) do
        if not KEY_BLACKLIST[key] then
            local ok = pcall(function()
                AshitaCore:GetChatManager():QueueCommand(-1, string.format('/unbind %s', key))
            end)
            if not ok then
                errorf("Failed to unbind key: %s", key)
            end
        end
    end
    printf('Previous job/subjob binds unloaded.')
end

-- Load new profile via /exec
local function load_profile(jobid, subjobid)
    local profile_path = get_profile_path(jobid, subjobid)
    -- Ensure file exists
    local file = io.open(profile_path, "r")
    if not file then
        errorf('Profile %s not found.', profile_path)
        return false
    end
    file:close()
    local ok = pcall(function()
        AshitaCore:GetChatManager():QueueCommand(-1, string.format('/exec %s', get_profile_filename(jobid, subjobid)))
    end)
    if ok then
        printf('Loaded jobbinds profile: %s', get_profile_filename(jobid, subjobid))
        return true
    else
        errorf('Failed to load profile: %s', get_profile_filename(jobid, subjobid))
        return false
    end
end

-- Handle job change logic
local function handle_job_change()
    local jobid, subjobid = get_current_jobs()
    if not jobid or not subjobid then return end
    if jobid == last_job and subjobid == last_subjob then
        return
    end
    -- Unload previous profile
    unload_profile(last_profile_keys)
    last_job, last_subjob = jobid, subjobid
    last_profile_keys = nil

    -- Delay before loading new profile
    ashita.tasks.once(jobbinds_delay, function()
        -- Load new profile
        local loaded = load_profile(jobid, subjobid)
        if loaded then
            -- Track keys for future unload
            last_profile_keys = read_profile_keys(get_profile_path(jobid, subjobid))
        end
    end)
end

-- Initial load event
ashita.events.register('load', 'jobbinds_load', function()
    -- Populate initial job/subjob and load profile
    local jobid, subjobid = get_current_jobs()
    last_job, last_subjob = jobid, subjobid
    if jobid and subjobid then
        local loaded = load_profile(jobid, subjobid)
        if loaded then
            last_profile_keys = read_profile_keys(get_profile_path(jobid, subjobid))
        end
    end
end)

-- Listen for job/subjob change packets (0x1B, 0x44 most common for job change)
ashita.events.register('packet_in', 'jobbinds_packet_in', function(e)
    -- 0x1B = job info, 0x44 = character update, 0x1A = party update; all candidates
    if (e.id == 0x1B or e.id == 0x44 or e.id == 0x1A) then
        ashita.tasks.once(0.5, function()
            handle_job_change()
        end)
    end
end)

-- On zone change (optional: could unload/reload profile, but FFXI job changes are not zone-based)
-- You could hook 0x0A (zone enter) if needed.

-- For future: Add a /jobbinds debug command, or more options.

-- Startup message
printf('JobBinds v%s by %s loaded. Profiles will auto-load on job/subjob change.', addon.version, addon.author)
