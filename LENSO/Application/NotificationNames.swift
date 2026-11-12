import Foundation

extension Notification.Name {
    static let screenshotSaved = Notification.Name("com.lenso.screenshotSaved")
    /// 截图后显示预览：保存完成后发给菜单栏面板，打开预览窗口
    static let openPreviewForScreenshot = Notification.Name("com.lenso.openPreviewForScreenshot")
    /// 编辑器滚轮事件通知
    static let editorScrollWheel = Notification.Name("com.lenso.editorScrollWheel")
    /// 编辑器鼠标右键事件通知
    static let editorRightClick = Notification.Name("com.lenso.editorRightClick")
}
