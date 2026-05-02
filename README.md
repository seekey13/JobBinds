# JobBinds

JobBinds is an Ashita v4 addon for Final Fantasy XI that automatically loads keybind profile scripts based on your current job and subjob, featuring a built-in graphical configuration interface for managing your keybinds.

> **Note:**  
> This addon is designed for **Ashita v4** and expects your keybind profile scripts to be placed in the `Ashita/scripts` directory.  
> Each profile must be named in the format `JOB_SUB.txt` (e.g., `WAR_NIN.txt`).  
> No fallback or default profile is loaded if a job/subjob combination is missing.

## Quick Setup
### Click any key to configure bindings
<img width="518" height="224" alt="image" src="https://github.com/user-attachments/assets/b82859b1-f3f0-4b82-8125-8ae065ee0d09" />

### If you only have a single command just type it in and click save
<img width="515" height="312" alt="image" src="https://github.com/user-attachments/assets/9652e4b2-0aff-4bb5-bb95-74cb1522cfdb" />

### Enable the Macro checkbox to expand multiline binding, command name will be listed as a tooltip, scroll a list of other bindings in your `scripts` folder
<img width="524" height="424" alt="image" src="https://github.com/user-attachments/assets/7f00c4f8-284c-4597-93f8-d89df085e3d4" />


### Some keys do not have conflicting system functions and can bind Ctrl & Alt
<img width="523" height="379" alt="image" src="https://github.com/user-attachments/assets/a917ecd3-188a-4aa3-855a-67e6b94c4745" />

### Keys with Compact game function are disabled.

## Features

- **Automatic Profile Switching:** Loads the correct keybind profile when you change jobs
- **Visual Keyboard Interface:** Interactive keyboard layout with color-coded keys (green=selected, standard=bound, gray=unbound, red=blocked)
- **Script Browser:** Browse and load existing macros with automatic filtering of job profiles
- **Filename Validation:** Real-time validation prevents invalid Windows filename characters
- **Key Tooltips:** Hover over bound keys to see their commands
- **Multi-Modifier Support:** Configure up to 4 bindings per key (base, Ctrl, Alt, Shift)
- **Quick Clear:** Remove individual bindings with one-click Clear buttons
- **Profile Display:** Shows current job/subjob combination in the interface

---

## Installation

1. Download or clone this repository into your Ashita v4 `addons` folder:

    ```
    git clone https://github.com/seekey13/jobbinds.git
    ```

2. Start or restart Ashita.
3. Load the addon in-game:

    ```
    /addon load jobbinds
    ```
4. Open the in-game configuration:

    ```
    /jb
    ```
---

## Usage

JobBinds runs automatically in the background. When you change jobs or subjobs, it will unbind the previous profile's keys and load the new profile.

### Commands

- `/jb` or `/jobbinds` - Opens the configuration window

### Configuration Interface

Access the keyboard interface with `/jb` or `/jobbinds`:

- **Visual Keyboard:** Click any key to configure bindings
- **Color Coding:** Green (selected), standard (bound), gray (unbound), dark red (blocked)
- **Tooltips:** Hover over keys to see bound commands
- **Binding Editor:** Configure up to 4 modifier combinations per key
- **Script List:** Browse and load existing macros (filters out job profiles)
- **Validation:** Red text indicates invalid filename characters; Save button disabled until fixed
- **Clear Buttons:** Remove individual bindings without deleting entire key
- **Profile Display:** Current job/subjob shown after Delete button

### Keybind Profiles

- **Naming Convention:**  
  Profile scripts must be named as `JOB_SUB.txt`, e.g., `WAR_NIN.txt`, `BLM_RDM.txt`
- **Location:**  
  Place scripts in `Ashita/scripts/`
- **Contents:**  
  Use Ashita's `/bind` commands in your scripts.  
  Example:
  ```
  /bind ^F1 /wave
  /bind ^1 /attack
  /bind +F2 /exec macro_heal
  ```
- **Modifier Keys:**  
  - `^` = Ctrl
  - `!` = Alt  
  - `+` = Shift

### Blocked Keys

Essential game keys are protected from being bound:

**Movement & Interface:** `W` `A` `S` `D` `F` `V` `R` `Y` `H` `I` `J` `K` `L` `N`  
**Navigation:** Arrow keys, `TAB`, `ENTER`, `SPACE`, `ESCAPE`  
**Function Keys:** `F1` through `F12`  
**System Keys:** Modifier keys and system shortcuts

Some keys like `B` `E` `M` `Q` `T` `U` `X` and numbers can be used alone or with Shift, but not with Ctrl/Alt.

---

## Output

JobBinds provides color-coded chat messages:

```
[JobBinds] Loaded jobbinds profile: WAR_NIN.txt
[JobBinds] Job change detected: WAR/NIN -> BLM/RDM
[JobBinds] ERROR: Profile BLM_RDM.txt not found.
[JobBinds] [DEBUG] Found bindable key: ^F1
```

---

## Advanced Script Features (Ashita v4)

Scripts may use argument tokens (`%0%`) and `/include` directives. See [Ashita v4 documentation](https://www.ashitaxi.com/) for details.

---

## Compatibility

- **Ashita v4** (required)

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Credits

- Author: Seekey
- Inspired by the need for job-based keybind management.

---

## Support

Open an issue or pull request on the [GitHub repository](https://github.com/seekey13/jobbinds) for suggestions or problems.

---

## Changelog

### Version 0.5 (Current)
- Visual keyboard interface with interactive key selection
- Color-coded keyboard keys with status tooltips
- Script browser with automatic job profile filtering
- Filename validation for macros with visual feedback
- Clear buttons for individual bindings
- Profile/job combination display
- Multi-modifier support (base, Ctrl, Alt, Shift per key)
- Removed legacy configuration UI

### Version 0.4
- Enhanced messaging system with color-coded chat output
- Comprehensive key blocking with real-time validation
- Code consolidation and improved maintainability
- Better error handling and debug output

### Version 0.3
- Added graphical configuration interface with ImGui
- Real-time keybind editing and macro support
- Instant profile loading and debug mode
- Enhanced error handling

### Version 0.2
- Improved packet monitoring for job changes
- Enhanced key tracking and unbinding
- Better error handling with pcall wrappers

### Version 0.1
- Initial release with automatic profile loading/unloading
- Per-job/subjob keybind management
- Key blacklist enforcement
- Basic error handling
