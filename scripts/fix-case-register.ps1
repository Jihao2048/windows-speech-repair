$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\fix-case-register.txt'
$lines = @()

$lines += "=== FIX MANIFEST CASE + REGISTER $(Get-Date -Format s) ==="
$lines += ""

$dst = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'

$lines += "=== 1. Actual on-disk casing (cmd dir shows true case) ==="
foreach ($p in $dst, 'C:\Windows\SystemApps\MicrosoftWindows.Client.Core_cw5n1h2txyewy', 'C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy') {
  $lines += "  --- $p"
  $raw = cmd /c "dir /b `"$p`" 2>nul"
  $raw | Where-Object { $_ -match 'manifest' } | ForEach-Object { $lines += "     manifest entry: [$_]" }
}

$lines += ""
$lines += "=== 2. Two-step rename to force correct on-disk case ==="
$lower = Join-Path $dst 'appxmanifest.xml'
$tmp = Join-Path $dst '_manifest_tmp.xml'
$upper = Join-Path $dst 'AppxManifest.xml'
if (Test-Path $lower) {
  Rename-Item -Path $lower -NewName '_manifest_tmp.xml' -Force -ErrorAction Continue
  $lines += "  renamed to _manifest_tmp.xml: $(Test-Path $tmp)"
  Rename-Item -Path $tmp -NewName 'AppxManifest.xml' -Force -ErrorAction Continue
  $lines += "  renamed to AppxManifest.xml: $(Test-Path $upper)"
} else {
  $lines += "  lowercase manifest not found"
}
$lines += "  --- on-disk casing now:"
(cmd /c "dir /b `"$dst`" 2>nul") | Where-Object { $_ -match 'manifest' } | ForEach-Object { $lines += "     [$_]" }

$lines += ""
$lines += "=== 3. Register ==="
try {
  Add-AppxPackage -Register $upper -DisableDevelopmentMode -ErrorAction Stop
  $lines += "  REGISTER SUCCEEDED"
} catch {
  $lines += ("  REGISTER FAILED: {0}" -f $_.Exception.Message)
}

$lines += ""
$lines += "=== 4. State ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
$lines += "  LKG packages for current user: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0}  {1}  {2}  {3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation) }

$lines += ""
$lines += "=== 5. Restart TextInputHost ==="
Get-Process -Name TextInputHost -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
$ti = Get-Process -Name TextInputHost -ErrorAction SilentlyContinue
if ($ti) { $lines += "  TextInputHost pid $($ti.Id)" } else { $lines += "  TextInputHost not running" }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
