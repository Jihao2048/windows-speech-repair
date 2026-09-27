$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\damage-scope.txt'
$lines = @()

$lines += "=== DAMAGE SCOPE SCAN $(Get-Date -Format s) ==="
$lines += ""

function Get-FolderStat($path) {
  try {
    $files = Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue
    $count = @($files).Count
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    if (-not $bytes) { $bytes = 0 }
    return @{ Count = $count; Bytes = $bytes }
  } catch {
    return @{ Count = -1; Bytes = -1 }
  }
}

$lines += "=== 1. SystemApps\LKG folders ==="
Get-ChildItem 'C:\Windows\SystemApps\LKG' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $s = Get-FolderStat $_.FullName
  $flag = if ($s.Count -eq 0) { '  <== EMPTY!' } elseif ($s.Count -lt 5) { '  <== SUSPICIOUSLY SMALL' } else { '' }
  $lines += ("  {0,-55} files={1,-6} size={2:N0}{3}" -f $_.Name, $s.Count, $s.Bytes, $flag)
}

$lines += ""
$lines += "=== 2. SystemApps folders with speech/input/critical names ==="
Get-ChildItem 'C:\Windows\SystemApps' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Speech|Input|CBS|Core|AI|Shell|Start|Text' } | ForEach-Object {
  $s = Get-FolderStat $_.FullName
  $flag = if ($s.Count -eq 0) { '  <== EMPTY!' } else { '' }
  $lines += ("  {0,-60} files={1,-6} size={2:N0}{3}" -f $_.Name, $s.Count, $s.Bytes, $flag)
}

$lines += ""
$lines += "=== 3. All SystemApps folders (empty ones only) ==="
$empty = 0
Get-ChildItem 'C:\Windows\SystemApps' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $s = Get-FolderStat $_.FullName
  if ($s.Count -eq 0) { $lines += "  EMPTY: $($_.Name)"; $empty++ }
}
$lines += "  total empty SystemApps folders: $empty"

$lines += ""
$lines += "=== 4. WindowsApps speech packages content ==="
foreach ($p in '.','.') {
  $s = Get-FolderStat $p
  $lines += ("  {0,-70} files={1} size={2:N0}" -f (Split-Path $p -Leaf), $s.Count, $s.Bytes)
}

$lines += ""
$lines += "=== 5. WinSxS speech component payloads available for restore ==="
foreach ($pat in 'microsoft-onecore-speechservice-component','microsoft-windows-speechcommon') {
  $dirs = Get-ChildItem 'C:\Windows\WinSxS' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$pat*" }
  foreach ($d in $dirs) {
    $s = Get-FolderStat $d.FullName
    $lines += ("  {0}" -f $d.Name)
    $lines += ("     files={0} size={1:N0}" -f $s.Count, $s.Bytes)
    Get-ChildItem $d.FullName -File -ErrorAction SilentlyContinue | Select-Object -First 25 | ForEach-Object { $lines += ("       {0,-45} {1,12:N0}" -f $_.Name, $_.Length) }
  }
}

$lines += ""
$lines += "=== 6. SpeechRuntime.exe in WinSxS (search all) ==="
$hits = @(Get-ChildItem 'C:\Windows\WinSxS' -Recurse -Filter 'SpeechRuntime.exe' -ErrorAction SilentlyContinue | Select-Object -First 10)
$lines += "  hits: $($hits.Count)"
$hits | ForEach-Object { $lines += ("    {0}  ({1:N0} bytes)" -f $_.FullName, $_.Length) }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
