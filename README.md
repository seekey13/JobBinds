# JobBinds

JobBinds is an Ashita v4 addon for Final Fantasy XI that gives every job its own key bindings. Pick a key on a visual
keyboard, type what it should do, and the binding follows you whenever you change job or subjob. Hotbars put your keys
on screen, with what each one runs and a countdown while its ability or spell recasts.

## What's new in 2.0

2.0 is a rewrite. The idea is the same; how it works is not.

- **No more script files.** 1.x kept each profile and each macro as a `/exec` script in `Ashita/scripts`. 2.0 runs
  bindings itself: a macro is just several lines typed into the editor, with nothing to name and no files to manage.
- **Profiles stack.** A binding can be global, or apply to a main job with any subjob, to a subjob under any main job,
  or to one exact combination. Bind your BLM nukes once instead of once per subjob.
- **Your 1.x profiles are imported** the first time 2.0 loads (see [Upgrading from 1.x](#upgrading-from-1x)).

## Installation

1. Download or clone this repository into your Ashita v4 `addons` folder:

    ```
    git clone https://github.com/seekey13/jobbinds.git
    ```

2. Load the addon in-game (add the line to `scripts/default.txt` to load it every time):

    ```
    /addon load jobbinds
    ```

3. Open the window:

    ```
    /jb
    ```

## Usage

### Binding a key

1. Click a key on the keyboard. Keys the game needs are faded and can't be picked.
2. Choose the profile the binding belongs to, at the bottom left of the window (see below). It starts on your exact job/subjob.
3. Type a command next to the key, or next to `Ctrl +`, `Alt +` or `Shift +` the key.
4. Click **Save**. The key works straight away.

**Delete** removes the key's bindings from the selected profile. The `X` beside a row empties just that row (then Save).

Key colours: outlined in blue is the key you're editing, a raised lighter key is one that's bound, a dark sunken key
is free, a faded one is protected. Hover a bound key to see what it runs and which profile that comes from.

### Macros

Turn on **Macro** on a row to get a multi-line box. Each line is one command, sent in order:

```
/ja "Sneak Attack" <me>
/wait 1.1
/ws "Viper Bite" <t>
```

- `/wait 2` on its own line pauses for 2 seconds (fractions are fine).
- A trailing `<wait 2>`, as in the game's own macros, pauses after that line.
- Pressing the key again while its macro is still waiting starts it over.

### Profiles

Four profiles apply to any job combination. When two bind the same key, the one lower in this table wins:

| Profile | Applies to | File |
|---------|------------|------|
| Any/NIN | any main job with that subjob | `SUB_NIN.txt` |
| BLM/Any | that main job with any subjob | `BLM.txt` |
| BLM/NIN | exactly that combination | `BLM_NIN.txt` |
| Global | every job, overriding the job profiles | `ALL.txt` |

The editor notes under a row when another profile supplies or overrides that key.

### Hotbars

A hotbar is a row, column or grid of slots on screen. Each slot shows a key, a label for what the key runs, and while
an ability or spell the key uses is recasting, a dark fade with the seconds left. Click a slot to run its key.

Open the **Hotbars** page at the top of the window (or type `/jb bars`) and click **New bar**. While the page is open
every bar is shown with a tab above it: drag the tab to move the bar, and click a slot to edit it.

- **Bar**: its name, how many slots (up to 40), how many columns (one column per slot for a single row, one column for a
  single column, anything in between for a grid), the slot size, and the text size of the key in each slot's corner
  and of its label.
- **Slot**: the key it shows, written as in the profile files (`1`, `^G` for Ctrl+G, `!C` for Alt+C, `+1` for Shift+1).
  The slot runs whatever that key is bound to for your current job, so one bar works for every job.
- **Label**: leave it empty to take the name from the key's commands (`/ma Holy <t>` shows *Holy*), or type your own.
- **Recasts**: **Auto** takes the recasts of the abilities and spells the key's commands use. Search to pick your own
  instead (one or several: the slot shows the longest), or pick **None**.

A new bar starts on the keys 1 to 0, the next on Shift+1 to Shift+0.

#### Shown when

A bar with no conditions is always shown. Add conditions to show it only at times; with several, all must hold.

| Condition | Shows the bar while |
|-----------|---------------------|
| TP, HP%, MP% | the value is at least, or below, a number (e.g. TP at least 1000) |
| Ctrl, Alt, Shift | the key is held, or not held |
| Engaged | you are engaged, or not |
| Buff | a status is on you (Up), or isn't (Missing), by name: *Haste*, *Sneak Attack* |

For example, a bar on `+1` to `+0` shown while Shift is held, over a bar on `1` to `0` shown while Shift isn't, swaps
the two as you hold Shift.

Hotbars are saved as you change them, in `Ashita/config/addons/jobbinds/hotbars.lua`, for every character. Run
`/jb reload` after editing that file by hand. Abilities with charges (Stratagems, Quick Draw, Ready) show their timer
as the game keeps it, not their charges.

### Commands

| Command | |
|---------|---|
| `/jb` or `/jobbinds` | Open or close the window |
| `/jb bars` | Open the window on its Hotbars page |
| `/jb reload` | Read the profile and hotbar files again after editing them by hand |
| `/jb import` | Import JobBinds 1.x profiles from the scripts folder |

### Profile files

Profiles are plain text in `Ashita/config/addons/jobbinds/`, so they're easy to back up, share or edit. A key on its own
line, then its commands indented beneath it:

```
# BLM_NIN.txt
^G
    /ma "Utsusemi: Ichi" <me>
+Q
    /ja "Elemental Seal" <me>
    /wait 1
    /ma "Sleepga II" <t>
```

Key prefixes: `^` Ctrl, `!` Alt, `+` Shift. Run `/jb reload` after editing a file while the game is running.

### Protected keys

Keys the game uses can't be bound:

**Movement and menus:** `W` `A` `S` `D` `F` `V` `R` `Y` `H` `I` `J` `K` `L` `N` `,` `.` `/` `-`  
**Navigation:** arrow keys, `Tab`, `Enter`, `Space`, `Escape`, `Backspace`, `Page Up`, `Page Down`  
**Function keys:** `F1` to `F12`

`B` `E` `M` `Q` `T` `U` `X` and the number keys can be bound alone or with Shift, but not with Ctrl or Alt. A protected
key written into a profile file by hand is ignored.

## Upgrading from 1.x

The first time 2.0 loads it reads your old `scripts/JOB_SUB.txt` profiles, and the global `scripts/JobBinds.txt` if you
had one, and writes each as a 2.0 profile, with the
contents of any macro file a key `/exec`'d copied into the binding. Nothing in the scripts folder is changed or
removed; once you're happy, the old profile and macro files can be deleted. `/jb import` runs the import again and never
replaces a 2.0 profile that already exists.

An imported profile lands on its exact job/subjob. To share bindings across subjobs, move them to the main job's
profile (for example from `BLM_NIN.txt` to `BLM.txt`) in the window or in the files.

## Compatibility

- **Ashita v4** (required)

## License

MIT License. See [LICENSE](LICENSE) for details.

## Credits

- Author: Seekey

## Support

Open an issue or pull request on the [GitHub repository](https://github.com/seekey13/jobbinds).

## Changelog

### Version 2.1
- Hotbars: rows, columns or grids of your keys on screen, moved by dragging
- Slots take their label and recasts from what the key runs for the current job, or set their own
- Recast countdowns: a fade and the seconds left, for one or more abilities and spells per slot
- Conditions to show a bar only at times: TP, HP%, MP%, Ctrl/Alt/Shift held, engaged, a buff up or missing
- Click a slot to run its key

### Version 2.0
- Rewritten from scratch
- Bindings run by the addon: no `/exec` scripts or macro files
- Stacking profiles: subjob, main job, exact job/subjob, global
- Multi-line macros with `/wait` typed straight into the editor
- Plain-text profiles in `config/addons/jobbinds`
- Automatic import of 1.x profiles
- Job changes detected by watching the job itself rather than packets
- Keys are released when the addon unloads

### Version 1.0
- Visual keyboard interface, script browser, multi-modifier support

### Versions 0.1 to 0.4
- Automatic profile loading by job/subjob, key blacklist, first configuration interface
