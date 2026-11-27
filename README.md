# minecraft2shell-fix

一键检测并修复 **Minecraft2Shell**（FreeType 字体资源包 RCE）漏洞的 Windows 脚本工具。

## 漏洞背景

Minecraft Java 版使用的 FreeType 字体库存在一个 TrueType hinting 越界写漏洞：恶意资源包中的特制字体可在渲染时触发原生内存越界写，进而**在玩家电脑上执行任意代码**（俗称 "Minecraft2Shell"，弹计算器即为演示）。

- **触发方式**：接受服务器推送的恶意资源包，或手动安装来路不明的资源包。
- **根因**：FreeType < 2.15.0（对应 FreeType #1419 / CVE-2026-10701）。
- **官方修复**：Mojang 为 **26.x** 系列发布了补丁库 `lwjgl-freetype:*-mojang-2.15.0`，通过修改版本元数据下发；**1.20.5 ~ 1.21.11 暂无官方补丁**。

> 第三方启动器（PCL / HMCL 等）点"版本检查/文件校验"**无法**获取此补丁——它只校验文件、不重新下载 version JSON。本工具正是为此而做。

## 功能

- **按 freetype 库版本判定**：以版本实际引用的 `lwjgl-freetype` 库版本（自身或经 `inheritsFrom` 继承）为准，**与 MC 版本名无关**——Fabric/Forge/OptiFine 整合包、改名版本都能正确识别。
- **全盘扫描**：扫描所有固定磁盘上的 `.minecraft` 目录，覆盖第三方启动器的游戏目录。
- **分类处理**：
  | 实际引用的 freetype | 处理 |
  |---|---|
  | 已是 `*-mojang-2.15.0` | 已修复，跳过 |
  | `3.4.3` / `3.4.1`（有官方补丁） | 换成对应 `-mojang-2.15.0` 并下载校验（原版整份覆盖，整合包外科替换保留其余配置） |
  | `3.3.x` 等（官方无补丁） | 需缓解（关资源包 / 缓解模组） |
  | 无 freetype（1.20.4 及更早） | 不受影响 |
- **安全**：扫描后交互确认（y/n）；改前自动备份 `*.bak-mc2shell-*`；下载逐个 SHA1 校验。

## 使用

### 方式一：双击（最简单）

双击 **`mc2shell一键修复.bat`** —— 自动扫描所有 Minecraft 安装，列出每个版本状态，若有可修复项会提示 `(y/n)`，输入 `y` 才会修复。

### 方式二：命令行（源脚本）

```powershell
# 只读自检（不修改任何文件）
powershell -ExecutionPolicy Bypass -File mc2shell-check.ps1

# 扫描并交互确认修复
powershell -ExecutionPolicy Bypass -File mc2shell-fix.ps1

# 批量修复（不询问直接修）
powershell -ExecutionPolicy Bypass -File mc2shell-fix.ps1 -Yes

# 纯预览（只看不改）
powershell -ExecutionPolicy Bypass -File mc2shell-fix.ps1 -DryRun

# 指定某个 .minecraft 目录
powershell -ExecutionPolicy Bypass -File mc2shell-fix.ps1 -McPath "D:\xxx\.minecraft"
```

## 文件说明

| 文件 | 说明 |
|---|---|
| `mc2shell一键修复.bat` | 单文件、双击即用，内嵌完整修复逻辑 |
| `mc2shell-fix.ps1` | 修复源脚本（扫描 + 交互修复） |
| `mc2shell-check.ps1` | 只读自检源脚本 |
| `一键自检.bat` / `一键修复.bat` | 调用对应 `.ps1` 的两文件版启动器 |

## 对无官方补丁版本（1.20.5 ~ 1.21.11）的缓解

1. 游戏设置里将 **"服务器资源包"设为"已禁用"**，且不加载来路不明的资源包；
2. 模组端可安装缓解模组（如 `minecraft2shell-fix` 类，关闭 hinting）；
3. 官方修复到位前，不要接受任何服务器推送的资源包。

## 安全与免责

- 脚本仅从 Mojang 官方库地址（`libraries.minecraft.net`）下载，并逐个校验 SHA1。
- 所有改动均先备份，可用 `*.bak-mc2shell-*` 还原。
- 请从可信来源获取本工具，并自行核对校验值后使用。作者不对使用后果负责。
