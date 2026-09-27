$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\compare-plan.txt'
$lines = @()

$wim = 'D:\sources\install.wim'
$mnt = 'C:\hidisp\wim-mount'
$stage = 'C:\hidisp\stage'

$lines += "=== COMPARE + STAGE $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== A. Manifest identity comparison (recovered vs machine DB) ==="
$recManifest = 'C:\hidisp\recovered\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy\appxmanifest.xml'
$dbManifest = 'C:\hidisp\LKG.SpeechRuntime.manifest.xml'
$lines += "  recovered exists: $(Test-Path $recManifest)"
$lines += "  db copy exists: $(Test-Path $dbManifest)"
if ((Test-Path $recManifest) -and (Test-Path $dbManifest)) {
  $a = Get-Content $recManifest -Raw
  $b = Get-Content $dbManifest -Raw
  $lines += ("  recovered length: {0}   db length: {1}" -f $a.Length, $b.Length)
  $lines += ("  IDENTICAL: {0}" -f ($a -eq $b))
  $ia = ([regex]::Match($a, '<Identity[^>]*>')).Value
  $ib = ([regex]::Match($b, '<Identity[^>]*>')).Value
  $lines += "  recovered Identity: $ia"
  $lines += "  db        Identity: $ib"
}
$lines += ""
$lines += "  --- recoverd package file list with versions ---"
Get-ChildItem 'C:\hidisp\recovered\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy' -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
  $v = ''
  if ($_.Extension -match '\.(dll|exe)$') { $v = $_.VersionInfo.FileVersion }
  $lines += ("    {0,-70} {1,12:N0}  {2}" -f $_.FullName.Replace('C:\hidisp\recovered\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy',''), $_.Length, $v)
}

$lines += ""
$lines += "=== B. Machine: System32\Speech_OneCore tree ==="
$machineSOC = 'C:\Windows\System32\Speech_OneCore'
Get-ChildItem $machineSOC -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $lines += ("    {0,-70} {1,12:N0}" -f $_.FullName.Replace($machineSOC,''), $_.Length)
}
$mc = @(Get-ChildItem $machineSOC -Recurse -File -Force -ErrorAction SilentlyContinue).Count
$lines += "  machine file count under Speech_OneCore: $mc"

$lines += ""
$lines += "=== C. Mount image and compare Speech_OneCore + Speech ==="
if (Test-Path $mnt) { Remove-Item $mnt -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $mnt -Force | Out-Null
$mounted = $false
try {
  Mount-WindowsImage -ImagePath $wim -Index 2 -Path $mnt -ReadOnly -ErrorAction Stop | Out-Null
  $mounted = $true
  $lines += "  mounted OK"
} catch {
  $lines += "  MOUNT FAILED: $($_.Exception.Message)"
}

if ($mounted) {
  foreach ($rel in 'Windows\System32\Speech_OneCore','Windows\System32\Speech','Windows\System32\SpeechRuntime.exe') {
    $src = Join-Path $mnt $rel
    $lines += ""
    $lines += "  --- image: $rel (exists: $(Test-Path $src))"
    if (Test-Path $src -PathType Container) {
      Get-ChildItem $src -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $lines += ("      {0,-70} {1,12:N0}" -f $_.FullName.Replace($src,''), $_.Length)
      }
    }
  }

  $lines += ""
  $lines += "=== D. Stage missing Speech_OneCore files ==="
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  $imgSOC = Join-Path $mnt 'Windows\System32\Speech_OneCore'
  if (Test-Path $imgSOC) {
    $miss = 0
    foreach ($f in Get-ChildItem $imgSOC -Recurse -File -Force -ErrorAction SilentlyContinue) {
      $rel = $f.FullName.Substring($imgSOC.Length)
      $target = Join-Path $machineSOC $rel
      if (-not (Test-Path $target)) {
        $stagePath = Join-Path (Join-Path $stage 'Speech_OneCore') $rel
        New-Item -ItemType Directory -Path (Split-Path $stagePath) -Force | Out-Null
        Copy-Item $f.FullName $stagePath -Force -ErrorAction SilentlyContinue
        $lines += ("    MISSING -> staged: {0}  ({1:N0})" -f $rel, $f.Length)
        $miss++
      }
    }
    $lines += "  staged missing files: $miss"
  }

  $lines += ""
  $lines += "=== E. Dismount ==="
  try { Dismount-WindowsImage -Path $mnt -Discard -ErrorAction Stop | Out-Null; $lines += "  dismounted OK" }
  catch { $lines += "  DISMOUNT FAILED: $($_.Exception.Message)" }
}

$lines += ""
$lines += "=== F. Verify extracted LKG packages against image manifests (sanity) ==="
foreach ($d in Get-ChildItem 'C:\hidisp\recovered' -Directory -ErrorAction SilentlyContinue) {
  $mf = Join-Path $d.FullName 'appxmanifest.xml'
  $id = ''
  if (Test-Path $mf) { $id = ([regex]::Match((Get-Content $mf -Raw), '<Identity[^>]*>')).Value }
  $lines += ("  {0}" -f $d.Name)
  $lines += ("     {0}" -f $id)
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
