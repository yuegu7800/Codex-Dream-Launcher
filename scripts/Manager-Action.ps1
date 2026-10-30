[CmdletBinding()]
param([ValidateSet('List','Import','Apply','Pause','Resume','Normal','Wallpaper')][string]$Action='List',[string]$Path,[string]$VideoId,[string]$PresetId,[int]$Reveal=90)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$env:PSModulePath += ';'+(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Theme-Library.ps1')
try {
    switch($Action){
        List { $value=@{videos=@(Get-DragonVideos $root);presets=@(Get-DragonPresets)} }
        Import { $value=@{id=(Import-DragonVideo $root $Path)} }
        Apply { Set-DragonTheme $root $VideoId $PresetId $Reveal;$value=@{ok=$true} }
        Pause {Set-DragonPaused $root $true;$value=@{ok=$true}}
        Resume {Set-DragonPaused $root $false;$value=@{ok=$true}}
        Normal {& (Join-Path $PSScriptRoot 'Set-StartupMode.ps1') -Mode Normal | Out-Null;$value=@{ok=$true}}
        Wallpaper {& (Join-Path $PSScriptRoot 'Set-StartupMode.ps1') -Mode Wallpaper | Out-Null;$value=@{ok=$true}}
    }
    [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
    Write-Output ($value | ConvertTo-Json -Depth 12 -Compress)
} catch {[Console]::Error.WriteLine($_.Exception.Message);exit 1}
