$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\three-experiments.txt'
$lines = @()

$lines += "=== THREE EXPERIMENTS $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== A. AppXDeploymentServer operational log: recent 40 entries ==="
try {
  Get-WinEvent -LogName 'Microsoft-Windows-AppXDeploymentServer/Operational' -MaxEvents 40 -ErrorAction Stop | ForEach-Object {
    $m = $_.Message
    if ($m) { $m = ($m -split "`r?`n")[0]; if ($m.Length -gt 220) { $m = $m.Substring(0,220) } }
    $lines += ("  [{0}] lvl={1} id={2} :: {3}" -f $_.TimeCreated.ToString('HH:mm:ss'), $_.LevelDisplayName, $_.Id, $m)
  }
} catch { $lines += "  read failed: $($_.Exception.Message)" }

$lines += ""
$lines += "=== A2. AppXDeployment-Server log (alternative name) ==="
try {
  Get-WinEvent -LogName 'Microsoft-Windows-AppXDeployment-Server/Operational' -MaxEvents 20 -ErrorAction Stop | ForEach-Object {
    $m = $_.Message; if ($m) { $m = ($m -split "`r?`n")[0]; if ($m.Length -gt 220) { $m = $m.Substring(0,220) } }
    $lines += ("  [{0}] lvl={1} id={2} :: {3}" -f $_.TimeCreated.ToString('HH:mm:ss'), $_.LevelDisplayName, $_.Id, $m)
  }
} catch { $lines += "  not available: $($_.Exception.Message)" }

$lines += ""
$lines += "=== B. DISM provisioning attempt ==="
$dst = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
$lines += "  folder: $dst"
$r = DISM /Online /Add-ProvisionedAppxPackage /FolderPath:$dst /SkipLicense 2>&1
$r | ForEach-Object { $lines += "     $_" }
$lines += ("  exit code: {0}" -f $LASTEXITCODE)

$lines += ""
$lines += "=== C. Renamed-identity test copy registration ==="
$testRoot = 'C:\hidisp\testpkg2'
$testDst = Join-Path $testRoot 'Test.SpeechRuntime_cw5n1h2txyewy'
if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $testDst -Force | Out-Null
Copy-Item (Join-Path $dst '*') $testDst -Recurse -Force -ErrorAction Continue

$mf = Join-Path $testDst 'AppxManifest.xml'
if (-not (Test-Path $mf)) { $mf = Join-Path $testDst 'appxmanifest.xml' }
$content = Get-Content $mf -Raw
$newContent = $content -replace 'Name="MicrosoftWindows\.LKG\.SpeechRuntime"', 'Name="Test.LKG.SpeechRuntime"'
Set-Content -Path $mf -Value $newContent -Encoding UTF8 -NoNewline
$lines += "  identity changed: $($newContent -ne $content)"
foreach ($f in 'appxsignature.p7x','appxblockmap.xml') {
  $p = Join-Path $testDst $f
  if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue; $lines += "  removed $f" }
}
try {
  Add-AppxPackage -Register $mf -DisableDevelopmentMode -ErrorAction Stop
  $lines += "  RENAMED-IDENTITY REGISTER SUCCEEDED  --> conflict with existing identity is the cause"
} catch {
  $lines += ("  RENAMED-IDENTITY REGISTER FAILED: {0}" -f $_.Exception.Message)
  $lines += "  --> manifest/package structure itself is rejected"
}

$lines += ""
$lines += "=== D. Full raw manifest dump for reference ==="
$lines += (Get-Content $mf -Raw)

$lines += ""
$lines += "=== E. State ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG|Test\.' })
$lines += "  matching packages: $($cur.Count)"
$cur | ForEach-Object { $lines += ("     {0} {1} {2}" -f $_.Name, $_.Version, $_.Status) }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
