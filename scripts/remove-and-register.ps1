$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\remove-and-register.txt'
$lines = @()

$lines += "=== REMOVE MACHINE-WIDE REGISTRATION THEN RE-REGISTER $(Get-Date -Format s) ==="
$lines += ""

$pfn = 'MicrosoftWindows.LKG.SpeechRuntime_1000.26100.3775.0_x64__cw5n1h2txyewy'
$family = 'MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
$dst = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
$backup = 'C:\hidisp\recovered\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'

$lines += "=== 1. Back up current package folder (in case removal deletes it) ==="
$b2 = 'C:\hidisp\pkg-backup'
if (Test-Path $b2) { Remove-Item $b2 -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $b2 -Force | Out-Null
Copy-Item (Join-Path $dst '*') $b2 -Recurse -Force -ErrorAction Continue
$lines += ("  backed up {0} files to {1}" -f @(Get-ChildItem $b2 -Recurse -File -Force -ErrorAction SilentlyContinue).Count, $b2)

$lines += ""
$lines += "=== 2. Attempt Remove-AppxPackage -AllUsers ==="
try {
  Remove-AppxPackage -Package $pfn -AllUsers -ErrorAction Stop
  $lines += "  REMOVE -AllUsers SUCCEEDED"
} catch {
  $lines += ("  REMOVE -AllUsers FAILED: {0}" -f $_.Exception.Message)
  $lines += "  --- trying per-user removal for current user only ---"
  try {
    Remove-AppxPackage -Package $pfn -ErrorAction Stop
    $lines += "  REMOVE (current user) SUCCEEDED"
  } catch {
    $lines += ("  REMOVE (current user) FAILED: {0}" -f $_.Exception.Message)
  }
}

$lines += ""
$lines += "=== 3. State after removal attempt ==="
$all = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'MicrosoftWindows.LKG.SpeechRuntime' })
$lines += "  all-users entries: $($all.Count)"
$all | ForEach-Object {
  $lines += ("     {0} {1} {2}" -f $_.Name, $_.Version, $_.Status)
  foreach ($u in $_.PackageUserInformation) { $lines += ("        {0}" -f $u.InstallState) }
}
$lines += ("  folder file count: {0}" -f @(Get-ChildItem $dst -Recurse -File -Force -ErrorAction SilentlyContinue).Count)

$lines += ""
$lines += "=== 4. Re-copy payload if removal wiped it ==="
if (@(Get-ChildItem $dst -Recurse -File -Force -ErrorAction SilentlyContinue).Count -lt 5) {
  Copy-Item (Join-Path $b2 '*') $dst -Recurse -Force -ErrorAction Continue
  $lines += ("  restored payload, files now: {0}" -f @(Get-ChildItem $dst -Recurse -File -Force -ErrorAction SilentlyContinue).Count)
} else {
  $lines += "  payload intact"
}

$lines += ""
$lines += "=== 5. Try loose registration now ==="
$mf = Join-Path $dst 'AppxManifest.xml'
if (-not (Test-Path $mf)) { $mf = Join-Path $dst 'appxmanifest.xml' }
try {
  Add-AppxPackage -Register $mf -ErrorAction Stop
  $lines += "  REGISTER SUCCEEDED"
} catch {
  $lines += ("  REGISTER FAILED: {0}" -f $_.Exception.Message)
}

$lines += ""
$lines += "=== 6. Fallback: RegisterByFamilyName ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'MicrosoftWindows.LKG.SpeechRuntime' })
if ($cur.Count -eq 0) {
  try {
    Add-AppxPackage -RegisterByFamilyName -MainPackage $family -ErrorAction Stop
    $lines += "  RegisterByFamilyName SUCCEEDED"
  } catch {
    $lines += ("  RegisterByFamilyName FAILED: {0}" -f $_.Exception.Message)
  }
} else { $lines += "  already registered for current user" }

$lines += ""
$lines += "=== 7. Final state ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
$lines += "  LKG packages for current user: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0}  {1}  {2}  {3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation) }

$lines += ""
$lines += "=== 8. Restart TextInputHost ==="
Get-Process -Name TextInputHost -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
$ti = Get-Process -Name TextInputHost -ErrorAction SilentlyContinue
if ($ti) { $lines += "  TextInputHost pid $($ti.Id)" } else { $lines += "  not running" }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
