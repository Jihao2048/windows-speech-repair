#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 11 语音键入（Win+H）故障一键诊断与自动修复脚本

.DESCRIPTION
    适用于「按 Win+H 面板弹出但一直转圈、永远不出字」的故障。
    脚本会依次完成：故障判定 -> 原因定位 -> 自动修复 -> 验证，共 8 个阶段。

    主要覆盖的原因：
      1. 在线语音识别开关未开启
      2. 麦克风隐私授权被拒
      3. SystemApps\LKG 下的系统应用包（含语音引擎 SpeechRuntime）文件被清理工具清空
      4. 语音引擎包的用户注册状态异常（pending removal）
      5. Windows 更新被封锁导致无法修复系统

.PARAMETER IsoPath
    用于提取语音引擎的 Windows 11 ISO 路径。省略时脚本会自动扫描各磁盘寻找。

.PARAMETER Auto
    全自动模式：跳过所有交互确认，直接执行修复。

.PARAMETER DiagnoseOnly
    只诊断不修复。

.PARAMETER SkipDism
    跳过耗时的 DISM 组件存储修复。

.PARAMETER LogDir
    日志与备份输出目录，默认为脚本所在目录下的 SpeechFix_<时间戳>。

.EXAMPLE
    .\Fix-Win11VoiceTyping.ps1
    交互式运行，逐项确认。

.EXAMPLE
    .\Fix-Win11VoiceTyping.ps1 -Auto -IsoPath "D:\win11.iso"
    全自动运行，指定 ISO。

.NOTES
    需要管理员权限。建议执行前创建系统还原点。
    修改系统文件与注册表前，脚本会自动备份到日志目录。
#>

[CmdletBinding()]
param(
    [string]$IsoPath,
    [switch]$Auto,
    [switch]$DiagnoseOnly,
    [switch]$SkipDism,
    [string]$LogDir
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ============================================================================
#  全局状态
# ============================================================================
$script:Root       = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:TimeStamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogDir     = if ($LogDir) { $LogDir } else { Join-Path $script:Root "SpeechFix_$($script:TimeStamp)" }
$script:Report     = New-Object System.Collections.ArrayList
$script:Findings   = [ordered]@{}
$script:IsAdmin    = $false
$script:Utf8Bom    = New-Object System.Text.UTF8Encoding($true)

$script:LkgPath        = 'C:\Windows\SystemApps\LKG'
$script:SpeechPkgName  = 'MicrosoftWindows.LKG.SpeechRuntime'
$script:ExpectedFiles  = @{
    'MicrosoftWindows.LKG.SpeechRuntime'      = 22
    'MicrosoftWindows.LKG.AccountsService'    = 13
    'MicrosoftWindows.LKG.DesktopSpotlight'   = 21
    'MicrosoftWindows.LKG.IrisService'        = 13
    'MicrosoftWindows.LKG.RulesEngine'        = 12
    'MicrosoftWindows.LKG.TwinSxS'            = 12
}

# ============================================================================
#  输出工具
# ============================================================================
function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    [void]$script:Report.Add("`n=== $Text ===")
}

function Write-Step {
    param([string]$Text)
    Write-Host "  -> $Text" -ForegroundColor White
    [void]$script:Report.Add("  $Text")
}

function Write-Ok {
    param([string]$Text)
    Write-Host "     [OK] $Text" -ForegroundColor Green
    [void]$script:Report.Add("     [OK] $Text")
}

function Write-Bad {
    param([string]$Text)
    Write-Host "     [!!] $Text" -ForegroundColor Red
    [void]$script:Report.Add("     [!!] $Text")
}

function Write-Warn2 {
    param([string]$Text)
    Write-Host "     [??] $Text" -ForegroundColor Yellow
    [void]$script:Report.Add("     [??] $Text")
}

function Write-Info {
    param([string]$Text)
    Write-Host "          $Text" -ForegroundColor Gray
    [void]$script:Report.Add("          $Text")
}

function Confirm-Action {
    param([string]$Question, [switch]$DefaultYes)
    if ($Auto) { return $true }
    $hint = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    Write-Host ''
    Write-Host "  $Question $hint " -ForegroundColor Magenta -NoNewline
    $ans = Read-Host
    if ([string]::IsNullOrWhiteSpace($ans)) { return [bool]$DefaultYes }
    return ($ans -match '^[Yy]')
}

function Save-Text {
    param([string]$Name, [string]$Content)
    $p = Join-Path $script:LogDir $Name
    [System.IO.File]::WriteAllText($p, $Content, $script:Utf8Bom)
}

function Invoke-Exe {
    param([string]$File, [string[]]$Arguments)
    try {
        $out = & $File @Arguments 2>&1 | Out-String
        return $out
    } catch {
        return "EXEC FAILED: $($_.Exception.Message)"
    }
}

function Get-FileCount {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return -1 }
    return @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue).Count
}

# ============================================================================
#  阶段 0：环境检查
# ============================================================================
function Stage0-Environment {
    Write-Head '阶段 0/7  环境检查'

    # 管理员权限
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $script:IsAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($script:IsAdmin) { Write-Ok '管理员权限：已获得' }
    else {
        Write-Bad '管理员权限：未获得'
        Write-Info '本脚本需要管理员权限，正在尝试提权重启...'
        if (-not $Auto) {
            Write-Host ''
            Write-Host '  将以管理员身份重新启动本脚本，请在弹出的 UAC 窗口中点"是"。' -ForegroundColor Yellow
            Read-Host '  按回车继续'
        }
        $argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($Auto)       { $argsList += '-Auto' }
        if ($DiagnoseOnly) { $argsList += '-DiagnoseOnly' }
        if ($SkipDism)   { $argsList += '-SkipDism' }
        if ($IsoPath)    { $argsList += @('-IsoPath', "`"$IsoPath`"") }
        if ($LogDir)     { $argsList += @('-LogDir', "`"$LogDir`"") }
        try {
            Start-Process -FilePath 'powershell.exe' -Verb runAs -ArgumentList $argsList
            Write-Host '  已启动提权进程，本窗口可关闭。' -ForegroundColor Green
        } catch {
            Write-Bad "提权失败：$($_.Exception.Message)"
            Write-Host '  请手动右键 PowerShell -> 以管理员身份运行，再执行本脚本。' -ForegroundColor Yellow
            Read-Host '  按回车退出'
        }
        exit
    }

    # 系统版本（部分定制/精简镜像的 ProductName、DisplayVersion 不可靠，按 Build 号纠正）
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $script:OsBuild = "$($cv.CurrentBuild).$($cv.UBR)"
    $bNum = [int]$cv.CurrentBuild

    # 按 Build 号推断 Windows 主版本（Build 号比 ProductName 可靠）
    if     ($bNum -ge 26100) { $major = 'Windows 11' }
    elseif ($bNum -ge 22000) { $major = 'Windows 11' }
    elseif ($bNum -ge 10240) { $major = 'Windows 10' }
    else                     { $major = 'Windows' }

    # 从 ProductName 中提取版本分支（Enterprise / Professional / Home ...）
    $edition = "$($cv.ProductName)".Trim()
    $edition = $edition -replace '(?i)^\s*Windows\s*(11|10|8\.1|8|7)?\s*', ''
    if ([string]::IsNullOrWhiteSpace($edition)) { $edition = 'Unknown Edition' }
    $script:OsName = "$major $edition"

    $script:OsVersion = "$($cv.DisplayVersion)".Trim()
    if ([string]::IsNullOrWhiteSpace($script:OsVersion)) {
        $script:OsVersion = "$($cv.ReleaseId)".Trim()
    }
    if ([string]::IsNullOrWhiteSpace($script:OsVersion)) { $script:OsVersion = "Build $($cv.CurrentBuild)" }

    # 定制镜像中 ProductName 常被改错，此处仅作提示
    if ("$($cv.ProductName)" -match '(?i)Windows 10' -and $bNum -ge 22000) {
        Write-Info "注意：注册表 ProductName 为「$($cv.ProductName)」，但 Build $bNum 属于 $major，已按 Build 号判定"
    }

    Write-Info "系统：$($script:OsName) $($script:OsVersion)  Build $($script:OsBuild)"
    [void]$script:Findings.Add('系统版本', "$($script:OsName) $($script:OsVersion) / Build $($script:OsBuild)")

    if ($bNum -lt 26100) {
        Write-Warn2 '当前系统早于 Windows 11 24H2。本机可能不使用 LKG 语音引擎机制，'
        Write-Info '脚本仍会执行，但第 3 节的判定可能不适用。'
    }

    # 日志目录
    if (-not (Test-Path -LiteralPath $script:LogDir)) {
        New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    }
    Write-Info "日志目录：$($script:LogDir)"

    # 还原点提示
    if (-not $Auto -and -not $DiagnoseOnly) {
        if (Confirm-Action '建议先创建系统还原点。现在创建吗？' -DefaultYes) {
            Write-Step '创建系统还原点...'
            try {
                Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
                # 默认 24 小时内已有还原点时会跳过，属正常
                Checkpoint-Computer -Description "SpeechFix $($script:TimeStamp)" -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
                Write-Ok '还原点已创建'
            } catch {
                Write-Warn2 "还原点创建失败（可忽略）：$(($_.Exception.Message -split "`n")[0])"
                Write-Info '可手动执行：Win+R -> sysdm.cpl -> 系统保护 -> 创建'
            }
        } else {
            Write-Info '已跳过还原点创建'
        }
    }
}

# ============================================================================
#  阶段 1：诊断
# ============================================================================
function Stage1-Diagnose {
    Write-Head '阶段 1/7  故障诊断'

    $needFix  = $false     # 是否需要跑修复流程
    $causeLkg = $false     # LKG 包被清空
    $causeCns = $false     # 在线语音识别未开启
    $causeMic = $false     # 麦克风授权异常
    $causeReg = $false     # 注册状态异常

    # ---- 1.1 LKG 系统应用包文件数（最关键） ----
    Write-Step '1.1  检查 SystemApps\LKG 系统应用包文件完整性'
    if (-not (Test-Path -LiteralPath $script:LkgPath)) {
        Write-Warn2 'LKG 目录不存在；本系统可能不使用该机制'
        [void]$script:Findings.Add('LKG目录', '不存在')
    } else {
        $emptyPkgs = @()
        foreach ($d in Get-ChildItem -LiteralPath $script:LkgPath -Directory -ErrorAction SilentlyContinue) {
            $n = Get-FileCount $d.FullName
            $exp = 0
            $shortName = $d.Name -replace '_cw5n1h2txyewy$', ''
            if ($script:ExpectedFiles.ContainsKey($shortName)) { $exp = $script:ExpectedFiles[$shortName] }

            if ($n -eq 0) {
                Write-Bad "$($d.Name)  文件数=0  <== 包已被清空"
                $emptyPkgs += $d.Name
                if ($shortName -eq $script:SpeechPkgName) { $causeLkg = $true }
            } elseif ($n -lt 5) {
                Write-Warn2 "$($d.Name)  文件数=$n  (异常偏少)"
                $emptyPkgs += $d.Name
                if ($shortName -eq $script:SpeechPkgName) { $causeLkg = $true }
            } else {
                Write-Ok "$($d.Name)  文件数=$n  (正常值 $exp)"
            }
        }
        [void]$script:Findings.Add('LKG空包数', $emptyPkgs.Count)
        if ($emptyPkgs.Count -gt 0) { $needFix = $true }
    }

    # ---- 1.2 语音引擎关键文件 ----
    Write-Step '1.2  检查语音引擎关键文件'
    $srDir = Join-Path $script:LkgPath "$($script:SpeechPkgName)_cw5n1h2txyewy"
    $keyFiles = @(
        'Microsoft.CognitiveServices.Speech.extension.embedded.sr.runtime.dll',
        'Microsoft.CognitiveServices.Speech.extension.onnxruntime.dll',
        'resources.pri'
    )
    if (Test-Path -LiteralPath $srDir) {
        foreach ($k in $keyFiles) {
            if (Test-Path -LiteralPath (Join-Path $srDir $k)) { Write-Ok $k }
            else { Write-Bad "$k  <== 缺失"; $causeLkg = $true; $needFix = $true }
        }
    } else {
        Write-Bad "语音引擎包目录不存在：$srDir"
        $causeLkg = $true; $needFix = $true
    }

    # ---- 1.3 在线语音识别开关 ----
    Write-Step '1.3  检查在线语音识别开关（Win+H 的必要条件）'
    $cnKey = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\PrivacyPolicy'
    $hasAcc = (Get-ItemProperty $cnKey -ErrorAction SilentlyContinue).HasAccepted
    if ($hasAcc -eq 1) { Write-Ok 'HasAccepted = 1（已开启）' }
    else {
        Write-Bad "HasAccepted = $hasAcc  <== 未开启"
        $causeCns = $true; $needFix = $true
    }
    [void]$script:Findings.Add('在线语音识别', $hasAcc)

    # ---- 1.4 麦克风隐私授权 ----
    Write-Step '1.4  检查麦克风隐私授权'
    $mk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
    $mv = (Get-ItemProperty $mk -ErrorAction SilentlyContinue).Value
    if ($mv -eq 'Allow') { Write-Ok '全局麦克风访问：Allow' }
    else { Write-Warn2 "全局麦克风访问：$mv  <== 建议设为 Allow"; $causeMic = $true; $needFix = $true }
    [void]$script:Findings.Add('麦克风授权', $mv)

    # ---- 1.5 语言能力与语言包 ----
    Write-Step '1.5  检查语音语言能力与语言包'
    try {
        $caps = Get-WindowsCapability -Online -ErrorAction Stop |
                Where-Object { $_.Name -match 'Language\.Speech' -and $_.State -eq 'Installed' }
        if ($caps) { $caps | ForEach-Object { Write-Ok "语言能力：$($_.Name)" } }
        else { Write-Bad '没有任何 Language.Speech 语言能力被安装'; $needFix = $true }
    } catch { Write-Warn2 "语言能力检查失败：$(($_.Exception.Message -split "`n")[0])" }

    $langPkgs = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Speech\.|Voice\.' })
    if ($langPkgs) { $langPkgs | ForEach-Object { Write-Ok "语言包：$($_.Name)  $($_.Version)" } }
    else { Write-Bad '未找到语音语言包'; $needFix = $true }

    # ---- 1.6 包注册状态 ----
    Write-Step '1.6  检查语音引擎包的注册状态'
    $all = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -eq $script:SpeechPkgName }
    if ($all) {
        Write-Info "包：$($all.PackageFullName)"
        Write-Info "状态：$($all.Status)"
        $pending = @($all.PackageUserInformation | Where-Object { $_.InstallState -like '*pending removal*' })
        if ($pending.Count -gt 0) {
            Write-Bad "存在 $($pending.Count) 条 pending removal 登记  <== 需清除"
            $causeReg = $true; $needFix = $true
        } else {
            Write-Ok '无 pending removal 登记'
        }
    } else {
        Write-Warn2 '未找到 SpeechRuntime 包（可能是较旧系统）'
    }
    $mine = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
    Write-Info "当前用户已注册的 LKG 包数量：$($mine.Count)"

    # ---- 1.7 网络与语音服务连通性 ----
    Write-Step '1.7  检查微软语音服务连通性'
    foreach ($h in 'speech.platform.bing.com', 'www.microsoft.com') {
        try {
            $ips = [System.Net.Dns]::GetHostAddresses($h) | ForEach-Object { $_.IPAddressToString }
            Write-Ok "$h -> $(($ips | Select-Object -First 2) -join ', ')"
        } catch { Write-Bad "$h -> DNS 解析失败"; $needFix = $true }
    }

    # ---- 1.8 hosts 与代理 ----
    Write-Step '1.8  检查 hosts 与代理设置'
    $hosts = 'C:\Windows\System32\drivers\etc\hosts'
    $bad = @(Get-Content $hosts -ErrorAction SilentlyContinue |
             Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' })
    if ($bad.Count -eq 0) { Write-Ok 'hosts 无自定义条目' }
    else { Write-Warn2 "hosts 有 $($bad.Count) 条自定义条目（若含 microsoft/speech 域名需处理）"; $bad | ForEach-Object { Write-Info $_ } }

    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($ie.ProxyEnable -eq 1) { Write-Warn2 "系统代理已启用：$($ie.ProxyServer)"; $causeMic = $causeMic }
    else { Write-Ok '系统代理未启用' }

    # ---- 1.9 语音键入界面组件 ----
    Write-Step '1.9  检查语音键入界面组件'
    $ui = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'InpApp|Voiess|Speion' })
    if ($ui) { $ui | ForEach-Object { Write-Ok "$($_.Name)  $($_.Version)  $($_.Status)" } }
    else { Write-Bad '未找到语音键入界面组件  <== 组件可能损坏'; $needFix = $true }

    # ---- 1.10 Windows 更新与累积更新 ----
    Write-Step '1.10 检查 Windows 更新状态'
    $wu = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($wu) {
        if ($wu.StartType -eq 'Disabled') { Write-Bad "wuauserv 已禁用  <== DISM 将没有修复源"; $needFix = $true }
        else { Write-Ok "wuauserv：$($wu.Status) / $($wu.StartType)" }
    }
    $gpc = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache'
    if (Test-Path $gpc) {
        $badWsus = Get-ChildItem $gpc -Recurse -ErrorAction SilentlyContinue |
                   ForEach-Object { @(Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).PSObject.Properties |
                       Where-Object { $_.Name -match 'WUServer|UpdateServiceUrlAlternate' -and $_.Value -match 'localdomain|localserver' } }
        if ($badWsus) { Write-Bad '发现 WUB 残留的假更新服务器地址  <== 需清除'; $needFix = $true }
        else { Write-Ok '无 WUB 残留' }
    }

    # ---- 诊断汇总 ----
    Write-Head '诊断结论'
    $causes = @()
    if ($causeLkg) { $causes += '语音引擎文件缺失（SystemApps\LKG 包被清空）' }
    if ($causeCns) { $causes += '在线语音识别未开启' }
    if ($causeMic) { $causes += '麦克风授权或代理设置异常' }
    if ($causeReg) { $causes += '包注册状态异常（pending removal）' }

    if ($causes.Count -eq 0) {
        Write-Ok '未发现明显问题。'
        Write-Info '若 Win+H 仍转圈，建议执行阶段 5 的 DISM 组件存储修复，'
        Write-Info '或直接采用就地修复安装（见脚本结尾提示）。'
    } else {
        Write-Bad "发现 $($causes.Count) 项问题："
        $causes | ForEach-Object { Write-Info "- $_" }
    }
    [void]$script:Findings.Add('判定原因', ($causes -join '; '))

    # 保存诊断日志
    $diag = @()
    $diag += "诊断时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $diag += "系统：$($script:OsName) $($script:OsVersion) Build $($script:OsBuild)"
    $diag += ''
    foreach ($k in $script:Findings.Keys) { $diag += ("{0}: {1}" -f $k, $script:Findings[$k]) }
    $diag += ''
    $diag += '--- LKG 包文件数 ---'
    if (Test-Path -LiteralPath $script:LkgPath) {
        foreach ($d in Get-ChildItem -LiteralPath $script:LkgPath -Directory -ErrorAction SilentlyContinue) {
            $diag += ("{0} = {1}" -f $d.Name, (Get-FileCount $d.FullName))
        }
    }
    Save-Text 'diagnose.txt' ($diag -join "`r`n")
    Write-Info "诊断结果已保存：$(Join-Path $script:LogDir 'diagnose.txt')"

    return $needFix
}

# ============================================================================
#  阶段 2：基础修复（注册表 / 授权）
# ============================================================================
function Stage2-BasicFix {
    Write-Head '阶段 2/7  基础修复（注册表与授权）'

    # 2.1 在线语音识别
    $cnKey = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\PrivacyPolicy'
    $hasAcc = (Get-ItemProperty $cnKey -ErrorAction SilentlyContinue).HasAccepted
    if ($hasAcc -ne 1) {
        if (Confirm-Action '开启"在线语音识别"？' -DefaultYes) {
            Write-Step '写入 HasAccepted = 1 ...'
            try {
                if (-not (Test-Path $cnKey)) { New-Item -Path $cnKey -Force | Out-Null }
                New-ItemProperty -Path $cnKey -Name 'HasAccepted' -PropertyType DWord -Value 1 -Force | Out-Null
                $v = (Get-ItemProperty $cnKey).HasAccepted
                if ($v -eq 1) { Write-Ok '在线语音识别已开启' } else { Write-Bad "写入失败，当前值 $v" }
            } catch { Write-Bad "写入失败：$($_.Exception.Message)" }
        } else { Write-Info '已跳过' }
    } else { Write-Ok '在线语音识别已是开启状态，无需处理' }

    # 2.2 麦克风授权
    $mk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
    $mv = (Get-ItemProperty $mk -ErrorAction SilentlyContinue).Value
    if ($mv -ne 'Allow') {
        if (Confirm-Action '将全局麦克风访问设为 Allow？' -DefaultYes) {
            try {
                if (-not (Test-Path $mk)) { New-Item -Path $mk -Force | Out-Null }
                Set-ItemProperty -Path $mk -Name 'Value' -Value 'Allow' -Force
                Write-Ok '麦克风授权已设为 Allow'
            } catch { Write-Bad "设置失败：$($_.Exception.Message)" }
        } else { Write-Info '已跳过' }
    } else { Write-Ok '麦克风授权已是 Allow，无需处理' }

    # 2.3 WUB 残留策略
    $policies = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\ScheduledInstallDay'
    )
    $found = @($policies | Where-Object { Test-Path $_ })
    if ($found.Count -gt 0) {
        Write-Warn2 "发现 $($found.Count) 个 Windows 更新策略键（可能来自 WUB 等工具）"
        $found | ForEach-Object { Write-Info $_ }
        if (Confirm-Action '备份并删除这些策略键，恢复 Windows 更新？' -DefaultYes) {
            Write-Step '备份策略键...'
            foreach ($k in $found) {
                $name = ($k -replace '.*\\', '') + '.reg'
                $bak = Join-Path $script:LogDir "backup_$name"
                $regPath = $k -replace '^HKLM:', 'HKLM'
                [void](Invoke-Exe 'reg' @('export', $regPath, $bak, '/y'))
            }
            Write-Ok "已备份到 $($script:LogDir)"
            Write-Step '删除策略键...'
            foreach ($k in ($found | Sort-Object -Descending)) {
                $regPath = $k -replace '^HKLM:', 'HKLM'
                $r = Invoke-Exe 'reg' @('delete', $regPath, '/f')
                if ($r -match '成功|success') { Write-Ok "已删除 $regPath" } else { Write-Warn2 "删除返回：$(($r -split "`n")[0].Trim())" }
            }
        } else { Write-Info '已跳过' }
    } else { Write-Ok '无 Windows 更新策略键残留' }

    # 2.4 WUB 策略缓存（导致 0x80072EE6 的关键）
    $gpc = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache'
    if (Test-Path $gpc) {
        $t = @(Get-ChildItem $gpc -Recurse -ErrorAction SilentlyContinue)
        if ($t.Count -gt 0) {
            Write-Warn2 "发现更新策略缓存 GPCache（$($t.Count) 项）"
            if (Confirm-Action '备份并清除该缓存（修复 0x80072EE6）？' -DefaultYes) {
                $bak = Join-Path $script:LogDir 'backup_GPCache.reg'
                [void](Invoke-Exe 'reg' @('export', 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache', $bak, '/y'))
                Write-Ok "已备份到 $bak"
                $r = Invoke-Exe 'reg' @('delete', 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache', '/f')
                if (-not (Test-Path $gpc)) { Write-Ok 'GPCache 已清除' } else { Write-Warn2 "清除返回：$(($r -split "`n")[0].Trim())" }
            } else { Write-Info '已跳过' }
        } else { Write-Ok 'GPCache 为空' }
    }

    # 2.5 恢复并重启 Windows 更新服务
    Write-Step '恢复并重启 Windows 更新相关服务...'
    $svcs = @{
        'wuauserv'  = 2
        'BITS'      = 3
        'UsoSvc'    = 2
        'DoSvc'     = 2
        'cryptsvc'  = 2
        'TrustedInstaller' = 3
    }
    foreach ($n in $svcs.Keys) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if (-not $s) { Write-Warn2 "$n 不存在，跳过"; continue }
        try {
            if ($s.StartType -eq 'Disabled') {
                Set-Service -Name $n -StartupType $(if ($svcs[$n] -eq 2) { 'Automatic' } else { 'Manual' }) -ErrorAction Stop
                Write-Ok "$n 启动类型已恢复为 $(if ($svcs[$n] -eq 2) { 'Automatic' } else { 'Manual' })"
            }
            if ($s.Status -ne 'Running' -and $n -ne 'TrustedInstaller') {
                Start-Service -Name $n -ErrorAction SilentlyContinue
            }
        } catch { Write-Warn2 "$n 处理失败：$(($_.Exception.Message -split "`n")[0])" }
    }

    # 2.6 清除 pending removal 标记
    Write-Step '检查并清除包的 pending removal 登记...'
    $all = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $script:SpeechPkgName }
    if ($all) {
        $pending = @($all.PackageUserInformation | Where-Object { $_.InstallState -like '*pending removal*' })
        if ($pending.Count -gt 0) {
            Write-Info '尝试通过一次移除操作清除标记（报"Windows 的一部分，无法卸载"属正常）'
            try {
                Remove-AppxPackage -Package $all.PackageFullName -AllUsers -ErrorAction Stop
                Write-Ok '移除操作完成'
            } catch {
                $msg = ($_.Exception.Message -split "`n")[0]
                Write-Info "移除返回：$msg"
                $all2 = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $script:SpeechPkgName }
                $pending2 = @($all2.PackageUserInformation | Where-Object { $_.InstallState -like '*pending removal*' })
                if ($pending2.Count -eq 0) { Write-Ok 'pending removal 标记已清除' }
                else { Write-Warn2 "仍有 $($pending2.Count) 条标记；可重启后再试" }
            }
        } else { Write-Ok '无 pending removal 登记，无需处理' }
    } else { Write-Info '未找到 SpeechRuntime 包，跳过' }
}

# ============================================================================
#  阶段 3：定位并提取语音引擎包
# ============================================================================
function Find-WindowsIso {
    Write-Step '自动扫描各磁盘寻找 Windows 11 ISO...'
    $found = @()
    foreach ($drv in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                      Where-Object { $_.Free -ne $null -and $_.Used -gt 0 })) {
        $root = "$($drv.Name):\"
        try {
            $isos = Get-ChildItem -LiteralPath $root -Recurse -Depth 4 -Filter '*.iso' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '(?i)windows|win11|win10|zh-cn|zh-hans' }
            $found += $isos
        } catch { }
    }
    if ($found.Count -eq 0) { return $null }
    $found = $found | Sort-Object Length -Descending
    Write-Info "找到 $($found.Count) 个候选镜像："
    $i = 0
    foreach ($f in $found) {
        $i++
        Write-Info ("  [{0}] {1}  ({2:N2} GB)" -f $i, $f.FullName, ($f.Length / 1GB))
    }
    if ($Auto) { Write-Info "全自动模式：选用 [1] $($found[0].FullName)"; return $found[0].FullName }
    Write-Host ''
    Write-Host '  请选择要使用的镜像编号（回车 = 1，输入 0 = 跳过）： ' -ForegroundColor Magenta -NoNewline
    $sel = Read-Host
    if ([string]::IsNullOrWhiteSpace($sel)) { return $found[0].FullName }
    if ($sel -eq '0') { return $null }
    $idx = 0
    if ([int]::TryParse($sel, [ref]$idx) -and $idx -ge 1 -and $idx -le $found.Count) { return $found[$idx - 1].FullName }
    return $found[0].FullName
}

function Mount-IsoSafe {
    param([string]$Path)
    try {
        $m = Mount-DiskImage -ImagePath $Path -Access ReadOnly -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 4
        $vol = $m | Get-Volume -ErrorAction SilentlyContinue
        return @{ Ok = $true; Drive = $vol.DriveLetter; Image = $m }
    } catch {
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}

function Dismount-IsoSafe {
    param([string]$Path)
    try { Dismount-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue } catch { }
}

function Find-WimInIso {
    param([string]$DriveLetter)
    $root = "${DriveLetter}:\sources"
    foreach ($n in 'install.wim', 'install.esd') {
        $p = Join-Path $root $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Stage3-Extract {
    Write-Head '阶段 3/7  从官方 ISO 提取语音引擎包'

    $iso = $IsoPath
    if (-not $iso -or -not (Test-Path -LiteralPath $iso)) {
        if ($IsoPath) { Write-Warn2 "指定的 ISO 不存在：$IsoPath" }
        $iso = Find-WindowsIso
    }
    if (-not $iso) {
        Write-Bad '未找到可用的 Windows ISO。'
        Write-Info '请从微软官网下载 Windows 11 ISO 后重新运行，并指定路径：'
        Write-Info "  .\$([System.IO.Path]::GetFileName($PSCommandPath)) -IsoPath `"D:\win11.iso`""
        return $false
    }
    Write-Ok "使用镜像：$iso"

    # 挂载 ISO
    Write-Step '挂载 ISO（只读）...'
    $mnt = Mount-IsoSafe $iso
    if (-not $mnt.Ok) { Write-Bad "挂载失败：$($mnt.Error)"; return $false }
    $dl = $mnt.Drive
    if (-not $dl) { Write-Bad '挂载后未获得盘符'; Dismount-IsoSafe $iso; return $false }
    Write-Ok "ISO 挂载于 $dl :"

    $result = $false
    $wimPath = $null
    $wimMount = Join-Path $env:TEMP "SpeechFix_wim_$($script:TimeStamp)"

    try {
        # 找 WIM
        $wimPath = Find-WimInIso $dl
        if (-not $wimPath) { Write-Bad '镜像中未找到 sources\install.wim 或 install.esd'; return $false }
        Write-Ok "镜像文件：$wimPath"

        if ($wimPath -match '\.esd$') {
            Write-Warn2 'install.esd 无法直接挂载，需要先转换为 wim'
            if (-not (Confirm-Action '现在转换为 install.wim？（约需 5-15 分钟）' -DefaultYes)) {
                Write-Info '已取消。可手动转换：'
                Write-Info "  DISM /Export-Image /SourceImageFile:`"$wimPath`" /SourceIndex:2 /DestinationImageFile:D:\install.wim /Compress:max"
                return $false
            }
            $conv = Join-Path $script:LogDir 'install.wim'
            Write-Step '转换 ESD -> WIM ...'
            $out = Invoke-Exe 'dism.exe' @('/Export-Image', "/SourceImageFile:$wimPath", '/SourceIndex:2', "/DestinationImageFile:$conv", '/Compress:max')
            if (Test-Path -LiteralPath $conv) { Write-Ok "转换完成：$conv"; $wimPath = $conv }
            else { Write-Bad '转换失败'; Write-Info (($out -split "`n") | Select-Object -Last 5) -join ' '; return $false }
        }

        # 列出镜像索引
        Write-Step '读取镜像版本列表...'
        $imgs = @()
        try {
            $imgs = @(Get-WindowsImage -ImagePath $wimPath -ErrorAction Stop)
            foreach ($i in $imgs) { Write-Info ("  [{0}] {1}" -f $i.ImageIndex, $i.ImageName) }
        } catch {
            Write-Bad "读取镜像失败：$(($_.Exception.Message -split "`n")[0])"
            return $false
        }
        if ($imgs.Count -eq 0) { Write-Bad '镜像中没有可用版本'; return $false }

        # 选择索引：优先企业版，其次专业版，否则第一个
        $idx = $imgs[0].ImageIndex
        foreach ($pref in '企业版', 'Enterprise', '专业版', 'Professional') {
            $hit = $imgs | Where-Object { $_.ImageName -match $pref } | Select-Object -First 1
            if ($hit) { $idx = $hit.ImageIndex; break }
        }
        Write-Ok "选用索引 $idx（$((($imgs | Where-Object { $_.ImageIndex -eq $idx }).ImageName))）"

        # 挂载 WIM
        Write-Step "只读挂载镜像到 $wimMount ..."
        if (Test-Path -LiteralPath $wimMount) { Remove-Item -LiteralPath $wimMount -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $wimMount -Force | Out-Null
        try {
            Mount-WindowsImage -ImagePath $wimPath -Index $idx -Path $wimMount -ReadOnly -ErrorAction Stop | Out-Null
            Write-Ok '镜像已挂载'
        } catch {
            Write-Bad "挂载失败：$(($_.Exception.Message -split "`n")[0])"
            return $false
        }

        # 检查并复制 LKG 包
        $srcLkg = Join-Path $wimMount 'Windows\SystemApps\LKG'
        if (-not (Test-Path -LiteralPath $srcLkg)) {
            Write-Bad '镜像中不存在 Windows\SystemApps\LKG'; return $false
        }
        Write-Step '镜像中的 LKG 包：'
        foreach ($d in Get-ChildItem -LiteralPath $srcLkg -Directory -ErrorAction SilentlyContinue) {
            Write-Info ("  {0}  ({1} 个文件)" -f $d.Name, (Get-FileCount $d.FullName))
        }

        # 提取到日志目录（备份）
        $extractDir = Join-Path $script:LogDir 'extracted_LKG'
        if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        Write-Step "提取 LKG 包到备份目录 ..."
        foreach ($d in Get-ChildItem -LiteralPath $srcLkg -Directory -ErrorAction SilentlyContinue) {
            Copy-Item -LiteralPath $d.FullName -Destination $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        $exCount = @(Get-ChildItem -LiteralPath $extractDir -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Ok "已提取 $exCount 个文件到 $extractDir"

        # 判断是否需要回填
        $needRestore = @()
        foreach ($d in Get-ChildItem -LiteralPath $srcLkg -Directory -ErrorAction SilentlyContinue) {
            $target = Join-Path $script:LkgPath $d.Name
            $cur = Get-FileCount $target
            $ref = Get-FileCount $d.FullName
            if ($cur -lt $ref) { $needRestore += [pscustomobject]@{ Name = $d.Name; Cur = $cur; Ref = $ref } }
        }

        if ($needRestore.Count -eq 0) {
            Write-Ok '系统内的 LKG 包文件均完整，无需回填'
            $result = $true
        } else {
            Write-Warn2 "有 $($needRestore.Count) 个包需要回填："
            $needRestore | ForEach-Object { Write-Info ("  {0}  当前 {1} -> 应有 {2}" -f $_.Name, $_.Cur, $_.Ref) }

            if (Confirm-Action '现在把这些文件回填到 C:\Windows\SystemApps\LKG ？' -DefaultYes) {
                Write-Step '备份系统现有包目录 ...'
                $sysBak = Join-Path $script:LogDir 'before_restore_backup'
                New-Item -ItemType Directory -Path $sysBak -Force | Out-Null
                foreach ($d in Get-ChildItem -LiteralPath $script:LkgPath -Directory -ErrorAction SilentlyContinue) {
                    Copy-Item -LiteralPath $d.FullName -Destination $sysBak -Recurse -Force -ErrorAction SilentlyContinue
                }
                Write-Ok "已备份"

                Write-Step '回填文件 ...'
                foreach ($item in $needRestore) {
                    $src = Join-Path $srcLkg $item.Name
                    $dst = Join-Path $script:LkgPath $item.Name
                    if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
                    Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
                    $now = Get-FileCount $dst
                    if ($now -ge $item.Ref) { Write-Ok "$($item.Name)  已还原 $now 个文件" }
                    else { Write-Warn2 "$($item.Name)  仅 $now / $($item.Ref) 个文件" }
                }

                Write-Step '设置属主为 TrustedInstaller（与正常系统包一致）...'
                foreach ($d in Get-ChildItem -LiteralPath $script:LkgPath -Directory -ErrorAction SilentlyContinue) {
                    [void](Invoke-Exe 'icacls.exe' @($d.FullName, '/setowner', 'NT SERVICE\TrustedInstaller', '/T', '/C', '/Q'))
                }
                Write-Ok '属主设置完成'
                $result = $true
            } else { Write-Info '已跳过回填' }
        }
    } finally {
        # 卸载 WIM 与 ISO
        Write-Step '卸载临时挂载...'
        if (Test-Path -LiteralPath $wimMount) {
            try { Dismount-WindowsImage -Path $wimMount -Discard -ErrorAction Stop; Write-Ok 'WIM 已卸载' }
            catch { Write-Warn2 "WIM 卸载失败：$(($_.Exception.Message -split "`n")[0])" }
            Remove-Item -LiteralPath $wimMount -Recurse -Force -ErrorAction SilentlyContinue
        }
        Dismount-IsoSafe $iso
        Write-Ok 'ISO 已卸载'
    }
    return $result
}

# ============================================================================
#  阶段 4：尝试注册（尽力而为）
# ============================================================================
function Stage4-Register {
    Write-Head '阶段 4/7  尝试注册语音引擎包'

    $srDir = Join-Path $script:LkgPath "$($script:SpeechPkgName)_cw5n1h2txyewy"
    $mf = Join-Path $srDir 'AppxManifest.xml'
    if (-not (Test-Path -LiteralPath $mf)) { $mf = Join-Path $srDir 'appxmanifest.xml' }
    if (-not (Test-Path -LiteralPath $mf)) { Write-Warn2 '找不到包清单，跳过本阶段'; return }

    Write-Info '提示：Windows 内置包通常不允许按用户重新注册，失败属正常现象。'
    Write-Info '实测中仅还原文件 + 开启在线语音识别 + 重启，功能即可恢复。'
    Write-Host ''

    # 方式 A：不带 -DisableDevelopmentMode（本机实测该参数可能全局失效）
    Write-Step '方式 A：Add-AppxPackage -Register（不带 -DisableDevelopmentMode）'
    try {
        Add-AppxPackage -Register $mf -ErrorAction Stop
        Write-Ok '注册成功'
        return
    } catch {
        $msg = ($_.Exception.Message -split "`n")[0]
        Write-Info "返回：$msg"
        if ($msg -match '0x80073CFB') {
            Write-Warn2 '0x80073CFB = 已有打包版本，散装版本无法替换；这属系统规则，不必强求'
        } elseif ($msg -match '0x80073CF9') {
            Write-Warn2 '0x80073CF9 = 部署路径异常（该参数在本机可能失效，已避开）'
        }
    }

    # 方式 B：强制更新
    Write-Step '方式 B：加上 -ForceUpdateFromAnyVersion'
    try {
        Add-AppxPackage -Register $mf -ForceUpdateFromAnyVersion -ErrorAction Stop
        Write-Ok '注册成功'
        return
    } catch {
        Write-Info "返回：$(($_.Exception.Message -split "`n")[0])"
    }

    # 方式 C：按家族名注册
    Write-Step '方式 C：RegisterByFamilyName'
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage "$($script:SpeechPkgName)_cw5n1h2txyewy" -ErrorAction Stop
        Write-Ok '注册成功'
        return
    } catch {
        Write-Info "返回：$(($_.Exception.Message -split "`n")[0])"
    }

    Write-Warn2 '三种注册方式均未成功，这在实测案例中属正常。'
    Write-Info '功能恢复不依赖注册成功，请继续执行后续阶段并重启实测。'
}

# ============================================================================
#  阶段 5：组件存储修复（可选）
# ============================================================================
function Stage5-Dism {
    Write-Head '阶段 5/7  组件存储修复（DISM）'

    if ($SkipDism) { Write-Info '已通过 -SkipDism 跳过'; return }

    # 先确认 Windows 更新可用
    $wu = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($wu.StartType -eq 'Disabled') { Set-Service wuauserv -StartupType Manual -ErrorAction SilentlyContinue }
    if ($wu.Status -ne 'Running') { Start-Service wuauserv -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2

    $wuOk = $false
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $r = $searcher.Search("IsInstalled=0 and Type='Software'")
        Write-Ok "Windows 更新可用，检索到 $($r.Updates.Count) 个待安装项"
        $wuOk = $true
    } catch {
        Write-Bad "Windows 更新不可用：$(($_.Exception.Message -split "`n")[0])"
        Write-Info 'DISM 将缺少修复源，很可能报 0x800f0915。建议先处理更新问题。'
    }

    if (-not (Confirm-Action '执行 DISM 组件存储修复？（可能需要 10-60 分钟，且会下载数 GB 数据）' -DefaultYes)) {
        Write-Info '已跳过'
        return
    }

    Write-Step 'DISM /ScanHealth'
    $scan = Invoke-Exe 'dism.exe' @('/Online', '/Cleanup-Image', '/ScanHealth')
    $scanOk = $scan -match '可以修复组件存储|No component store corruption'
    ($scan -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 3) | ForEach-Object { Write-Info $_.Trim() }

    if (-not $scanOk) {
        Write-Ok '组件存储健康，无需修复'
        return
    }
    Write-Warn2 '组件存储存在可修复的损坏'
    Write-Info '说明：部分组件的修复源缺失时，RestoreHealth 可能仍然失败（0x800f0915）。'

    if (-not $wuOk) {
        Write-Warn2 'Windows 更新不可用，RestoreHealth 大概率失败。'
        if (-not (Confirm-Action '仍要继续尝试？' -DefaultYes)) { Write-Info '已跳过'; return }
    }

    Write-Step 'DISM /RestoreHealth（耗时较长，请耐心等待）...'
    $journal = Join-Path $script:LogDir 'dism_restorehealth.log'
    $proc = Start-Process -FilePath 'dism.exe' `
            -ArgumentList '/Online', '/Cleanup-Image', '/RestoreHealth' `
            -RedirectStandardOutput $journal -NoNewWindow -PassThru -ErrorAction SilentlyContinue
    if ($proc) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $proc.HasExited) {
            Start-Sleep -Seconds 15
            $el = [int]$sw.Elapsed.TotalMinutes
            Write-Host ("`r          已运行 {0} 分钟...（详见 dism_restorehealth.log）" -f $el) -ForegroundColor Gray -NoNewline
            if ($el -gt 90) { Write-Warn2 '超时 90 分钟，停止等待'; break }
        }
        Write-Host ''
    } else {
        [void](Invoke-Exe 'dism.exe' @('/Online', '/Cleanup-Image', '/RestoreHealth'))
    }

    $log = ''
    if (Test-Path -LiteralPath $journal) {
        $log = [System.IO.File]::ReadAllText($journal, [System.Text.Encoding]::Unicode)
        if (-not $log) { $log = [System.IO.File]::ReadAllText($journal) }
    }
    if ($log -match '操作成功完成' -and $log -notmatch '错误: 0x') {
        Write-Ok '组件存储修复成功'
    } elseif ($log -match '0x800f0915') {
        Write-Bad '修复失败：找不到修复内容（0x800f0915）'
        Write-Info '说明系统部分组件缺少可用修复源，建议采用就地修复安装。'
    } else {
        Write-Warn2 '修复结果不明确，请查看 dism_restorehealth.log'
    }

    Write-Step 'DISM /CheckHealth 复核'
    $chk = Invoke-Exe 'dism.exe' @('/Online', '/Cleanup-Image', '/CheckHealth')
    ($chk -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 3) | ForEach-Object { Write-Info $_.Trim() }
}

# ============================================================================
#  阶段 6：重启输入进程
# ============================================================================
function Stage6-RestartInput {
    Write-Head '阶段 6/7  重启输入体验进程'

    foreach ($n in 'TextInputHost') {
        $p = Get-Process -Name $n -ErrorAction SilentlyContinue
        if ($p) {
            Write-Step "重启 $n ..."
            try {
                $p | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Write-Ok "$n 已停止，下次按 Win+H 时会自动重新启动"
            } catch { Write-Warn2 "无法停止 $n：$($_.Exception.Message)" }
        } else {
            Write-Info "$n 未在运行（正常）"
        }
    }
}

# ============================================================================
#  阶段 7：验证与报告
# ============================================================================
function Stage7-Verify {
    Write-Head '阶段 7/7  验证与生成报告'

    $pass = 0; $fail = 0

    # 7.1 LKG 文件完整性
    Write-Step '7.1  LKG 系统应用包文件完整性'
    if (Test-Path -LiteralPath $script:LkgPath) {
        foreach ($d in Get-ChildItem -LiteralPath $script:LkgPath -Directory -ErrorAction SilentlyContinue) {
            $n = Get-FileCount $d.FullName
            if ($n -gt 0) { Write-Ok "$($d.Name)  $n 个文件"; $pass++ }
            else { Write-Bad "$($d.Name)  仍为空"; $fail++ }
        }
    }

    # 7.2 语音引擎关键文件
    Write-Step '7.2  语音引擎关键文件'
    $srDir = Join-Path $script:LkgPath "$($script:SpeechPkgName)_cw5n1h2txyewy"
    foreach ($k in 'Microsoft.CognitiveServices.Speech.extension.embedded.sr.runtime.dll',
                   'Microsoft.CognitiveServices.Speech.extension.onnxruntime.dll',
                   'resources.pri', 'appxmanifest.xml', 'appxsignature.p7x') {
        if (Test-Path -LiteralPath (Join-Path $srDir $k)) { Write-Ok $k; $pass++ }
        else { Write-Bad "$k 缺失"; $fail++ }
    }

    # 7.3 在线语音识别
    Write-Step '7.3  在线语音识别开关'
    $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\PrivacyPolicy' -ErrorAction SilentlyContinue).HasAccepted
    if ($v -eq 1) { Write-Ok 'HasAccepted = 1'; $pass++ } else { Write-Bad "HasAccepted = $v"; $fail++ }

    # 7.4 语音界面组件
    Write-Step '7.4  语音键入界面组件'
    $ui = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'InpApp|Voiess|Speion' })
    if ($ui.Count -gt 0) { Write-Ok "$($ui.Count) 个界面组件正常"; $pass++ } else { Write-Bad '界面组件缺失'; $fail++ }

    # 7.5 Windows 更新
    Write-Step '7.5  Windows 更新可用性'
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $r = $searcher.Search("IsInstalled=0 and Type='Software'")
        Write-Ok "可检索更新（$($r.Updates.Count) 项）"; $pass++
    } catch { Write-Bad "更新不可用：$(($_.Exception.Message -split "`n")[0])"; $fail++ }

    # 7.6 累积更新是否安装失败
    Write-Step '7.6  累积更新历史（结果码 0x4 = 失败）'
    try {
        $s2 = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $n2 = $s2.GetTotalHistoryCount()
        $hist = $s2.QueryHistory(0, [Math]::Min(10, $n2))
        $failedUpd = @($hist | Where-Object { $_.ResultCode -eq 4 })
        if ($failedUpd.Count -eq 0) { Write-Ok '近期无失败的更新安装'; $pass++ }
        else {
            Write-Bad "有 $($failedUpd.Count) 项更新安装失败（组件存储受损的信号）"
            $failedUpd | Select-Object -First 3 | ForEach-Object { Write-Info ("  {0}  {1}" -f $_.Date.ToString('yyyy-MM-dd'), $_.Title) }
            $fail++
        }
    } catch { Write-Warn2 "历史读取失败：$(($_.Exception.Message -split "`n")[0])" }

    # 汇总
    Write-Head '验证汇总'
    Write-Host ("  通过：{0}    未通过：{1}" -f $pass, $fail) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Yellow' })
    [void]$script:Report.Add("`n  通过 $pass 项，未通过 $fail 项")

    # 生成报告
    $rep = @()
    $rep += '# Windows 11 语音键入修复报告'
    $rep += ''
    $rep += "- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $rep += "- 系统：$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName) $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion)"
    $rep += "- 验证通过：$pass 项 / 未通过：$fail 项"
    $rep += ''
    $rep += '## 诊断发现'
    $rep += ''
    foreach ($k in $script:Findings.Keys) { $rep += ("- **{0}**：{1}" -f $k, $script:Findings[$k]) }
    $rep += ''
    $rep += '## 执行日志'
    $rep += ''
    $rep += '```text'
    $rep += ($script:Report -join "`n")
    $rep += '```'
    $rep += ''
    $rep += '## 后续步骤'
    $rep += ''
    $rep += '1. **重启电脑**（必须，让系统重新加载应用包与语音引擎）。'
    $rep += '2. 重启后打开记事本，点进正文，按 `Win+H`，对麦克风说一句话，验证是否出字。'
    $rep += '3. 若仍转圈：'
    $rep += '   - 确认「设置 > 隐私和安全性 > 语音 > 在线语音识别」已开启'
    $rep += '   - 确认「设置 > 隐私和安全性 > 麦克风」已允许'
    $rep += '   - 检查累积更新能否安装；若安装失败（结果码 0x4），'
    $rep += '     说明组件存储损坏，需执行**就地修复安装**：'
    $rep += '     下载与当前系统版本一致的 Windows 11 ISO -> 挂载 -> 运行 setup.exe'
    $rep += '     -> 选择「保留个人文件和应用」。'
    $rep += ''
    $rep += '## 预防'
    $rep += ''
    $rep += '- 不要让第三方安全软件的「系统盘瘦身 / 大文件清理 / 系统急救」处理系统分区。'
    $rep += '- 不要使用来源不明的系统精简 / debloat 脚本。'
    $rep += '- 若用工具关闭了 Windows 更新，日后修复系统会缺少文件源，请谨慎。'

    $repPath = Join-Path $script:LogDir 'report.md'
    [System.IO.File]::WriteAllText($repPath, ($rep -join "`r`n"), $script:Utf8Bom)
    Write-Info "报告已生成：$repPath"

    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Green
    Write-Host '   全部阶段执行完毕。' -ForegroundColor Green
    Write-Host '   请【重启电脑】后按 Win+H 实测。' -ForegroundColor Yellow
    Write-Host "   日志与报告：$($script:LogDir)" -ForegroundColor Gray
    Write-Host '  ============================================================' -ForegroundColor Green
}

# ============================================================================
#  主流程
# ============================================================================
function Main {
    Clear-Host
    Write-Host ''
    Write-Host '  +--------------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host '  |   Windows 11 语音键入 (Win+H) 一键诊断与自动修复              |' -ForegroundColor Cyan
    Write-Host '  |   适用：面板弹出但一直转圈、永远不出字                        |' -ForegroundColor Cyan
    Write-Host '  +--------------------------------------------------------------+' -ForegroundColor Cyan

    if (-not $Auto -and -not $DiagnoseOnly) {
        Write-Host ''
        Write-Host '  本脚本将检查并可能修改：' -ForegroundColor Yellow
        Write-Host '    - 在线语音识别与麦克风隐私开关（当前用户注册表）'
        Write-Host '    - Windows 更新策略键（有备份，可还原）'
        Write-Host '    - C:\Windows\SystemApps\LKG 下的系统应用包文件（有备份）'
        Write-Host ''
        Write-Host '  修改前均会自动备份到日志目录。建议先创建系统还原点。' -ForegroundColor Yellow
        Write-Host ''
        Read-Host '  按回车开始，Ctrl+C 取消'
    }

    Stage0-Environment

    $needFix = Stage1-Diagnose

    if ($DiagnoseOnly) {
        Write-Head '仅诊断模式，未做任何修改'
        Write-Info "诊断日志：$(Join-Path $script:LogDir 'diagnose.txt')"
        Read-Host '  按回车退出'
        return
    }

    if (-not $needFix) {
        Write-Host ''
        Write-Host '  诊断未发现需要修复的问题。是否继续执行完整修复流程（可能包含 DISM）？' -ForegroundColor Yellow
        if (-not (Confirm-Action '继续？' )) {
            Write-Info '已退出。若 Win+H 仍不可用，可尝试 -SkipDism 之外的完整流程或就地修复安装。'
            Write-Info "诊断日志：$(Join-Path $script:LogDir 'diagnose.txt')"
            Read-Host '  按回车退出'
            return
        }
    }

    Stage2-BasicFix

    # 仅当语音引擎文件缺失时才需要提取
    $srDir  = Join-Path $script:LkgPath "$($script:SpeechPkgName)_cw5n1h2txyewy"
    $hasKey = Test-Path -LiteralPath (Join-Path $srDir 'Microsoft.CognitiveServices.Speech.extension.embedded.sr.runtime.dll')
    if (-not $hasKey) {
        if (Confirm-Action '检测到语音引擎文件缺失，现在从官方 ISO 提取并还原？' -DefaultYes) {
            [void](Stage3-Extract)
            Stage4-Register
        } else {
            Write-Info '已跳过引擎还原。'
        }
    } else {
        Write-Ok '语音引擎文件已存在，跳过 ISO 提取阶段'
        Stage4-Register
    }

    Stage5-Dism
    Stage6-RestartInput
    Stage7-Verify

    if (-not $Auto) { Read-Host '  按回车退出' }
}

Main
