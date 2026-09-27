$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\force-update-test.txt'
$lines = @()

$lines += "=== FORCE UPDATE TEST $(Get-Date -Format s) ==="
$lines += ""

$sr = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
$mf = Join-Path $sr 'appxmanifest.xml'
$lines += ("  manifest: {0} exists: {1}" -f $mf, (Test-Path $mf))

function Show($label, $scriptBlock) {
  $r = @()
  try {
    & $scriptBlock
    $r += "  $label : SUCCEEDED"
  } catch {
    $m = ($_.Exception.Message -split "`r?`n")[0]
    $r += "  $label : FAILED -> $m"
  }
  return $r
}

$lines += ""
$lines += "=== Variant 1: -Register with -ForceUpdateFromAnyVersion ==="
$lines += Show 'ForceUpdate' { Add-AppxPackage -Register $mf -ForceUpdateFromAnyVersion -ErrorAction Stop }

$lines += ""
$lines += "=== Variant 2: + -ForceTargetApplicationShutdown ==="
$lines += Show 'ForceUpdate+Shutdown' { Add-AppxPackage -Register $mf -ForceUpdateFromAnyVersion -ForceTargetApplicationShutdown -ErrorAction Stop }

$lines += ""
$lines += "=== Variant 3: -RegisterByFamilyName with -ForceUpdateFromAnyVersion ==="
$lines += Show 'FamilyName+Force' { Add-AppxPackage -RegisterByFamilyName -MainPackage 'MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy' -ForceUpdateFromAnyVersion -ErrorAction Stop }

$lines += ""
$lines += "=== Variant 4: higher version + -ForceUpdateFromAnyVersion ==="
$orig = Get-Content $mf -Raw
$bumped = $orig -replace 'Version="1000\.26100\.3470\.0"', 'Version="1000.26100.8888.0"'
Set-Content -Path $mf -Value $bumped -Encoding UTF8 -NoNewline
$lines += Show 'Bumped+Force' { Add-AppxPackage -Register $mf -ForceUpdateFromAnyVersion -ErrorAction Stop }
Set-Content -Path $mf -Value $orig -Encoding UTF8 -NoNewline
$lines += "  manifest restored to original version"

$lines += ""
$lines += "=== Registration state ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
$lines += "  LKG for current user: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0}  {1}  {2}  {3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation) }

$lines += ""
$lines += "=== All-users state ==="
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' } | ForEach-Object {
  $lines += ("  {0} {1} {2}" -f $_.Name, $_.Version, $_.Status)
  foreach ($u in $_.PackageUserInformation) { $lines += ("     {0}" -f $u.InstallState) }
}

$lines += ""
$lines += "=== If registered: restart TextInputHost ==="
Get-Process -Name TextInputHost -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
$ti = Get-Process -Name TextInputHost -ErrorAction SilentlyContinue
if ($ti) { $lines += "  TextInputHost pid $($ti.Id)" } else { $lines += "  not running" }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
