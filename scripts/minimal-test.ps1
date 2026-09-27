$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\minimal-test.txt'
$lines = @()

$lines += "=== MINIMAL PACKAGE TEST + LKG HISTORY $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== A. Create a minimal, brand-new test package and try to register it ==="
$dir = 'C:\hidisp\minimal\Minimal.TestApp_cw5n1h2txyewy'
if (Test-Path 'C:\hidisp\minimal') { Remove-Item 'C:\hidisp\minimal' -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $dir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dir 'Assets') -Force | Out-Null

$png = [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,0x89,0x00,0x00,0x00,0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82)
foreach ($n in 'StoreLogo.png','Square150x150Logo.png','Square44x44Logo.png') {
  [System.IO.File]::WriteAllBytes((Join-Path $dir "Assets\$n"), $png)
}

$manifest = @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         IgnorableNamespaces="uap">
  <Identity Name="Minimal.TestApp" Publisher="CN=TestPublisher" Version="1.0.0.0" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>Minimal Test App</DisplayName>
    <PublisherDisplayName>Test</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.1" />
  </Dependencies>
  <Resources>
    <Resource Language="en-US" />
  </Resources>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities" />
  </Capabilities>
</Package>
'@
$mfPath = Join-Path $dir 'AppxManifest.xml'
Set-Content -Path $mfPath -Value $manifest -Encoding UTF8
$lines += "  created $mfPath"

try {
  Add-AppxPackage -Register $mfPath -DisableDevelopmentMode -ErrorAction Stop
  $lines += "  MINIMAL REGISTER SUCCEEDED  --> loose registration works; our speech package content is the problem"
} catch {
  $lines += ("  MINIMAL REGISTER FAILED: {0}" -f $_.Exception.Message)
  $lines += "  --> loose/unpacked registration appears BROKEN on this machine"
}

$lines += ""
$lines += "=== B. Try registering the minimal package WITHOUT -DisableDevelopmentMode ==="
try {
  Add-AppxPackage -Register $mfPath -ErrorAction Stop
  $lines += "  REGISTER (no flag) SUCCEEDED"
} catch {
  $lines += ("  REGISTER (no flag) FAILED: {0}" -f $_.Exception.Message)
}

$lines += ""
$lines += "=== C. History of LKG.SpeechRuntime in the deployment log ==="
try {
  Get-WinEvent -LogName 'Microsoft-Windows-AppXDeploymentServer/Operational' -MaxEvents 4000 -ErrorAction Stop |
    Where-Object { $_.Message -match 'LKG\.SpeechRuntime' } |
    Select-Object -First 45 | ForEach-Object {
      $m = $_.Message
      if ($m) { $m = ($m -split "`r?`n")[0]; if ($m.Length -gt 260) { $m = $m.Substring(0,260) } }
      $lines += ("  [{0}] lvl={1} id={2} :: {3}" -f $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $_.LevelDisplayName, $_.Id, $m)
    }
} catch { $lines += "  log read failed: $($_.Exception.Message)" }

$lines += ""
$lines += "=== D. Which local users exist (SID map) ==="
try {
  Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction Stop | ForEach-Object {
    $lines += ("  {0,-25} {1}" -f $_.Name, $_.SID)
  }
} catch { $lines += "  WMI failed: $($_.Exception.Message)" }

$lines += ""
$lines += "=== E. State ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Minimal|LKG' })
$lines += "  matching: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0} {1} {2}" -f $_.Name, $_.Version, $_.Status) }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
