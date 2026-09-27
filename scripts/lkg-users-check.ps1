$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\lkg-users-check.txt'
$lines = @()

$lines += "=== LKG PACKAGE USER REGISTRATION $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== 1. All LKG packages: install location and file counts ==="
foreach ($p in Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' }) {
  $loc = $p.InstallLocation
  $cnt = -1
  if ($loc -and (Test-Path $loc)) { $cnt = @(Get-ChildItem $loc -Recurse -File -Force -ErrorAction SilentlyContinue).Count }
  $lines += ("  {0}" -f $p.Name)
  $lines += ("     version={0}  status={1}" -f $p.Version, $p.Status)
  $lines += ("     location={0}" -f $loc)
  $lines += ("     file count in location={0}" -f $cnt)
}

$lines += ""
$lines += "=== 2. Per-user registration state for LKG packages ==="
foreach ($p in Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' }) {
  $lines += ("  --- {0}" -f $p.Name)
  foreach ($u in $p.PackageUserInformation) {
    $sid = [string]$u.UserSecurityId
    $name = $sid
    try {
      $acct = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount])
      $name = "$sid ($($acct.Value))"
    } catch { $name = "$sid (unresolved)" }
    $lines += ("      {0}  ->  {1}" -f $name, $u.InstallState)
  }
}

$lines += ""
$lines += "=== 3. Current user identity ==="
$lines += ("  whoami: {0}" -f (whoami))
$lines += ("  SID: {0}" -f ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value))

$lines += ""
$lines += "=== 4. AppRepository folder ==="
Get-ChildItem 'C:\ProgramData\Microsoft\Windows\AppRepository' -Force -ErrorAction SilentlyContinue | ForEach-Object { $lines += ("  {0,-50} {1,15:N0}" -f $_.Name, $_.Length) }

$lines += ""
$lines += "=== 5. Search WinSxS manifests for LKG.SpeechRuntime string ==="
$hits = 0
foreach ($m in Get-ChildItem 'C:\Windows\WinSxS\Manifests' -File -ErrorAction SilentlyContinue) {
  try {
    $bytes = [System.IO.File]::ReadAllBytes($m.FullName)
    $txt = [System.Text.Encoding]::Unicode.GetString($bytes)
    if ($txt -match 'LKG\.SpeechRuntime' -or $txt -match 'LKG\.AccountsService') {
      $lines += ("  HIT: {0}" -f $m.Name)
      $hits++
      if ($hits -ge 15) { break }
    }
  } catch { }
}
$lines += "  total hits: $hits"

$lines += ""
$lines += "=== 6. Where is appxmanifest for LKG packages? search component dirs ==="
$cands = @(Get-ChildItem 'C:\Windows\WinSxS' -Recurse -Filter 'appxmanifest.xml' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'LKG' })
$lines += "  appxmanifest.xml under LKG-named component paths: $($cands.Count)"
$cands | ForEach-Object { $lines += "    $($_.FullName)" }

$lines += ""
$lines += "=== 7. Speech package registration for current user (detailed) ==="
$cur = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Speech|Voice|LKG' }
$lines += "  count for current user: $(@($cur).Count)"
$cur | ForEach-Object { $lines += ("    {0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status) }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
