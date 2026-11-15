--[[
* JobBinds import: brings JobBinds 1.x profiles (scripts/JOB_SUB.txt and the
* global scripts/JobBinds.txt, made of /bind lines and /exec'd macro files)
* into 2.0 profiles. The old files are
* left as they are, and a 2.0 profile that already exists is never replaced.
--]]

local profiles = require('profiles');

local import = {};

local function trim(text)
    return (text:match('^%s*(.-)%s*$'));
end

local function read_lines(path)
    local file = io.open(path, 'r');
    if not file then
        return nil;
    end
    local lines = {};
    for line in file:lines() do
        line = trim(line);
        if line ~= '' then
            lines[#lines + 1] = line;
        end
    end
    file:close();
    return lines;
end

-- What a 1.x bind ran: the lines of the macro file it /exec'd, or the command itself.
local function commands_of(command)
    command = command:match('^"(.*)"$') or command;
    local script = command:match('^/exec%s+(.+)$');
    if script then
        if not script:lower():match('%.txt$') then
            script = script .. '.txt';
        end
        local lines = read_lines(profiles.scripts_dir .. '\\' .. script);
        if lines and #lines > 0 then
            return lines;
        end
    end
    return { command };
end

-- Returns how many profiles were imported and how many were skipped because
-- a 2.0 profile of that name already exists.
function import.run()
    local ok, files = pcall(ashita.fs.get_dir, profiles.scripts_dir, '.*', true);
    if not ok or type(files) ~= 'table' then
        return 0, 0;
    end

    local imported, skipped = 0, 0;
    for _, name in pairs(files) do
        local main, sub = name:upper():match('^(%u%u%u)_(%u%u%u)%.TXT$');
        -- JobBinds.txt held 1.x's global bindings
        local id = main and (main .. '_' .. sub) or (name:upper() == 'JOBBINDS.TXT' and 'ALL') or nil;
        local lines = id and read_lines(profiles.scripts_dir .. '\\' .. name) or {};
        local found = false;

        if id and ashita.fs.exists(profiles.path(id)) then
            skipped = skipped + 1;
        else
            for _, line in ipairs(lines) do
                local spec, command = line:match('^/bind%s+(%S+)%s+(.+)$');
                local chord = spec and profiles.parse_chord(spec);
                if chord then
                    profiles.set(id, chord.id, commands_of(command));
                    found = true;
                end
            end
        end

        if found and profiles.save(id) then
            imported = imported + 1;
        end
    end
    return imported, skipped;
end

return import;
