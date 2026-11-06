$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'engine\scripts\common-windows.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Common script parse failed' }
$fn = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Stop-DreamSkinRecordedInjector'}, $true)
. ([scriptblock]::Create($fn.Extent.Text))
function Get-Process { param($Id,$ErrorAction) return $script:fakeProcess }
function Get-CimInstance { param($ClassName,$Filter,$ErrorAction) return $null }
function Stop-Process { throw 'An unrelated process must never be stopped' }
$state = [pscustomobject]@{injectorPid=3920; injectorStartedAt='2026-11-05T09:05:58.0000000Z'}
$script:fakeProcess = $null
if (!(Stop-DreamSkinRecordedInjector $state)) { throw 'Exited watcher blocked startup' }
$script:fakeProcess = [pscustomobject]@{ProcessName='unrelated'; HasExited=$false}
if (!(Stop-DreamSkinRecordedInjector $state)) { throw 'Reused non-node PID blocked startup' }
$script:fakeProcess = [pscustomobject]@{ProcessName='node'; StartTime=[datetime]'2026-11-06T08:00:00Z'; HasExited=$false}
if (!(Stop-DreamSkinRecordedInjector $state)) { throw 'Reused node PID blocked startup' }
$script:fakeProcess.StartTime = [DateTimeOffset]::Parse($state.injectorStartedAt).LocalDateTime
$blocked = $false
try { Stop-DreamSkinRecordedInjector $state | Out-Null } catch { $blocked = $_.Exception.Message -match 'identity cannot be inspected' }
if (!$blocked) { throw 'Unknown identity must still fail closed' }
Write-Output 'PASS: exited watcher, reused non-node/node PID, unknown identity preserved; no process terminated.'
