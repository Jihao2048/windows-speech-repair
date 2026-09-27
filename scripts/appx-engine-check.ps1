$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\appx-engine-check.txt'
$lines = @()

$lines += "=== APPX DEPLOYMENT ENGINE HEALTH CHECK $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== 1. Critical Appx / deployment services ==="
foreach ($n in 'AppXSvc','ClipSVC','StateRepository','AppReadiness','TokenBroker','InstallService','LicenseManager','EntAppSvc','wlidsvc','AppMgmt','BITS','TrustedInstaller','msiserver','storsvc','InstallService') {
  $s = Get-Service -Name $n -ErrorAction SilentlyContinue
  if ($s) {
    $lines += ("  {0,-20} {1,-10} {2}" -f $s.Name, $s.Status, $s.StartType)
  } else {
    $lines += ("  {0,-20} NOT FOUND" -f $n)
  }
}

$lines += ""
$lines += "=== 2. Registry Start values for those services ==="
foreach ($n in 'AppXSvc','ClipSVC','StateRepository','AppReadiness','TokenBroker','InstallService','LicenseManager','EntAppSvc') {
  $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$n"
  $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
  if ($p) { $lines += ("  {0,-20} Start={1}  Type={2}  ImagePath={3}" -f $n, $p.Start, $p.Type, $p.ImagePath) }
  else { $lines += ("  {0,-20} key missing" -f $n) }
}

$lines += ""
$lines += "=== 3. Appx-related policies (could block deployment) ==="
foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx','HKCU:\SOFTWARE\Policies\Microsoft\Windows\Appx','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Appx','HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller') {
  $lines += "  -- $k exists: $(Test-Path $k)"
  $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
  if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $lines += ("     {0} = {1}" -f $_.Name, $_.Value) } }
}

$lines += ""
$lines += "=== 4. Developer mode / sideloading state ==="
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock') {
  $lines += "  -- $k exists: $(Test-Path $k)"
  $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
  if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $lines += ("     {0} = {1}" -f $_.Name, $_.Value) } }
}

$lines += ""
$lines += "=== 5. CONTROL TEST: try registering a KNOWN-GOOD system package ==="
$good = 'C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy'
$gm = Join-Path $good 'appxmanifest.xml'
$lines += "  target: $gm"
if (Test-Path $gm) {
  try {
    Add-AppxPackage -Register $gm -DisableDevelopmentMode -ErrorAction Stop
    $lines += "  CONTROL REGISTER SUCCEEDED (so the engine works)"
  } catch {
    $lines += ("  CONTROL REGISTER FAILED: {0}" -f $_.Exception.Message)
  }
} else { $lines += "  manifest not found" }

$lines += ""
$lines += "=== 6. Control test 2: a small normal system app ==="
$good2 = 'C:\Windows\SystemApps\Microsoft.AsyncTextService_8wekyb3d8bbwe'
$gm2 = Join-Path $good2 'AppxManifest.xml'
$lines += "  target: $gm2 exists: $(Test-Path $gm2)"
if (Test-Path $gm2) {
  try {
    Add-AppxPackage -Register $gm2 -DisableDevelopmentMode -ErrorAction Stop
    $lines += "  CONTROL2 REGISTER SUCCEEDED"
  } catch {
    $lines += ("  CONTROL2 REGISTER FAILED: {0}" -f $_.Exception.Message)
  }
}

$lines += ""
$lines += "=== 7. Anything in the StateRepository folder ==="
Get-ChildItem 'C:\ProgramData\Microsoft\Windows\AppRepository' -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'srd|StateRepository' } | ForEach-Object {
  $lines += ("  {0,-50} {1,15:N0}" -f $_.Name, $_.Length)
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
