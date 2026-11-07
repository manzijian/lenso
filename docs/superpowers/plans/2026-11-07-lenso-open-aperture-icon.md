# LENSO Open Aperture Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已确认的「开放光圈 · Open Aperture」视觉方案落成 macOS AppIcon 资源，并用同一符号替换菜单栏的系统相机图标。

**Architecture:** 用 `LensoMark` SwiftUI View 负责菜单栏所需的单色模板图形；用独立的 Core Graphics 生成脚本绘制带克莱因蓝圆角底、白色开放光圈和中心镜头的 AppIcon PNG。资源放入 Xcode Asset Catalog，`LENSOApp` 只负责把品牌 View 作为 `MenuBarExtra` label 接入，不把绘制逻辑塞进 App 场景文件。

**Tech Stack:** Swift 6、SwiftUI、AppKit/Core Graphics、Xcode Asset Catalog、XcodeGen、xcodebuild。

---

### Task 1: Add the reusable menu bar brand mark

**Files:**
- Create: `LENSO/Brand/LensoMark.swift`

- [ ] **Step 1: Add the smallest reusable API**

Create `LensoMark` with one rendering mode and no state:

```swift
import SwiftUI

struct LensoMark: View {
    enum Rendering {
        case template
    }

    let rendering: Rendering

    init(rendering: Rendering = .template) {
        self.rendering = rendering
    }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = side * 0.34
            let innerRadius = side * 0.13
            let strokeWidth = side * 0.13
            let color = Color.primary

            var aperture = Path()
            aperture.addArc(
                center: center,
                radius: outerRadius,
                startAngle: .degrees(28),
                endAngle: .degrees(154),
                clockwise: false
            )
            aperture.addArc(
                center: center,
                radius: outerRadius,
                startAngle: .degrees(208),
                endAngle: .degrees(334),
                clockwise: false
            )
            context.stroke(
                aperture,
                with: .color(color),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
            )

            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - innerRadius,
                    y: center.y - innerRadius,
                    width: innerRadius * 2,
                    height: innerRadius * 2
                )),
                with: .color(color)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("LENSO")
    }
}
```

`Rendering` is intentionally small so future variants can be added without changing call sites. The first implementation must remain a monochrome template: no blue square, gradient, shadow, sparkle, or text in the menu bar mark.

- [ ] **Step 2: Run the source-level check before integration**

Run:

```bash
rg -n "struct LensoMark|case template|StrokeStyle|accessibilityLabel" LENSO/Brand/LensoMark.swift
```

Expected: the four declarations are present and there is no `Image(systemName:)` or hard-coded blue fill in this file.

- [ ] **Step 3: Commit the isolated brand mark**

```bash
git add LENSO/Brand/LensoMark.swift
git commit -m "feat: add open aperture brand mark"
```

---

### Task 2: Replace the system menu bar icon

**Files:**
- Modify: `LENSO/LENSOApp.swift:10`

- [ ] **Step 1: Keep the menu behavior and replace only its label**

Change the `MenuBarExtra` declaration from the system-image initializer to a custom label while leaving every existing menu action and keyboard shortcut unchanged:

```swift
MenuBarExtra {
    Button("区域截图") {
        CaptureCoordinator.shared.startRegionCapture()
    }
    .keyboardShortcut("1", modifiers: [.command, .shift])
    Divider()
    Button("打开图库") {
        openWindow(id: "library")
        NSApp.activate(ignoringOtherApps: true)
    }
    Button("设置…") {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
    Divider()
    Button("退出 LENSO") {
        NSApp.terminate(nil)
    }
    .keyboardShortcut("q")
} label: {
    LensoMark()
        .frame(width: 18, height: 18)
}
```

The surrounding `body` and window scenes remain unchanged. The custom label must not add a blue background, because macOS menu bar template rendering supplies the foreground appearance.

- [ ] **Step 2: Check that no menu behavior was dropped**

Run:

```bash
rg -n "区域截图|打开图库|设置…|退出 LENSO|keyboardShortcut|MenuBarExtra|LensoMark" LENSO/LENSOApp.swift
```

Expected: all four menu labels, both shortcuts, one `MenuBarExtra`, and one `LensoMark` label are present; `camera.viewfinder` is absent from the file.

- [ ] **Step 3: Commit the menu bar integration**

```bash
git add LENSO/LENSOApp.swift
git commit -m "feat: use open aperture mark in menu bar"
```

---

### Task 3: Generate and register AppIcon assets

**Files:**
- Create: `scripts/generate-lenso-app-icon.swift`
- Create: `LENSO/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `LENSO/Assets.xcassets/AppIcon.appiconset/icon_16.png`
- Create: `LENSO/Assets.xcassets/AppIcon.appiconset/icon_32.png`
- Create: `LENSO/Assets.xcassets/AppIcon.appiconset/icon_64.png`
- Create: `LENSO/Assets.xcassets/AppIcon.appiconset/icon_128.png`
- Create: `LENSO/Assets.xcassets/AppIcon.appiconset/icon_256.png`
- Create: `LENSO/Assets.xcassets/AppIcon.appiconset/icon_512.png`
- Create: `LENSO/Assets.xcassets/AppIcon.appiconset/icon_1024.png`

- [ ] **Step 1: Add a deterministic Core Graphics generator**

Create `scripts/generate-lenso-app-icon.swift` with this deterministic renderer:

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

precondition(CommandLine.arguments.count == 2, "usage: generate-lenso-app-icon.swift OUTPUT_DIR")

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let pixelSize = 1024
let canvas = CGFloat(pixelSize)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
let context = CGContext(
    data: nil,
    width: pixelSize,
    height: pixelSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo
)!

func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
context.saveGState()
let backgroundRect = CGRect(x: 72, y: 72, width: 880, height: 880)
let backgroundPath = CGPath(
    roundedRect: backgroundRect,
    cornerWidth: 220,
    cornerHeight: 220,
    transform: nil
)
context.addPath(backgroundPath)
context.clip()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(0.043, 0.282, 0.757), rgb(0.000, 0.157, 0.545)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 72, y: 952),
    end: CGPoint(x: 952, y: 72),
    options: []
)
context.restoreGState()

context.setStrokeColor(rgb(1, 1, 1))
context.setLineWidth(112)
context.setLineCap(.round)
context.addArc(
    center: CGPoint(x: canvas / 2, y: canvas / 2),
    radius: 304,
    startAngle: radians(28),
    endAngle: radians(154),
    clockwise: false
)
context.addArc(
    center: CGPoint(x: canvas / 2, y: canvas / 2),
    radius: 304,
    startAngle: radians(208),
    endAngle: radians(334),
    clockwise: false
)
context.strokePath()

let lensCenter = CGPoint(x: canvas / 2, y: canvas / 2)
let lensRect = CGRect(x: lensCenter.x - 104, y: lensCenter.y - 104, width: 208, height: 208)
context.setFillColor(rgb(0.000, 0.157, 0.545))
context.fillEllipse(in: lensRect)
context.setStrokeColor(rgb(1, 1, 1))
context.setLineWidth(48)
context.strokeEllipse(in: lensRect)
context.setFillColor(rgb(1, 1, 1))
context.fillEllipse(in: CGRect(x: 476, y: 480, width: 32, height: 32))

let outputURL = outputDirectory.appendingPathComponent("icon_1024.png")
let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
destination.addImage(context.makeImage()!)
precondition(CGImageDestinationFinalize(destination), "failed to write \(outputURL.path)")
```

This renders a transparent-corner square containing the `#002FA7` open aperture, a subtle `#0B48C1` to `#00278B` diagonal gradient, and the blue/white center lens. It has no text or external image dependency. The generator accepts one output directory argument and writes `icon_1024.png`.

- [ ] **Step 2: Generate the master PNG and verify its dimensions**

Run:

```bash
swift scripts/generate-lenso-app-icon.swift /tmp/lenso-appicon-master
sips -g pixelWidth -g pixelHeight /tmp/lenso-appicon-master/icon_1024.png
```

Expected: `pixelWidth: 1024` and `pixelHeight: 1024`.

- [ ] **Step 3: Create the required scaled PNG files**

Run:

```bash
mkdir -p LENSO/Assets.xcassets/AppIcon.appiconset
cp /tmp/lenso-appicon-master/icon_1024.png LENSO/Assets.xcassets/AppIcon.appiconset/icon_1024.png
sips -z 512 512 /tmp/lenso-appicon-master/icon_1024.png --out LENSO/Assets.xcassets/AppIcon.appiconset/icon_512.png
sips -z 256 256 /tmp/lenso-appicon-master/icon_1024.png --out LENSO/Assets.xcassets/AppIcon.appiconset/icon_256.png
sips -z 128 128 /tmp/lenso-appicon-master/icon_1024.png --out LENSO/Assets.xcassets/AppIcon.appiconset/icon_128.png
sips -z 64 64 /tmp/lenso-appicon-master/icon_1024.png --out LENSO/Assets.xcassets/AppIcon.appiconset/icon_64.png
sips -z 32 32 /tmp/lenso-appicon-master/icon_1024.png --out LENSO/Assets.xcassets/AppIcon.appiconset/icon_32.png
sips -z 16 16 /tmp/lenso-appicon-master/icon_1024.png --out LENSO/Assets.xcassets/AppIcon.appiconset/icon_16.png
```

The 1024 master is intentionally scaled down rather than redrawn so the family keeps the same proportions. The generator remains the source of truth if the mark is changed later.

- [ ] **Step 4: Register the macOS icon slots**

Create `Contents.json` with this exact structure:

```json
{
  "images": [
    { "filename": "icon_16.png", "idiom": "mac", "scale": "1x", "size": "16x16" },
    { "filename": "icon_32.png", "idiom": "mac", "scale": "2x", "size": "16x16" },
    { "filename": "icon_32.png", "idiom": "mac", "scale": "1x", "size": "32x32" },
    { "filename": "icon_64.png", "idiom": "mac", "scale": "2x", "size": "32x32" },
    { "filename": "icon_128.png", "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "filename": "icon_256.png", "idiom": "mac", "scale": "2x", "size": "128x128" },
    { "filename": "icon_256.png", "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "filename": "icon_512.png", "idiom": "mac", "scale": "2x", "size": "256x256" },
    { "filename": "icon_512.png", "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "icon_1024.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

The final JSON must reference only files that exist, use `idiom: "mac"` for every slot, and contain ten macOS image entries.

- [ ] **Step 5: Validate the catalog metadata and dimensions**

Run:

```bash
plutil -lint LENSO/Assets.xcassets/AppIcon.appiconset/Contents.json
find LENSO/Assets.xcassets/AppIcon.appiconset -name 'icon_*.png' -print | sort
```

Expected: `OK`, followed by seven PNG files (`icon_16`, `icon_32`, `icon_64`, `icon_128`, `icon_256`, `icon_512`, `icon_1024`) with no missing filename referenced by `Contents.json`.

- [ ] **Step 6: Commit the AppIcon assets**

```bash
git add scripts/generate-lenso-app-icon.swift LENSO/Assets.xcassets
git commit -m "feat: add open aperture app icon assets"
```

---

### Task 4: Regenerate the Xcode project and build

**Files:**
- Modify: `LENSO.xcodeproj/project.pbxproj` only if XcodeGen updates source references

- [ ] **Step 1: Regenerate the project from the existing manifest**

Run:

```bash
xcodegen generate
```

Expected: the existing `LENSO.xcodeproj` is regenerated from `project.yml`, the new `LensoMark.swift` source is included, and the `AppIcon` build setting remains present.

- [ ] **Step 2: Build without code signing**

Run:

```bash
xcodebuild -project LENSO.xcodeproj -scheme LENSO -configuration Debug -derivedDataPath /tmp/lenso-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` and no Swift compiler errors for `LensoMark` or `MenuBarExtra`.

- [ ] **Step 3: Verify the project still points at AppIcon**

Run:

```bash
rg -n "ASSETCATALOG_COMPILER_APPICON_NAME|AppIcon|LensoMark|camera.viewfinder" LENSO.xcodeproj/project.pbxproj LENSO/LENSOApp.swift
```

Expected: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` remains, and `camera.viewfinder` is absent from `LENSO/LENSOApp.swift`.

- [ ] **Step 4: Commit the generated project update**

```bash
git add LENSO.xcodeproj/project.pbxproj
git commit -m "chore: register brand mark in xcode project"
```

---

### Task 5: Remove exploration-only previews and perform final verification

**Files:**
- Delete: `demo/icon-candidates.html`
- Delete: `demo/icon-candidates-v2.html`
- Delete: `demo/icon-candidates-v3.html`
- Delete: `demo/icon-candidates-v4.html`
- Delete: `demo/icon-candidates-v5.html`
- Delete: `demo/icon-candidates-v6.html`
- Delete: `demo/icon-circle-candidate.html`
- Delete: `demo/icon-simple-candidate.html`

- [ ] **Step 1: Remove only the temporary visual exploration files**

These files were created during brainstorming and are not part of the approved product implementation. Delete exactly the eight paths above; keep `demo/lenso-ui-demo.html` unchanged.

- [ ] **Step 2: Run final repository checks**

Run:

```bash
git diff --check
git status --short
xcodebuild -project LENSO.xcodeproj -scheme LENSO -configuration Debug -derivedDataPath /tmp/lenso-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: no whitespace errors, only the intended icon/specification commits in history, and `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit cleanup**

```bash
git add -u demo
git commit -m "chore: remove icon exploration drafts"
```

After this task, report the generated asset paths, the `LensoMark` integration, the build output, and any verification limitation (for example, if the actual macOS menu bar cannot be rendered in the browser preview).
