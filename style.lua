--[[
* The look of the JobBinds window: the VanaCore style (a dark navy panel with
* one blue accent), as VanaCore's /vana window and Sidekick's windows have it.
*
* ImGui draws nothing of the window. Each control is an invisible button that
* takes the mouse, with its picture drawn on the window's draw list. Every size
* goes through S() (it follows the screen's height), every colour comes from P,
* and hover and selected states are eased.
*
* Labels are Segoe UI. What the user typed (the commands) stays in ImGui's own
* font, which has the client's language.
--]]

require('common');
local imgui = require('imgui');

local style = {};

style.P = {
    bg = '#161822', border = '#2A2E3E', line = '#242838', hover = '#1F2334',
    well = '#0E1017', well_edge = '#272B3C', field = '#080A10', field_edge = '#3E4460', popup = '#0F1118',
    white = '#FFFFFF', text = '#E8EAF1', text2 = '#BDC1D0', dim = '#7B8095', faint = '#4E536A',
    accent = '#7AA2F7', accent2 = '#A9C1FF', accent_lo = '#3E5CB3', accent_bg = '#1B2340',
    teal = '#5FD3B3', rose = '#EE6F78', seg = '#313752', ink = '#0B1020',
};
local P = style.P;

style.BODY, style.SMALL = 16, 13.5; -- the text sizes, unscaled

local function clamp(v, lo, hi) return math.min(math.max(v, lo), hi); end
local function round(v) return math.floor(v + 0.5); end

-- Colours ---------------------------------------------------------------------

local function rgb(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16);
end

-- '#RRGGBB' and an alpha as an ImU32 (0xAABBGGRR), for a draw list
function style.u32(hex, alpha)
    local r, g, b = rgb(hex);
    local a = round(clamp(alpha or 1, 0, 1) * 255);
    return ((a * 256 + b) * 256 + g) * 256 + r;
end
local u32 = style.u32;

-- '#RRGGBB' and an alpha as { r, g, b, a }, for PushStyleColor
function style.rgba(hex, alpha)
    local r, g, b = rgb(hex);
    return { r / 255, g / 255, b / 255, alpha or 1 };
end
local rgba = style.rgba;

-- The colour t of the way from a to b
function style.mix(a, b, t)
    t = clamp(t, 0, 1);
    if t == 0 then return a; end
    if t == 1 then return b; end
    local r1, g1, b1 = rgb(a);
    local r2, g2, b2 = rgb(b);
    return ('#%02X%02X%02X'):format(round(r1 + (r2 - r1) * t), round(g1 + (g2 - g1) * t), round(b1 + (b2 - b1) * t));
end
local mix = style.mix;

-- Scale -----------------------------------------------------------------------

local scale = 1;

function style.S(n) return round(n * scale); end
local S = style.S;

-- The screen's size, 1920 by 1080 until ImGui says
function style.screen()
    local ok, size = pcall(function () return imgui.GetIO().DisplaySize; end);
    local w, h = ok and size and tonumber(size.x), ok and size and tonumber(size.y);
    if not (w and h and w > 0 and h > 0) then
        return 1920, 1080;
    end
    return w, h;
end

-- Fonts and text --------------------------------------------------------------

-- ImGui 1.92 (Ashita 4.30's, as VanaCore gives it) draws a font at any size and
-- takes one mid-frame. 1.81 (Ashita 4.16) takes fonts only outside a frame and
-- scales them from the size they were added at.
local DYNAMIC = (tonumber(IMGUI_VERSION_NUM) or 0) >= 19200;
local BAKE = 18;

style.fonts = {};  -- text, semi, semi_italic (Segoe UI) and base (ImGui's own)
local fonts = style.fonts;
local segoe, pending, tried = nil, nil, false;

local function add_font(name)
    local path = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\' .. name;
    local file = io.open(path, 'rb');
    if not file then
        return nil;
    end
    file:close();
    local ok, font = pcall(imgui.AddFontFromFileTTF, path, BAKE);
    return ok and font or nil;
end

-- Add Segoe UI, once. Called from Ashita's load event, before any frame; the
-- faces are drawn from the next style.frame().
function style.load()
    if tried then
        return;
    end
    tried = true;
    local text = add_font('segoeui.ttf');
    if text then
        local semi = add_font('seguisb.ttf') or text;
        pending = { text = text, semi = semi, semi_italic = add_font('seguisbi.ttf') or semi };
    end
end

local measured, measured_n = {}, 0;

-- The width and height of s in font at px pixels. Cached: the same labels are
-- measured every frame.
function style.measure(s, font, px)
    s = tostring(s);
    local key = tostring(font) .. '|' .. px .. '|' .. s;
    local m = measured[key];
    if not m then
        if measured_n > 2000 then
            measured, measured_n = {}, 0;
        end
        local own = font ~= fonts.base;
        local w, h;
        if own and DYNAMIC then
            imgui.PushFont(font, px);
            w, h = imgui.CalcTextSize(s);
            imgui.PopFont();
        else
            if own then imgui.PushFont(font); end
            w, h = imgui.CalcTextSize(s);
            local k = px / imgui.GetFontSize();
            if own then imgui.PopFont(); end
            w, h = w * k, h * k;
        end
        m = { w, h };
        measured[key], measured_n = m, measured_n + 1;
    end
    return m[1], m[2];
end
local measure = style.measure;

function style.text(dl, x, y, s, color, font, px, alpha)
    dl:AddText(font, px, { round(x), round(y) }, u32(color, alpha), s);
end

-- Text with its middle at cy, align of its width left of x. Segoe UI's line
-- box holds a tall ascent, so text centred by its box sits low: it is raised.
local function aligned(dl, x, cy, s, color, font, px, alpha, align)
    local w, h = measure(s, font, px);
    local lift = font ~= fonts.base and round(h * 0.06) or 0;
    style.text(dl, x - w * align, cy - h / 2 - lift, s, color, font, px, alpha);
end

-- Text with its middle at cy: starting at x, ending at right, or centred on cx
function style.text_mid(dl, x, cy, s, color, font, px, alpha) aligned(dl, x, cy, s, color, font, px, alpha, 0); end
function style.text_right(dl, right, cy, s, color, font, px, alpha) aligned(dl, right, cy, s, color, font, px, alpha, 1); end
function style.text_centred(dl, cx, cy, s, color, font, px, alpha) aligned(dl, cx, cy, s, color, font, px, alpha, 0.5); end

-- Capitals drawn a letter at a time, spacing pixels apart (ImGui has no letter
-- spacing). Returns the width; with dl nil it only measures.
function style.text_spaced(dl, x, cy, s, color, font, px, spacing)
    local start = x;
    for i = 1, #s do
        local letter = s:sub(i, i);
        if dl then
            style.text_mid(dl, x, cy, letter, color, font, px);
        end
        x = x + measure(letter, font, px) + spacing;
    end
    return math.max(0, x - start - spacing);
end

-- s cut to room pixels with '...', never inside a UTF-8 character
function style.fit(s, room, font, px)
    s = tostring(s);
    if measure(s, font, px) <= room then
        return s;
    end
    local n = #s;
    repeat
        n = n - 1;
        while n > 0 and (s:byte(n + 1) or 0) >= 0x80 and (s:byte(n + 1) or 0) < 0xC0 do
            n = n - 1;
        end
    until n <= 0 or measure(s:sub(1, n) .. '...', font, px) <= room;
    return s:sub(1, math.max(0, n)) .. '...';
end

-- Shapes ----------------------------------------------------------------------

function style.fill(dl, x, y, w, h, color, radius, alpha)
    dl:AddRectFilled({ x, y }, { x + w, y + h }, u32(color, alpha), radius or 0);
end
local fill = style.fill;

function style.outline(dl, x, y, w, h, color, radius, alpha)
    dl:AddRect({ x, y }, { x + w, y + h }, u32(color, alpha), radius or 0);
end
local outline = style.outline;

function style.line(dl, x1, y1, x2, y2, color, alpha, thickness)
    dl:AddLine({ x1, y1 }, { x2, y2 }, u32(color, alpha), thickness or 1);
end

-- Frames, easing and the mouse ------------------------------------------------

local anim, last, dt = {}, nil, 0;
local tip_pending = nil;

-- Once a frame, before the window: the time since the last frame, the fonts
-- and the scale (a screen 1440 pixels tall is 1.1).
function style.frame()
    local now = os.clock();
    dt = last and clamp(now - last, 0, 0.1) or 0; -- capped: a hitch takes one step, not a jump
    last = now;

    if pending then
        segoe, pending = pending, nil; -- added before this frame: usable from it
    elseif not tried and DYNAMIC then
        style.load();
    end
    fonts.base = imgui.GetFont();
    fonts.text = segoe and segoe.text or fonts.base;
    fonts.semi = segoe and segoe.semi or fonts.base;
    fonts.semi_italic = segoe and segoe.semi_italic or fonts.base;

    local _, h = style.screen();
    scale = clamp(h / 1440, 0.75, 1.6) * 1.1;
    tip_pending = nil;
end

-- id's value, moved towards target a share of the way each frame
function style.ease(id, target, speed)
    local v = anim[id];
    if v == nil then
        v = target; -- a new control starts where it should be
    else
        v = v + (target - v) * math.min(1, dt * (speed or 18));
        if math.abs(v - target) < 0.003 then
            v = target;
        end
    end
    anim[id] = v;
    return v;
end
local ease = style.ease;

-- The input half of every control: an invisible button over its box.
-- Returns hovered, clicked, held.
function style.hit(id, x, y, w, h)
    imgui.SetCursorScreenPos({ x, y });
    local clicked = imgui.InvisibleButton(id, { math.max(1, w), math.max(1, h) });
    return imgui.IsItemHovered(), clicked, imgui.IsItemActive();
end
local hit = style.hit;

-- Tooltips --------------------------------------------------------------------

-- A tooltip by the mouse, drawn by style.tooltips() once the window is
function style.tooltip(s)
    if s and s ~= '' then
        tip_pending = tostring(s);
    end
end

-- The last item's tooltip, while it is hovered
function style.tip(s)
    if imgui.IsItemHovered() then
        style.tooltip(s);
    end
end

-- Once a frame, after the window. TextUnformatted draws a '%' as written.
function style.tooltips()
    local s = tip_pending;
    if not s then
        return;
    end
    tip_pending = nil;
    imgui.PushStyleColor(ImGuiCol_PopupBg, rgba(P.popup, 0.97));
    imgui.PushStyleColor(ImGuiCol_Border, rgba(P.border));
    imgui.PushStyleColor(ImGuiCol_Text, rgba(P.text));
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { S(9), S(6) });
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, S(4));
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, S(4));
    imgui.PushStyleVar(ImGuiStyleVar_PopupBorderSize, 1);
    if imgui.BeginTooltip() ~= false then -- (1.92 says whether to draw; 1.81 says nothing)
        imgui.TextUnformatted(s);
        imgui.EndTooltip();
    end
    imgui.PopStyleVar(4);
    imgui.PopStyleColor(3);
end

-- Controls: each is centred on cy -----------------------------------------------

function style.button_width(label)
    return measure(label, fonts.text, S(style.SMALL + 0.5)) + S(22);
end

-- A button: 'ghost' (an outline), 'accent' (filled) or 'danger' (rose), at
-- least min_w wide. Returns clicked, its width.
function style.button(id, x, cy, label, kind, min_w)
    local w, h = math.max(min_w or 0, style.button_width(label)), S(24);
    local y = cy - h / 2;
    local hovered, clicked, held = hit(id, x, y, w, h);
    local dl = imgui.GetWindowDrawList();
    local t = ease(id, hovered and 1 or 0, 22);
    local fg;
    if kind == 'accent' then
        fill(dl, x, y, w, h, mix(P.accent, P.accent2, t * 0.6), S(4));
        outline(dl, x, y, w, h, '#FFFFFF', S(4), 0.22);
        fg = P.ink;
    elseif kind == 'danger' then
        fill(dl, x, y, w, h, mix(P.well, P.rose, 0.10 + 0.10 * t), S(4));
        outline(dl, x, y, w, h, P.rose, S(4), 0.45 + 0.25 * t);
        fg = mix(P.rose, '#FFFFFF', t * 0.35);
    else
        fill(dl, x, y, w, h, mix(P.well, P.hover, t), S(4));
        outline(dl, x, y, w, h, mix(P.well_edge, P.accent_lo, t), S(4));
        fg = mix(P.text2, P.text, t);
    end
    if held then
        fill(dl, x, y, w, h, '#000000', S(4), 0.15);
    end
    style.text_centred(dl, x + w / 2, cy, label, fg, fonts.text, S(style.SMALL + 0.5));
    return clicked, w;
end

function style.segments_width(labels)
    local px = S(style.BODY - 1);
    local widths, total = {}, S(4);
    for i, label in ipairs(labels) do
        widths[i] = measure(label, fonts.text, px) + S(20);
        total = total + widths[i] + (i > 1 and S(1) or 0);
    end
    return total, widths;
end

-- Words side by side in a sunken box, the one at index chosen.
-- Returns index, changed.
function style.segments(id, x, cy, labels, index)
    local dl = imgui.GetWindowDrawList();
    local px = S(style.BODY - 1);
    local h = px + S(8);
    local y = cy - h / 2;
    local total, widths = style.segments_width(labels);
    fill(dl, x, y, total, h, P.well, S(4));
    outline(dl, x, y, total, h, P.well_edge, S(4));
    local changed, at = false, x + S(2);
    for i, label in ipairs(labels) do
        local sid, sy, sh = id .. '_' .. i, y + S(2), h - S(4);
        local hovered, clicked = hit(sid, at, sy, widths[i], sh);
        if clicked and index ~= i then
            index, changed = i, true;
        end
        local t = ease(sid, index == i and 1 or 0);
        if t > 0.01 then
            fill(dl, at, sy, widths[i], sh, P.seg, S(3), t);
        end
        if hovered and index ~= i then
            fill(dl, at, sy, widths[i], sh, '#FFFFFF', S(3), 0.05);
        end
        style.text_centred(dl, at + widths[i] / 2, cy, label, mix(P.dim, P.text, t), fonts.text, px);
        at = at + widths[i] + S(1);
    end
    return index, changed;
end

function style.chip_width(label)
    return math.max(S(30), measure(label, fonts.text, S(style.SMALL - 0.5)) + S(14));
end

-- A small toggle, in the accent while on. Returns clicked.
function style.chip(id, x, cy, label, on)
    local w, h = style.chip_width(label), S(20);
    local y = cy - h / 2;
    local hovered, clicked = hit(id, x, y, w, h);
    local dl = imgui.GetWindowDrawList();
    local t = ease(id, on and 1 or 0);
    fill(dl, x, y, w, h, mix(P.well, P.accent_bg, t), S(4));
    outline(dl, x, y, w, h, mix(P.well_edge, P.accent_lo, t), S(4));
    if hovered then
        fill(dl, x, y, w, h, '#FFFFFF', S(4), 0.06);
    end
    style.text_centred(dl, x + w / 2, cy, label, mix(P.dim, P.accent2, t), fonts.text, S(style.SMALL - 0.5));
    return clicked;
end

-- A keycap ("Ctrl"), only drawn. Returns its width.
function style.keycap(dl, x, cy, label)
    local px = S(style.SMALL - 0.5);
    local w, h = measure(label, fonts.semi, px) + S(10), S(18);
    fill(dl, x, cy - h / 2, w, h, P.seg, S(3));
    style.text_centred(dl, x + w / 2, cy, label, P.text, fonts.semi, px);
    return w;
end

-- An X in a box-sized hit area centred on (cx, cy): dim, rose under the
-- pointer. Returns clicked.
function style.cross(id, cx, cy, box)
    local hovered, clicked = hit(id, cx - box / 2, cy - box / 2, box, box);
    local dl = imgui.GetWindowDrawList();
    local color = u32(mix(P.dim, P.rose, ease(id, hovered and 1 or 0, 22)));
    local r, thickness = box * 0.2, math.max(1, box / 12);
    dl:AddLine({ cx - r, cy - r }, { cx + r, cy + r }, color, thickness);
    dl:AddLine({ cx + r, cy - r }, { cx - r, cy + r }, color, thickness);
    return clicked;
end

local CLEAR = { 0, 0, 0, 0 };

-- A text field over a sunken box, w by h with its top left at (x, y); buf is
-- its { text }. With multiline it takes several lines. The text is in ImGui's
-- own font: it is what the user typed, in the client's language.
function style.field(id, x, y, w, h, buf, max, multiline)
    local dl = imgui.GetWindowDrawList();
    fill(dl, x, y, w, h, P.field, S(5));

    imgui.PushStyleColor(ImGuiCol_FrameBg, CLEAR);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, CLEAR);
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, CLEAR);
    imgui.PushStyleColor(ImGuiCol_Text, rgba(P.text));
    imgui.PushStyleColor(ImGuiCol_TextSelectedBg, rgba(P.accent_lo, 0.6));
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, CLEAR);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, rgba('#3A4158'));
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, rgba('#4A5270'));
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, rgba(P.accent_lo));
    local pad_y = multiline and S(5) or math.max(0, (h - 2 - imgui.GetFontSize()) / 2);
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { S(8), pad_y });
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 0);
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarSize, S(6));
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, S(3));

    -- An error in here must still reach the pops: ImGui asserts on a style left pushed
    local ok, lit = pcall(function ()
        imgui.SetCursorScreenPos({ x + 1, y + 1 });
        if multiline then
            imgui.InputTextMultiline(id, buf, max, { w - 2, h - 2 });
        else
            imgui.SetNextItemWidth(w - 2);
            imgui.InputText(id, buf, max, ImGuiInputTextFlags_None);
        end
        return ease(id, (imgui.IsItemActive() or imgui.IsItemHovered()) and 1 or 0, 22);
    end);

    imgui.PopStyleVar(4);
    imgui.PopStyleColor(9);
    if not ok then
        error(lit, 0);
    end
    outline(dl, x, y, w, h, mix(P.field_edge, P.accent_lo, lit), S(5));
end

return style;
