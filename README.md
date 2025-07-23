# JobBinds

<img width="828" height="462" alt="image" src="https://github.com/user-attachments/assets/720ee5c8-6ad9-4d89-a164-23a525a846a4" />

JobBinds is an Ashita v4 addon for Final Fantasy XI that automatically loads keybind profile scripts based on your current job and subjob.

> **Note:**  
> This addon is designed for **Ashita v4** and expects your keybind profile scripts to be placed in the `Ashita/scripts` directory.  
> Each profile must be named in the format `JOB_SUB.txt` (e.g., `WAR_NIN.txt`).  
> No fallback or default profile is loaded if a job/subjob combination is missing.

---

## Features

- **Automatic Profile Switching:**  
  Monitors your current job and subjob, automatically loads the correct keybind profile script when you change jobs.
- **Unbinds Previous Profile:**  
  Ensures all keys set by the previous profile are safely unbound before loading the new one.
- **Blacklist Support:**  
  Protects essential movement and interface keys from being rebound or unbound (`W`, `A`, `S`, `D`, `F`, `V`).
- **Smart Delay:**  
  Uses a configurable delay (default 10 seconds) after job change before loading new binds to prevent issues with rapid job switching.
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
   Monitors relevant game packets to track changes.
2. **Unbind keys from previous profile:**  
   Safely unbinds all keys set by the last loaded profile except blacklisted keys.
3. **Load new profile:**  
   Executes `/exec JOB_SUB.txt` to load the new profile after a brief delay.
4. **Track profile keys:**  
   Remembers which keys were loaded for future unbinding.

### Keybind Profiles

- **Naming Convention:**  
  Profile scripts must be named as `JOB_SUB.txt`, e.g., `WAR_NIN.txt`, `BLM_RDM.txt`
- **Location:**  
  Place scripts in `Ashita/scripts/`
- **Contents:**  
  Use Ashita's `/bind` commands in your scripts.  
  Example:
  ```
  /bind ^!F1 /wave
  /bind ^1 /attack
  ```

### Blacklisted Keys

The following keys are **never** rebound or unbound by JobBinds for safety:
- `W` `A` `S` `D` `F` `V`

### Delay

- JobBinds waits **10 seconds** (configurable in code) after a job/subjob change before loading new binds.

### Error Handling

- All AshitaCore API calls are wrapped in `pcall`; failures are reported as `[JobBinds] ERROR: ...` in chat.

---

## Output

By default, JobBinds prints minimal output to chat when profiles are loaded or errors occur.

**Example Output:**
```
[JobBinds] Loaded jobbinds profile: WAR_NIN.txt
[JobBinds] Previous job/subjob binds unloaded.
[JobBinds] ERROR: Profile ... not found.
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

### Version 0.1
- Initial release with automatic profile loading/unloading
- Per-job/subjob keybind management
- Key blacklist enforcement
- Robust error handling
