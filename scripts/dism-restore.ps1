$ErrorActionPreference = 'Continue'
$log = 'C:\hidisp\dism-restore-log.txt'
Start-Transcript -Path $log -Force | Out-Null

Write-Output "=== DISM RESTOREHEALTH START $(Get-Date -Format s) ==="
DISM /Online /Cleanup-Image /RestoreHealth
Write-Output "=== DISM RESTOREHEALTH EXIT: $LASTEXITCODE $(Get-Date -Format s) ==="

Write-Output ""
Write-Output "=== POST-CHECK: LKG folder contents ==="
$lkg = 'C:\Windows\SystemApps\LKG'
Get-ChildItem $lkg -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $n = @(Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  Write-Output ("  {0,-55} files={1}" -f $_.Name, $n)
}

Write-Output ""
Write-Output "=== POST-CHECK: SpeechRuntime.exe ==="
foreach ($p in 'C:\Windows\System32\SpeechRuntime.exe','C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy\SpeechRuntime.exe') {
  Write-Output ("  {0} -> {1}" -f $p, (Test-Path $p))
}

Write-Output ""
Write-Output "=== DISM SCRIPT DONE $(Get-Date -Format s) ==="
Stop-Transcript | Out-Null
