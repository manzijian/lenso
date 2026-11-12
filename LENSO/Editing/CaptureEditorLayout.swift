import Foundation
import CoreGraphics

// MARK: - 布局计算与避免遮挡

struct EditorLayoutPositions {
    let toolbarFrame: CGRect
    let panelFrame: CGRect
}

enum CaptureEditorLayout {
    /// 计算工具栏与属性面板（OCR卡片）位置，严格保证二者永不重叠，避免保存/取消按钮被遮挡
    static func calculateLayout(
        selection: CGRect,
        screenSize: CGSize,
        toolbarSize: CGSize,
        panelSize: CGSize
    ) -> EditorLayoutPositions {
        let margin: CGFloat = 8
        let spacing: CGFloat = 12

        // 1. 计算 bottomToolbar 位置
        let toolbarX = min(
            max(toolbarSize.width / 2 + margin, selection.midX),
            screenSize.width - toolbarSize.width / 2 - margin
        )

        // 优先在选区下方；放不下放选区上方；都放不下放选区内底端（Snipaste 策略）
        let toolbarY: CGFloat
        if selection.maxY + spacing + toolbarSize.height + margin <= screenSize.height {
            toolbarY = selection.maxY + spacing + toolbarSize.height / 2
        } else if selection.minY - spacing - toolbarSize.height >= margin {
            toolbarY = selection.minY - spacing - toolbarSize.height / 2
        } else {
            toolbarY = min(
                selection.maxY - spacing - toolbarSize.height / 2,
                screenSize.height - toolbarSize.height / 2 - margin
            )
        }

        let toolbarRect = CGRect(
            x: toolbarX - toolbarSize.width / 2,
            y: toolbarY - toolbarSize.height / 2,
            width: toolbarSize.width,
            height: toolbarSize.height
        )

        // 2. 计算 sidePanel（OCR/属性面板）位置
        // 优先放选区右侧；右侧不够放选区左侧；两边都不够放屏幕右侧
        let panelX: CGFloat
        if selection.maxX + spacing + panelSize.width + margin <= screenSize.width {
            panelX = selection.maxX + spacing + panelSize.width / 2
        } else if selection.minX - spacing - panelSize.width >= margin {
            panelX = selection.minX - spacing - panelSize.width / 2
        } else {
            panelX = screenSize.width - panelSize.width / 2 - margin
        }

        let panelLeft = panelX - panelSize.width / 2
        let panelRight = panelX + panelSize.width / 2

        // 判断 X 轴是否与底部工具栏重叠（留出间距）
        let overlapsX = panelLeft < toolbarRect.maxX + spacing && panelRight > toolbarRect.minX - spacing

        var panelY: CGFloat
        if overlapsX {
            // X 轴重叠：垂直方向严格避让工具栏，绝不能遮挡保存/取消按钮
            if toolbarRect.midY > screenSize.height / 2 {
                // 工具栏偏屏幕下方：属性面板放置在工具栏上方
                let maxPanelBottom = toolbarRect.minY - spacing
                panelY = maxPanelBottom - panelSize.height / 2
                panelY = max(panelSize.height / 2 + margin, panelY)
            } else {
                // 工具栏偏屏幕上方：属性面板放置在工具栏下方
                let minPanelTop = toolbarRect.maxY + spacing
                panelY = minPanelTop + panelSize.height / 2
                panelY = min(screenSize.height - panelSize.height / 2 - margin, panelY)
            }
        } else {
            // X 轴不重叠：垂直居中于选区
            panelY = min(
                max(panelSize.height / 2 + margin, selection.midY),
                screenSize.height - panelSize.height / 2 - margin
            )
        }

        let panelRect = CGRect(
            x: panelX - panelSize.width / 2,
            y: panelY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )

        return EditorLayoutPositions(toolbarFrame: toolbarRect, panelFrame: panelRect)
    }
}
