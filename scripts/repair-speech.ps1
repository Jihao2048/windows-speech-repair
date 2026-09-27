$ErrorActionPreference = 'Continue'
$log = 'C:\hidisp\repair-log.txt'

Start-Transcript -Path $log -Force | Out-Null

Write-Output "=== SPEECH REPAIR START $(Get-Date -Format s) ==="
Write-Output "Elevated: $((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

Write-Output ""
Write-Output "=== STEP 1/4: DISM ScanHealth ==="
DISM /Online /Cleanup-Image /ScanHealth

Write-Output ""
Write-Output "=== STEP 2/4: DISM RestoreHealth ==="
DISM /Online /Cleanup-Image /RestoreHealth

Write-Output ""
Write-Output "=== STEP 3/4: SFC scannow ==="
sfc /scannow

Write-Output ""
Write-Output "=== STEP 4/4: VERIFY ==="
$targets = @(
  'C:\Windows\System32\sapi.dll',
  'C:\Windows\System32\SpeechRuntime.exe',
  'C:\Windows\SysWOW64\sapi.dll',
  'C:\Windows\System32\Speech\SpeechUX\sapi.cpl',
  'C:\Windows\System32\Speech_OneCore\Engines\SR\zh-CN'
)
foreach ($f in $targets) {
  Write-Output ("{0} exists: {1}" -f $f, (Test-Path $f))
}

Write-Output ""
Write-Output "--- Speech services ---"
$svc = Get-Service | Where-Object { $_.Name -match 'Speech|Sapi' }
if ($svc) { $svc | ForEach-Object { Write-Output ("{0}  {1}  {2}" -f $_.Name, $_.Status, $_.StartType) } } else { Write-Output "(none registered)" }

Write-Output ""
Write-Output "--- Speech service registry keys ---"
$keys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'Speech|Sapi' }
if ($keys) { $keys | ForEach-Object { Write-Output $_.PSChildName } } else { Write-Output "(none)" }

Write-Output ""
Write-Output "--- Speech language packs ---"
Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Speech|Voice' } | ForEach-Object { Write-Output ("{0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status) }

Write-Output ""
Write-Output "=== SPEECH REPAIR DONE $(Get-Date -Format s) ==="

Stop-Transcript | Out-Null
