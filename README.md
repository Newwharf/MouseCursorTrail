# CursorTrailBar

> macOS 鼠标轨迹 / 点击特效 / 快捷放大镜工具（常驻型菜单栏应用）

`CursorTrailBar` 是一个基于 Swift + AppKit 的 macOS 桌面工具，聚焦于鼠标视觉增强与效率体验：

- 轨迹效果（多风格 + 特效 + 加速爆发）
- 点击效果（按键级独立配置）
- 快捷放大镜（按住触发，滚轮动态变焦）
- 常规设置（开机启动、日志、菜单栏显示等）

---

## ✨ 特性

### 轨迹效果

- 轨迹开关与样式切换（双层霓虹 / 渐隐丝带 / 彩虹拖尾 / 闪电轨迹）
- 特效类型（粒子火花 / 墨迹扩散 / 电弧闪点）
- 特效强度分级（关闭 / 低 / 中 / 高）
- 轨迹参数可调（轨迹粗细、轨迹长度）
- 加速爆发（“一之闪”）支持独立开关与参数配置

### 点击效果

- 点击总开关
- 点击样式（实心脉冲 / 十字闪光）
- 点击时长与半径可调
- 左键 / 右键 / 中键独立开关与颜色设置

### 放大镜

- 放大镜总开关
- 支持按住快捷键触发（键盘/鼠标快捷键录制）
- 支持滚轮临时缩放（释放后恢复配置值）
- 放大镜激活时可选择是否显示轨迹与特效
- 边框颜色、边框宽度、阴影强度可调

### 常规能力

- 开机启动（macOS 13+）
- 菜单栏图标显示开关
- 语言切换（内置简体中文 / English）
- 日志输出与日志目录快捷打开
- 权限状态提示（输入监控 / 屏幕录制 / 辅助功能）

---

## 🧱 技术栈

- **Language**: Swift
- **UI Framework**: AppKit
- **Architecture**: MVC（按模块拆分）
- **Build**: Swift Package Manager（`swift run` / `swift build`）

---

## 📦 环境要求

- macOS 13.0+
- Xcode Command Line Tools
- Swift 6.2（与 `Package.swift` 对齐）

---

## 🚀 快速开始

### 1) 本地运行

```bash
swift run
```

运行后会自动打开设置窗口；关闭设置窗口后应用继续常驻后台。

默认全局开关快捷键：

```text
⌃⌥⌘T
```

### 2) 构建

```bash
swift build
```

---

## 🛠 打包为 `.app`

```bash
./scripts/build_app.sh
```

输出路径：

```bash
dist/CursorTrailBar.app
```

说明：

- 脚本会构建 release 可执行文件并组装 `.app` 目录结构
- 会尝试进行 ad-hoc 签名（失败不阻断）
- 默认 `LSUIElement=true`（后台工具形态，无 Dock 图标）

---

## 🔐 权限说明

部分能力依赖系统权限：

- **输入监控**：影响全局快捷键 / 鼠标键触发
- **屏幕录制**：影响放大镜抓屏
- **辅助功能**：部分全局输入拦截场景需要

项目内提供权限状态提示与系统设置跳转入口，建议首次运行后先在设置页完成授权。

---

## 🌐 多语言与语言包

- 在设置页 `设置 -> 常规 -> 语言` 可切换语言
- 在 `设置 -> 常规 -> 语言包目录` 可打开语言包文件夹
- 首次运行会自动写入 `zh-Hans.json` 与 `en.json` 两个默认语言包
- 实际可选语言严格由该目录中的语言包文件决定
- 若目录中读取不到任何语言包文件，应用会回退为**仅简体中文**

语言包目录（自动创建）：

```text
~/Library/Application Support/CursorTrailBar/LanguagePacks
```

你可以放入自定义 JSON 文件（后缀 `.json`），格式支持两种：

1) 带元信息格式（推荐）：

```json
{
  "code": "ja",
  "name": "日本語",
  "strings": {
    "sidebar.trailEffects": "軌跡エフェクト",
    "menu.quit": "終了"
  }
}
```

2) 纯键值格式（语言代码默认取文件名）：

```json
{
  "sidebar.trailEffects": "Trail Effects (Custom)",
  "menu.quit": "Quit (Custom)"
}
```

> 修改或新增语言包后，重新聚焦设置窗口即可刷新语言列表。

---

## 🧭 项目结构（MVC）

```text
Sources/CursorTrailBar/
├─ App/
│  └─ CursorTrailBarApp.swift
├─ Models/
│  └─ SettingsModels.swift
├─ Views/
│  └─ TrailOverlayView.swift
├─ Controllers/
│  ├─ AppDelegate.swift
│  ├─ OverlayWindowManager.swift
│  └─ SettingsWindowController.swift
├─ Services/
│  ├─ SettingsStore.swift
│  ├─ LocalizationManager.swift
│  ├─ MouseMonitor.swift
│  ├─ GlobalShortcutMonitor.swift
│  ├─ GlobalScrollInterceptor.swift
│  ├─ HotKeyManager.swift
│  ├─ LaunchAtLoginManager.swift
│  └─ AppLogger.swift
└─ Utilities/
   └─ ClampUtils.swift
```

---

## 🧰 常用脚本

```bash
# 打包 app
./scripts/build_app.sh

# 生成图标资源
./scripts/generate_app_icon.sh

# 安装开机自启（LaunchAgent）
./scripts/install_launch_agent.sh

# 卸载开机自启
./scripts/uninstall_launch_agent.sh
```

---

## 🗺️ Roadmap

结合当前规划，后续会继续扩展：

- **轨迹模块**：更多轨迹/特效/爆发类型与各自独立参数
- **点击模块**：更多点击视觉效果与可配置项
- **常规模块**：多语言、更多全局快捷操作等

---

## 🐞 问题排查

- 建议先在设置中开启日志输出，再复现问题
- 使用“打开日志文件夹”快速定位日志
- 权限相关问题优先检查设置页中的权限状态

---

## 📄 License

请根据你的 GitHub 仓库选择更新（如 `MIT` / `Apache-2.0`）。
