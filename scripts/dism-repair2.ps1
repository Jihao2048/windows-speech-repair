$ErrorActionPreference = 'Continue'
$log = 'C:\hidisp\dism-repair2-log.txt'
Start-Transcript -Path $log -Force | Out-Null

Write-Output "=== DISM COMPONENT STORE REPAIR (WU ENABLED) $(Get-Date -Format s) ==="

Write-Output ""
Write-Output "=== 0. Safety backup of the restored LKG payloads ==="
$safety = 'C:\hidisp\lkg-safety-backup'
if (Test-Path $safety) { Remove-Item $safety -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $safety -Force | Out-Null
foreach ($d in Get-ChildItem 'C:\Windows\SystemApps\LKG' -Directory -ErrorAction SilentlyContinue) {
  Copy-Item $d.FullName (Join-Path $safety $d.Name) -Recurse -Force -ErrorAction Continue
}
Get-ChildItem $safety -Directory | ForEach-Object {
  Write-Output ("  backed up {0} ({1} files)" -f $_.Name, @(Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count)
}

Write-Output ""
Write-Output "=== 1. DISM ScanHealth ==="
DISM /Online /Cleanup-Image /ScanHealth
Write-Output "  scan exit code: $LASTEXITCODE"

Write-Output ""
Write-Output "=== 2. DISM RestoreHealth (repair) ==="
DISM /Online /Cleanup-Image /RestoreHealth
Write-Output "  restore exit code: $LASTEXITCODE"

Write-Output ""
Write-Output "=== 3. DISM CheckHealth after repair ==="
DISM /Online /Cleanup-Image /CheckHealth
Write-Output "  check exit code: $LASTEXITCODE"

Write-Output ""
Write-Output "=== 4. LKG folder state after repair ==="
foreach ($d in Get-ChildItem 'C:\Windows\SystemApps\LKG' -Directory -ErrorAction SilentlyContinue) {
  $n = @(Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  Write-Output ("  {0,-58} files={1}" -f $d.Name, $n)
}

Write-Output ""
Write-Output "=== 5. If any LKG folder was wiped, restore from safety backup ==="
foreach ($d in Get-ChildItem $safety -Directory -ErrorAction SilentlyContinue) {
  $target = Join-Path 'C:\Windows\SystemApps\LKG' $d.Name
  $cur = @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  $ref = @(Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  if ($cur -lt $ref) {
    Copy-Item (Join-Path $d.FullName '*') $target -Recurse -Force -ErrorAction Continue
    Write-Output ("  RESTORED {0}: {1} -> {2} files" -f $d.Name, $cur, @(Get-ChildItem $target -Recurse -File -Force -ErrorAction SilentlyContinue).Count)
  } else {
    Write-Output ("  ok {0} ({1} files)" -f $d.Name, $cur)
  }
}

Write-Output ""
Write-Output "=== 6. Speech registration state ==="
$cur = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
Write-Output "  LKG for current user: $($cur.Count)"
$cur | ForEach-Object { Write-Output ("     {0} {1} {2}" -f $_.Name, $_.Version, $_.Status) }
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG.SpeechRuntime' } | ForEach-Object {
  Write-Output ("  all-users {0} {1} {2}" -f $_.Name, $_.Version, $_.Status)
  foreach ($u in $_.PackageUserInformation) { Write-Output ("     {0}" -f $u.InstallState) }
}

Write-Output ""
Write-Output "=== 7. Windows Update still healthy? ==="
try {
  $session = New-Object -ComObject Microsoft.Update.Session
  $searcher = $session.CreateUpdateSearcher()
  $result = $searcher.Search("IsInstalled=0")
  Write-Output ("  WU search OK, updates available: {0}" -f $result.Updates.Count)
} catch {
  Write-Output ("  WU search FAILED: {0}" -f $_.Exception.Message)
}

Write-Output ""
Write-Output "=== SPEECH-DISM-DONE $(Get-Date -Format s) ==="
Stop-Transcript | Out-Null
