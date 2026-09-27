$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\iso-inspect.txt'
$lines = @()

$lines += "=== ISO INSPECTION $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== 1. Search WinSxS for SpeechRuntime.dll and related ==="
foreach ($n in 'SpeechRuntime.dll','SpeechRuntime.exe','SpeechRuntime.winmd') {
  $hits = @(Get-ChildItem 'C:\Windows\WinSxS' -Recurse -Filter $n -ErrorAction SilentlyContinue | Select-Object -First 8)
  $lines += "  $n -> $($hits.Count) hit(s)"
  $hits | ForEach-Object { $lines += ("     {0}  ({1:N0} bytes)" -f $_.FullName, $_.Length) }
}

$lines += ""
$lines += "=== 2. Any component folder that looks like an LKG appx payload (has Assets or appxmanifest) ==="
$manifests = @(Get-ChildItem 'C:\Windows\WinSxS' -Recurse -Filter 'appxmanifest.xml' -ErrorAction SilentlyContinue)
$lines += "  appxmanifest.xml count under WinSxS: $($manifests.Count)"
$manifests | ForEach-Object { $lines += "     $($_.FullName)" }

$lines += ""
$lines += "=== 3. Locate the Windows 11 ISO ==="
$iso = $null
$cands = @(Get-ChildItem '.' -Recurse -Depth 4 -Filter '*.iso' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'windows_11' })
$lines += "  windows_11 iso candidates: $($cands.Count)"
$cands | ForEach-Object { $lines += ("     {0}  ({1:N2} GB)" -f $_.FullName, ($_.Length/1GB)) }
if ($cands.Count -gt 0) { $iso = $cands[0].FullName }

$lines += ""
$lines += "=== 4. Mount the ISO read-only ==="
$dl = $null
if ($iso) {
  try {
    $m = Mount-DiskImage -ImagePath $iso -Access ReadOnly -PassThru -ErrorAction Stop
    Start-Sleep -Seconds 5
    $vol = $m | Get-Volume -ErrorAction SilentlyContinue
    $dl = $vol.DriveLetter
    $lines += "  mounted, drive letter: $dl"
  } catch {
    $lines += "  MOUNT FAILED: $($_.Exception.Message)"
  }
} else {
  $lines += "  no iso found"
}

if ($dl) {
  $root = $dl + ':\'
  $lines += ""
  $lines += "  --- ISO root ---"
  Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object { $lines += "     $($_.Name)" }
  $lines += ""
  $lines += "  --- sources\install.* and boot.wim ---"
  Get-ChildItem ($root + 'sources') -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(install|boot)\.' } | ForEach-Object {
    $lines += ("     {0,-20} {1,15:N0}" -f $_.Name, $_.Length)
  }
  $lines += ""
  $lines += "  --- image info ---"
  foreach ($img in @('install.wim','install.esd')) {
    $p = $root + 'sources\' + $img
    if (Test-Path $p) {
      $lines += "     $p"
      try {
        Get-WindowsImage -ImagePath $p -ErrorAction Stop | ForEach-Object {
          $lines += ("        [{0}] {1}   version={2}" -f $_.ImageIndex, $_.ImageName, $_.Version)
        }
      } catch {
        $lines += "        FAILED: $($_.Exception.Message)"
      }
    }
  }
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
