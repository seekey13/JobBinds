--[[
* JobBinds hotbars on screen. Each bar is a borderless window of slots: a slot
* shows its key, a label, and while a recast it watches is running, a dark
* fade with the seconds left. Clicking a slot runs its key's binding.
*
* While the window's Hotbars page is open every bar shows, a bar whose
* conditions don't hold now faded. A tab with the bar's name moves it, and
* clicking a slot picks it for the page to edit.
--]]

require('common');
local imgui = require('imgui');
local style = require('style');
local profiles = require('profiles');
local engine = require('engine');
local hotbars = require('hotbars');
local recasts = require('recasts');
local conditions = require('conditions');

local P, S, mix = style.P, style.S, style.mix;

local hotbar_ui = {};

local TAB_H = 22;     -- the tab a bar is moved by, in the editor
local EDGE = 6;       -- round a bar: room for its outline in the editor
local FLASH = 0.6;    -- seconds a slot glows once its recast is over
local HIDDEN = 0.45;  -- a bar's alpha in the editor while its conditions don't hold

local BAR_FLAGS = ImGuiWindowFlags_NoTitleBar + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_NoScrollbar
    + ImGuiWindowFlags_NoScrollWithMouse + ImGuiWindowFlags_NoCollapse + ImGuiWindowFlags_NoBackground
    + ImGuiWindowFlags_NoNavInputs + ImGuiWindowFlags_NoMove + ImGuiWindowFlags_NoSavedSettings
    + ImGuiWindowFlags_NoFocusOnAppearing + ImGuiWindowFlags_NoBringToFrontOnFocus;

local by_id = {};          -- chord id -> { binding, label, recasts }: what each bound key runs now
local broken = nil;        -- why the bars stopped drawing, until /jb reload
local drag = nil;          -- { bar, x, y }: the bar being moved and where it was
local was_cooling, flash_at = {}, {};
local open_flag = { true };

local function clamp(v, lo, hi) return math.min(math.max(v, lo), math.max(lo, hi)); end
local function round(v) return math.floor(v + 0.5); end

-- ImGui gives a vector as a table or as two numbers, by version
local function xy(a, b)
    if type(a) == 'number' then
        return a, tonumber(b) or 0;
    end
    if a == nil then
        return 0, 0;
    end
    return tonumber(a.x or a[1]) or 0, tonumber(a.y or a[2]) or 0;
end

-- '^+1' -> 'Ctrl+Shift+1'
function hotbar_ui.combo(key)
    local chord = key and profiles.parse_chord(key);
    if not chord then
        return tostring(key);
    end
    return (chord.ctrl and 'Ctrl+' or '') .. (chord.alt and 'Alt+' or '') .. (chord.shift and 'Shift+' or '') .. chord.key;
end

-- The bindings in force (profiles.effective's list): what each slot's key runs,
-- with the label and recasts a slot takes from it when it sets none.
function hotbar_ui.set_bindings(bindings)
    by_id = {};
    for _, binding in ipairs(bindings) do
        local list, label = recasts.from_lines(binding.lines);
        by_id[binding.id] = { binding = binding, label = label, recasts = list };
    end
end

-- What a key runs now, or nil
function hotbar_ui.bound(key)
    return key and by_id[key] or nil;
end

-- A slot as it shows now: what its key runs (or nil), its label, its recasts
function hotbar_ui.resolve(slot)
    local entry = hotbar_ui.bound(slot.key);
    local label = slot.label or (entry and entry.label) or '';
    return entry, label, slot.recasts or (entry and entry.recasts) or {};
end

-- Draw the bars again after an error (/jb reload)
function hotbar_ui.reset()
    broken = nil;
    drag = nil;
end

-- Logged in, in a zone: the bars draw nothing on the character screen or while zoning
local function in_world()
    local ok, yes = pcall(function ()
        local player = AshitaCore:GetMemoryManager():GetPlayer();
        return player ~= nil and player:GetLoginStatus() == 2 and player:GetIsZoning() == 0
            and player:GetMainJob() ~= 0;
    end);
    return ok and yes;
end

-- A label in one line, or two split at the space that suits it best, cut to room
local function label_lines(label, room, font, px)
    if style.measure(label, font, px) <= room then
        return { label };
    end
    local best, best_w = nil, nil;
    for at in label:gmatch('() ') do
        local a, b = label:sub(1, at - 1), label:sub(at + 1);
        local w = math.max(style.measure(a, font, px), style.measure(b, font, px));
        if a ~= '' and b ~= '' and (not best_w or w < best_w) then
            best, best_w = { a, b }, w;
        end
    end
    if not best then
        return { style.fit(label, room, font, px) };
    end
    return { style.fit(best[1], room, font, px), style.fit(best[2], room, font, px) };
end

-- What the tooltip says about a slot outside the editor
local function describe(slot, entry, list)
    if not slot.key then
        return 'Empty slot';
    end
    local lines = {};
    if not entry then
        lines[1] = hotbar_ui.combo(slot.key) .. ' is not bound for this job';
    else
        lines[1] = ('%s  [%s]'):format(hotbar_ui.combo(slot.key), entry.binding.scope.label);
        for i, command in ipairs(entry.binding.lines) do
            if i > 8 then
                lines[#lines + 1] = '...';
                break;
            end
            lines[#lines + 1] = command;
        end
    end
    for _, rc in ipairs(list) do
        local left = recasts.left(rc);
        lines[#lines + 1] = ('%s: %s'):format(rc.name ~= '' and rc.name or '?', left > 0 and (recasts.format(left) .. 's') or 'ready');
    end
    return table.concat(lines, '\n');
end

local function draw_slot(dl, bar_i, slot_i, slot, x, y, s, alpha, editing)
    local id = ('##jb_slot_%d_%d'):format(bar_i, slot_i);
    local entry, label, list = hotbar_ui.resolve(slot);
    local hovered, clicked = style.hit(id, x, y, s, s);

    -- The longest of its recasts: the slot is ready once they all are
    local left, frac = 0, 0;
    for _, rc in ipairs(list) do
        local l, f = recasts.state(rc);
        if l > left then
            left, frac = l, f;
        end
    end
    local cooling = left > 0;
    local now = os.clock();
    if was_cooling[id] and not cooling then
        flash_at[id] = now;
    end
    was_cooling[id] = cooling;
    local flash = flash_at[id] and math.max(0, 1 - (now - flash_at[id]) / FLASH) or 0;
    if flash == 0 then
        flash_at[id] = nil;
    end

    local selected = editing and hotbars.edit.bar == bar_i and hotbars.edit.slot == slot_i;
    local lit = style.ease(id .. '.lit', hovered and 1 or 0, 22);
    local picked = style.ease(id .. '.picked', selected and 1 or 0);
    local r = S(4);

    -- A raised face while its key is bound, sunken while it isn't
    local face = entry and P.seg or P.well;
    local edge = entry and mix(P.seg, P.white, 0.12) or P.well_edge;
    style.fill(dl, x, y, s, s, mix(face, P.accent_bg, picked), r, alpha * (entry and 0.92 or 0.7));
    if lit > 0.01 then
        style.fill(dl, x, y, s, s, '#FFFFFF', r, 0.06 * lit * alpha);
    end
    -- The fade: what is left of the recast, shrinking towards the top
    if cooling then
        local fh = math.max(1, s * frac);
        style.fill(dl, x, y, s, fh, '#000000', math.min(r, fh / 2), 0.55 * alpha);
    end
    if flash > 0 then
        style.fill(dl, x, y, s, s, P.accent, r, 0.25 * flash * alpha);
    end
    style.outline(dl, x, y, s, s, mix(mix(edge, P.accent_lo, lit), P.accent, math.max(picked, flash)), r, alpha);

    local font = style.fonts.text;
    if slot.key then
        style.text(dl, x + S(3), y + S(1), slot.key, entry and P.text2 or P.faint, font,
            math.max(S(9), round(s * 0.22)), alpha * (cooling and 0.6 or 1));
    end
    if cooling then
        -- the seconds take the label's place
        local px, text = math.max(S(11), round(s * 0.36)), recasts.format(left);
        style.text_centred(dl, x + s / 2 + 1, y + s / 2 + 1, text, '#000000', style.fonts.semi, px, alpha * 0.8);
        style.text_centred(dl, x + s / 2, y + s / 2, text, P.white, style.fonts.semi, px, alpha);
    elseif label ~= '' then
        local px = math.max(S(9), round(s * 0.25));
        local lines = label_lines(label, s - S(6), font, px);
        local _, lh = style.measure('Ag', font, px);
        local cy = y + s / 2 + (slot.key and s * 0.08 or 0) - lh * (#lines - 1) / 2;
        for n, line in ipairs(lines) do
            style.text_centred(dl, x + s / 2, cy + (n - 1) * lh, line, entry and P.text or P.dim, font, px, alpha);
        end
    end

    if hovered then
        style.tooltip(editing and ('Slot %d: click to edit it'):format(slot_i) or describe(slot, entry, list));
    end
    if clicked then
        if editing then
            hotbars.edit.bar, hotbars.edit.slot = bar_i, slot_i;
        elseif slot.key then
            engine.press(slot.key);
        end
    end
end

-- The editor's tab over a bar: its name, and dragged, it moves the bar
local function draw_tab(dl, i, bar, tab, x, y, sw, sh, w, h, alpha)
    local id = '##jb_bar_tab_' .. i;
    local hovered, _, held = style.hit(id, tab.x, tab.y, tab.w, tab.h);
    if imgui.IsItemActivated() then
        drag = { bar = bar, x = x, y = y };
        if hotbars.edit.bar ~= i then
            hotbars.edit.bar, hotbars.edit.slot = i, nil;
        end
    end
    if held and drag and drag.bar == bar then
        local dx, dy = xy(imgui.GetMouseDragDelta(0));
        local nx, ny = clamp(round(drag.x + dx), 0, sw - w), clamp(round(drag.y + dy), 0, sh - h);
        if nx ~= bar.x or ny ~= bar.y then
            bar.x, bar.y = nx, ny;
            hotbars.mark_dirty();
        end
    end

    local on = hotbars.edit.bar == i;
    local t = style.ease(id, (hovered or held) and 1 or 0, 22);
    style.fill(dl, tab.x, tab.y, tab.w, tab.h, mix(on and P.accent_bg or P.well, P.hover, t * 0.5), S(4), alpha);
    style.outline(dl, tab.x, tab.y, tab.w, tab.h, mix(on and P.accent_lo or P.well_edge, P.accent, t), S(4), alpha);
    style.text_centred(dl, tab.x + tab.w / 2, tab.y + tab.h / 2, style.fit(bar.name, tab.w - S(10), style.fonts.text,
        S(style.SMALL)), on and P.accent2 or P.text2, style.fonts.text, S(style.SMALL), alpha);
    if hovered and not held then
        style.tooltip('Drag to move ' .. bar.name);
    end
end

local function draw_bar(i, bar, editing, shown, sw, sh)
    local s, gap, columns, _, w, h = hotbars.metrics(bar, S);
    local x, y = clamp(bar.x, 0, sw - w), clamp(bar.y, 0, sh - h);
    local edge = S(EDGE);

    -- The window: the bar, room round it, and in the editor its tab
    local wx, wy, ww, wh = x - edge, y - edge, w + edge * 2, h + edge * 2;
    local tab = nil;
    if editing then
        local th = S(TAB_H);
        local tw = math.max(S(70), style.measure(bar.name, style.fonts.text, S(style.SMALL)) + S(24));
        local ty = y - edge - th;
        if ty < 0 then
            ty = y + h + edge; -- a bar at the top of the screen has its tab under it
        end
        tab = { x = x, y = ty, w = tw, h = th };
        local top, bottom = math.min(wy, ty), math.max(wy + wh, ty + th);
        wy, wh = top, bottom - top;
        ww = math.max(ww, tw + edge * 2);
    end

    imgui.SetNextWindowPos({ wx, wy }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ ww, wh }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, { 1, 1 });

    -- An error while drawing must still reach End: ImGui asserts on a window left open
    local ok, err = true, nil;
    if imgui.Begin(('JobBinds bar###jb_bar_%d'):format(i), open_flag, BAR_FLAGS) then
        ok, err = pcall(function ()
            local dl = imgui.GetWindowDrawList();
            local alpha = shown and 1 or HIDDEN;
            if editing then
                local on = hotbars.edit.bar == i;
                style.outline(dl, x - S(3), y - S(3), w + S(6), h + S(6), on and P.accent_lo or P.border, S(5), alpha);
                draw_tab(dl, i, bar, tab, x, y, sw, sh, w, h, alpha);
            end
            for n, slot in ipairs(bar.slots) do
                local col, row = (n - 1) % columns, math.floor((n - 1) / columns);
                draw_slot(dl, i, n, slot, x + col * (s + gap), y + row * (s + gap), s, alpha, editing);
            end
        end);
    end
    imgui.End();
    imgui.PopStyleVar(3);
    if not ok then
        error(err, 0);
    end
end

-- Every frame, after style.frame() and recasts.frame(). editing: the window's
-- Hotbars page is open.
function hotbar_ui.render(editing)
    if broken then
        return;
    end
    local list = hotbars.list();
    if #list == 0 or not in_world() then
        drag = nil;
        return;
    end

    local sw, sh = style.screen();
    local snap = conditions.snapshot();
    local ok, err = pcall(function ()
        for i, bar in ipairs(list) do
            local shown = conditions.met(bar.conditions, snap);
            if shown or editing then
                draw_bar(i, bar, editing, shown, sw, sh);
            end
        end
    end);
    if not imgui.IsMouseDown(0) then
        drag = nil;
    end
    if not ok then
        broken = tostring(err);
        error('JobBinds hotbars stopped: ' .. broken .. ' (/jb reload starts them again)', 0);
    end
end

return hotbar_ui;
