--[[
* JobBinds
* Key bindings that follow your job and subjob, edited on a visual keyboard.
* Copyright (c) 2025 Seekey
*
* This addon is designed for Ashita v4.
--]]

addon.name      = 'JobBinds';
addon.author    = 'Seekey';
addon.version   = '2.1';
addon.desc      = 'Key bindings that follow your job and subjob, and hotbars that show them.';
addon.link      = 'https://github.com/seekey13/jobbinds';

require('common');
local chat = require('chat');
local profiles = require('profiles');
local engine = require('engine');
local style = require('style');
local keyboard_ui = require('keyboard_ui');
local hotbars = require('hotbars');
local hotbar_ui = require('hotbar_ui');
local recasts = require('recasts');
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

-- Bind the keys for the applied job from its profiles, and show them in the
-- window and on the hotbars.
local function refresh()
    local main, sub = job_name(applied_main), job_name(applied_sub);
    local scopes = profiles.scopes(main, sub);
    local bindings = main and profiles.effective(scopes) or {};
    engine.apply(bindings);
    keyboard_ui.set_context(scopes, bindings, refresh);
    hotbar_ui.set_bindings(bindings, hotbars.job_key(main, sub));
    return #bindings, main, sub;
end

local function load_hotbars()
    local ok, err = hotbars.load();
    if not ok then
        printf('%s', err);
    end
    hotbar_ui.reset();
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
    keyboard_ui.load(); -- the window's fonts, before any frame
    -- First run of 2.0: bring the 1.x profiles along
    if not ashita.fs.exists(profiles.dir) then
        local imported = import.run();
        if imported > 0 then
            printf('Imported %d JobBinds 1.x profile%s from the scripts folder.', imported, imported == 1 and '' or 's');
        end
    end
    load_hotbars();
    refresh();
end);

ashita.events.register('unload', 'jobbinds_unload', function ()
    engine.clear();
    if hotbars.is_dirty() then
        local ok, err = hotbars.save(); -- a change made in the last moment before unloading
        if not ok then
            printf('Could not save hotbars.lua: %s', tostring(err));
        end
    end
end);

ashita.events.register('d3d_present', 'jobbinds_present', function ()
    local now = os.clock();
    if now >= next_poll then
        next_poll = now + POLL_SECONDS;
        poll_job();
    end
    engine.tick();

    style.frame(); -- once a frame, for the bars and the window both
    recasts.frame();
    hotbar_ui.render(keyboard_ui.editing_hotbars());
    keyboard_ui.render();
    style.tooltips();
    hotbars.save_if_idle();
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
    elseif action == 'bars' or action == 'hotbars' then
        keyboard_ui.open('hotbars');
    elseif action == 'reload' then
        profiles.reload();
        load_hotbars();
        local count = refresh();
        printf('Profiles and hotbars reloaded: %d key%s bound, %d hotbar%s.', count, count == 1 and '' or 's',
            #hotbars.list(), #hotbars.list() == 1 and '' or 's');
    elseif action == 'import' then
        run_import();
    else
        printf('/jb         - open or close the keyboard window');
        printf('/jb bars    - open the window on its Hotbars page');
        printf('/jb reload  - read the profile and hotbar files again after editing them by hand');
        printf('/jb import  - import JobBinds 1.x profiles from the scripts folder');
    end
end);
