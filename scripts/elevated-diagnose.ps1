$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\elevated-diag.txt'
$lines = @()

$lines += "=== ELEVATED READ-ONLY DIAGNOSTIC $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== 1. Speech related Windows capabilities ==="
try {
  $caps = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -match 'Speech' }
  if ($caps) { $caps | ForEach-Object { $lines += ("  {0}  -> {1}" -f $_.Name, $_.State) } } else { $lines += "  (none matching Speech)" }
} catch { $lines += "  ERROR: $($_.Exception.Message)" }

$lines += ""
$lines += "=== 2. Language capabilities for zh-CN ==="
try {
  $langs = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -match 'Language' -and $_.Name -match 'zh-CN' }
  if ($langs) { $langs | ForEach-Object { $lines += ("  {0}  -> {1}" -f $_.Name, $_.State) } } else { $lines += "  (none for zh-CN)" }
} catch { $lines += "  ERROR: $($_.Exception.Message)" }

$lines += ""
$lines += "=== 3. ComponentDetect owned paths for speech components ==="
$base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\ComponentDetect'
$comps = Get-ChildItem $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'speech|sapi' }
$lines += "  matching components: $($comps.Count)"
foreach ($c in $comps) {
  $subs = Get-ChildItem $c.PSPath -ErrorAction SilentlyContinue
  $lines += ("  --- {0}  (owned paths: {1})" -f $c.PSChildName, $subs.Count)
  $subs | Select-Object -First 40 | ForEach-Object { $lines += "      $($_.PSChildName)" }
}

$lines += ""
$lines += "=== 4. Speech related event logs present ==="
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.LogName -match 'Speech|Voice|Dictation|Input' } | ForEach-Object {
  $lines += ("  {0}  ({1} records)" -f $_.LogName, $_.RecordCount)
}

$lines += ""
$lines += "=== 5. Recent errors from System log (last 3 days) mentioning speech/input/audio ==="
$since = (Get-Date).AddDays(-3)
try {
  Get-WinEvent -FilterHashtable @{ LogName='System'; StartTime=$since; Level=1,2,3 } -ErrorAction Stop |
    Where-Object { $_.Message -match '语音|Speech|sapi|TextInput|Dictation' } |
    Select-Object -First 20 |
    ForEach-Object { $lines += ("  [{0}] {1} :: {2}" -f $_.TimeCreated, $_.ProviderName, (($_.Message -split "`r?`n")[0])) }
} catch { $lines += "  no matching events: $($_.Exception.Message)" }

$lines += ""
$lines += "=== 6. Speech language pack Appx full state ==="
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Speech|Voice' } | ForEach-Object {
  $lines += ("  {0}  {1}  Status={2}  Install={3}" -f $_.Name, $_.Version, $_.Status, $_.InstallLocation)
}

$lines += ""
$lines += "=== 7. Windows install media available for repair source? ==="
foreach ($p in 'C:\ESD','C:\Windows\ESD','C:\ISO','D:\','E:\') {
  if (Test-Path $p) {
    $wim = @(Get-ChildItem $p -Filter 'install.*' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 3)
    $iso = @(Get-ChildItem $p -Filter '*.iso' -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 3)
    foreach ($i in $iso) { $lines += ("  ISO: {0}  ({1:N1} GB)" -f $i.FullName, ($i.Length/1GB)) }
    foreach ($w in $wim) { $lines += ("  WIM/ESD: {0}" -f $w.FullName) }
  }
}

$lines += ""
$lines += "=== DIAGNOSTIC DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
