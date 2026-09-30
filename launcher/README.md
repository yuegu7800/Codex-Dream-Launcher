# Codex Dream Launcher

A private Windows launcher that shows a configurable startup animation while opening the official Codex desktop application.

It does not modify Codex, inject CSS, use CDP, or access Euzhi/API/model configuration.

## Build

Run `build.ps1`. The packaged files are written to `build/`.

## Customize

Edit `launcher.json` and replace `assets/violet-evergarden.jpg`. Keep the same file name or update `backgroundImage`.

Press Escape or click the close icon to dismiss the splash. Dismissing the splash does not terminate Codex.

Run `CodexDreamLauncher.exe --preview` to inspect the animation without launching Codex.
