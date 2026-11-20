--[[
* JobBinds window, Hotbars page: the bar picked (its name and shape), when it
* shows, and the slot picked (its key, label and recasts). Every change is
* saved by itself (hotbars.save_if_idle).
*
* As on the Keys page, the page is planned before it is drawn: plan() gives
* its rows and their heights, so the window is sized before anything is in it.
--]]

require('common');
local style = require('style');
local profiles = require('profiles');
local hotbars = require('hotbars');
local recasts = require('recasts');
local conditions = require('conditions');
local hotbar_ui = require('hotbar_ui');

local P, S = style.P, style.S;

local hotbar_page = {};

-- Layout, in unscaled pixels (style.S scales each one)
local PICK_H   = 46;  -- the bar picker, New bar and Delete
local HEAD_H   = 30;  -- a section's heading
local ROW_H    = 34;
local NOTE_H   = 20;  -- a line of small print
local FIELD_H  = 26;
local MATCH_H  = 24;  -- a recast found by the search
local LABEL_W  = 74;  -- the rows' labels; what they label starts here
local ERROR_H  = 24;
local BOTTOM   = 10;
local CHIP_GAP = 6;

local HINTS = {
    tp = 'Show the bar while your TP is at least, or below, a number',
    hpp = 'Show the bar while your HP% is at least, or below, a number',
    mpp = 'Show the bar while your MP% is at least, or below, a number',
    ctrl = 'Show the bar while Ctrl is held, or while it isn\'t',
    alt = 'Show the bar while Alt is held, or while it isn\'t',
    shift = 'Show the bar while Shift is held, or while it isn\'t',
    engaged = 'Show the bar while you are engaged, or while you aren\'t',
    buff = 'Show the bar while a status is on you, or while it isn\'t',
};

-- The fields' text. Filled from the bar and slot picked when another is picked.
local buf = { name = { '' }, key = { '' }, label = { '' }, search = { '' } };
local cond_bufs = setmetatable({}, { __mode = 'k' }); -- condition -> its value field's { text }
local loaded_bar, loaded_slot, loaded_job = nil, nil, nil;
local confirm_bar, confirm_until = nil, 0;            -- Delete asks once
local last_search, last_matches = nil, {};

local function trim(text)
    return (text:match('^%s*(.-)%s*$'));
end

local function name_of(bar, i)
    return bar.name ~= '' and bar.name or ('Bar ' .. i);
end

-- What a binding runs, in a line
local function describe(binding)
    local first = binding.lines[1] or '';
    return #binding.lines > 1 and (first .. ' ...') or first;
end

local function sync(bar, slot, job)
    if bar ~= loaded_bar then
        buf.name[1] = bar.name;
        loaded_bar = bar;
    end
    if slot ~= loaded_slot or job ~= loaded_job then
        local own = hotbars.for_job(slot, job);
        buf.key[1] = slot.key or '';
        buf.label[1] = own and own.label or '';
        buf.search[1] = '';
        loaded_slot, loaded_job = slot, job;
    end
end

-- Drawing helpers ---------------------------------------------------------------

local function row_label(dl, x, cy, text)
    style.text_mid(dl, x, cy, text, P.text2, style.fonts.text, S(style.BODY - 1));
end

local function note(dl, x, cy, text, room, color)
    local font, px = style.fonts.text, S(style.SMALL);
    style.text_mid(dl, x, cy, style.fit(text, room, font, px), color or P.dim, font, px);
end

-- Spaced capitals in teal, then a hairline, as the Keys page's BINDINGS, and
-- an aside at the right end when there is one
local function heading(dl, x, y, right, text, aside)
    local cy = y + S(6) + S(HEAD_H) / 2;
    local w = style.text_spaced(dl, x, cy, text, P.teal, style.fonts.semi_italic, S(style.SMALL), math.max(1, S(1.2)));
    local line_end = right;
    if aside then
        local font, px = style.fonts.text, S(style.SMALL);
        style.text_right(dl, right, cy, aside, P.dim, font, px);
        line_end = right - style.measure(aside, font, px) - S(10);
    end
    style.line(dl, x + w + S(10), cy, line_end, cy, P.line);
end

-- A faint hint in a field while it's empty
local function placeholder(dl, x, y, b, text)
    if b[1] == '' and text and text ~= '' then
        style.text_mid(dl, x + S(9), y + S(FIELD_H) / 2, text, P.faint, style.fonts.text, S(style.SMALL));
    end
end

-- A field centred on cy. Returns whether its text changed.
local function field(id, x, cy, w, b, max)
    return style.field(id, x, cy - S(FIELD_H) / 2, w, S(FIELD_H), b, max);
end

local function removable_width(label)
    return style.measure(label, style.fonts.text, S(style.BODY - 1)) + S(10) + S(22);
end

-- A recast picked for a slot: its name and a cross. Returns removed, its width.
local function removable(dl, id, x, cy, label)
    local w, h = removable_width(label), S(24);
    local y = cy - h / 2;
    style.fill(dl, x, y, w, h, P.accent_bg, S(4));
    style.outline(dl, x, y, w, h, P.accent_lo, S(4));
    style.text_mid(dl, x + S(10), cy, label, P.accent2, style.fonts.text, S(style.BODY - 1));
    local removed = style.cross(id, x + w - S(12), cy, S(18));
    style.tip('Remove ' .. label);
    return removed, w;
end

-- Items of the given widths in lines no wider than room: { { i, ... }, ... }
local function wrap(widths, room)
    local lines, used = { {} }, 0;
    for i, w in ipairs(widths) do
        if used > 0 and used + w > room then
            lines[#lines + 1] = {};
            used = 0;
        end
        table.insert(lines[#lines], i);
        used = used + w + S(CHIP_GAP);
    end
    return lines;
end

-- Give a slot this recast on a job. A slot on auto there starts from the recasts it had.
local function add_recast(slot, job, rc)
    local own = hotbars.for_job(slot, job, true);
    if not own.recasts then
        local _, _, list = hotbar_ui.resolve(slot);
        own.recasts = {};
        for _, have in ipairs(list) do
            own.recasts[#own.recasts + 1] = { kind = have.kind, id = have.id, name = have.name };
        end
    end
    for _, have in ipairs(own.recasts) do
        if have.kind == rc.kind and have.id == rc.id then
            return;
        end
    end
    own.recasts[#own.recasts + 1] = { kind = rc.kind, id = rc.id, name = rc.name };
    hotbars.mark_dirty();
end

-- Set a slot's own recasts on a job: a list, {} for none, nil for auto
local function set_recasts(slot, job, list)
    local own = hotbars.for_job(slot, job, list ~= nil);
    if own then
        own.recasts = list;
        hotbars.prune(slot, job);
        hotbars.mark_dirty();
    end
end

-- The search's matches, less those the slot has
local function matches(slot)
    local text = buf.search[1];
    if text ~= last_search then
        last_search, last_matches = text, recasts.search(text, 8);
    end
    local _, _, list = hotbar_ui.resolve(slot);
    local have, out = {}, {};
    for _, rc in ipairs(list) do
        have[rc.kind .. rc.id] = true;
    end
    for _, rc in ipairs(last_matches) do
        if not have[rc.kind .. rc.id] and #out < 5 then
            out[#out + 1] = rc;
        end
    end
    return out;
end

-- Sections ------------------------------------------------------------------------

-- The bar picker, with New bar and Delete, over a line across the window
local function draw_picker(dl, x, y, right, x0, x1)
    local list, edit = hotbars.list(), hotbars.edit;
    local cy = y + S(PICK_H) / 2;
    local new_w = math.max(S(84), style.button_width('New bar'));
    local del_w = math.max(S(84), style.button_width('Delete'));

    if style.button('##jb_bar_new', right - new_w, cy, 'New bar', 'accent', new_w) then
        local sw, sh = style.screen();
        edit.bar, edit.slot = hotbars.new_bar(sw, sh, S), nil;
    end
    style.tip('Add a bar of ten slots near the bottom of the screen');

    local bar = list[edit.bar];
    if not bar then
        row_label(dl, x, cy, 'No hotbars yet');
    else
        local now = os.clock();
        local sure = confirm_bar == bar and now < confirm_until;
        if style.button('##jb_bar_delete', right - new_w - S(8) - del_w, cy, sure and 'Sure?' or 'Delete', 'danger', del_w) then
            if sure then
                hotbars.remove(edit.bar);
                confirm_bar = nil;
            else
                confirm_bar, confirm_until = bar, now + 3;
            end
        end
        style.tip(sure and ('Click again to delete ' .. name_of(bar, edit.bar)) or 'Delete this bar');

        local room = right - new_w - S(8) - del_w - S(16) - x;
        local font, px = style.fonts.text, S(style.BODY - 1);
        local labels = {};
        for i, b in ipairs(list) do
            labels[i] = style.fit(name_of(b, i), S(120), font, px);
        end
        if style.segments_width(labels) <= room then
            local index, changed, hovered = style.segments('##jb_bars', x, cy, labels, edit.bar);
            if changed then
                edit.bar, edit.slot = index, nil;
            end
            if hovered then
                style.tooltip('The bar being edited. Drag its tab on screen to move it.');
            end
        else
            -- too many to show side by side: step through them
            local index, changed, w = style.stepper('##jb_bar_step', x, cy, edit.bar, 1, #list);
            if changed then
                edit.bar, edit.slot = index, nil;
            end
            style.text_mid(dl, x + w + S(10), cy, style.fit(name_of(list[index], index), room - w - S(10), font, px),
                P.text, font, px);
        end
    end
    style.line(dl, x0, y + S(PICK_H), x1, y + S(PICK_H), P.border);
end

local function plan_bar(add, bar)
    add(S(6) + S(HEAD_H), function (dl, x, y, right) heading(dl, x, y, right, 'BAR'); end);

    add(S(ROW_H), function (dl, x, y, right)
        local cy = y + S(ROW_H) / 2;
        row_label(dl, x, cy, 'Name');
        local fx = x + S(LABEL_W);
        if field('##jb_bar_name', fx, cy, math.min(S(220), right - fx), buf.name, 64) then
            bar.name = trim(buf.name[1]);
            hotbars.mark_dirty();
        end
    end);

    add(S(ROW_H), function (dl, x, y, right)
        local cy = y + S(ROW_H) / 2;
        local font, px = style.fonts.text, S(style.BODY - 1);
        row_label(dl, x, cy, 'Slots');
        local at = x + S(LABEL_W);
        local v, changed, w = style.stepper('##jb_bar_count', at, cy, #bar.slots, 1, hotbars.MAX_SLOTS);
        if changed then
            hotbars.set_count(bar, v);
        end

        at = at + w + S(16);
        style.text_mid(dl, at, cy, 'Columns', P.text2, font, px);
        at = at + style.measure('Columns', font, px) + S(8);
        v, changed, w = style.stepper('##jb_bar_cols', at, cy, math.min(bar.columns, #bar.slots), 1, #bar.slots);
        if changed then
            bar.columns = v;
            hotbars.mark_dirty();
        end

        at = at + w + S(16);
        style.text_mid(dl, at, cy, 'Size', P.text2, font, px);
        at = at + style.measure('Size', font, px) + S(8);
        v, changed = style.stepper('##jb_bar_size', at, cy, bar.size, hotbars.MIN_SIZE, hotbars.MAX_SIZE, 2);
        if changed then
            bar.size = v;
            hotbars.mark_dirty();
        end
    end);

    add(S(NOTE_H), function (dl, x, y, right)
        local n = #bar.slots;
        local _, _, columns, rows = hotbars.metrics(bar, S);
        local shape = rows == 1 and ('One row of %d'):format(n)
            or columns == 1 and ('One column of %d'):format(n)
            or ('%d rows of %d'):format(rows, columns);
        note(dl, x + S(LABEL_W), y + S(NOTE_H) / 2 - S(3), shape .. '. Drag the bar\'s tab on screen to move it.',
            right - x - S(LABEL_W));
    end);

    -- The text on the slots: the key in the corner, and the label
    add(S(ROW_H), function (dl, x, y, right)
        local cy = y + S(ROW_H) / 2;
        local font, px = style.fonts.text, S(style.BODY - 1);
        row_label(dl, x, cy, 'Key text');
        local at = x + S(LABEL_W);
        local v, changed, w = style.stepper('##jb_bar_key_text', at, cy, bar.key_text, hotbars.MIN_TEXT, hotbars.MAX_TEXT);
        if changed then
            bar.key_text = v;
            hotbars.mark_dirty();
        end

        at = at + w + S(16);
        style.text_mid(dl, at, cy, 'Label text', P.text2, font, px);
        at = at + style.measure('Label text', font, px) + S(8);
        v, changed = style.stepper('##jb_bar_label_text', at, cy, bar.label_text, hotbars.MIN_TEXT, hotbars.MAX_TEXT);
        if changed then
            bar.label_text = v;
            hotbars.mark_dirty();
        end
    end);
end

-- One condition: its kind, which way, its value, a cross
local function plan_condition(add, bar, c, n, width)
    local k = conditions.by_kind[c.kind];
    local unknown = k.type == 'buff' and c.name ~= '' and not conditions.status_ids(c.name);
    add(S(ROW_H) + (unknown and S(NOTE_H) or 0), function (dl, x, y, right)
        local cy = y + S(ROW_H) / 2;
        local id = '##jb_cond_' .. n;
        row_label(dl, x, cy, k.label);

        local at = x + S(LABEL_W);
        local labels = k.type == 'number' and conditions.OPS or k.states;
        local index;
        if k.type == 'number' then
            index = c.op == '<' and 2 or 1;
        else
            index = c.is == false and 2 or 1;
        end
        local picked, changed = style.segments(id, at, cy, labels, index);
        if changed then
            if k.type == 'number' then
                c.op = picked == 2 and '<' or '>=';
            else
                c.is = picked == 1;
            end
            hotbars.mark_dirty();
        end
        at = at + style.segments_width(labels) + S(10);

        local cross = S(20);
        if k.type ~= 'flag' then
            local b = cond_bufs[c];
            if not b then
                b = { k.type == 'number' and tostring(c.value) or c.name };
                cond_bufs[c] = b;
            end
            if k.type == 'number' then
                if field(id .. '_v', at, cy, S(70), b, 8) then
                    local v = tonumber(trim(b[1]));
                    if v then
                        c.value = math.min(math.max(math.floor(v + 0.5), k.lo), k.hi);
                        hotbars.mark_dirty();
                    end
                end
                note(dl, at + S(80), cy, ('%d to %d'):format(k.lo, k.hi), right - cross - at - S(80), P.faint);
            else
                local fw = right - cross - S(8) - at;
                if field(id .. '_v', at, cy, fw, b, 64) then
                    c.name = trim(b[1]);
                    hotbars.mark_dirty();
                end
                placeholder(dl, at, cy - S(FIELD_H) / 2, b, 'A status, such as Haste');
                if unknown then
                    note(dl, at + S(2), y + S(ROW_H) + S(NOTE_H) / 2 - S(4), 'No status has that name', fw, P.rose);
                end
            end
        end

        if style.cross(id .. '_x', right - cross / 2, cy, cross) then
            for i, have in ipairs(bar.conditions) do
                if have == c then
                    table.remove(bar.conditions, i);
                    break;
                end
            end
            hotbars.mark_dirty();
        end
        style.tip('Remove this condition');
    end);
end

local function plan_conditions(add, bar, width)
    add(S(6) + S(HEAD_H), function (dl, x, y, right) heading(dl, x, y, right, 'SHOWN WHEN'); end);

    if #bar.conditions == 0 then
        add(S(ROW_H), function (dl, x, y, right)
            note(dl, x, y + S(ROW_H) / 2, 'Always. Add a condition to show the bar only at times; with several, all must hold.',
                right - x, P.dim);
        end);
    end
    for n, c in ipairs(bar.conditions) do
        plan_condition(add, bar, c, n, width);
    end

    local widths = {};
    for i, k in ipairs(conditions.KINDS) do
        widths[i] = style.chip_width(k.label);
    end
    local lines = wrap(widths, width - S(LABEL_W));
    add(S(ROW_H) * #lines, function (dl, x, y, right)
        row_label(dl, x, y + S(ROW_H) / 2, 'Add');
        for l, line in ipairs(lines) do
            local cy, at = y + (l - 0.5) * S(ROW_H), x + S(LABEL_W);
            for _, i in ipairs(line) do
                local k = conditions.KINDS[i];
                if style.chip('##jb_add_' .. k.kind, at, cy, k.label, false) then
                    table.insert(bar.conditions, conditions.new(k.kind));
                    hotbars.mark_dirty();
                end
                style.tip(HINTS[k.kind]);
                at = at + widths[i] + S(CHIP_GAP);
            end
        end
    end);
end

-- The slot's rows. They keep to the slot planned: a row above them may pick
-- another bar (and no slot) part way through the frame. The label and recasts
-- are the current job/subjob's: each job/subjob has its own.
local function plan_slot(add, bar, width)
    local edit = hotbars.edit;
    local index = edit.slot;
    local slot = bar.slots[index];
    local entry = hotbar_ui.bound(slot.key);
    local job = hotbar_ui.job();
    local job_name = job and hotbars.job_label(job) or nil;

    add(S(6) + S(HEAD_H), function (dl, x, y, right)
        heading(dl, x, y, right, 'SLOT', job_name and ('Label and recasts for ' .. job_name) or nil);
    end);

    -- Which slot, and Clear slot
    add(S(ROW_H), function (dl, x, y, right)
        local cy = y + S(ROW_H) / 2;
        row_label(dl, x, cy, 'Slot');
        local at = x + S(LABEL_W);
        local v, changed, w = style.stepper('##jb_slot_step', at, cy, index, 1, #bar.slots);
        if changed then
            edit.slot = v;
        end
        note(dl, at + w + S(10), cy, ('of %d. Or click a slot on screen.'):format(#bar.slots), S(220), P.dim);

        local clear_w = math.max(S(84), style.button_width('Clear slot'));
        if style.button('##jb_slot_clear', right - clear_w, cy, 'Clear slot', 'ghost', clear_w) and bar.slots[index] then
            bar.slots[index] = {};
            hotbars.mark_dirty();
        end
        style.tip('Empty this slot: its key, and its labels and recasts on every job');
    end);

    -- Key, and what it runs now
    add(S(ROW_H), function (dl, x, y, right)
        local cy = y + S(ROW_H) / 2;
        row_label(dl, x, cy, 'Key');
        local fx, fw = x + S(LABEL_W), S(96);
        if field('##jb_slot_key', fx, cy, fw, buf.key, 16) then
            local text = trim(buf.key[1]);
            local chord = text ~= '' and profiles.parse_chord(text) or nil;
            slot.key = chord and chord.id or nil;
            hotbars.mark_dirty();
        end
        placeholder(dl, fx, cy - S(FIELD_H) / 2, buf.key, 'such as ^1');

        local nx = fx + fw + S(12);
        local room = right - nx;
        local chord = slot.key and profiles.parse_chord(slot.key);
        local now = hotbar_ui.bound(slot.key);
        if not chord then
            note(dl, nx, cy, 'A key, after ^ for Ctrl, ! for Alt, + for Shift', room, P.dim);
        elseif profiles.is_blocked(chord) then
            note(dl, nx, cy, 'The game keeps this key: it can\'t be bound', room, P.rose);
        elseif now then
            note(dl, nx, cy, ('%s  [%s]'):format(describe(now.binding), now.binding.scope.label), room, P.text2);
            if style.hit('##jb_slot_runs', nx, cy - S(FIELD_H) / 2, room, S(FIELD_H)) then
                style.tooltip(table.concat(now.binding.lines, '\n'));
            end
        else
            note(dl, nx, cy, ('Not bound for %s: hidden when this page is closed'):format(job_name or 'this job'),
                room, P.dim);
        end
    end);

    if not job then
        add(S(ROW_H), function (dl, x, y, right)
            note(dl, x + S(LABEL_W), y + S(ROW_H) / 2, 'Labels and recasts are set for each job: log in to set them.',
                right - x - S(LABEL_W), P.dim);
        end);
        return;
    end

    -- Label on this job: empty takes the one from what the key runs
    add(S(ROW_H), function (dl, x, y, right)
        local cy = y + S(ROW_H) / 2;
        row_label(dl, x, cy, 'Label');
        local fx, fw = x + S(LABEL_W), S(200);
        if field('##jb_slot_label', fx, cy, fw, buf.label, 64) then
            local text = trim(buf.label[1]);
            hotbars.for_job(slot, job, true).label = text ~= '' and text or nil;
            hotbars.prune(slot, job);
            hotbars.mark_dirty();
        end
        local auto = entry and entry.label or '';
        placeholder(dl, fx, cy - S(FIELD_H) / 2, buf.label, auto);
        local own = hotbars.for_job(slot, job);
        local said = own and own.label and (job_name .. ' only')
            or auto ~= '' and ('Empty: taken from the key on ' .. job_name) or 'Empty';
        note(dl, fx + fw + S(12), cy, said, right - fx - fw - S(12), P.dim);
    end);

    -- Recasts on this job: those picked, or what auto finds
    local own = hotbars.for_job(slot, job);
    local picked = own and own.recasts;
    local widths = {};
    for i, rc in ipairs(picked or {}) do
        widths[i] = removable_width(rc.name ~= '' and rc.name or '?');
    end
    local lines = (picked and #picked > 0) and wrap(widths, width - S(LABEL_W)) or { {} };
    add(S(ROW_H) * #lines, function (dl, x, y, right)
        row_label(dl, x, y + S(ROW_H) / 2, 'Recasts');
        local at0 = x + S(LABEL_W);
        if not picked then
            local names = {};
            for _, rc in ipairs(entry and entry.recasts or {}) do
                names[#names + 1] = rc.name;
            end
            local text = #names > 0 and ('Auto: ' .. table.concat(names, ', ')) or 'Auto: none in what the key runs';
            note(dl, at0, y + S(ROW_H) / 2, text, right - at0, #names > 0 and P.text2 or P.dim);
            return;
        end
        if #picked == 0 then
            note(dl, at0, y + S(ROW_H) / 2, 'None', right - at0, P.dim);
            return;
        end
        local drop = nil;
        for l, line in ipairs(lines) do
            local cy, at = y + (l - 0.5) * S(ROW_H), at0;
            for _, i in ipairs(line) do
                local rc = picked[i];
                if removable(dl, ('##jb_rc_%d'):format(i), at, cy, rc.name ~= '' and rc.name or '?') then
                    drop = i;
                end
                at = at + widths[i] + S(CHIP_GAP);
            end
        end
        if drop then
            table.remove(picked, drop);
            hotbars.mark_dirty();
        end
    end);

    -- Search to add one, and Auto / None
    local found = matches(slot);
    add(S(ROW_H), function (dl, x, y, right)
        local cy = y + S(ROW_H) / 2;
        local fx = x + S(LABEL_W);
        local auto_w, none_w = style.chip_width('Auto'), style.chip_width('None');
        local fw = right - fx - auto_w - none_w - S(CHIP_GAP) - S(12);
        field('##jb_slot_search', fx, cy, fw, buf.search, 64);
        placeholder(dl, fx, cy - S(FIELD_H) / 2, buf.search, 'Add: type an ability or spell');

        local now = hotbars.for_job(slot, job);
        local list = now and now.recasts;
        local at = fx + fw + S(12);
        if style.chip('##jb_rc_auto', at, cy, 'Auto', list == nil) then
            set_recasts(slot, job, nil);
        end
        style.tip('On ' .. job_name .. ', take the recasts from the abilities and spells the key uses');
        at = at + auto_w + S(CHIP_GAP);
        if style.chip('##jb_rc_none', at, cy, 'None', list ~= nil and #list == 0) then
            set_recasts(slot, job, {});
        end
        style.tip('Show no recast on this slot on ' .. job_name);
    end);

    if #found > 0 then
        add(#found * S(MATCH_H) + S(6), function (dl, x, y, right)
            local fx = x + S(LABEL_W);
            local fw = right - fx;
            local font, px = style.fonts.text, S(style.BODY - 1);
            for i, rc in ipairs(found) do
                local ry = y + (i - 1) * S(MATCH_H);
                local id = '##jb_match_' .. i;
                local hovered, clicked = style.hit(id, fx, ry, fw, S(MATCH_H));
                local t = style.ease(id, hovered and 1 or 0, 22);
                if t > 0.01 then
                    style.fill(dl, fx, ry, fw, S(MATCH_H), P.hover, S(4), t);
                end
                local cy = ry + S(MATCH_H) / 2;
                style.text_mid(dl, fx + S(9), cy, rc.name, style.mix(P.text2, P.white, t), font, px);
                style.text_right(dl, fx + fw - S(9), cy, rc.kind == 'ja' and 'Ability' or 'Spell', P.dim, font,
                    S(style.SMALL));
                if clicked then
                    add_recast(slot, job, rc);
                    buf.search[1] = '';
                end
            end
        end);
    end
end

-- The page ------------------------------------------------------------------------

-- The page's rows for a window width wide: { rows = { { h, draw }, ... }, h }
function hotbar_page.plan(width)
    local list, edit = hotbars.list(), hotbars.edit;
    local rows, h = {}, 0;
    local function add(row_h, draw)
        rows[#rows + 1] = { h = row_h, draw = draw };
        h = h + row_h;
    end

    edit.bar = math.max(1, math.min(edit.bar or 1, #list));
    local bar = list[edit.bar];
    add(S(PICK_H), draw_picker);

    if not bar then
        add(S(ROW_H) * 2, function (dl, x, y, right)
            note(dl, x, y + S(ROW_H) / 2 + S(4), 'A hotbar shows your keys on screen: what each runs, and its recast.',
                right - x, P.dim);
            note(dl, x, y + S(ROW_H) * 1.5 - S(4), 'Click New bar to make one.', right - x, P.dim);
        end);
    else
        if not edit.slot or edit.slot < 1 or edit.slot > #bar.slots then
            edit.slot = 1;
        end
        sync(bar, bar.slots[edit.slot], hotbar_ui.job());
        plan_bar(add, bar);
        plan_conditions(add, bar, width);
        plan_slot(add, bar, width);
    end

    if hotbars.error then
        local message = hotbars.error;
        add(S(ERROR_H), function (dl, x, y, right)
            note(dl, x, y + S(ERROR_H) / 2, message, right - x, P.rose);
            style.hit('##jb_hotbars_error', x, y, right - x, S(ERROR_H));
            style.tip(message); -- whole, when it was cut to fit
        end);
    end
    add(S(BOTTOM), nil);
    return { rows = rows, h = h };
end

-- Draw the rows planned, from (x, y) to right. x0 and x1 are the window's
-- edges, for the lines that cross it.
function hotbar_page.draw(dl, plan, x, y, right, x0, x1)
    for _, row in ipairs(plan.rows) do
        if row.draw then
            row.draw(dl, x, y, right, x0, x1);
        end
        y = y + row.h;
    end
end

return hotbar_page;
