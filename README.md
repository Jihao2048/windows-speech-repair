# windows-speech-repair

Windows 11 语音键入（Win+H）故障的完整排查与修复资料。

**症状**：按 `Win+H` 后语音键入面板能弹出，但**一直转圈、永远不出字**；
麦克风、网络、语言包检查都正常，就是识别不了。

本仓库提供一份可分享的排查指南、一个一键诊断修复脚本，以及本次故障的原始诊断记录与备份文件。

---

## 快速开始

### 只想解决问题

1. 阅读 **[docs/Win11语音键入故障排查指南.md](docs/Win11语音键入故障排查指南.md)**
   —— 含五分钟快速诊断脚本与两种修复方案。
2. 或直接运行一键脚本：

```powershell
# 以管理员身份打开 PowerShell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 先只看诊断结论，不做任何修改
.\Fix-Win11VoiceTyping.ps1 -DiagnoseOnly

# 确认后再执行修复（交互式，每步都会询问）
.\Fix-Win11VoiceTyping.ps1
```

详细参数说明见 **[docs/一键脚本使用说明.md](docs/一键脚本使用说明.md)**。

---

## 故障根因（简述）

从 Windows 11 24H2 起，Win+H 的语音键入依赖一套新的「本地 + 神经网络」混合引擎，
它以 **Appx 系统应用包**的形式安装在：

```text
C:\Windows\SystemApps\LKG\
    MicrosoftWindows.LKG.SpeechRuntime       <- 语音识别引擎（22 个文件）
    MicrosoftWindows.LKG.AccountsService
    MicrosoftWindows.LKG.DesktopSpotlight
    MicrosoftWindows.LKG.IrisService
    MicrosoftWindows.LKG.RulesEngine
    MicrosoftWindows.LKG.TwinSxS
```

**故障时这 6 个包的文件被整体清空，而系统部署数据库仍认为它们已安装。**
语音界面调用不到引擎，于是无限转圈。

常见起因是第三方安全软件的「系统盘瘦身 / 大文件清理 / 系统急救」，
或来源不明的系统精简脚本。

### 为什么常规手段查不出来

| 工具 | 结论 | 原因 |
| --- | --- | --- |
| `sfc /scannow` | 「未找到完整性违规」 | SFC 不校验 Appx 包内容 |
| `DISM /RestoreHealth` | 无法感知 | 相关组件未登记在 ComponentDetect |
| 包管理查询 | 显示已安装 | 部署数据库与磁盘状态脱节 |

---

## 修复思路

这些系统应用包的原始文件就在 Windows 安装镜像的 `install.wim` 里。
挂载镜像并把 `Windows\SystemApps\LKG\` 下的包提取回来即可，**无需重装系统**。

一键脚本会自动完成：定位 ISO → 挂载 `install.wim` → 提取 6 个包 →
回填缺失文件 → 设置属主 → 开启在线语音识别 → 清除异常注册标记 → 验证。

---

## 仓库结构

```text
.
├── Fix-Win11VoiceTyping.ps1      一键诊断与自动修复脚本（8 个阶段）
├── docs/
│   ├── Win11语音键入故障排查指南.md   面向公众的自救指南（含可复制脚本）
│   ├── 一键脚本使用说明.md            参数、流程、FAQ、安全提示
│   └── 文件说明.md                   全部资料的索引
├── scripts/                      31 个分步脚本（诊断 / 对照实验 / 修复）
├── 日志/                          42 个诊断日志（已脱敏）
├── 报告/                          修复报告与任务总结
└── 备份/                          提取的原装 LKG 包与注册表备份
```

### 关于 `备份/`

`备份/` 内是从 Windows 安装映像中提取的**微软原装系统应用包**（含官方签名），
用于在需要时还原语音引擎，以及供研究参考。
这些文件原本就存在于 Windows 系统中，此处仅作修复用途的副本留存。

### 关于 `scripts/`

`scripts/` 保留了故障排查过程中的 31 个分步脚本，
其中若干「对照实验」脚本记录了定位过程，例如：

- `minimal-test.ps1` —— 证明 `Add-AppxPackage -Register -DisableDevelopmentMode`
  在某些机器上是**全局失效路径**
- `path-discriminator.ps1` —— 区分「包内容问题」与「路径问题」
- `version-experiment.ps1` —— 验证版本号与强制参数均无法绕过注册限制

---

## 排查中发现的几个关键点

1. **`-DisableDevelopmentMode` 可能全局失效**
   几乎所有教程都让你加这个参数重新注册系统应用，但在某些机器上它会报
   `0x80073CF9 部件清单没有位于程序包根目录中`。判定方法：用一个全新的最小测试包
   分别带/不带该参数注册，若「不带」成功而「带」失败，即确认失效。

2. **注册失败不影响功能恢复**
   还原文件后会遇到 `0x80073CFB 未打包版本无法替换打包版本`，
   这是 Windows 内置包的正常规则（提高版本号、`-ForceUpdateFromAnyVersion`
   均无效，且内置包不允许按用户卸载）。
   实测中仅需「还原文件 + 开启在线语音识别 + 重启」即可恢复。

3. **WUB（Windows Update Blocker）的残留不止策略键**
   `HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\GPCache` 中的缓存条目
   同样生效。其中缺少协议前缀的 `UpdateServiceUrlAlternate` 会导致
   Windows 更新报 `0x80072EE6（URL 协议无法识别）`，进而使 DISM 失去修复源。

4. **`C:\ProgramData\Microsoft\Windows\AppRepository\<PackageFullName>.xml`
   就是 AppxManifest 原文**，可用于重建包或比对身份信息。

---

## 环境

- 复现环境：Windows 11 Enterprise 25H2（Build 26200.8655）
- 脚本：Windows PowerShell 5.1 / PowerShell 7 均可
- 编码：所有脚本与文档均为 **UTF-8 带 BOM**
  （PS 5.1 读取无 BOM 的 UTF-8 脚本会按 ANSI 解码，导致中文乱码与语法错误）

---

## 免责声明

- 本仓库内容基于一次真实故障的排查记录整理，命令与脚本均经过实测。
  但系统环境差异较大，**执行任何注册表或系统文件操作前请先创建还原点或备份**。
- `备份/` 内的文件为微软系统组件的原样副本，版权归 Microsoft 所有，
  此处仅用于系统修复目的。使用者应自行遵守相应的软件许可条款。
- 修复脚本会修改系统文件与注册表（改动前自动备份），请自行评估风险。

---

## 许可

本仓库中**由作者编写的**文档与脚本采用 [MIT License](LICENSE)。
`备份/` 目录下的微软系统文件不适用该许可，版权归 Microsoft 所有。
