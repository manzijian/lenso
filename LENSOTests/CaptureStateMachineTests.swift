import Testing
import AppKit
import CoreGraphics
import Foundation
@testable import LENSO

@Suite("CaptureCoordinator 状态机与依赖注入测试", .serialized)
struct CaptureStateMachineTests {

    private func make1x1Image() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: UInt32 = 0xFF0000FF
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private func makeTemporaryStore() -> (ScreenshotStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LENSO_CaptureTest_\(UUID().uuidString)", isDirectory: true)
        let store = ScreenshotStore(baseDirectory: tempDir)
        return (store, tempDir)
    }

    @Test("抓帧成功：captureFrameAndProceed 调用底层抓帧并成功流转")
    @MainActor
    func testCaptureSuccess() async throws {
        let image = make1x1Image()
        let mockCapture = MockCaptureService(image: image)
        let mockClipboard = MockClipboard()
        let mockPresenter = MockErrorPresenter()
        let (store, tempDir) = makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = CaptureCoordinator(
            capture: mockCapture,
            clipboard: mockClipboard,
            errorPresenter: mockPresenter,
            store: store
        )

        let success = await coordinator.captureFrameAndProceed(
            displayID: 1,
            excludedWindowIDs: [],
            prefrozen: nil,
            rect: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        #expect(success == true)
        #expect(mockPresenter.presentedErrors.isEmpty)
        coordinator.closeEditor()
    }

    @Test("权限失败：captureFrameAndProceed 捕获 SCStreamErrorDomain 并唤起权限提示")
    @MainActor
    func testCapturePermissionFailure() async throws {
        let mockCapture = MockCaptureService()
        mockCapture.shouldThrowPermissionError = true
        let mockClipboard = MockClipboard()
        let mockPresenter = MockErrorPresenter()
        let (store, tempDir) = makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = CaptureCoordinator(
            capture: mockCapture,
            clipboard: mockClipboard,
            errorPresenter: mockPresenter,
            store: store
        )

        let success = await coordinator.captureFrameAndProceed(
            displayID: 1,
            excludedWindowIDs: [],
            prefrozen: nil,
            rect: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        #expect(success == false)
        #expect(mockPresenter.presentedErrors.count == 1)
        #expect(mockPresenter.presentedErrors.first?.isPermission == true)
        #expect(mockPresenter.presentedErrors.first?.title.contains("权限") == true)
    }

    @Test("一般失败：底层发生非权限未知错误时唤起普通错误弹窗")
    @MainActor
    func testCaptureGenericFailure() async throws {
        let mockCapture = MockCaptureService()
        mockCapture.shouldThrowGenericError = true
        let mockClipboard = MockClipboard()
        let mockPresenter = MockErrorPresenter()
        let (store, tempDir) = makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = CaptureCoordinator(
            capture: mockCapture,
            clipboard: mockClipboard,
            errorPresenter: mockPresenter,
            store: store
        )

        let success = await coordinator.captureFrameAndProceed(
            displayID: 1,
            excludedWindowIDs: [],
            prefrozen: nil,
            rect: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        #expect(success == false)
        #expect(mockPresenter.presentedErrors.count == 1)
        #expect(mockPresenter.presentedErrors.first?.isPermission == false)
    }

    @Test("丢弃分支：handleFinish(finalImage: nil) 不落盘、不写剪贴板、不发通知")
    @MainActor
    func testHandleFinishDiscard() throws {
        let mockCapture = MockCaptureService()
        let mockClipboard = MockClipboard()
        let mockPresenter = MockErrorPresenter()
        let (store, tempDir) = makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = CaptureCoordinator(
            capture: mockCapture,
            clipboard: mockClipboard,
            errorPresenter: mockPresenter,
            store: store
        )

        var notificationFired = false
        let observer = NotificationCenter.default.addObserver(
            forName: .screenshotSaved,
            object: nil,
            queue: .main
        ) { _ in
            notificationFired = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        coordinator.handleFinish(finalImage: nil)

        #expect(notificationFired == false)
        #expect(mockClipboard.writtenImages.isEmpty)
        let records = try store.list()
        #expect(records.isEmpty)
    }

    @Test("保存完成：handleFinish(finalImage: img) 落盘、写剪贴板并发送通知")
    @MainActor
    func testHandleFinishSuccess() throws {
        let image = make1x1Image()
        let mockCapture = MockCaptureService()
        let mockClipboard = MockClipboard()
        let mockPresenter = MockErrorPresenter()
        let (store, tempDir) = makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = CaptureCoordinator(
            capture: mockCapture,
            clipboard: mockClipboard,
            errorPresenter: mockPresenter,
            store: store
        )

        var receivedRecord: ScreenshotRecord?
        let observer = NotificationCenter.default.addObserver(
            forName: .screenshotSaved,
            object: nil,
            queue: .main
        ) { note in
            receivedRecord = note.object as? ScreenshotRecord
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        coordinator.handleFinish(finalImage: image)

        #expect(receivedRecord != nil)
        #expect(mockClipboard.writtenImages.count == 1)

        let records = try store.list()
        #expect(records.count == 1)
        #expect(records.first?.id == receivedRecord?.id)
    }
}

// MARK: - Mocks

final class MockCaptureService: ScreenCapturing, @unchecked Sendable {
    var shouldThrowPermissionError: Bool = false
    var shouldThrowGenericError: Bool = false
    var imageToReturn: CGImage?

    init(image: CGImage? = nil) {
        self.imageToReturn = image
    }

    func captureDisplayExcluding(displayID: CGDirectDisplayID, excludedWindowIDs: [CGWindowID]) async throws -> CGImage {
        if shouldThrowPermissionError {
            throw NSError(
                domain: "SCStreamErrorDomain",
                code: -3801,
                userInfo: [NSLocalizedDescriptionKey: "Screen capture not permitted"]
            )
        }
        if shouldThrowGenericError {
            throw NSError(
                domain: "CaptureTestDomain",
                code: 999,
                userInfo: [NSLocalizedDescriptionKey: "Generic capture failed"]
            )
        }
        if let img = imageToReturn {
            return img
        }
        throw NSError(
            domain: "CaptureTestDomain",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No image provided"]
        )
    }
}

@MainActor
final class MockClipboard: ClipboardWriting {
    var writtenImages: [CGImage] = []
    var writtenTexts: [String] = []

    func writeImage(_ image: CGImage) {
        writtenImages.append(image)
    }

    func writeText(_ text: String) {
        writtenTexts.append(text)
    }
}

@MainActor
final class MockErrorPresenter: ErrorPresenting {
    struct PresentedError {
        let title: String
        let message: String
        let isPermission: Bool
    }
    var presentedErrors: [PresentedError] = []

    func presentCaptureError(title: String, message: String, isPermission: Bool) {
        presentedErrors.append(PresentedError(title: title, message: message, isPermission: isPermission))
    }
}
