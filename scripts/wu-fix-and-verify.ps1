$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\wu-fix-and-verify.txt'
$lines = @()

$lines += "=== WU LEFTOVER CLEANUP + VOICE VERIFY $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== 1. Backup the GP cache key ==="
$bak = 'C:\hidisp\wu-gpcache-backup.reg'
Remove-Item $bak -ErrorAction SilentlyContinue
$r = reg export 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache' $bak /y 2>&1
$lines += ("  export -> {0}" -f ($r -join ' '))
$lines += ("  backup exists: {0}" -f (Test-Path $bak))

$lines += ""
$lines += "=== 2. Current cached policy values ==="
$r = reg query 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache' /s 2>&1
$r | Where-Object { $_ -match '\S' } | ForEach-Object { $lines += "     $_" }

$lines += ""
$lines += "=== 3. Remove the stale cached policy set ==="
$r = reg delete 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache' /f 2>&1
$lines += ("  delete -> {0}" -f ($r -join ' '))
$lines += ("  still exists: {0}" -f (Test-Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache'))

$lines += ""
$lines += "=== 4. Restart Windows Update services ==="
foreach ($n in 'wuauserv','BITS','UsoSvc','DoSvc','cryptsvc') {
  try {
    Restart-Service -Name $n -Force -ErrorAction Stop
    $lines += "  restarted $n"
  } catch {
    $lines += ("  restart {0} failed: {1}" -f $n, (($_.Exception.Message -split "`r?`n")[0]))
  }
}
Start-Sleep -Seconds 5

$lines += ""
$lines += "=== 5. Retry the Windows Update search ==="
try {
  $session = New-Object -ComObject Microsoft.Update.Session
  $searcher = $session.CreateUpdateSearcher()
  $result = $searcher.Search("IsInstalled=0")
  $lines += ("  WU SEARCH OK - available updates: {0}" -f $result.Updates.Count)
  $result.Updates | Select-Object -First 15 | ForEach-Object {
    $t = $_.Title; if ($t.Length -gt 140) { $t = $t.Substring(0,140) }
    $lines += ("     {0}" -f $t)
  }
} catch {
  $lines += ("  WU SEARCH FAILED: {0}" -f $_.Exception.Message)
}

$lines += ""
$lines += "=== 6. VOICE INPUT CURRENT STATE ==="
$lines += "--- LKG packages for current user ---"
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
$lines += "  count: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0}  {1}  {2}  {3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation) }

$lines += "--- all-users SpeechRuntime ---"
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG.SpeechRuntime' } | ForEach-Object {
  $lines += ("     {0} {1} {2}" -f $_.Name, $_.Version, $_.Status)
  foreach ($u in $_.PackageUserInformation) { $lines += ("        {0}" -f $u.InstallState) }
}

$lines += "--- engine files present? ---"
$sr = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
$lines += ("  folder files: {0}" -f @(Get-ChildItem $sr -Recurse -File -Force -ErrorAction SilentlyContinue).Count)
foreach ($f in 'Microsoft.CognitiveServices.Speech.extension.embedded.sr.runtime.dll','Microsoft.CognitiveServices.Speech.extension.onnxruntime.dll','resources.pri','appxmanifest.xml','appxsignature.p7x') {
  $lines += ("  {0} -> {1}" -f $f, (Test-Path (Join-Path $sr $f)))
}

$lines += "--- voice typing related packages (current user) ---"
Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'InpApp|Voiess|Speion|Livtop|Speech\.|Voice\.' } | ForEach-Object {
  $lines += ("     {0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status)
}

$lines += "--- online speech recognition consent ---"
$hasAcc = (Get-ItemProperty 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\PrivacyPolicy' -ErrorAction SilentlyContinue).HasAccepted
$lines += "  HasAccepted = $hasAcc"

$lines += "--- running processes ---"
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'SpeechRuntime|TextInputHost|Speech' } | ForEach-Object {
  $lines += ("     {0} (pid {1})" -f $_.ProcessName, $_.Id)
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
