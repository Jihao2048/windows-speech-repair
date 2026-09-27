$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\wu-policy-fix.txt'
$lines = @()

$lines += "=== WINDOWS UPDATE POLICY CLEANUP $(Get-Date -Format s) ==="
$lines += ""

$backup = 'C:\hidisp\wu-policy-backup.reg'
$keys = @(
  'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
  'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
)

$lines += "=== 1. Backup current policies to $backup ==="
foreach ($k in $keys) {
  $regPath = $k -replace '^HKLM\\', 'HKLM\'
  $r = reg export $regPath "C:\hidisp\wu-backup-tmp.reg" /y 2>&1
  $lines += ("  export {0} -> {1}" -f $k, ($r -join ' '))
  if (Test-Path 'C:\hidisp\wu-backup-tmp.reg') {
    Add-Content -Path $backup -Value (Get-Content 'C:\hidisp\wu-backup-tmp.reg' -Raw) -ErrorAction SilentlyContinue
    Remove-Item 'C:\hidisp\wu-backup-tmp.reg' -Force -ErrorAction SilentlyContinue
  }
}
$lines += "  backup file exists: $(Test-Path $backup)"

$lines += ""
$lines += "=== 2. Values before deletion ==="
foreach ($k in $keys) {
  $ps = $k -replace '^HKLM', 'HKLM:'
  $lines += "-- $ps"
  $p = Get-ItemProperty $ps -ErrorAction SilentlyContinue
  if ($p) {
    $names = ($p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }).Name
    if ($names) { foreach ($n in $names) { $lines += ("     {0} = {1}" -f $n, $p.$n) } } else { $lines += "     (no values)" }
  } else { $lines += "     (key not readable)" }
}

$lines += ""
$lines += "=== 3. Removing policy keys ==="
foreach ($k in $keys) {
  $r = reg delete $k /f 2>&1
  $lines += ("  delete {0} -> {1}" -f $k, ($r -join ' '))
}

$lines += ""
$lines += "=== 4. Verify removal ==="
foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate','HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU') {
  $lines += ("  {0} still exists: {1}" -f $k, (Test-Path $k))
}

$lines += ""
$lines += "=== 5. Service state after cleanup ==="
foreach ($n in 'wuauserv','BITS','UsoSvc','DoSvc') {
  $s = Get-Service -Name $n -ErrorAction SilentlyContinue
  if ($s) { $lines += ("  {0,-12} {1,-10} {2}" -f $s.Name, $s.Status, $s.StartType) }
}
$wu = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv' -ErrorAction SilentlyContinue
$lines += "  wuauserv registry Start = $($wu.Start)"

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
