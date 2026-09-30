# Codex Dream Launcher

Personal Windows companions for the official Codex Desktop application:

- **Launcher**: starts the official Store application with an optional full-screen startup animation.
- **Control Center**: chooses a local wallpaper for the launcher and offers an optional, external, click-through visual overlay for the Codex window.

## Safety model

This project does not use DOM, CDP, CSS, DLL, or process injection. It does not edit Codex, `WindowsApps`, `app.asar`, Euzhi, API keys, providers, models, authentication, or `.codex` configuration.

The experimental workspace overlay is disabled by default. It is a separate transparent window that shows only while Codex is foregrounded and exits when Codex closes or the user selects stop/restore.

## Build

Windows includes the .NET Framework C# compiler used by these scripts. Run the following commands in PowerShell:

```powershell
Set-Location .\launcher
.\build.ps1

Set-Location ..\control-center
.\build.ps1
```

Each application is emitted to its own `build` directory. The optional wallpaper is intentionally not included. Add a local image at the configured `assets` path, or choose one through the control center after building.

## Repository layout

- `launcher/`: splash launcher source and configuration.
- `control-center/`: wallpaper and experimental overlay settings application.

The code is intended for personal use on Windows with the official Microsoft Store Codex application.
