$ErrorActionPreference = 'Continue'
$log = 'C:\hidisp\repair-stage2-log.txt'
Start-Transcript -Path $log -Force | Out-Null

Write-Output "=== STAGE 2 START $(Get-Date -Format s) ==="

Write-Output ""
Write-Output "=== 1. Verify restored engine files ==="
foreach ($f in 'C:\Windows\System32\sapi.dll','C:\Windows\System32\SpeechRuntime.exe','C:\Windows\SysWOW64\sapi.dll') {
  $exists = Test-Path $f
  $ver = ''
  if ($exists) { $ver = (Get-Item $f).VersionInfo.FileVersion }
  Write-Output ("  {0} -> exists={1} version={2}" -f $f, $exists, $ver)
}

Write-Output ""
Write-Output "=== 2. Enable online speech recognition consent ==="
$key = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\PrivacyPolicy'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name 'HasAccepted' -PropertyType DWord -Value 1 -Force | Out-Null
$v = (Get-ItemProperty $key -ErrorAction SilentlyContinue).HasAccepted
Write-Output "  HasAccepted = $v"

Write-Output ""
Write-Output "=== 3. Re-register speech related Appx packages ==="
$pkgs = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Speech|Voice' }
foreach ($p in $pkgs) {
  Write-Output ("  re-registering {0} {1}" -f $p.Name, $p.Version)
  $manifest = Join-Path $p.InstallLocation 'AppXManifest.xml'
  if (Test-Path $manifest) {
    try {
      Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
      Write-Output "    OK"
    } catch {
      Write-Output ("    FAILED: {0}" -f $_.Exception.Message)
    }
  } else {
    Write-Output "    manifest not found: $manifest"
  }
}

Write-Output ""
Write-Output "=== 4. Speech services state ==="
$svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Speech|Sapi' }
if ($svc) { $svc | ForEach-Object { Write-Output ("  {0} {1} {2}" -f $_.Name, $_.Status, $_.StartType) } } else { Write-Output "  (no speech services registered - expected on this build)" }

Write-Output ""
Write-Output "=== 5. Speech language packs registered for current user ==="
Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Speech|Voice' } | ForEach-Object {
  Write-Output ("  {0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status)
}

Write-Output ""
Write-Output "=== STAGE 2 DONE $(Get-Date -Format s) ==="
Stop-Transcript | Out-Null
