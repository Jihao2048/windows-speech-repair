$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\wu-leftovers.txt'
$lines = @()

$lines += "=== HUNT WU / WSUS LEFTOVERS $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== 1. WindowsUpdate client keys ==="
foreach ($k in 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate',
               'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update',
               'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\UX\Settings',
               'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Setup',
               'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services',
               'HKLM\SYSTEM\CurrentControlSet\Services\wuauserv',
               'HKLM\SYSTEM\CurrentControlSet\Services\wuauserv\Parameters') {
  $r = reg query $k /s 2>&1
  $lines += "  --- $k"
  if ($r -match 'ERROR|错误') { $lines += "     (not present)" }
  else { $r | Where-Object { $_ -match '\S' } | Select-Object -First 40 | ForEach-Object { $lines += "     $_" } }
}

$lines += ""
$lines += "=== 2. Search whole HKLM\SOFTWARE for the fake WSUS strings ==="
foreach ($needle in '.','.') {
  $r = reg query "HKLM\SOFTWARE" /s /f $needle 2>&1
  $lines += "  needle: $needle"
  $r | Where-Object { $_ -match '\S' } | Select-Object -First 25 | ForEach-Object { $lines += "     $_" }
}

$lines += ""
$lines += "=== 3. Search HKLM\SYSTEM for the fake WSUS strings ==="
foreach ($needle in '.','.') {
  $r = reg query "HKLM\SYSTEM\CurrentControlSet\Services" /s /f $needle 2>&1
  $lines += "  needle: $needle"
  $r | Where-Object { $_ -match '\S' } | Select-Object -First 20 | ForEach-Object { $lines += "     $_" }
}

$lines += ""
$lines += "=== 4. BITS / DO / UsoSvc config ==="
foreach ($k in 'HKLM\SYSTEM\CurrentControlSet\Services\BITS','HKLM\SYSTEM\CurrentControlSet\Services\UsoSvc','HKLM\SYSTEM\CurrentControlSet\Services\DoSvc','HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc','HKLM\SYSTEM\CurrentControlSet\Services\TokenBroker') {
  $p = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($k.Split('\')[-1])" -ErrorAction SilentlyContinue
  if ($p) { $lines += ("  {0,-40} Start={1}" -f $k.Split('\')[-1], $p.Start) }
}

$lines += ""
$lines += "=== 5. Windows Update medic / service state ==="
foreach ($n in 'wuauserv','BITS','UsoSvc','DoSvc','WaaSMedicSvc','cryptsvc','TrustedInstaller') {
  $s = Get-Service -Name $n -ErrorAction SilentlyContinue
  if ($s) { $lines += ("  {0,-20} {1,-10} {2}" -f $s.Name, $s.Status, $s.StartType) }
  else { $lines += ("  {0,-20} NOT FOUND" -f $n) }
}

$lines += ""
$lines += "=== 6. Can the machine reach the real update endpoints? ==="
foreach ($h in 'fe2.update.microsoft.com','tlu.dl.delivery.mp.microsoft.com','sls.update.microsoft.com','download.windowsupdate.com') {
  try {
    $ips = [System.Net.Dns]::GetHostAddresses($h) | ForEach-Object { $_.IPAddressToString }
    $lines += ("  {0} -> {1}" -f $h, (($ips | Select-Object -First 2) -join ', '))
  } catch { $lines += ("  {0} -> DNS FAIL" -f $h) }
}
try {
  $req = [System.Net.WebRequest]::Create('https://fe2.update.microsoft.com/v6/ClientWebService/client.asmx')
  $req.Method = 'GET'
  $req.Timeout = 8000
  $resp = $req.GetResponse()
  $lines += ("  HTTPS to fe2.update.microsoft.com: HTTP {0}" -f ([int]$resp.StatusCode))
  $resp.Close()
} catch {
  $lines += ("  HTTPS to fe2: FAILED - {0}" -f $_.Exception.Message)
}

$lines += ""
$lines += "=== 7. Proxy settings again (WU uses WinHTTP) ==="
$r = netsh winhttp show proxy 2>&1
$r | Where-Object { $_ -match '\S' } | ForEach-Object { $lines += "     $_" }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
