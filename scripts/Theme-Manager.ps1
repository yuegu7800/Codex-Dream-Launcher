$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Start-Process -FilePath (Join-Path $root 'DragonStudio.exe') -WorkingDirectory $root
