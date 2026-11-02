$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\Theme-Library.ps1')
$root=Split-Path $PSScriptRoot -Parent
$store=Initialize-DragonLibrary $root
$hash='b'*64
$meta=Join-Path $store ($hash+'.json')
$file=Join-Path $store ($hash+'.mp4')
if(Test-Path $file){throw 'Fixture collision'}
try {
 Copy-Item (Join-Path $root 'themes\dragon\wallpaper.mp4') $file
 Write-DragonJson $meta @{name='中文素材·龙娘壁纸'}
 $name=(Get-DragonVideos $root|Where-Object Id -eq $hash).Name
 if($name -cne '中文素材·龙娘壁纸'){throw 'Chinese name roundtrip failed'}
 Write-Output 'PASS: Chinese names preserved by Windows PowerShell 5.1.'
} finally {Remove-Item -LiteralPath $file,$meta -ErrorAction SilentlyContinue}