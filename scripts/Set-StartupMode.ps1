[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Normal','Wallpaper')][string]$Mode)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Package-Common.ps1')
$root = Assert-DragonOrdinaryPath $root
$configPath = Assert-DragonOrdinaryPath (Join-Path $root 'launcher.json')
$config = Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw | ConvertFrom-Json
$backupDir = Assert-DragonOrdinaryPath (Join-Path $root 'backups')
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Copy-Item -LiteralPath $configPath -Destination (Join-Path $backupDir ('launcher-mode-' + [guid]::NewGuid().ToString('N') + '.json'))
$config.LaunchScript = if ($Mode -eq 'Wallpaper') { 'scripts/Wait-DragonSkinReady.ps1' } else { '' }
$config.ReadyFile = if ($Mode -eq 'Wallpaper') { 'state/skin-ready.flag' } else { '' }
Write-DragonJson $configPath $config
Write-Output "Next animation launch mode: $Mode"
Write-Output 'Save work and fully quit Codex before reopening the animation shortcut to apply the new mode.'
Write-Output 'Changing configuration does not close a live debugging port. Removing wallpaper alone does not close it either.'
