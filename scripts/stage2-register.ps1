$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\stage2-result.txt'
$lines = @()

$lines += "=== STAGE 2: REGISTER SPEECH RUNTIME + ENABLE ONLINE SPEECH $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== 1. Current state before changes ==="
$before = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG|SpeechRuntime' })
$lines += "  speech runtime packages for current user: $($before.Count)"
$before | ForEach-Object { $lines += ("    {0} {1} {2}" -f $_.Name, $_.Version, $_.Status) }

$lines += ""
$lines += "=== 2. Enable online speech recognition consent (HKCU) ==="
$key = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\PrivacyPolicy'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name 'HasAccepted' -PropertyType DWord -Value 1 -Force | Out-Null
$lines += "  HasAccepted = $((Get-ItemProperty $key -ErrorAction SilentlyContinue).HasAccepted)"

$lines += ""
$lines += "=== 3. Re-register SpeechRuntime package for current user (RegisterByFamilyName) ==="
$families = @(
  'MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy',
  'MicrosoftWindows.LKG.AccountsService_cw5n1h2txyewy',
  'MicrosoftWindows.LKG.IrisService_cw5n1h2txyewy',
  'MicrosoftWindows.LKG.RulesEngine_cw5n1h2txyewy',
  'MicrosoftWindows.LKG.DesktopSpotlight_cw5n1h2txyewy',
  'MicrosoftWindows.LKG.TwinSxS_cw5n1h2txyewy'
)
foreach ($f in $families) {
  $lines += "  --- $f"
  try {
    Add-AppxPackage -RegisterByFamilyName -MainPackage $f -ErrorAction Stop
    $lines += "      REGISTER OK"
  } catch {
    $lines += ("      FAILED: {0}" -f $_.Exception.Message)
  }
}

$lines += ""
$lines += "=== 4. State after registration attempt ==="
$after = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG|SpeechRuntime' })
$lines += "  speech runtime packages for current user: $($after.Count)"
$after | ForEach-Object { $lines += ("    {0} {1} {2}" -f $_.Name, $_.Version, $_.Status) }

$lines += ""
$lines += "=== 5. Re-register speech language packs ==="
foreach ($p in Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Speech\.|Voice\.' }) {
  $manifest = Join-Path $p.InstallLocation 'AppXManifest.xml'
  $lines += ("  {0} -> manifest exists: {1}" -f $p.Name, (Test-Path $manifest))
  if (Test-Path $manifest) {
    try {
      Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
      $lines += "     register OK"
    } catch {
      $lines += ("     FAILED: {0}" -f $_.Exception.Message)
    }
  }
}

$lines += ""
$lines += "=== 6. Restart TextInputHost so it picks up changes ==="
Get-Process -Name TextInputHost -ErrorAction SilentlyContinue | ForEach-Object {
  $lines += ("  stopping TextInputHost pid {0}" -f $_.Id)
  Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3
$ti = Get-Process -Name TextInputHost -ErrorAction SilentlyContinue
if ($ti) { $lines += ("  TextInputHost restarted, pid {0}" -f $ti.Id) } else { $lines += "  TextInputHost not running (will start on next Win+H)" }

$lines += ""
$lines += "=== 7. Voice typing related packages for current user ==="
Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'InpApp|Voiess|Speion|Livtop|SpeechRuntime|Speech\.' } | ForEach-Object {
  $lines += ("  {0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status)
}

$lines += ""
$lines += "=== STAGE 2 DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
