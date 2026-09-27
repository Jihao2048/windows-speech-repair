$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\apply-speechruntime.txt'
$lines = @()

$lines += "=== APPLY: RESTORE LKG.SpeechRuntime PACKAGE $(Get-Date -Format s) ==="
$lines += ""

$src = 'C:\hidisp\recovered\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
$dst = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'

$lines += "=== 1. Also check if the machine store has Cognitive Services speech payloads ==="
foreach ($n in 'Microsoft.CognitiveServices.Speech.core.dll','FPIEProcessor.dll','Microsoft.CognitiveServices.Speech.extension.onnxruntime.dll') {
  $hits = @(Get-ChildItem 'C:\Windows\WinSxS' -Recurse -Filter $n -ErrorAction SilentlyContinue | Select-Object -First 3)
  $lines += "  $n -> $($hits.Count)"
  $hits | ForEach-Object { $lines += ("     {0}" -f $_.FullName) }
}

$lines += ""
$lines += "=== 2. Copy package payload into $dst ==="
$lines += "  source exists: $(Test-Path $src)"
$lines += "  target exists: $(Test-Path $dst)"
if (Test-Path $src) {
  if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
  Copy-Item (Join-Path $src '*') $dst -Recurse -Force -ErrorAction Continue
  $n = @(Get-ChildItem $dst -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  $lines += "  files now in target: $n"
  Get-ChildItem $dst -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $len = $_.Length; if ($null -eq $len) { $len = 0 }
    $lines += ("     {0,-60} {1,12:N0}" -f $_.Name, $len)
  }
}

$lines += ""
$lines += "=== 3. Fix permissions on the package folder to match sibling system apps ==="
try {
  $ref = 'C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy'
  $acl = Get-Acl $ref
  $lines += "  reference ACL owner: $($acl.Owner)"
  icacls $dst /reset /T /C /Q 2>&1 | ForEach-Object { $lines += "     $_" }
  $lines += "  icacls reset done"
} catch { $lines += "  ACL step failed: $($_.Exception.Message)" }

$lines += ""
$lines += "=== 4. Register the package for the current user ==="
$manifest = Join-Path $dst 'appxmanifest.xml'
$lines += "  manifest exists: $(Test-Path $manifest)"
if (Test-Path $manifest) {
  try {
    Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
    $lines += "  REGISTER SUCCEEDED"
  } catch {
    $lines += ("  REGISTER FAILED: {0}" -f $_.Exception.Message)
  }
}

$lines += ""
$lines += "=== 5. Registration state after attempt ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'SpeechRuntime|LKG' })
$lines += "  packages for current user: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0}  {1}  {2}  {3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation) }

$all = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG.SpeechRuntime' })
$lines += ""
$lines += "  all-users state:"
$all | ForEach-Object {
  $lines += ("     {0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status)
  foreach ($u in $_.PackageUserInformation) { $lines += ("        {0}" -f $u.InstallState) }
}

$lines += ""
$lines += "=== 6. Restart TextInputHost ==="
Get-Process -Name TextInputHost -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
$ti = Get-Process -Name TextInputHost -ErrorAction SilentlyContinue
if ($ti) { $lines += "  TextInputHost pid $($ti.Id)" } else { $lines += "  TextInputHost not running (starts on next Win+H)" }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
