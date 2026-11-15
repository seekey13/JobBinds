--[[
* JobBinds
* Key bindings that follow your job and subjob, edited on a visual keyboard.
* Copyright (c) 2025 Seekey
*
* This addon is designed for Ashita v4.
--]]

addon.name      = 'JobBinds';
addon.author    = 'Seekey';
addon.version   = '2.0';
addon.desc      = 'Key bindings that follow your job and subjob.';
addon.link      = 'https://github.com/seekey13/jobbinds';

require('common');
local chat = require('chat');
local profiles = require('profiles');
local engine = require('engine');
local keyboard_ui = require('keyboard_ui');
local import = require('import');

local function printf(fmt, ...) print(chat.header(addon.name) .. chat.message(fmt:format(...))); end

local POLL_SECONDS = 0.5;

local applied_main, applied_sub = nil, nil; -- the job ids the keys are bound for
local seen_main, seen_sub = nil, nil;       -- the job ids at the last poll
local next_poll = 0;

local function job_name(id)
    if id == nil or id == 0 then
        return nil;
    end
    local name = AshitaCore:GetResourceManager():GetString('jobs.names_abbr', id);
    return (name ~= nil and name ~= '') and name:upper() or nil;
end

-- Bind the keys for the applied job from its profiles, and show them in the window.
local function refresh()
    local main, sub = job_name(applied_main), job_name(applied_sub);
    local scopes = profiles.scopes(main, sub);
    local bindings = main and profiles.effective(scopes) or {};
    engine.apply(bindings);
    keyboard_ui.set_context(scopes, bindings, refresh);
    return #bindings, main, sub;
end

-- The job is read twice a second and acted on once it reads the same twice
-- running, so a half-updated job during a change or a zone is never applied.
local function poll_job()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then
        return;
    end
    local main, sub = player:GetMainJob(), player:GetSubJob();
    local settled = main == seen_main and sub == seen_sub;
    seen_main, seen_sub = main, sub;
    if not settled or (main == applied_main and sub == applied_sub) then
        return;
    end

    applied_main, applied_sub = main, sub;
    local count, main_name, sub_name = refresh();
    if main_name then
        printf('%s/%s: %d key%s bound.', main_name, sub_name or 'NON', count, count == 1 and '' or 's');
    end
end

local function run_import()
    local imported, skipped = import.run();
    printf('Imported %d JobBinds 1.x profile%s from the scripts folder%s.', imported, imported == 1 and '' or 's',
        skipped > 0 and (' (%d already existed)'):format(skipped) or '');
    refresh();
end

ashita.events.register('load', 'jobbinds_load', function ()
    -- First run of 2.0: bring the 1.x profiles along
    if not ashita.fs.exists(profiles.dir) then
        local imported = import.run();
        if imported > 0 then
            printf('Imported %d JobBinds 1.x profile%s from the scripts folder.', imported, imported == 1 and '' or 's');
        end
    end
    refresh();
end);

ashita.events.register('unload', 'jobbinds_unload', function ()
    engine.clear();
end);

ashita.events.register('d3d_present', 'jobbinds_present', function ()
    local now = os.clock();
    if now >= next_poll then
        next_poll = now + POLL_SECONDS;
        poll_job();
    end
    engine.tick();
    keyboard_ui.render();
end);

ashita.events.register('command', 'jobbinds_command', function (e)
    local args = e.command:args();
    if #args == 0 then
        return;
    end
    local command = args[1]:lower();
    if command ~= '/jobbinds' and command ~= '/jb' then
        return;
    end
    e.blocked = true;

    local action = args[2] and args[2]:lower() or nil;
    if action == nil then
        keyboard_ui.toggle();
    elseif action == 'run' then
        engine.run(tonumber(args[3])); -- what the bound keys send
    elseif action == 'reload' then
        profiles.reload();
        local count = refresh();
        printf('Profiles reloaded: %d key%s bound.', count, count == 1 and '' or 's');
    elseif action == 'import' then
        run_import();
    else
        printf('/jb         - open or close the keyboard window');
        printf('/jb reload  - read the profile files again after editing them by hand');
        printf('/jb import  - import JobBinds 1.x profiles from the scripts folder');
    end
end);
