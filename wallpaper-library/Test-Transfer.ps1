$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Transfer.ps1')
$fixture=Join-Path $PSScriptRoot ('data\transfer-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force|Out-Null
$converter=Get-LibraryConverter
$count=0
foreach($kind in @('png','gif','webm')) {
    $folder=Join-Path $fixture $kind
    New-Item -ItemType Directory -Path $folder|Out-Null
    $media=Join-Path $folder ('sample.'+$kind)
    $arguments=@('-nostdin','-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc=size=96x64:rate=5')
    if ($kind -eq 'png') {$arguments+=@('-frames:v','1')}
    else {$arguments+=@('-t','1')}
    & $converter @arguments $media
    if($LASTEXITCODE-ne 0){throw 'Fixture generation failed.'}
    [IO.File]::WriteAllText((Join-Path $folder 'project.json'),(@{title=('TEST '+$kind);type=$(if($kind-eq 'webm'){'video'}else{'image'});file=('sample.'+$kind)}|ConvertTo-Json))
    $item=@(Read-WallpaperCatalog @($folder))[0]
    if(!$item.Convertible){throw "$kind should be convertible"}
    $output=Invoke-LibraryConversion $item (Join-Path $fixture 'exports') 1
    & $converter -nostdin -hide_banner -loglevel error -i $output -f null NUL
    if($LASTEXITCODE-ne 0){throw 'Converted MP4 cannot decode.'}
    $hash=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    $root=Split-Path -Parent $PSScriptRoot
    $libraryFile=Join-Path $root ('skin\library\'+$hash+'.mp4')
    $alreadyExists=Test-Path -LiteralPath $libraryFile
    $added=Add-ExperimentalVideo $output ('TEST '+$kind)
    . (Join-Path $root 'scripts\Theme-Library.ps1')
    if (!(@(Get-DragonVideos $root | Where-Object {$_.Id -eq $added.Id}).Count -eq 1)) {throw 'Export did not appear in manager list.'}
    if ($added.AutomaticApply) {throw 'Must not auto-apply.'}
    if(!$alreadyExists) {
        # Delete only this test's exact hash-named generated files.
        Remove-Item -LiteralPath $libraryFile -Force
        Remove-Item -LiteralPath ([IO.Path]::ChangeExtension($libraryFile,'.json')) -Force
    }
    $count++
}
Write-Output "PASS: $count real conversions (PNG, GIF, WebM) decoded; all appeared in experimental manager list; no automatic apply."
