# LENSO「开放光圈」图标设计规格

日期：2026-11-07
状态：视觉方向已确认，规格已完成自检，等待用户复核

## 目标

为 LENSO 建立一套统一的 App 图标与菜单栏图标，采用用户确认的「开放光圈 · Open Aperture」方案。图标需要延续 LENSO 当前的蓝白品牌气质，并在 Dock、应用切换器、菜单栏小尺寸下保持识别度。

## 已确认的视觉方向

- 主色：克莱因蓝，基准色 `#002FA7`；外壳可使用左上 `#0B48C1` 到右下 `#00278B` 的极轻渐变。
- 主图形：白色开放圆环 / 光圈，中心为蓝白镜头焦点。
- 外壳：正式 App 资源包含透明角与蓝色圆角方形，圆角比例固定，带非常轻的顶部高光与底部阴影。
- 语义：外圈是镜头与记忆边界，中心是被看见并留下来的瞬间。
- 语言：清爽、成熟、简洁；不使用卡通表情、书签、星星、循环箭头或多余装饰。
- 禁止：直接复刻其他品牌的贝壳或相似注册图形；内部图形必须保持 LENSO 的开放光圈识别。

## 交付物

### 1. App 图标

在 Xcode Asset Catalog 中创建 `AppIcon.appiconset`，至少覆盖 macOS 当前目标使用的 16、32、128、256、512、1024 px 规格（1x/2x 由对应文件名表达）。

图形规则：

- 圆角由 macOS 图标容器处理时，源图形保留安全边距；若使用预圆角源图，则所有尺寸保持同一圆角比例。
- 白色开放光圈位于几何中心，外环粗细统一；开口位置与缩小后仍可辨识。
- 中心镜头使用蓝色内芯、白色细环与一点柔和高光；缩小到 16/32 px 时减少高光细节，优先保留外圈、开口与中心点。
- 不在正式资源中加入文字。

### 2. 菜单栏图标

菜单栏使用同一「开放光圈」符号的单色模板，不直接使用完整 App 图标方形底。

- SwiftUI `MenuBarExtra` 使用自定义 `LensoMark` View 或等价模板图像。
- 浅色菜单栏使用深蓝/黑色模板，深色菜单栏使用白色模板；由 `foregroundStyle(.primary)` 或模板渲染负责适配。
- 默认尺寸约 18–20 pt，线宽需在该尺寸下连续、不糊成一团。
- 菜单栏图标保留：开放圆环、中心焦点；去除渐变、高光与阴影。
- 菜单栏图标应替换当前 `camera.viewfinder` 系统符号，不改变现有菜单交互或入口行为。

## 接入位置

- App 图标：当前 `project.yml` 使用 Xcode 默认 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`，实现时补充 `LENSO/Assets.xcassets/AppIcon.appiconset/`，不改变 bundle identifier 或构建设置。
- 菜单栏入口：`LENSO/LENSOApp.swift` 中的 `MenuBarExtra` 当前使用 `systemImage: "camera.viewfinder"`，改为承载自定义 `LensoMark` 的 label，同时保留菜单内容与快捷键。
- 菜单栏快捷面板 `LENSO/MenuBar/MenuBarPanelView.swift` 中的四个功能图标不属于本次品牌资产交付范围，继续使用各自的 SF Symbols；如后续需要品牌角标，应复用 `LensoMark`，不要复制 App 图标的蓝色方形底。

## 组件边界

- `LensoMark`：只负责绘制单色开放光圈符号，可被菜单栏、空状态、通知角标复用；不持有交互状态。
- `AppIcon.appiconset`：只负责 macOS App 图标位图资源，不由运行时 SwiftUI 绘制。
- `LENSOApp`：只负责把 `LensoMark` 接入 `MenuBarExtra` label，不把品牌绘制逻辑写进 App 场景文件。

## 验证标准

1. Xcode 能识别 `AppIcon.appiconset`，构建设置仍指向 `AppIcon`。
2. App 图标在 Finder/Dock 的 16–1024 px 规格下轮廓一致，缩小后仍能识别为开放光圈。
3. 菜单栏浅色与深色外观下都能看到连续的开放圆环和中心焦点。
4. `MenuBarExtra` 的现有区域截图、打开图库、设置、退出与快捷键行为不改变。
5. Swift 编译通过；新增的 `LensoMark` 没有引入第三方依赖。

## 不在本次范围

- 不重做菜单栏快捷面板内的四个功能图标。
- 不调整 LENSO 现有 DesignSystem 的颜色令牌；图标资源使用本规格中的品牌色。
- 不导出 iOS、iPadOS 或 Windows 图标规格。
- 不改变产品名称、菜单文字、窗口布局或截图流程。
