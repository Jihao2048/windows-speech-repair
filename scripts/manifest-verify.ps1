$ErrorActionPreference = 'Continue'
$out = 'C:\hidisp\manifest-verify.txt'
$lines = @()

$repo = 'C:\ProgramData\Microsoft\Windows\AppRepository'

$lines += "=== MANIFEST VERIFICATION $(Get-Date -Format s) ==="
$lines += ""

$lines += "=== 1. Is AppRepository xml == real AppXManifest.xml? (test with Speech.zh-CN.1) ==="
$repoXml = Join-Path $repo 'MicrosoftWindows.Speech.zh-CN.1_1.0.23.0_x64__cw5n1h2txyewy.xml'
$realManifest = '.'
$lines += "  repo xml exists: $(Test-Path $repoXml)"
$lines += "  real manifest exists: $(Test-Path $realManifest)"

if ((Test-Path $repoXml) -and (Test-Path $realManifest)) {
  $a = Get-Content $repoXml -Raw -ErrorAction SilentlyContinue
  $b = Get-Content $realManifest -Raw -ErrorAction SilentlyContinue
  $lines += ("  repo xml length: {0}" -f $a.Length)
  $lines += ("  real manifest length: {0}" -f $b.Length)
  $lines += ("  identical: {0}" -f ($a -eq $b))
  $na = ([regex]::Matches($a, '<Identity ')).Count
  $nb = ([regex]::Matches($b, '<Identity ')).Count
  $lines += "  Identity elements: repo=$na real=$nb"
  $lines += ""
  $lines += "  --- repo xml first 1200 chars ---"
  $lines += $a.Substring(0, [Math]::Min(1200, $a.Length))
  $lines += ""
  $lines += "  --- real manifest first 1200 chars ---"
  $lines += $b.Substring(0, [Math]::Min(1200, $b.Length))
}

$lines += ""
$lines += "=== 2. Copy the LKG.SpeechRuntime manifest out for inspection ==="
$lkgXml = Join-Path $repo 'MicrosoftWindows.LKG.SpeechRuntime_1000.26100.3775.0_x64__cw5n1h2txyewy.xml'
$lines += "  source exists: $(Test-Path $lkgXml)"
if (Test-Path $lkgXml) {
  Copy-Item $lkgXml 'C:\hidisp\LKG.SpeechRuntime.manifest.xml' -Force
  $c = Get-Content $lkgXml -Raw
  $lines += ("  length: {0}" -f $c.Length)
  $lines += "  --- full content ---"
  $lines += $c
}

$lines += ""
$lines += "=== 3. What files does the SpeechRuntime component payload provide? ==="
$comp = 'C:\Windows\WinSxS\amd64_microsoft-onecore-s..chservice-component_31bf3856ad364e35_10.0.26100.8521_none_4956195b3bec2813'
Get-ChildItem $comp -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $lines += ("  {0,-45} {1,12:N0}" -f $_.Name, $_.Length)
}

$lines += ""
$lines += "=== 4. Current ACL/owner of an existing LKG package folder vs a healthy one ==="
foreach ($p in 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy','C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy') {
  $lines += "  --- $p"
  $exists = Test-Path $p
  $lines += "     exists: $exists"
  if ($exists) {
    $acl = Get-Acl $p -ErrorAction SilentlyContinue
    if ($acl) {
      $lines += ("     owner: {0}" -f $acl.Owner)
      $acl.Access | Select-Object -First 8 | ForEach-Object {
        $lines += ("     ace: {0} {1} {2}" -f $_.IdentityReference, $_.FileSystemRights, $_.AccessControlType)
      }
    }
  }
}

$lines += ""
$lines += "=== 5. Find the ISO robustly (handles non-ASCII path) ==="
$isoDirs = @(Get-ChildItem '.' -Directory -ErrorAction SilentlyContinue)
foreach ($d in $isoDirs) { $lines += "  . }
$found = @()
foreach ($d in $isoDirs) {
  $sub = @(Get-ChildItem $d.FullName -Directory -ErrorAction SilentlyContinue)
  foreach ($s in $sub) { $lines += "  $($s.FullName)" }
}
$isos = @(Get-ChildItem '.' -Recurse -Depth 3 -Filter '*.iso' -ErrorAction SilentlyContinue)
$lines += "  ISO files found: $($isos.Count)"
$isos | ForEach-Object { $lines += ("    {0}  ({1:N2} GB)" -f $_.FullName, ($_.Length/1GB)) }

$lines += ""
$lines += "=== DONE $(Get-Date -Format s) ==="
$lines | Set-Content -Path $out -Encoding UTF8
