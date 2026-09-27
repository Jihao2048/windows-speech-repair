$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\final-register.txt'
$lines = @()

$lines += "=== FINAL REGISTRATION (no -DisableDevelopmentMode) $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== 1. Clean up the minimal test package ==="
$t = Get-AppxPackage -Name 'Minimal.TestApp' -ErrorAction SilentlyContinue
if ($t) {
  try { Remove-AppxPackage -Package $t.PackageFullName -ErrorAction Stop; $lines += "  removed Minimal.TestApp" }
  catch { $lines += "  remove failed: $($_.Exception.Message)" }
} else { $lines += "  nothing to clean" }
if (Test-Path 'C:\hidisp\minimal') { Remove-Item 'C:\hidisp\minimal' -Recurse -Force -ErrorAction SilentlyContinue }

$lines += ""
$lines += "=== 2. Register MicrosoftWindows.LKG.SpeechRuntime (WITHOUT -DisableDevelopmentMode) ==="
$dst = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
$mf = Join-Path $dst 'AppxManifest.xml'
$lines += "  manifest: $mf exists: $(Test-Path $mf)"
try {
  Add-AppxPackage -Register $mf -ErrorAction Stop
  $lines += "  REGISTER SUCCEEDED"
} catch {
  $lines += ("  REGISTER FAILED: {0}" -f $_.Exception.Message)
}

$lines += ""
$lines += "=== 3. Registration state ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
$lines += "  LKG packages for current user: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0}  {1}  {2}  {3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation) }

$lines += ""
$lines += "=== 4. Restore the other 5 LKG packages as well ==="
$rec = 'C:\hidisp\recovered'
foreach ($d in Get-ChildItem $rec -Directory -ErrorAction SilentlyContinue) {
  $target = Join-Path 'C:\Windows\SystemApps\LKG' $d.Name
  if ($d.Name -match 'SpeechRuntime') { continue }
  if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
  Copy-Item (Join-Path $d.FullName '*') $target -Recurse -Force -ErrorAction Continue
  $n = @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  $lines += ("  {0} -> files={1}" -f $d.Name, $n)
  $m = Join-Path $target 'appxmanifest.xml'
  if (-not (Test-Path $m)) { $m = Join-Path $target 'AppxManifest.xml' }
  if (Test-Path $m) {
    try {
      Add-AppxPackage -Register $m -ErrorAction Stop
      $lines += "     registered OK"
    } catch {
      $lines += ("     register FAILED: {0}" -f $_.Exception.Message)
    }
  } else { $lines += "     manifest missing" }
}

$lines += ""
$lines += "=== 5. Final state ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
$lines += "  LKG packages for current user: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status) }

$lines += ""
$lines += "=== 6. Restart TextInputHost so voice typing picks up the engine ==="
Get-Process -Name TextInputHost -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
$ti = Get-Process -Name TextInputHost -ErrorAction SilentlyContinue
if ($ti) { $lines += "  TextInputHost restarted pid $($ti.Id)" } else { $lines += "  TextInputHost not running" }

$lines += ""
$lines += "=== 7. Verify the engine files are present ==="
foreach ($f in 'SpeechRuntime.exe','Microsoft.CognitiveServices.Speech.extension.embedded.sr.runtime.dll','resources.pri','Assets\StoreLogo.png') {
  $p = Join-Path $dst $f
  $lines += ("  {0} -> {1}" -f $f, (Test-Path $p))
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
