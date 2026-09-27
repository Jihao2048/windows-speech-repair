$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\post-reboot.txt'
$lines = @()

$lines += "=== POST-REBOOT CHECK $(Get-Date -Format s) ==="
$lines += ("  boot time: {0}" -f (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
$lines += ("  whoami: {0}" -f (whoami))
$lines += ("  user SID: {0}" -f ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$lines += ""

$lines += "=== 1. LKG packages registered for CURRENT user ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
$lines += "  count: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0}  {1}  {2}  {3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation) }

$lines += ""
$lines += "=== 2. SpeechRuntime specifically ==="
$sr = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'MicrosoftWindows.LKG.SpeechRuntime' })
$lines += "  current user: $($sr.Count)"
$sr | ForEach-Object { $lines += ("     {0} {1} {2}" -f $_.Name, $_.Version, $_.Status) }
$all = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'MicrosoftWindows.LKG.SpeechRuntime' })
foreach ($p in $all) {
  $lines += ("  all-users: {0} {1} {2}" -f $p.Name, $p.Version, $p.Status)
  foreach ($u in $p.PackageUserInformation) { $lines += ("     {0}" -f $u.InstallState) }
}

$lines += ""
$lines += "=== 3. LKG folder file counts (payload intact?) ==="
foreach ($d in Get-ChildItem 'C:\Windows\SystemApps\LKG' -Directory -ErrorAction SilentlyContinue) {
  $n = @(Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  $mf = (cmd /c "dir /b `"$($d.FullName)`" 2>nul") | Where-Object { $_ -match 'manifest' }
  $lines += ("  {0,-58} files={1,-4} manifest=[{2}]" -f $d.Name, $n, ($mf -join ','))
}

$lines += ""
$lines += "=== 4. Try registering SpeechRuntime again (post-reboot) ==="
$target = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy\appxmanifest.xml'
if (Test-Path $target) {
  try { Add-AppxPackage -Register $target -ErrorAction Stop; $lines += "  loose REGISTER: SUCCEEDED" }
  catch { $lines += ("  loose REGISTER FAILED -> {0}" -f (($_.Exception.Message -split "`r?`n")[0])) }
} else { $lines += "  manifest missing" }

$lines += ""
$lines += "=== 5. Windows Update client state (was 0x80072EE6) ==="
$s = Get-Service wuauserv -ErrorAction SilentlyContinue
$lines += ("  wuauserv: {0} / {1}" -f $s.Status, $s.StartType)
foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate','HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU') {
  $lines += ("  policy {0} exists: {1}" -f $k, (Test-Path $k))
}
try {
  $session = New-Object -ComObject Microsoft.Update.Session
  $searcher = $session.CreateUpdateSearcher()
  $result = $searcher.Search("IsInstalled=0")
  $lines += ("  WU search OK - available updates: {0}" -f $result.Updates.Count)
  $result.Updates | Select-Object -First 12 | ForEach-Object {
    $t = $_.Title; if ($t.Length -gt 140) { $t = $t.Substring(0,140) }
    $lines += ("     {0}" -f $t)
  }
} catch {
  $lines += ("  WU search FAILED: {0}" -f $_.Exception.Message)
}

$lines += ""
$lines += "=== 6. Speech-related processes ==="
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Speech|TextInput|InputApp|Voiess' } | ForEach-Object {
  $lines += ("  {0} (pid {1})" -f $_.ProcessName, $_.Id)
}

$lines += ""
$lines += "=== 7. Component store state (quick) ==="
$r = DISM /Online /Cleanup-Image /CheckHealth 2>&1
$r | Where-Object { $_ -match '\S' } | Select-Object -Last 4 | ForEach-Object { $lines += "     $_" }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
