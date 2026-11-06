param([Parameter(Mandatory=$true)][string]$NodePath)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\Theme-Library.ps1')
$fixture=Join-Path $repo ('.local\library-'+[guid]::NewGuid().ToString('N'))
foreach($dir in @('themes\dragon','engine\scripts','engine\assets','engine\runtime\node','skin')){New-Item -ItemType Directory -Path (Join-Path $fixture $dir) -Force | Out-Null}
Copy-Item (Join-Path $repo 'themes\dragon\*') (Join-Path $fixture 'themes\dragon')
Copy-Item (Join-Path $repo 'engine\scripts\*') (Join-Path $fixture 'engine\scripts')
Copy-Item (Join-Path $repo 'engine\assets\*') (Join-Path $fixture 'engine\assets')
Copy-Item $NodePath (Join-Path $fixture 'engine\runtime\node\node.exe')
$video=Join-Path $fixture 'themes\dragon\wallpaper.mp4'
$original=(Get-FileHash (Join-Path $fixture 'themes\dragon\theme.json')).Hash
$id=Import-DragonVideo $fixture $video
$null=Import-DragonVideo $fixture $video
if(@(Get-DragonVideos $fixture).Count -ne 2){throw 'Video deduplication failed'}
if((Get-FileHash (Join-Path $fixture 'themes\dragon\theme.json')).Hash -ne $original){throw 'Import changed active theme'}
foreach($preset in Get-DragonPresets){Set-DragonTheme $fixture $id $preset.Id ([int]($preset.Opacity*100))}
$current=Get-Content (Join-Path $fixture 'themes\dragon\theme.json') -Raw | ConvertFrom-Json
if($current.colors.accent -ne '#73716a' -or $current.image -ne ('library-'+$id+'.mp4')){throw 'Theme apply failed'}
$pref=Get-Content (Join-Path $fixture 'skin\theme-preferences.json') -Raw | ConvertFrom-Json
if($pref.themes.'dragon-codex-light'.transparency -ne 45){throw 'Transparency preference mismatch'}
Set-DragonTheme $fixture bundled dragon 90
if((Get-Content (Join-Path $fixture 'themes\dragon\theme.json') -Raw | ConvertFrom-Json).image -ne 'wallpaper.mp4'){throw 'Bundled restore failed'}
Set-DragonPaused $fixture $true
if(!(Test-Path (Join-Path $fixture 'skin\paused'))){throw 'Pause failed'}
Set-DragonPaused $fixture $false
if(Test-Path (Join-Path $fixture 'skin\paused')){throw 'Resume failed'}
$rejected=$false
try{Set-DragonTheme $fixture '../escape' dragon 90}catch{$rejected=$true}
if(!$rejected){throw 'Unknown ID accepted'}
$invalid=Join-Path $fixture 'fake.mp4'
[IO.File]::WriteAllBytes($invalid,(New-Object byte[] 32))
$rejected=$false
try{Import-DragonVideo $fixture $invalid}catch{$rejected=$true}
if(!$rejected){throw 'Invalid MP4 accepted'}
Write-Output 'PASS: local import/dedup without auto-apply; 5 presets; restore; transparency; pause/resume; invalid ID and invalid MP4 rejected.'
