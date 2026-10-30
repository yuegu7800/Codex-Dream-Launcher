$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$output=Join-Path $root '.local\manager'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$compilerRoot=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$refs=@('System.dll','System.Core.dll','System.Web.Extensions.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Xaml.dll')
foreach($name in @('WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll')){$refs+=Join-Path $compilerRoot ('WPF\'+$name)}
$arguments=@('/nologo','/target:winexe','/platform:x64','/optimize+',('/out:'+(Join-Path $output 'DragonStudio.exe')))
foreach($ref in $refs){$arguments+='/reference:'+$ref}
$arguments+=Join-Path $root 'src\DragonStudio.cs'
& (Join-Path $compilerRoot 'csc.exe') @arguments
if($LASTEXITCODE -ne 0){throw 'Manager compilation failed'}
Write-Output (Join-Path $output 'DragonStudio.exe')
