$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\version-experiment.txt'
$lines = @()

$lines += "=== VERSION CONFLICT EXPERIMENT $(Get-Date -Format s) ==="
$lines += ""

$dst = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
$mf = Join-Path $dst 'AppxManifest.xml'
$orig = Get-Content $mf -Raw

$lines += "=== 0. Baseline error with version 1000.26100.3470.0 ==="
$lines += ("  manifest identity: {0}" -f ([regex]::Match($orig, '<Identity[^>]*>')).Value)

function Try-Register([string]$label, [string]$manifestPath) {
  $lines = @()
  try {
    Add-AppxPackage -Register $manifestPath -ErrorAction Stop
    $lines += "  $label : SUCCEEDED"
  } catch {
    $m = $_.Exception.Message
    if ($m.Length -gt 400) { $m = $m.Substring(0,400) }
    $lines += "  $label : FAILED -> $m"
  }
  return $lines
}

$lines += ""
$lines += "=== 1. Variant A: version 1000.26100.3775.0 (same as registered) ==="
$va = $orig -replace 'Version="1000\.26100\.3470\.0"', 'Version="1000.26100.3775.0"'
Set-Content -Path $mf -Value $va -Encoding UTF8 -NoNewline
$lines += Try-Register 'VariantA' $mf

$lines += ""
$lines += "=== 2. Variant B: version 1000.26100.9999.0 (higher = upgrade) ==="
$vb = $orig -replace 'Version="1000\.26100\.3470\.0"', 'Version="1000.26100.9999.0"'
Set-Content -Path $mf -Value $vb -Encoding UTF8 -NoNewline
$lines += Try-Register 'VariantB' $mf

$lines += ""
$lines += "=== 3. Variant C: bump to 1000.26100.9999.0 and drop signature/blockmap ==="
foreach ($f in 'appxsignature.p7x','appxblockmap.xml') {
  $p = Join-Path $dst $f
  if (Test-Path $p) {
    $bak = $p + '.bak'
    if (-not (Test-Path $bak)) { Move-Item $p $bak -Force -ErrorAction SilentlyContinue }
    $lines += "  moved $f aside"
  }
}
$lines += Try-Register 'VariantC' $mf

$lines += ""
$lines += "=== 4. Restore manifest to original version 3470 ==="
Set-Content -Path $mf -Value $orig -Encoding UTF8 -NoNewline
$lines += "  restored"
$lines += ("  identity now: {0}" -f ([regex]::Match((Get-Content $mf -Raw), '<Identity[^>]*>')).Value)

$lines += ""
$lines += "=== 5. Current registration state ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
$lines += "  LKG for current user: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0}  {1}  {2}  {3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation) }

$lines += ""
$lines += "=== 6. All-users state for SpeechRuntime ==="
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'MicrosoftWindows.LKG.SpeechRuntime' } | ForEach-Object {
  $lines += ("  {0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status)
  foreach ($u in $_.PackageUserInformation) { $lines += ("     state={0}" -f $u.InstallState) }
}

$lines += ""
$lines += "=== 7. Check if a newer Windows update is available (would re-project LKG payloads) ==="
try {
  $session = New-Object -ComObject Microsoft.Update.Session
  $searcher = $session.CreateUpdateSearcher()
  $result = $searcher.Search("IsInstalled=0 and Type='Software'")
  $lines += ("  available updates: {0}" -f $result.Updates.Count)
  $result.Updates | Select-Object -First 15 | ForEach-Object {
    $t = $_.Title; if ($t.Length -gt 150) { $t = $t.Substring(0,150) }
    $lines += ("     {0}" -f $t)
  }
} catch {
  $lines += ("  WU search failed: {0}" -f $_.Exception.Message)
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
$lines
