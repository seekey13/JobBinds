# JobBinds

JobBinds is an Ashita v4 addon for Final Fantasy XI that gives every job its own key bindings. Pick a key on a visual
keyboard, type what it should do, and the binding follows you whenever you change job or subjob.

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
2. Choose the **Profile** the binding belongs to (see below). It starts on your exact job/subjob.
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

### Commands

| Command | |
|---------|---|
| `/jb` or `/jobbinds` | Open or close the window |
| `/jb reload` | Read the profile files again after editing them by hand |
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
