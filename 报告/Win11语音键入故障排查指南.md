# Windows 11 语音键入（Win+H）一直转圈不出字？完整排查与修复指南

> 适用系统：Windows 11 24H2 / 25H2（Build 26100 / 26200）
> 症状关键词：`Win+H` 面板弹出但**一直转圈、永远不出字**；麦克风图标点了没反应；
> 麦克风、网络、语言包检查都正常，就是识别不了。
>
> 本文基于一次真实故障的完整排查记录整理，包含**可复制执行**的诊断脚本与修复脚本。
> 同时记录了几个「网上教程都在用、但会把你带进沟里」的常见坑。

---

## 目录

1. [先判断你属于哪一种故障](#一先判断你属于哪一种故障)
2. [五分钟快速诊断（可复制脚本）](#二五分钟快速诊断可复制脚本)
3. [关键根因：SystemApps\LKG 系统应用包被清空](#三关键根因systemappslkg-系统应用包被清空)
4. [为什么 SFC 和 DISM 查不出来](#四为什么-sfc-和-dism-查不出来)
5. [修复方案 A：从官方 ISO 还原缺失的语音引擎](#五修复方案-a从官方-iso-还原缺失的语音引擎)
6. [修复方案 B：就地修复安装（兜底方案）](#六修复方案-b就地修复安装兜底方案)
7. [验证修复结果](#七验证修复结果)
8. [七个常见坑（重点）](#八七个常见坑重点)
9. [如何避免再次发生](#九如何避免再次发生)
10. [附录：错误码对照表与 FAQ](#十附录错误码对照表与-faq)

---

## 一、先判断你属于哪一种故障

Win+H 故障不止一种原因，先按现象分支：

| 现象 | 最可能的原因 | 跳转 |
| --- | --- | --- |
| 面板弹出，**一直转圈、绝不出字**，界面本身正常 | ① 语音引擎文件缺失（LKG 包被清空）② 在线语音识别未开启 ③ 引擎注册损坏 | [方案 A](#五修复方案-a从官方-iso-还原缺失的语音引擎) |
| 提示「出现问题，无法输入你的语音键入文本」 | 网络无法访问微软语音服务、代理/hosts 劫持 | 见 [第 2 节检查项 5](#二五分钟快速诊断可复制脚本) |
| 提示麦克风被禁用 / 无声音输入 | 麦克风隐私授权、默认输入设备 | 见 [第 2 节检查项 4](#二五分钟快速诊断可复制脚本) |
| 按 Win+H **完全没反应**，面板都不弹 | 输入体验组件（TextInputHost / Client.CBS）异常 | 先修复输入组件，或直接用方案 B |
| 只有在某个软件里不出字（如重命名文件时） | 该程序抢占焦点，属正常限制 | 先点中目标输入框，等 1 秒再按 Win+H |

> **重要前提**：从 Windows 11 24H2 起，Win+H 的「语音键入」依赖 **在线语音识别**，
> 并且使用了一套新的「本地 + 神经网络」混合引擎，该引擎以
> **Appx 系统应用包**的形式安装在 `C:\Windows\SystemApps\LKG\` 下。
> 这是本指南与旧教程最大的不同点——**旧教程完全没提这个目录**。

---

## 二、五分钟快速诊断（可复制脚本）

**以管理员身份**打开 PowerShell，整段复制执行：

```powershell
# ============================================================
#  Win+H 语音键入 一键诊断
#  请以管理员身份运行
# ============================================================
$ErrorActionPreference = 'Continue'

function Line($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

Line '1. LKG 系统应用包文件数（最关键，异常项为 0）'
$lkgPath = 'C:\Windows\SystemApps\LKG'
if (Test-Path $lkgPath) {
    Get-ChildItem $lkgPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $n = @(Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count
        $flag = if ($n -eq 0) { '   <== 异常：包被清空！' } else { '' }
        Write-Host ("  {0,-58} {1,4}{2}" -f $_.Name, $n, $flag)
    }
} else {
    Write-Host '  LKG 目录不存在（本系统可能不使用该机制）'
}

Line '2. 语音引擎包注册状态'
$sr = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -eq 'MicrosoftWindows.LKG.SpeechRuntime' }
if ($sr) {
    Write-Host ("  包：{0}  版本：{1}  状态：{2}" -f $sr.Name, $sr.Version, $sr.Status)
    foreach ($u in $sr.PackageUserInformation) { Write-Host ("    用户登记状态：{0}" -f $u.InstallState) }
} else {
    Write-Host '  未找到 SpeechRuntime 包'
}
$mine = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LKG' })
Write-Host ("  当前用户已注册的 LKG 包数量：{0}" -f $mine.Count)

Line '3. 在线语音识别开关（必须是 1）'
$k = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\PrivacyPolicy'
$v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).HasAccepted
Write-Host ("  HasAccepted = {0}   {1}" -f $v, $(if ($v -eq 1) { '正常' } else { '<== 未开启，需开启' }))
Write-Host '  图形界面位置：设置 > 隐私和安全性 > 语音 > 在线语音识别'

Line '4. 麦克风隐私授权'
$mk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
Write-Host ("  全局麦克风访问：{0}" -f (Get-ItemProperty $mk -ErrorAction SilentlyContinue).Value)
Write-Host '  图形界面位置：设置 > 隐私和安全性 > 麦克风'

Line '5. 语音语言能力与语言包'
try {
    Get-WindowsCapability -Online -ErrorAction Stop |
        Where-Object { $_.Name -match 'Language\.Speech' -and $_.State -eq 'Installed' } |
        ForEach-Object { Write-Host ("  已安装：{0}" -f $_.Name) }
} catch { Write-Host '  需要管理员权限' }
Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Speech\.|Voice\.' } |
    ForEach-Object { Write-Host ("  语言包：{0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status) }

Line '6. 网络连通性（微软语音服务）'
foreach ($h in 'speech.platform.bing.com','www.microsoft.com') {
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($h) | ForEach-Object { $_.IPAddressToString }
        Write-Host ("  {0} -> {1}" -f $h, ($ips -join ', '))
    } catch { Write-Host ("  {0} -> DNS 解析失败" -f $h) }
}

Line '7. hosts 与代理（应为空 / 未启用）'
Get-Content 'C:\Windows\System32\drivers\etc\hosts' -ErrorAction SilentlyContinue |
    Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' } |
    ForEach-Object { Write-Host ("  hosts: {0}" -f $_) }
$ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
Write-Host ("  系统代理启用：{0}  服务器：{1}" -f $ie.ProxyEnable, $ie.ProxyServer)

Line '8. 语音键入相关组件'
Get-AppxPackage -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'InpApp|Voiess|Speion|TextInput' } |
    ForEach-Object { Write-Host ("  {0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status) }

Line '诊断结束'
Write-Host '判定标准：' -ForegroundColor Yellow
Write-Host '  第 1 项出现文件数为 0 的包  ->  属于「引擎文件缺失」，走方案 A'
Write-Host '  第 3 项 HasAccepted 不是 1   ->  先开启在线语音识别再测'
Write-Host '  其余项异常              ->  按对应章节处理'
```

### 判定要点

- **第 1 项出现 `0`** → 你的系统应用包被清理工具删空了，这就是「转圈不出字」的直接原因，走 [方案 A](#五修复方案-a从官方-iso-还原缺失的语音引擎)。
- **第 1 项文件数正常，第 3 项是 0 或不存在** → 先开启在线语音识别，重启后再测（很多时候仅此一步即可解决）。
- **两项都正常但仍转圈** → 组件存储可能已损坏，检查累积更新能否安装，考虑 [方案 B](#六修复方案-b就地修复安装兜底方案)。

---

## 三、关键根因：SystemApps\LKG 系统应用包被清空

在排查过的一台真实机器上，`C:\Windows\SystemApps\LKG\` 下的 **6 个系统应用包全部为空**：

| 包名 | 用途 | 故障时文件数 | 正常文件数 |
| --- | --- | --- | --- |
| `MicrosoftWindows.LKG.SpeechRuntime` | **语音识别引擎（Win+H 核心）** | 0 | 22 |
| `MicrosoftWindows.LKG.AccountsService` | 账户服务 | 0 | 13 |
| `MicrosoftWindows.LKG.DesktopSpotlight` | 聚焦 / 桌面 | 0 | 21 |
| `MicrosoftWindows.LKG.IrisService` | Windows AI | 0 | 13 |
| `MicrosoftWindows.LKG.RulesEngine` | 规则引擎 | 0 | 12 |
| `MicrosoftWindows.LKG.TwinSxS` | 组件服务 | 0 | 12 |

而系统的部署数据库（`StateRepository`）里，这些包**依然标记为已安装（Status = Ok）**，
磁盘状态与数据库状态完全脱节。

**结果**：Win+H 的界面组件（`MicrosoftWindows.61xxxxxx.InpApp`）是好的，面板能弹出；
但界面调用不到语音引擎，于是**永远转圈**。

### 语音引擎包里到底装了什么

`MicrosoftWindows.LKG.SpeechRuntime` 的 22 个文件里包含真正的识别内核：

| 文件 | 作用 |
| --- | --- |
| `Microsoft.CognitiveServices.Speech.extension.embedded.sr.runtime.dll` | 本地语音识别引擎（约 4.8 MB） |
| `Microsoft.CognitiveServices.Speech.extension.embedded.tts.dll` | 语音合成（约 6.1 MB） |
| `Microsoft.CognitiveServices.Speech.extension.onnxruntime.dll` | 神经网络推理（约 8.3 MB） |
| `Microsoft.CognitiveServices.Speech.extension.mas.dll` | 麦克风阵列处理 |
| `Microsoft.CognitiveServices.Speech.core.dll` 等 | 语音 SDK 核心与扩展 |
| `FPIEProcessor.dll`、`coreAppActivation.SCCD` | 核心应用激活 |
| `resources.pri`、`appxmanifest.xml`、`appxblockmap.xml`、`appxsignature.p7x` | 资源、包元数据与微软签名 |
| `Assets\*.png`、`MASmodels\aec_v1.fpie` | 图标与回声消除模型 |

### 谁删的

在排查的机器上装有一款第三方安全软件，其「**系统盘瘦身 / 大文件清理 / 系统急救箱**」
功能会识别「体积大又看起来"用不上"」的目录并删除。`SystemApps\LKG` 下的语音引擎包含
数 MB 级的神经网络库，很容易成为清理目标。

**这类故障的成因归纳起来通常是三类：**

1. 第三方安全软件的「清理 / 瘦身 / 优化」功能
2. 来源不明的「系统精简脚本 / debloat 脚本 / 一键优化批处理」
3. 手动删除了自认为"没用"的系统目录

**结论：任何"系统清理/精简/优化"操作都不要让它动系统分区。**

---

## 四、为什么 SFC 和 DISM 查不出来

这是本故障最误导人的地方——**所有常规体检都显示"健康"**：

```text
sfc /scannow
  -> Windows 资源保护未找到任何完整性违规。      # 但语音引擎确实是空的
```

原因有三层：

| 原因 | 说明 |
| --- | --- |
| 1. SFC 不校验 Appx 包内容 | SFC 只管「受保护的系统文件」，`SystemApps` 下的 Appx 包载荷不在其校验范围内 |
| 2. 相关组件未登记在 ComponentDetect | `microsoft-onecore-speechservice`、`userexperience-*` 等组件不在 `ComponentDetect` 中，DISM 也无法感知其文件缺失 |
| 3. 数据库状态与磁盘状态脱节 | 部署数据库认为包已安装，不报错 |

**所以：遇到「系统体检说没问题，但功能就是坏」的情况，必须直接核对磁盘文件与数据库状态**，
也就是第二节诊断脚本的第 1、2 项。

---

## 五、修复方案 A：从官方 ISO 还原缺失的语音引擎

**思路**：这些系统应用包的原始文件就在 Windows 安装镜像的 `install.wim` 里，
直接用官方介质把它们提取回来即可，无需重装系统。

### 前提条件

- 一个 **Windows 11 官方 ISO**（x64，与系统语言一致即可）。
  - 版本低于当前系统也没关系——**只当"文件源"用，不跑安装程序**。
  - 官方下载：微软官网「下载 Windows 11 磁盘映像 (ISO)」。
- 管理员权限。

### 第 1 步：挂载 ISO 与其中的 install.wim

```powershell
# 以管理员身份运行
$ErrorActionPreference = 'Continue'

# 1) 挂载 ISO（把路径换成你自己的）
$iso = 'D:\你的镜像文件.iso'
$m   = Mount-DiskImage -ImagePath $iso -Access ReadOnly -PassThru
$dl  = ($m | Get-Volume).DriveLetter
Write-Host "ISO 挂载于 $dl :"

# 2) 查看镜像里有哪些版本，挑一个（任意版本都可以，这些系统包是各版本共用的）
$wim = "${dl}:\sources\install.wim"
if (-not (Test-Path $wim)) { $wim = "${dl}:\sources\install.esd" }
Get-WindowsImage -ImagePath $wim | Format-Table ImageIndex, ImageName

# 3) 只读挂载到临时目录（企业版通常是索引 2；家庭版/专业版按上表选）
$mnt = 'C:\wim-mount'
New-Item -ItemType Directory -Path $mnt -Force | Out-Null
Mount-WindowsImage -ImagePath $wim -Index 2 -Path $mnt -ReadOnly
Write-Host '已挂载，可查看 C:\wim-mount\Windows\SystemApps\LKG'
```

> **注意**：`install.esd` 无法直接挂载。若你的镜像是 ESD，
> 可先用 `DISM /Export-Image /SourceImageFile:install.esd /SourceIndex:2 /DestinationImageFile:install.wim /Compress:max`
> 转换后再挂载；或直接用第三方解包工具提取。

### 第 2 步：把 6 个包复制回原位

```powershell
$src = 'C:\wim-mount\Windows\SystemApps\LKG'
$dst = 'C:\Windows\SystemApps\LKG'

Get-ChildItem $src -Directory | ForEach-Object {
    $target = Join-Path $dst $_.Name
    if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
    Copy-Item (Join-Path $_.FullName '*') $target -Recurse -Force
    $n = @(Get-ChildItem $target -Recurse -File -Force).Count
    Write-Host ("{0,-58} 已还原 {1} 个文件" -f $_.Name, $n)
}

# 把属主设为与正常系统包一致（TrustedInstaller）
Get-ChildItem $dst -Directory | ForEach-Object {
    icacls $_.FullName /setowner "NT SERVICE\TrustedInstaller" /T /C /Q | Out-Null
}
Write-Host '完成'
```

### 第 3 步：卸载镜像（重要，别忘）

```powershell
Dismount-WindowsImage -Path 'C:\wim-mount' -Discard
Dismount-DiskImage -ImagePath $iso
```

### 第 4 步：开启在线语音识别 + 解除"待移除"标记

```powershell
# 4.1 开启在线语音识别（Win+H 的必要条件）
$k = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\PrivacyPolicy'
if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
New-ItemProperty -Path $k -Name 'HasAccepted' -PropertyType DWord -Value 1 -Force | Out-Null
Write-Host '已开启在线语音识别'

# 4.2 若包的用户登记状态是 Installed(pending removal)，先清除该标记
$pfn = 'MicrosoftWindows.LKG.SpeechRuntime_1000.26100.3775.0_x64__cw5n1h2txyewy'
# 用 Get-AppxPackage -AllUsers 查到实际的 PackageFullName 再替换上面这行
try { Remove-AppxPackage -Package $pfn -AllUsers -ErrorAction Stop; Write-Host '已清除待移除标记' }
catch { Write-Host ('清除尝试返回：' + ($_.Exception.Message -split "`n")[0]) }
```

> 说明：这一步报「此应用是 Windows 的一部分，无法针对每个用户卸载」是**正常**的，
> 但它会把数据库里的 `pending removal` 标记清掉，这正是我们想要的效果。

### 第 5 步：重启

重启后按 Win+H 实测。若仍无效，继续看下一节与第八节的坑。

### 关于"包注册失败"

还原文件后，尝试重新注册这个包**很可能会失败**，典型错误：

```text
0x80073CFB  另一个用户已安装此应用的打包版本。未打包版本无法替换该版本。
```

这是系统规则，**与版本号高低无关**（实测提高版本号、使用
`-ForceUpdateFromAnyVersion`、`RegisterByFamilyName` 均无效），
而且此类内置包不允许按用户卸载。

**但在实测案例中，仅还原文件 + 开启在线语音识别 + 重启，语音键入就已恢复可用**，
并不依赖重新注册成功。所以不要卡在"注册必须成功"上，先按上面步骤做完再实测。
如果做完仍无效，直接走方案 B。

---

## 六、修复方案 B：就地修复安装（兜底方案）

当出现以下任一情况，说明系统底层（组件存储）已经损坏，任何"打补丁式"修复都不可靠：

- 累积更新安装失败（更新历史里结果码 `0x4`）
- `DISM /Online /Cleanup-Image /RestoreHealth` 报 `0x800f0915 在任何位置都找不到修复内容`
- 系统里有大量系统文件缺失且无法修复

### 步骤

1. **下载与当前系统版本一致的 ISO**（关键）。
   - 检查当前版本：`winver`，或在 PowerShell 执行
     `Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select ProductName, DisplayVersion, CurrentBuild, UBR`
   - **ISO 版本必须 ≥ 当前系统版本**，否则安装程序会拒绝「保留文件和应用」。
2. 在 Windows 中双击 ISO 挂载，运行根目录的 `setup.exe`。
3. 选择「**保留个人文件和应用**」，按提示完成（约 40-60 分钟，需重启数次）。

该操作会重新正确安装并注册全部系统应用（含语音引擎）、修复组件存储、
恢复累积更新安装能力，**个人文件与已安装软件均保留**。

---

## 七、验证修复结果

```powershell
# 1) 包文件是否还原（应分别为 13/21/13/12/22/12）
Get-ChildItem 'C:\Windows\SystemApps\LKG' -Directory |
  ForEach-Object { "{0,-58} {1}" -f $_.Name, @(Get-ChildItem $_.FullName -Recurse -File -Force).Count }

# 2) 语音引擎关键文件是否存在
$sr = 'C:\Windows\SystemApps\LKG\MicrosoftWindows.LKG.SpeechRuntime_cw5n1h2txyewy'
'Microsoft.CognitiveServices.Speech.extension.embedded.sr.runtime.dll',
'Microsoft.CognitiveServices.Speech.extension.onnxruntime.dll',
'resources.pri' | ForEach-Object { "{0,-70} {1}" -f $_, (Test-Path (Join-Path $sr $_)) }

# 3) 在线语音识别开关
(Get-ItemProperty 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\PrivacyPolicy').HasAccepted

# 4) 累积更新能否安装（结果码 0x4 表示失败）
$s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
$s.QueryHistory(0, [Math]::Min(10, $s.GetTotalHistoryCount())) |
  Format-Table Date, @{n='Result';e={'0x{0:X8}' -f $_.ResultCode}}, Title
```

最后**实测**：打开记事本 → 点进正文 → 按 `Win+H` → 对着麦克风说一句话。

---

## 八、七个常见坑（重点）

### 坑 1：`-DisableDevelopmentMode` 可能在本机全局失效

网上几乎所有教程都让你这样重新注册系统应用：

```powershell
Get-AppxPackage -AllUsers <包名> | ForEach-Object {
    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml"
}
```

但在某些机器上，**加上这个参数会走一条坏掉的代码路径**，报：

```text
0x80073CF9  正在拒绝从 AppxManifest.xml 进行注册的请求，
            因为部件清单(manifest)没有位于程序包根目录中。
```

**判断方法（重要）**：随便造一个全新的最小测试包，分别用带参数 / 不带参数注册：

```powershell
# 两种方式各试一次，如果"不带参数"成功而"带参数"失败，
# 说明该参数在本机全局失效，从此别再用了
Add-AppxPackage -Register 'C:\test\AppxManifest.xml' -DisableDevelopmentMode   # A
Add-AppxPackage -Register 'C:\test\AppxManifest.xml'                            # B
```

### 坑 2：用"已注册的包"做对照实验是无效对照

对**已经注册过**的包执行 `-Register` 属于刷新操作，**必然成功**，
不能用来证明"部署引擎正常"。做对照必须用**全新对象**（新建的最小包）。

### 坑 3：把 `-DisableDevelopmentMode` 的报错当成"包路径写错了"

该错误文本极具误导性，包和清单明明就在根目录。**不要反复检查路径和文件名大小写**
（实测大小写、路径位置都不是原因），直接做坑 1 的对照实验。

### 坑 4：关过 Windows 更新的机器，DISM 会莫名失败

如果你用过 **WUB（Windows Update Blocker）**、各类"关闭 Windows 更新"工具，
DISM 会因为拿不到修复源而报 `0x800f0915`。

而且**残留不止策略键**——只删
`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` 是不够的，
还要检查策略缓存：

```powershell
# 这里是 WUB 留下的假 WSUS 地址（注意它没有 http:// 前缀）
reg query "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache" /s
```

若存在 `UpdateServiceUrlAlternate = xxx.localdomain.yyy` 这类值，
会导致 Windows 更新报 `0x80072EE6（URL 协议无法识别）`。
处理方式（建议先导出备份）：

```powershell
reg export "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache" C:\wu-gpcache-backup.reg /y
reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache" /f
Restart-Service wuauserv -Force
```

### 坑 5：只看 SFC 的"健康"结论就放弃

如第四节所述，SFC 对 Appx 包内容**完全无感**。
"未找到完整性违规"≠ 系统完整。

### 坑 6：继续让清理/优化工具"再清理一次"

故障往往就是清理工具造成的。重复清理只会把更多系统包删掉，
甚至让组件存储损坏到无法修复。

### 坑 7：以为必须重装系统

方案 A 通常不需要重装，也不需要重置电脑。
只有当组件存储真的损坏（累积更新装不上）时，才需要方案 B 的**就地修复安装**——
它保留个人文件和已安装软件，不是重装。

---

## 九、如何避免再次发生

| 措施 | 说明 |
| --- | --- |
| 不让任何"清理/瘦身/优化"工具处理系统分区 | 尤其是「大文件清理 / 系统盘瘦身 / 系统急救箱 / 一键优化」类功能 |
| 不使用来源不明的系统精简脚本 | debloat / tiny 类脚本会移除系统组件与系统应用包 |
| 关闭系统更新前请三思 | 关闭后 DISM/SFC 会失去修复源，日后修系统会非常困难 |
| 定期确认累积更新能正常安装 | 更新历史出现失败（结果码 0x4）就是组件存储受损的信号 |
| 重要环境先建还原点 | `Win+R` → `sysdm.cpl` → 系统保护 → 创建 |

---

## 十、附录：错误码对照表与 FAQ

### 错误码对照表

| 错误码 | 含义 | 常见场景 |
| --- | --- | --- |
| `0x80073CF9` | 部署失败 | `-DisableDevelopmentMode` 失效路径 / 清单读取失败 |
| `0x80073CFB` | 提供的程序包已安装，禁止重装 | 打包版本与散装版本冲突 |
| `0x80073CFA` | 无法卸载 | 内置包按用户卸载 |
| `0x80070002` | 找不到指定文件 | 包目录为空时注册 |
| `0x80070032` | 不支持该请求 | 尝试卸载内置包 |
| `0x80070057` | 参数无效 | 与 0x80073CF9 伴生的内部错误 |
| `0x800f0915` | 找不到修复内容 | 组件存储损坏 / 更新源被封锁 |
| `0x800f081f` | 找不到源文件 | DISM 缺少修复源 |
| `0x80072EE6` | URL 协议无法识别 | 假 WSUS 地址残留（缺 `http://`） |
| `0x80070490` | 找不到元素 | 包注册状态异常 |

### FAQ

**Q1：我的 `SystemApps\LKG` 目录里文件是正常的，但 Win+H 还是转圈，怎么办？**
先确认在线语音识别为开（第二节第 3 项），然后重启；
若仍无效，检查累积更新是否能正常安装，必要时走方案 B。

**Q2：我的系统里根本没有 `SystemApps\LKG` 目录，是不是不能用这个指南？**
说明你的系统版本不使用该机制。请转而检查在线语音识别、麦克风隐私、
网络连通性，以及输入体验组件（`MicrosoftWindows.Client.CBS`）。

**Q3：ISO 版本比我的系统低，能用来提取文件吗？**
可以。**只当文件源用，不运行 `setup.exe`**。
（但方案 B 的就地修复安装必须用 ≥ 当前版本的 ISO。）

**Q4：复制文件时报"拒绝访问"？**
用管理员 PowerShell；若仍被拒，先对目标目录取得所有权：
`takeown /f "C:\Windows\SystemApps\LKG" /r /d y`

**Q5：还原文件后 `Get-AppxPackage` 仍显示当前用户没注册这个包，正常吗？**
在实测案例中属正常现象——语音键入依然可用。
是否注册成功不是唯一的验证标准，**以实际按 Win+H 能否出字为准**。

**Q6：做完方案 A，语音识别能出字但准确率低/延迟高？**
检查是否处于离线状态（引擎需要在线语音服务配合）、麦克风采样率，
以及在「设置 > 时间和语言 > 语言和区域」中确认中文语音功能已安装。

---

## 免责声明

本文基于一次真实故障的排查记录整理，命令与脚本均经过实测。
但系统环境差异较大，**执行任何注册表、系统文件操作前请先创建还原点或备份**。
若不熟悉命令行操作，建议直接采用方案 B（就地修复安装），它更简单也更彻底。

---

*如果这篇指南帮到了你，欢迎把它分享给遇到同样问题的人。*
