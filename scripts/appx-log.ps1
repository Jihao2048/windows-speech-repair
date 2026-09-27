$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\appx-log.txt'
$lines = @()

$lines += "=== APPX DEPLOYMENT DETAILED LOG $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== 1. Get-AppPackageLog for the failed attempts ==="
foreach ($id in '88529e63-4d5c-000b-aa8a-65885c4ddd01','88529e63-4d5c-0009-4ebe-61885c4ddd01','88529e63-4d5c-0004-9a9f-63885c4ddd01') {
  $lines += "  --- ActivityId $id"
  try {
    Get-AppPackageLog -ActivityID $id -ErrorAction Stop | Select-Object -First 60 | ForEach-Object {
      $m = $_.Message
      if ($m.Length -gt 300) { $m = $m.Substring(0,300) }
      $lines += ("     {0}" -f $m)
    }
  } catch {
    $lines += "     FAILED: $($_.Exception.Message)"
  }
}

$lines += ""
$lines += "=== 2. PackageUserInformation detail (resolve SIDs properly) ==="
$p = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'MicrosoftWindows.LKG.SpeechRuntime' }
if ($p) {
  $lines += ("  PackageFullName: {0}" -f $p.PackageFullName)
  $i = 0
  foreach ($u in $p.PackageUserInformation) {
    $i++
    $sidVal = ''
    try { $sidVal = $u.UserSecurityId.ToString() } catch { $sidVal = '??' }
    $name = $sidVal
    try {
      $sidObj = New-Object System.Security.Principal.SecurityIdentifier($sidVal)
      $name = $sidObj.Translate([System.Security.Principal.NTAccount]).Value
    } catch { }
    $lines += ("  [{0}] state={1} raw={2} resolved={3}" -f $i, $u.InstallState, $sidVal, $name)
  }
  $lines += ""
  $lines += "  --- raw Format-List of one entry ---"
  ($p.PackageUserInformation | Select-Object -First 1 | Format-List * | Out-String) -split "`r?`n" | Where-Object { $_ -match '\S' } | ForEach-Object { $lines += "     $_" }
}

$lines += ""
$lines += "=== 3. microsoft.system.package.metadata folder ==="
foreach ($base in 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy','C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy','C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.AccountsService_cw5n1h2txyewy') {
  $md = Join-Path $base 'microsoft.system.package.metadata'
  $lines += "  --- $base"
  $lines += ("     metadata dir exists: {0}" -f (Test-Path $md))
  if (Test-Path $md) {
    Get-ChildItem $md -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
      $len = $_.Length; if ($null -eq $len) { $len = 0 }
      $lines += ("        {0,-50} {1,10:N0}" -f $_.Name, $len)
    }
  }
  $lines += ("     SxS metadata (.SCCD etc): {0}" -f (@(Get-ChildItem $base -Filter '*.SCCD' -ErrorAction SilentlyContinue).Count))
}

$lines += ""
$lines += "=== 4. AppXDeploymentServer operational log: recent errors ==="
try {
  $ev = Get-WinEvent -LogName 'Microsoft-Windows-AppXDeploymentServer/Operational' -MaxEvents 400 -ErrorAction Stop |
        Where-Object { $_.LevelDisplayName -in @('Error','Warning') } | Select-Object -First 15
  foreach ($e in $ev) {
    $m = $e.Message
    if ($m.Length -gt 400) { $m = $m.Substring(0,400) }
    $lines += ("  [{0}] id={1} {2}" -f $e.TimeCreated, $e.Id, $m)
    $lines += "  ----"
  }
} catch { $lines += "  log read failed: $($_.Exception.Message)" }

$lines += ""
$lines += "=== 5. Compare: how does a WORKING system appx folder look? ==="
foreach ($base in 'C:\Windows\SystemApps\MicrosoftWindows.Client.Core_cw5n1h2txyewy') {
  $lines += "  --- $base"
  Get-ChildItem $base -Force -ErrorAction SilentlyContinue | Select-Object -First 25 | ForEach-Object {
    $kind = 'FILE'; if ($_.PSIsContainer) { $kind = 'DIR' }
    $lines += ("     {0,-55} {1}" -f $_.Name, $kind)
  }
}

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
