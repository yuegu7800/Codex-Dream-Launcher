[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$build = Join-Path $root 'build'
$assets = Join-Path $build 'assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null

$framework = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $framework 'csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw 'The Windows C# compiler was not found.' }

function Resolve-GacAssembly {
  param([Parameter(Mandatory = $true)][string]$Name)
  $item = Get-ChildItem 'C:\Windows\Microsoft.NET\assembly' -Filter $Name -Recurse -File |
    Where-Object { $_.FullName -match 'GAC_(MSIL|64)' } |
    Select-Object -First 1
  if (-not $item) { throw "Required assembly not found: $Name" }
  return $item.FullName
}

$references = @(
  (Resolve-GacAssembly 'PresentationCore.dll'),
  (Resolve-GacAssembly 'PresentationFramework.dll'),
  (Resolve-GacAssembly 'System.Xaml.dll'),
  (Resolve-GacAssembly 'WindowsBase.dll'),
  (Join-Path $framework 'System.dll'),
  (Join-Path $framework 'System.Core.dll'),
  (Join-Path $framework 'System.Runtime.Serialization.dll')
)
$referenceArgs = @($references | ForEach-Object { '/reference:' + $_ })
$output = Join-Path $build 'CodexDreamControlCenter.exe'
$arguments = @('/nologo', '/target:winexe', '/platform:x64', '/optimize+', '/warn:4', ('/out:' + $output)) + $referenceArgs + @((Join-Path $root 'src\Program.cs'))
& $csc $arguments
if ($LASTEXITCODE -ne 0) { throw "Compilation failed with exit code $LASTEXITCODE" }

Copy-Item -LiteralPath (Join-Path $root 'launcher.json') -Destination (Join-Path $build 'launcher.json') -Force
Copy-Item -LiteralPath (Join-Path $root 'CONTROL_CENTER_PROMPT.md') -Destination (Join-Path $build 'CONTROL_CENTER_PROMPT.md') -Force
$wallpaper = Join-Path $root 'assets\violet-evergarden.jpg'
if (Test-Path -LiteralPath $wallpaper) {
  Copy-Item -LiteralPath $wallpaper -Destination (Join-Path $assets 'violet-evergarden.jpg') -Force
} else {
  Write-Warning 'No optional wallpaper was supplied. Choose one from the control center after building.'
}
Write-Host "Built $output"
