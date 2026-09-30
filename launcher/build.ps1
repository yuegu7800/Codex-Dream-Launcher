[CmdletBinding()]
param(
  [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$build = Join-Path $root 'build'
$assets = Join-Path $build 'assets'

New-Item -ItemType Directory -Path $build -Force | Out-Null
New-Item -ItemType Directory -Path $assets -Force | Out-Null

$framework = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $framework 'csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
  throw 'The Windows C# compiler was not found.'
}

function Resolve-GacAssembly {
  param([Parameter(Mandatory = $true)][string]$Name)
  $item = Get-ChildItem 'C:\Windows\Microsoft.NET\assembly' -Filter $Name -Recurse -File |
    Where-Object { $_.FullName -match 'GAC_(MSIL|64)' } |
    Select-Object -First 1
  if (-not $item) { throw "Required WPF assembly not found: $Name" }
  return $item.FullName
}

$references = @(
  (Resolve-GacAssembly 'PresentationCore.dll'),
  (Resolve-GacAssembly 'PresentationFramework.dll'),
  (Resolve-GacAssembly 'System.Xaml.dll'),
  (Resolve-GacAssembly 'UIAutomationClient.dll'),
  (Resolve-GacAssembly 'UIAutomationTypes.dll'),
  (Resolve-GacAssembly 'WindowsBase.dll'),
  (Join-Path $framework 'System.dll'),
  (Join-Path $framework 'System.Core.dll'),
  (Join-Path $framework 'System.Runtime.Serialization.dll')
)

$referenceArgs = @($references | ForEach-Object { '/reference:' + $_ })
$output = Join-Path $build 'CodexDreamLauncher.exe'
$arguments = @(
  '/nologo',
  '/target:winexe',
  '/platform:x64',
  '/optimize+',
  '/warn:4',
  ('/win32manifest:' + (Join-Path $root 'app.manifest')),
  ('/out:' + $output)
) + $referenceArgs + @((Join-Path $root 'src\Program.cs'))

& $csc $arguments
if ($LASTEXITCODE -ne 0) { throw "Compilation failed with exit code $LASTEXITCODE" }

Copy-Item -LiteralPath (Join-Path $root 'launcher.json') -Destination (Join-Path $build 'launcher.json') -Force
$wallpaper = Join-Path $root 'assets\violet-evergarden.jpg'
if (Test-Path -LiteralPath $wallpaper) {
  Copy-Item -LiteralPath $wallpaper -Destination (Join-Path $assets 'violet-evergarden.jpg') -Force
} else {
  Write-Warning 'No optional wallpaper was supplied. Add assets\violet-evergarden.jpg or update launcher.json.'
}
Copy-Item -LiteralPath (Join-Path $root 'README.md') -Destination (Join-Path $build 'README.md') -Force
$projectPrompt = Join-Path $root 'PROJECT_PROMPT.md'
if (Test-Path -LiteralPath $projectPrompt) {
  Copy-Item -LiteralPath $projectPrompt -Destination (Join-Path $build 'PROJECT_PROMPT.md') -Force
}

Write-Host "Built $output"
