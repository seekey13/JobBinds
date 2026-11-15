--[[
* JobBinds engine: puts bindings on keys and runs their commands.
*
* Every bound key is bound to '/jobbinds run <n>'. The addon then sends the
* binding's commands itself, in order, honouring '/wait <seconds>' lines and a
* trailing '<wait n>'. Nothing is written to the scripts folder.
--]]

local engine = {};

local active = {}; -- the bindings on keys right now; a key runs active[n]
local runs = {};   -- n -> { lines, pos, at }: bindings part way through their commands

local function queue(command)
    AshitaCore:GetChatManager():QueueCommand(1, command);
end

-- Take every key back.
function engine.clear()
    for _, binding in ipairs(active) do
        queue('/unbind ' .. binding.id);
    end
    active = {};
    runs = {};
end

-- Replace what's bound with these bindings (profiles.effective's list).
function engine.apply(bindings)
    engine.clear();
    for n, binding in ipairs(bindings) do
        queue(('/bind %s /jobbinds run %d'):format(binding.id, n));
    end
    active = bindings;
end

-- Send the run's commands up to its next wait. True while there is more to do.
local function step(run, now)
    while run.pos <= #run.lines and now >= run.at do
        local line = run.lines[run.pos];
        run.pos = run.pos + 1;

        local wait = line:lower():match('^/wait%s*([%d%.]*)%s*$');
        if wait then
            wait = tonumber(wait) or 1;
        else
            local command, seconds = line:match('^(.-)%s*<wait%s+([%d%.]+)>%s*$');
            if command then
                line, wait = command, tonumber(seconds);
            end
            if line ~= '' then
                queue(line);
            end
        end
        if wait then
            run.at = now + wait;
        end
    end
    return run.pos <= #run.lines;
end

-- A bound key was pressed. Pressing it again part way through starts it over.
function engine.run(n)
    local binding = active[n];
    if not binding then
        return;
    end
    local run = { lines = binding.lines, pos = 1, at = 0 };
    runs[n] = step(run, os.clock()) and run or nil;
end

-- Call every frame: carries on the bindings that are waiting.
function engine.tick()
    if next(runs) == nil then
        return;
    end
    local now = os.clock();
    for n, run in pairs(runs) do
        if not step(run, now) then
            runs[n] = nil;
        end
    end
end

return engine;
