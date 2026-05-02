# JobBinds

### Click any key to configure bindings
<img width="518" height="224" alt="image" src="https://github.com/user-attachments/assets/b82859b1-f3f0-4b82-8125-8ae065ee0d09" />

### If you only have a single command just type it in and click save
<img width="515" height="312" alt="image" src="https://github.com/user-attachments/assets/9652e4b2-0aff-4bb5-bb95-74cb1522cfdb" />

### Enable the Macro checkbox to expand multiline binding, command name will be listed as a tooltip.
<img width="524" height="424" alt="image" src="https://github.com/user-attachments/assets/7f00c4f8-284c-4597-93f8-d89df085e3d4" />


### Some keys do not have conflicting system functions and can bind Ctrl & Alt
<img width="523" height="379" alt="image" src="https://github.com/user-attachments/assets/a917ecd3-188a-4aa3-855a-67e6b94c4745" />

### Keys with Compact game function are disabled.

JobBinds is an Ashita v4 addon for Final Fantasy XI that automatically loads keybind profile scripts based on your current job and subjob, featuring a built-in graphical configuration interface for managing your keybinds.

> **Note:**  
> This addon is designed for **Ashita v4** and expects your keybind profile scripts to be placed in the `Ashita/scripts` directory.  
> Each profile must be named in the format `JOB_SUB.txt` (e.g., `WAR_NIN.txt`).  
> No fallback or default profile is loaded if a job/subjob combination is missing.

---

## Features

- **Automatic Profile Switching:** Loads the correct keybind profile when you change jobs
- **Graphical Configuration Interface:** Built-in ImGui interface for managing keybinds
- **Real-time Key Validation:** Prevents binding of essential game keys with instant feedback
- **Macro Support:** Create and edit multi-line macro files from the UI
- **Profile Management:** Automatically unbinds previous profile keys before loading new ones
- **Debug Mode:** Toggle detailed logging with `/jobbinds debug`

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
    /jobbinds
    ```
---

## Usage

JobBinds runs automatically in the background. When you change jobs or subjobs, it will unbind the previous profile's keys and load the new profile.

### Commands

- `/jobbinds` - Opens the configuration window
- `/jobbinds debug` - Toggles debug mode

### Configuration Interface

Access the configuration interface with `/jobbinds`:

- View and edit current keybinds
- Create new bindings with key validation
- Macro support for multi-line commands
- Real-time profile updates

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
  - `@` = Win
  - `#` = Apps

### Blocked Keys

Essential game keys are protected from being bound:

**Movement & Interface:** `W` `A` `S` `D` `F` `V` `R` `Y` `H` `I` `J` `K` `L` `N`  
**Navigation:** Arrow keys, `TAB`, `ENTER`, `SPACE`, `ESCAPE`  
**Function Keys:** `F1` through `F12`  
**System Keys:** Modifier keys and system shortcuts

Some keys like `B` `E` `M` `Q` `T` `U` `X` and numbers can be used alone or with Shift, but not with Ctrl/Alt.

### Debug Mode

Enable debug mode with `/jobbinds debug` to see detailed logging of job changes, profile loading, and key operations.

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

### Version 0.4 (Current)
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
