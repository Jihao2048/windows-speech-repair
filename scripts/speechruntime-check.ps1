$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\speechruntime-pkg2.txt'
$lines = @()

$lines += "=== SPEECH RUNTIME PACKAGE STATE $(Get-Date -Format s) ==="
$lines += ""

$dir = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
$lines += "=== 1. Package folder: $dir ==="
$lines += "  exists: $(Test-Path $dir)"
if (Test-Path $dir) {
  Get-ChildItem $dir -ErrorAction SilentlyContinue | ForEach-Object { $lines += ("    {0,-45} {1,12}" -f $_.Name, $_.Length) }
}

$lines += ""
$lines += "=== 2. All-users state of speech/speechruntime packages ==="
try {
  Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -match 'SpeechRuntime' } | ForEach-Object {
    $lines += ("  {0}  {1}  Status={2}" -f $_.Name, $_.Version, $_.Status)
    $lines += ("     InstallLocation: {0}" -f $_.InstallLocation)
    $lines += ("     PackageFullName: {0}" -f $_.PackageFullName)
    $lines += ("     IsFramework={0}  NonRemovable={1}  SignatureKind={2}" -f $_.IsFramework, $_.NonRemovable, $_.SignatureKind)
    $lines += ("     PackageUserInformation entries: {0}" -f @($_.PackageUserInformation).Count)
    foreach ($u in $_.PackageUserInformation) { $lines += ("        {0} -> {1}" -f $u.UserSecurityId, $u.InstallState) }
  }
} catch { $lines += "  ERROR: $($_.Exception.Message)" }

$lines += ""
$lines += "=== 3. Current user state (all users not requested) ==="
Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'SpeechRuntime' } | ForEach-Object {
  $lines += ("  {0}  {1}  Status={2}  Location={3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation)
}
$curCount = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'SpeechRuntime' }).Count
$lines += "  current-user SpeechRuntime packages: $curCount"

$lines += ""
$lines += "=== 4. LKG folder listing ==="
Get-ChildItem 'C:\Windows\SystemApps\LKG' -ErrorAction SilentlyContinue | ForEach-Object { $lines += "  $($_.Name)" }

$lines += ""
$lines += "=== 5. SpeechRuntime.exe anywhere on disk ==="
foreach ($p in 'C:\Windows\System32\SpeechRuntime.exe','C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy\SpeechRuntime.exe') {
  $lines += ("  {0} -> {1}" -f $p, (Test-Path $p))
}
$found = @(Get-ChildItem 'C:\Windows\SystemApps' -Recurse -Filter 'SpeechRuntime.exe' -ErrorAction SilentlyContinue | Select-Object -First 5)
$lines += "  found copies under SystemApps: $($found.Count)"
$found | ForEach-Object { $lines += "    $($_.FullName)" }

$lines += ""
$lines += "=== 6. Windows Update service state (WUB effect) ==="
foreach ($n in 'wuauserv','BITS','UsoSvc','TrustedInstaller','msiserver') {
  $s = Get-Service -Name $n -ErrorAction SilentlyContinue
  if ($s) { $lines += ("  {0,-18} {1,-10} {2}" -f $s.Name, $s.Status, $s.StartType) } else { $lines += "  $n NOT FOUND" }
}
$wu = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv' -ErrorAction SilentlyContinue
$lines += "  wuauserv registry Start = $($wu.Start)  (4=Disabled, 3=Manual, 2=Automatic)"
foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate','HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU') {
  $lines += "-- $k exists: $(Test-Path $k)"
  $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
  if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $lines += ("     {0} = {1}" -f $_.Name, $_.Value) } }
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
