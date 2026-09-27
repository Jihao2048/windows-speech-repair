$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\path-discriminator.txt'
$lines = @()

$lines += "=== PATH DISCRIMINATOR TEST $(Get-Date -Format s) ==="
$lines += ""

$src = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
$testRoot = 'C:\hidisp\testpkg'
$testDst = Join-Path $testRoot 'MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'

$lines += "=== 1. Folder attributes (reparse point?) ==="
foreach ($p in 'C:\Windows\SystemApps\LKG', $src) {
  $i = Get-Item $p -Force -ErrorAction SilentlyContinue
  $lines += ("  {0}" -f $p)
  $lines += ("     attributes: {0}" -f $i.Attributes)
  $lines += ("     is reparse point: {0}" -f (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0))
  $lines += ("     link target: {0}" -f $i.Target)
}

$lines += ""
$lines += "=== 2. Owner comparison (ours vs healthy package) ==="
foreach ($f in (Join-Path $src 'Microsoft.CognitiveServices.Speech.core.dll'), 'C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy' ) {
  $lines += "  --- $f"
  $raw = cmd /c "dir /q `"$f`" 2>nul"
  $raw | Select-Object -First 12 | ForEach-Object { $lines += "     $_" }
}
$raw2 = cmd /c "dir /q `"$(Join-Path $src 'Microsoft.CognitiveServices.Speech.core.dll')`" 2>nul"
$lines += "  our dll owner line:"
$raw2 | ForEach-Object { $lines += "     $_" }
$raw3 = cmd /c "dir /q `"C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\MicrosoftWindows.Client.CBS.dll`" 2>nul"
$lines += "  healthy dll owner line:"
$raw3 | ForEach-Object { $lines += "     $_" }

$lines += ""
$lines += "=== 3. Copy package to a neutral location and try registering there ==="
if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
Copy-Item $src $testDst -Recurse -Force -ErrorAction Continue
$n = @(Get-ChildItem $testDst -Recurse -File -Force -ErrorAction SilentlyContinue).Count
$lines += "  copied $n files to $testDst"

$mf = Join-Path $testDst 'AppxManifest.xml'
$lines += "  manifest path: $mf exists: $(Test-Path $mf)"
if (Test-Path $mf) {
  try {
    Add-AppxPackage -Register $mf -DisableDevelopmentMode -ErrorAction Stop
    $lines += "  NEUTRAL-PATH REGISTER SUCCEEDED  --> the LKG location is the problem"
  } catch {
    $lines += ("  NEUTRAL-PATH REGISTER FAILED: {0}" -f $_.Exception.Message)
    $lines += "  --> the package content itself is the problem"
  }
}

$lines += ""
$lines += "=== 4. Try registering from LKG folder once more (sanity) ==="
$mf2 = Join-Path $src 'AppxManifest.xml'
try {
  Add-AppxPackage -Register $mf2 -DisableDevelopmentMode -ErrorAction Stop
  $lines += "  LKG REGISTER SUCCEEDED"
} catch {
  $lines += ("  LKG REGISTER FAILED: {0}" -f $_.Exception.Message)
}

$lines += ""
$lines += "=== 5. State after ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
$lines += "  LKG for current user: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0} {1} {2} {3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation) }

$lines += ""
$lines += "=== 6. Also compare the appxmanifest header bytes (BOM? encoding?) ==="
foreach ($f in (Join-Path $src 'AppxManifest.xml'), 'C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\appxmanifest.xml') {
  if (Test-Path $f) {
    $b = [System.IO.File]::ReadAllBytes($f)
    $head = ($b[0..15] | ForEach-Object { $_.ToString('X2') }) -join ' '
    $lines += ("  {0}" -f $f)
    $lines += ("     size={0}  first16bytes={1}" -f $b.Length, $head)
  }
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
