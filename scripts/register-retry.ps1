$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\register-retry.txt'
$lines = @()

$lines += "=== REGISTER RETRY $(Get-Date -Format s) ==="
$lines += ""

$dst = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'

$lines += "=== 1. Current folder content ==="
Get-ChildItem $dst -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $kind = 'FILE'; if ($_.PSIsContainer) { $kind = 'DIR' }
  $len = $_.Length; if ($null -eq $len) { $len = 0 }
  $lines += ("  {0,-65} {1,12:N0}  {2}" -f $_.Name, $len, $kind)
}

$lines += ""
$lines += "=== 2. Create AppxManifest.xml (correct casing) in package root ==="
$lower = Join-Path $dst 'appxmanifest.xml'
$upper = Join-Path $dst 'AppxManifest.xml'
$lines += "  lowercase exists: $(Test-Path $lower)"
$lines += "  AppxManifest.xml exists: $(Test-Path $upper)"
if ((Test-Path $lower) -and (-not (Test-Path $upper))) {
  Copy-Item $lower $upper -Force
  $lines += "  copied lowercase -> AppxManifest.xml"
}
$lines += "  AppxManifest.xml now exists: $(Test-Path $upper)"

$lines += ""
$lines += "=== 3. Attempt registration (path to AppxManifest.xml) ==="
try {
  Add-AppxPackage -Register $upper -DisableDevelopmentMode -ErrorAction Stop
  $lines += "  REGISTER SUCCEEDED"
} catch {
  $lines += ("  REGISTER FAILED: {0}" -f $_.Exception.Message)
}

$lines += ""
$lines += "=== 4. If that failed, try folder-based registration ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG.SpeechRuntime' })
if ($cur.Count -eq 0) {
  try {
    Add-AppxPackage -Register $dst -DisableDevelopmentMode -ErrorAction Stop
    $lines += "  FOLDER REGISTER SUCCEEDED"
  } catch {
    $lines += ("  FOLDER REGISTER FAILED: {0}" -f $_.Exception.Message)
  }
} else {
  $lines += "  already registered, skipping"
}

$lines += ""
$lines += "=== 5. Also try RegisterByFamilyName again (payload now present) ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG.SpeechRuntime' })
if ($cur.Count -eq 0) {
  try {
    Add-AppxPackage -RegisterByFamilyName -MainPackage 'MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy' -ErrorAction Stop
    $lines += "  RegisterByFamilyName SUCCEEDED"
  } catch {
    $lines += ("  RegisterByFamilyName FAILED: {0}" -f $_.Exception.Message)
  }
} else {
  $lines += "  already registered, skipping"
}

$lines += ""
$lines += "=== 6. Final registration state ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
$lines += "  LKG packages for current user: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0}  {1}  {2}  {3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation) }

$lines += ""
$lines += "=== 7. Restart TextInputHost ==="
Get-Process -Name TextInputHost -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
$ti = Get-Process -Name TextInputHost -ErrorAction SilentlyContinue
if ($ti) { $lines += "  TextInputHost pid $($ti.Id)" } else { $lines += "  TextInputHost not running" }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
