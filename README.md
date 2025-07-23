# JobBinds

<img width="828" height="462" alt="image" src="https://github.com/user-attachments/assets/720ee5c8-6ad9-4d89-a164-23a525a846a4" />

JobBinds is an Ashita v4 addon for Final Fantasy XI that automatically loads keybind profile scripts based on your current job and subjob, featuring a built-in graphical configuration interface for managing your keybinds.

> **Note:**  
> This addon is designed for **Ashita v4** and expects your keybind profile scripts to be placed in the `Ashita/scripts` directory.  
> Each profile must be named in the format `JOB_SUB.txt` (e.g., `WAR_NIN.txt`).  
> No fallback or default profile is loaded if a job/subjob combination is missing.

---

## Features

- **Automatic Profile Switching:**  
  Monitors your current job and subjob, automatically loads the correct keybind profile script when you change jobs.
- **Graphical Configuration Interface:**  
  Built-in ImGui interface for viewing, editing, creating, and managing keybinds without manually editing text files.
- **Macro Support:**  
  Create and edit multi-line macro files directly from the UI, with automatic file generation and management.
- **Real-time Binding Management:**  
  View all current bindings in an organized list with instant editing capabilities.
- **Unbinds Previous Profile:**  
  Ensures all keys set by the previous profile are safely unbound before loading the new one.
- **Blacklist Support:**  
  Protects essential movement and interface keys from being rebound or unbound (`W`, `A`, `S`, `D`, `F`, `V`).
- **Instant Profile Loading:**  
  Loads new keybind profiles immediately upon job change detection (no delay).
- **Debug Mode:**  
  Toggle detailed logging for troubleshooting with `/jobbinds debug`.
- **Robust Error Handling:**  
  Uses Ashita v4 best practices for safe API calls; errors are logged to chat for troubleshooting.
- **Minimal Setup:**  
  No configuration required—just add your profiles and let the addon handle everything.

---

## Installation

1. Download or clone this repository into your Ashita v4 `addons` folder:

    ```
    git clone https://github.com/seekey13/jobbinds.git
    ```

2. Place your keybind profile scripts (`JOB_SUB.txt`) in your `Ashita/scripts` directory.
3. Start or restart Ashita.
4. Load the addon in-game:

    ```
    /addon load jobbinds
    ```

---

## Usage

JobBinds runs automatically in the background. When you change jobs or subjobs, it will:

1. **Detect your job and subjob:**  
   Monitors relevant game packets (0x1B, 0x44, 0x1A) to track changes in real-time.
2. **Unbind keys from previous profile:**  
   Safely unbinds all keys set by the last loaded profile except blacklisted keys.
3. **Load new profile:**  
   Executes `/exec JOB_SUB.txt` to load the new profile immediately.
4. **Update configuration UI:**  
   Automatically updates the graphical interface with the new profile's bindings.

### Commands

- `/jobbinds` - Opens the configuration window
- `/jobbinds debug` - Toggles debug mode for detailed logging

### Configuration Interface

Access the graphical configuration interface with `/jobbinds`:

- **View Current Bindings:** See all keybinds for the current profile in an organized list
- **Edit Bindings:** Click on any binding to edit its key combination, modifiers, and command
- **Create New Bindings:** Add new keybinds with an intuitive interface
- **Macro Support:** Toggle macro mode to create multi-line command sequences
- **Real-time Updates:** Changes are applied immediately and saved to profile files
- **Delete Bindings:** Remove unwanted keybinds with a single click

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
  /bind @F2 /exec macro_heal
  ```
- **Modifier Keys:**  
  - `^` = Ctrl
  - `!` = Alt  
  - `@` = Shift
  - `#` = Win

### Blacklisted Keys

The following keys are **never** rebound or unbound by JobBinds for safety:
- `W` `A` `S` `D` `F` `V`

### Debug Mode

Enable debug mode with `/jobbinds debug` to see detailed information including:
- Job change detection
- Profile loading/unloading steps
- Key binding/unbinding operations
- File operations and errors
- Packet reception notifications

---

## Output

JobBinds provides informative chat output for profile operations and errors:

**Example Output:**
```
[JobBinds] JobBinds v0.3 by Seekey loaded. Profiles will auto-load on job/subjob change.
[JobBinds] Job change detected: WAR/NIN -> BLM/RDM
[JobBinds] Previous job/subjob binds unloaded.
[JobBinds] Loaded jobbinds profile: BLM_RDM.txt
[JobBinds] Opening JobBinds configuration window.
[JobBinds] Debug mode enabled.
[JobBinds] ERROR: Profile BLM_RDM.txt not found.
```

**Debug Output (when enabled):**
```
[JobBinds] DEBUG: Received packet 0x1B, scheduling job change check
[JobBinds] DEBUG: Current jobs detected: Main=1, Sub=13
[JobBinds] DEBUG: Attempting to load profile: /path/to/scripts/WAR_NIN.txt
[JobBinds] DEBUG: Found bindable key: F1
[JobBinds] DEBUG: Total keys found: 5
```

---

## Advanced Script Features (Ashita v4)

- Scripts may use argument tokens (`%0%`) and `/include` directives.  
  See [Ashita v4 documentation](https://www.ashitaxi.com/) for advanced script usage.

---

## Compatibility

- **Ashita v4** (required)

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Credits

- Author: Seekey
- Inspired by the need for fast and safe job-based keybind management.

---

## Support

Open an issue or pull request on the [GitHub repository](https://github.com/seekey13/jobbinds) if you have suggestions or encounter problems.

---

## Changelog

### Version 0.3 (Current)
- Added graphical configuration interface with ImGui
- Real-time keybind editing and management
- Macro creation and editing support
- Instant profile loading (removed delay)
- Debug mode toggle command
- Enhanced error handling and logging
- Consolidated code for better maintainability
- Config UI integration with profile management

### Version 0.2
- Improved packet monitoring for job changes
- Enhanced key tracking and unbinding
- Better error handling with pcall wrappers

### Version 0.1
- Initial release with automatic profile loading/unloading
- Per-job/subjob keybind management
- Key blacklist enforcement
- Basic error handling
