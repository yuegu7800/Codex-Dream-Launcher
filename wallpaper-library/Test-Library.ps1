$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Library.ps1')
$fixture=Join-Path $PSScriptRoot ('data\test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture -Force
$script:assertions=0
function Assert($Condition,[string]$Message){if(!$Condition){throw $Message};$script:assertions++}
function Reject([scriptblock]$Action){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};Assert $rejected 'Unsafe input was not rejected.'}
foreach($case in @('video','large','gif','scene','escape','broken','missing')){
 $folder=Join-Path $fixture $case;New-Item -ItemType Directory -Path $folder|Out-Null
 $data=@{title="Fixture $case";type='video';file='clip.mp4';preview='../outside.jpg'}
 if($case-eq 'gif'){$data.type='image';$data.file='image.gif'}
 if($case-eq 'scene'){$data.type='scene';$data.file='scene.pkg'}
 if($case-eq 'escape'){$data.file='../outside.mp4'}
 [IO.File]::WriteAllText((Join-Path $folder 'project.json'),($data|ConvertTo-Json))
 if($case-ne 'missing' -and $case-ne 'escape'){
  $media=Join-Path $folder $data.file
  $bytes=New-Object byte[] 32
  [Text.Encoding]::ASCII.GetBytes('ftyp').CopyTo($bytes,4)
  if($case-eq 'broken'){$bytes[4]=0}
  [IO.File]::WriteAllBytes($media,$bytes)
  if($case-eq 'large'){$s=[IO.File]::OpenWrite($media);$s.SetLength(16MB+1);$s.Dispose()}
 }
}
$catalog=@(Read-WallpaperCatalog @($fixture))
Assert ($catalog.Count-eq 7) 'Catalog should include every project, including invalid entries.'
Assert (@($catalog|Where-Object Compatible).Count-eq 1) 'Only valid small MP4 should be compatible.'
Assert (@($catalog|Where-Object Preview).Count-eq 0) 'Traversal preview must not load.'
$video=$catalog|Where-Object Compatible
$output=Join-Path $fixture 'exports'
$first=Export-WallpaperVideo $video $output
$second=Export-WallpaperVideo $video $output
Assert ($first-eq $second) 'Duplicate export did not deduplicate.'
Assert ((Get-FileHash $first).Hash-eq (Get-FileHash $video.Media).Hash) 'Export hash differs.'
Assert ((Get-Content ([IO.Path]::ChangeExtension($first,'.json')) -Encoding UTF8 -Raw|ConvertFrom-Json).automaticApply-eq $false) 'Export must not auto-apply.'
Reject {Resolve-WallpaperAsset $fixture '..\outside.mp4'}
Reject {Resolve-WallpaperAsset $fixture 'C:\outside.mp4'}
Reject {Assert-LocalPath '\\server\share\file.mp4'}
Reject {Assert-LocalPath 'C:\video.mp4:stream'}
Reject {Export-WallpaperVideo ($catalog|Where-Object Id -eq 'scene') $output}
[IO.File]::WriteAllBytes($video.Media,(New-Object byte[] 32))
Reject {Export-WallpaperVideo $video $output}
Write-Output "PASS: $script:assertions assertions; scan/classification, traversal, limits, stale metadata, export SHA-256, dedup and no automatic application."
Write-Output "Test data retained in: $fixture"
