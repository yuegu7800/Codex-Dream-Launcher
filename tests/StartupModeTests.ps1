$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts\Wait-DragonSkinReady.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Coordinator parse failed' }
$function = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Select-StartupPort'},$true)
. ([scriptblock]::Create($function.Extent.Text))
for ($n=0; $n -lt 12; $n++) {
    $port = Select-StartupPort
    if ($port -lt 1024 -or $port -gt 65535) { throw 'Port out of range' }
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port)
    try { $listener.Start() } finally { $listener.Stop() }
}
$fixture = Join-Path $root ('.local\mode-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'scripts') -Force | Out-Null
foreach ($name in @('Set-StartupMode.ps1','Package-Common.ps1')) {
    Copy-Item (Join-Path $root ('scripts\'+$name)) (Join-Path $fixture 'scripts')
}
Copy-Item (Join-Path $root 'config\launcher.json') (Join-Path $fixture 'launcher.json')
$original = Get-Content (Join-Path $fixture 'launcher.json') -Raw | ConvertFrom-Json
foreach ($mode in @('Normal','Wallpaper')) {
    & (Join-Path $fixture 'scripts\Set-StartupMode.ps1') -Mode $mode | Out-Null
    $cfg = Get-Content (Join-Path $fixture 'launcher.json') -Raw | ConvertFrom-Json
    if ($cfg.AppLaunch -ne $original.AppLaunch -or $cfg.Video -ne $original.Video) { throw 'Unrelated configuration changed' }
    if ($mode -eq 'Normal' -and ($cfg.LaunchScript -or $cfg.ReadyFile)) { throw 'Normal mode still depends on wallpaper' }
    if ($mode -eq 'Wallpaper' -and ($cfg.LaunchScript -ne 'scripts/Wait-DragonSkinReady.ps1' -or $cfg.ReadyFile -ne 'state/skin-ready.flag')) { throw 'Wallpaper mode not restored' }
}
if (@(Get-ChildItem (Join-Path $fixture 'backups')).Count -ne 2) { throw 'Mode backups missing' }
Write-Output 'PASS: 12 ephemeral loopback allocations; normal/wallpaper switch and backups in isolated fixture.'
