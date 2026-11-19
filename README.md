# LENSO

LENSO 是一款现代 macOS 原生截图、标注贴图、历史搜索与 OCR 文字收纳利器。基于 Swift 6 + SwiftUI + AppKit 原生打造，采用国际克莱因蓝（International Klein Blue）高对比与 Apple 纯白设计风格。

内置标准 Model Context Protocol (MCP) 服务，支持 Claude Desktop、Claude Code、Cursor、Windsurf 等 AI Agent 挂载读取本地截图与剪贴板历史。

---

## 快速上手（Four-Step Onboarding）

从零开始 clone 仓库后，只需标准四步即可完整构建并运行所有测试：

```bash
# 1. 克隆代码仓库
git clone https://github.com/manzijian/lenso.git
cd lenso

# 2. 生成 Xcode 工程（基于 project.yml）
xcodegen generate

# 3. 编译应用并自动完成固定身份代码签名
bash scripts/build.sh

# 4. 运行全量单元测试与自动化验证
xcodebuild test -project LENSO.xcodeproj -scheme LENSO -destination 'platform=macOS'
```

> **注意**：
> - 依赖工具：需安装 Xcode 16+ 以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)。
> - `scripts/build.sh` 会自动配置自签证书并进行确定性签名，解决 macOS 屏幕录制权限因每次 ad-hoc 重新生成 cdhash 导致失效的问题。

---

## 工程架构与设计规范

- **开发语言与规范**：Swift 6 Strict Concurrency Mode + SwiftUI / AppKit 响应式状态管理。
- **解耦设计**：
  - `ScreenCapturing`：抽象屏幕捕获服务，屏蔽底层 ScreenCaptureKit 权限依赖，支持测试环境 Mock 注入。
  - `ClipboardWriting`：剪贴板写入与读取抽象，支持内存 Mock，避免污染系统剪贴板。
  - `ErrorPresenting`：统一弹窗与权限引导错误呈现。
- **存储与健壮性**：
  - SQLite 开启 WAL 模式与 `PRAGMA integrity_check` 启动自检；遇到数据库严重损坏时自动重命名备份并原地重建。
  - 缩略图生成基于 ImageIO 降采样（`kCGImageSourceThumbnailMaxPixelSize`），严格抑制高分辨率屏幕截图引起的内存峰值。
  - 数据文件与数据库路径完全可注入，单元测试基于独立临时目录隔离，不触碰用户真实数据。
- **安全与本地服务**：
  - MCP 与本地服务严格绑定 `127.0.0.1` 环回地址。
  - 默认启用 128 位 Token 鉴权（支持 `Authorization: Bearer <token>` 及 `?token=<token>`），阻断未授权的跨域或恶意网络请求。
- **隐私合规**：已配置苹果官方规范 `PrivacyInfo.xcprivacy` 隐私清单。

---

## 常用功能与快捷键

| 功能 | 默认快捷键 | 说明 |
| :--- | :--- | :--- |
| **区域截图** | `⌥ A` | Snipaste 风格实时覆盖层、智能窗口吸附、微调与全功能画板标注 |
| **全局快速搜索** | `⇧ ⌘ F` | 照片墙方块展示最近截图、复制文本、富文本网址解析与代码高亮 |
| **数据看板** | - | 每日/每小时复制与截图活跃趋势统计分析 |
| **设置中心** | `⌘ ,` | 快捷键配置、数据保存期限（小时/天数自动清理）、MCP 服务一键接入 |

---

## 开源协议

本项目基于 [MIT License](LICENSE) 开源，版权归 manzijian 所有。

