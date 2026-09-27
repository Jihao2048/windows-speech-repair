$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\wim-extract.txt'
$lines = @()

$wim = 'D:\sources\install.wim'
$mnt = 'C:\hidisp\wim-mount'
$dest = 'C:\hidisp\recovered'

$lines += "=== WIM EXTRACTION $(Get-Date -Format s) ==="
$lines += "  wim exists: $(Test-Path $wim)"
$lines += ""

$lines += "=== 1. Image list ==="
try {
  Get-WindowsImage -ImagePath $wim -ErrorAction Stop | ForEach-Object {
    $lines += ("  [{0}] {1}" -f $_.ImageIndex, $_.ImageName)
  }
} catch { $lines += "  FAILED: $($_.Exception.Message)" }

$lines += ""
$lines += "=== 2. Mount image index 2 (Enterprise) read-only ==="
if (Test-Path $mnt) { Remove-Item $mnt -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $mnt -Force | Out-Null
$mounted = $false
try {
  Mount-WindowsImage -ImagePath $wim -Index 2 -Path $mnt -ReadOnly -ErrorAction Stop | Out-Null
  $mounted = $true
  $lines += "  mounted OK at $mnt"
} catch {
  $lines += "  MOUNT FAILED: $($_.Exception.Message)"
}

if ($mounted) {
  $lines += ""
  $lines += "=== 3. Image build info ==="
  $k = Join-Path $mnt 'Windows\System32\ntoskrnl.exe'
  if (Test-Path $k) {
    $lines += ("  ntoskrnl.exe version: {0}" -f (Get-Item $k).VersionInfo.FileVersion)
  }
  $cvPath = Join-Path $mnt 'Windows\System32\config\SOFTWARE'
  $lines += ("  SOFTWARE hive present: {0}" -f (Test-Path $cvPath))

  $lines += ""
  $lines += "=== 4. SystemApps\LKG content in the image ==="
  $lkg = Join-Path $mnt 'Windows\SystemApps\LKG'
  $lines += "  LKG dir exists: $(Test-Path $lkg)"
  if (Test-Path $lkg) {
    Get-ChildItem $lkg -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $n = @(Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count
      $lines += ("  {0,-60} files={1}" -f $_.Name, $n)
    }
  }

  $lines += ""
  $lines += "=== 5. Look for any SpeechRuntime package payload in the image ==="
  $hits = @(Get-ChildItem (Join-Path $mnt 'Windows') -Recurse -Filter 'SpeechRuntime.*' -ErrorAction SilentlyContinue | Select-Object -First 25)
  $lines += "  hits: $($hits.Count)"
  $hits | ForEach-Object { $lines += ("    {0}  ({1:N0} bytes)" -f $_.FullName.Replace($mnt,''), $_.Length) }

  $lines += ""
  $lines += "=== 6. Copy the LKG SpeechRuntime folder out of the image (if present) ==="
  $src = Get-ChildItem $lkg -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG.SpeechRuntime' } | Select-Object -First 1
  if ($src) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $target = Join-Path $dest $src.Name
    if (Test-Path $target) { Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue }
    Copy-Item $src.FullName $target -Recurse -Force -ErrorAction SilentlyContinue
    $lines += "  copied to: $target"
    Get-ChildItem $target -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
      $rel = $_.FullName.Substring($target.Length)
      $len = $_.Length; if ($null -eq $len) { $len = 0 }
      $lines += ("    {0,-50} {1,12:N0}" -f $rel, $len)
    }
  } else {
    $lines += "  LKG.SpeechRuntime NOT present in this image"
  }

  $lines += ""
  $lines += "=== 7. Also copy ALL LKG folders for reference ==="
  if (Test-Path $lkg) {
    foreach ($d in Get-ChildItem $lkg -Directory -ErrorAction SilentlyContinue) {
      $t = Join-Path $dest $d.Name
      if (-not (Test-Path $t) -or @(Get-ChildItem $t -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0) {
        Copy-Item $d.FullName $t -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
    Get-ChildItem $dest -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $n = @(Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count
      $lines += ("    recovered {0,-60} files={1}" -f $_.Name, $n)
    }
  }

  $lines += ""
  $lines += "=== 8. Dismount ==="
  try {
    Dismount-WindowsImage -Path $mnt -Discard -ErrorAction Stop | Out-Null
    $lines += "  dismounted OK"
  } catch {
    $lines += "  DISMOUNT FAILED: $($_.Exception.Message)"
  }
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
