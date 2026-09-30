# Codex Dream Control Center Prompt

Build a personal Windows control center for selecting a Codex startup wallpaper and providing an experimental workspace visual-overlay mode.

Hard safety boundaries:

- Do not use DOM, CDP, CSS, DLL, or process injection.
- Do not alter Codex, WindowsApps, app.asar, Euzhi, API keys, base URLs, providers, models, auth, or `.codex` configuration.
- Keep the workspace feature off by default.
- Implement the experimental feature as a separate, low-opacity, click-through Windows overlay. It may be visible only while the official Codex window is foregrounded, and must disappear if Codex exits or the user selects stop/restore.

Required user controls:

- Choose a local image and preview it.
- Change overlay opacity.
- Apply the selected image to the existing startup-animation launcher.
- Start experimental overlay and stop/restore it in one click.
- Clearly identify the experimental feature as an external visual overlay, not an internal Codex theme.

The program must be self-contained, use only Windows/.NET Framework components already present, persist only its own configuration, and remain fail-open.
