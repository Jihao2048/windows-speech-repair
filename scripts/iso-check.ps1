$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\iso-and-manifest-check.txt'
$lines = @()

$lines += "=== ISO + MANIFEST INVESTIGATION $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== A. AppRepository: robust scan for LKG / Speech manifests ==="
$repo = 'C:\ProgramData\Microsoft\Windows\AppRepository'
$lines += "  repo exists: $(Test-Path $repo)"
$raw = cmd /c "dir /s /b `"$repo`" 2>nul"
$files = @($raw | Where-Object { $_ -match '\.xml$' })
$lines += "  total xml files found: $($files.Count)"
$lkg = @($files | Where-Object { $_ -match 'LKG' })
$lines += "  LKG xml files: $($lkg.Count)"
$lkg | ForEach-Object { $lines += "    $_" }
$sp = @($files | Where-Object { $_ -match 'Speech|Voice|InpApp' })
$lines += "  Speech/Voice/InpApp xml files: $($sp.Count)"
$sp | ForEach-Object { $lines += "    $_" }

$lines += ""
$lines += "=== B. Mount the Windows 11 24H2 ISO (read only) ==="
$iso = '.'
$lines += "  iso exists: $(Test-Path $iso)"
$mountResult = $null
try {
  $mountResult = Mount-DiskImage -ImagePath $iso -Access ReadOnly -PassThru -ErrorAction Stop
  Start-Sleep -Seconds 4
  $vol = $mountResult | Get-Volume -ErrorAction SilentlyContinue
  $dl = $vol.DriveLetter
  $lines += "  mounted at: $dl :"
} catch {
  $lines += "  MOUNT FAILED: $($_.Exception.Message)"
}

if ($dl) {
  $root = "${dl}:\"
  $lines += ""
  $lines += "  --- ISO root ---"
  Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object { $lines += "    $($_.Name)" }
  $lines += ""
  $lines += "  --- sources\install.* ---"
  Get-ChildItem "${root}sources" -Filter 'install.*' -ErrorAction SilentlyContinue | ForEach-Object {
    $lines += ("    {0,-30} {1,15:N0}" -f $_.Name, $_.Length)
  }
  $lines += ""
  $lines += "  --- image info (build numbers) ---"
  foreach ($img in @('install.wim','install.esd')) {
    $p = "${root}sources\$img"
    if (Test-Path $p) {
      $lines += "    $p"
      try {
        $infos = Get-WindowsImage -ImagePath $p -ErrorAction Stop
        foreach ($i in $infos) {
          $lines += ("       [{0}] {1}  ver={2}  size={3:N0}" -f $i.ImageIndex, $i.ImageName, $i.Version, $i.ImageSize)
        }
      } catch {
        $lines += "       Get-WindowsImage FAILED: $($_.Exception.Message)"
      }
    }
  }
  $lines += ""
  $lines += "  --- does the ISO ship LKG.SpeechRuntime payload? (check mounted \Windows\SystemApps is not present in ISO, expected) ---"
  $lines += ("    sources\boot.wim exists: {0}" -f (Test-Path "${root}sources\boot.wim"))
}

$lines += ""
$lines += "=== C. Current OS version for reference ==="
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$lines += ("  OS build: {0}.{1}  ({2})" -f $cv.CurrentBuild, $cv.UBR, $cv.DisplayVersion)

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
