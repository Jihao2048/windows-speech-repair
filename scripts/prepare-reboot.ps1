$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\prepare-reboot.txt'
$lines = @()

$lines += "=== PREPARE FOR REBOOT $(Get-Date -Format s) ==="
$lines += ""

$lkg = 'C:\Windows\SystemApps\LKG'
$rec = 'C:\hidisp\recovered'
$sr = Join-Path $lkg 'MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'

$lines += "=== 1. Restore SpeechRuntime folder to exact image state ==="
foreach ($f in 'appxsignature.p7x','appxblockmap.xml') {
  $bak = Join-Path $sr ($f + '.bak')
  $real = Join-Path $sr $f
  if (Test-Path $bak) {
    Move-Item $bak $real -Force -ErrorAction Continue
    $lines += "  restored $f"
  }
}
$up = Join-Path $sr 'AppxManifest.xml'
$low = Join-Path $sr 'appxmanifest.xml'
$tmp = Join-Path $sr '_m.xml'
if (Test-Path $up) {
  Rename-Item $up '_m.xml' -Force -ErrorAction Continue
  Rename-Item $tmp 'appxmanifest.xml' -Force -ErrorAction Continue
  $lines += "  manifest renamed back to lowercase (matches OS norm)"
}
(cmd /c "dir /b `"$sr`" 2>nul") | Where-Object { $_ -match 'manifest|blockmap|signature' } | ForEach-Object { $lines += "     [$_]" }

$lines += ""
$lines += "=== 2. Verify all six LKG folders match the image content counts ==="
foreach ($d in Get-ChildItem $rec -Directory -ErrorAction SilentlyContinue) {
  $t = Join-Path $lkg $d.Name
  if (-not (Test-Path $t)) { New-Item -ItemType Directory -Path $t -Force | Out-Null }
  Copy-Item (Join-Path $d.FullName '*') $t -Recurse -Force -ErrorAction Continue
  $a = @(Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  $b = @(Get-ChildItem $t -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  $lines += ("  {0,-58} image={1,-4} system={2}" -f $d.Name, $a, $b)
}

$lines += ""
$lines += "=== 3. Set ownership to TrustedInstaller (match healthy system apps) ==="
foreach ($d in Get-ChildItem $lkg -Directory -ErrorAction SilentlyContinue) {
  $r = icacls $d.FullName /setowner "NT SERVICE\TrustedInstaller" /T /C /Q 2>&1
  $lines += ("  {0} -> {1}" -f $d.Name, (($r | Select-Object -Last 1) -replace '\s+',' '))
}

$lines += ""
$lines += "=== 4. Are the LKG packages in the provisioned (inbox) list? ==="
try {
  $prov = Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -match 'LKG|Speech' }
  if ($prov) {
    $prov | ForEach-Object { $lines += ("  {0}  {1}  {2}" -f $_.DisplayName, $_.Version, $_.InstallLocation) }
  } else { $lines += "  (no LKG/Speech entries provisioned)" }
} catch { $lines += "  failed: $($_.Exception.Message)" }

$lines += ""
$lines += "=== 5. Characterize -DisableDevelopmentMode (minimal package test) ==="
$mdir = 'C:\hidisp\min2\Minimal.TestApp2_cw5n1h2txyewy'
if (Test-Path 'C:\hidisp\min2') { Remove-Item 'C:\hidisp\min2' -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path (Join-Path $mdir 'Assets') -Force | Out-Null
$png = [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,0x89,0x00,0x00,0x00,0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82)
foreach ($n in 'StoreLogo.png','Square150x150Logo.png','Square44x44Logo.png') { [System.IO.File]::WriteAllBytes((Join-Path $mdir "Assets\$n"), $png) }
$man = @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap rescap">
  <Identity Name="Minimal.TestApp2" Publisher="CN=TestPublisher" Version="1.0.0.0" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>Minimal Test App 2</DisplayName>
    <PublisherDisplayName>Test</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.1" />
  </Dependencies>
  <Resources><Resource Language="en-US" /></Resources>
  <Capabilities><rescap:Capability Name="runFullTrust" /></Capabilities>
</Package>
'@
$m2 = Join-Path $mdir 'AppxManifest.xml'
Set-Content -Path $m2 -Value $man -Encoding UTF8

try { Add-AppxPackage -Register $m2 -DisableDevelopmentMode -ErrorAction Stop; $lines += "  WITH -DisableDevelopmentMode: SUCCEEDED" }
catch { $lines += ("  WITH -DisableDevelopmentMode: FAILED -> {0}" -f (($_.Exception.Message -split "`r?`n")[0])) }
try { Add-AppxPackage -Register $m2 -ErrorAction Stop; $lines += "  WITHOUT flag: SUCCEEDED" }
catch { $lines += ("  WITHOUT flag: FAILED -> {0}" -f (($_.Exception.Message -split "`r?`n")[0])) }

$lines += ""
$lines += "=== 6. Clean up test package ==="
$tp = Get-AppxPackage -Name 'Minimal.TestApp2' -ErrorAction SilentlyContinue
if ($tp) { try { Remove-AppxPackage -Package $tp.PackageFullName -ErrorAction Stop; $lines += "  removed test package" } catch { $lines += "  remove failed: $($_.Exception.Message)" } }
if (Test-Path 'C:\hidisp\min2') { Remove-Item 'C:\hidisp\min2' -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path 'C:\hidisp\testpkg') { Remove-Item 'C:\hidisp\testpkg' -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path 'C:\hidisp\testpkg2') { Remove-Item 'C:\hidisp\testpkg2' -Recurse -Force -ErrorAction SilentlyContinue }

$lines += ""
$lines += "=== 7. Summary of LKG folder state ==="
foreach ($d in Get-ChildItem $lkg -Directory -ErrorAction SilentlyContinue) {
  $n = @(Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  $mf = cmd /c "dir /b `"$($d.FullName)`" 2>nul" | Where-Object { $_ -match 'manifest' }
  $lines += ("  {0,-58} files={1,-4} manifest=[{2}]" -f $d.Name, $n, ($mf -join ','))
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
