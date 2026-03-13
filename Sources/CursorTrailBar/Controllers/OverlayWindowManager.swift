//
// OverlayWindowManager.swift
// MVC: Controller 层（多屏覆盖层协调）
//
import AppKit

@MainActor
/// 多屏覆盖层窗口管理器。
/// 职责：为每块屏幕构建一层透明渲染窗口，并在屏幕拓扑变化时重建。
final class OverlayWindowManager {
    private struct Overlay {
        let window: NSWindow
        let view: TrailOverlayView
    }

    private var overlays: [Overlay] = []
    private(set) var isEnabled = true
    private(set) var isTrackingEnabled = true
    private var isMagnifierActive = false
    private var settings: AppSettings = .default

    init() {
        rebuildOverlays()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenConfigurationChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// 设置 overlay 整体启停状态。
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            for overlay in overlays {
                overlay.window.orderFrontRegardless()
            }
        } else {
            clear()
            for overlay in overlays {
                overlay.view.setMagnifierActive(false)
                overlay.window.orderOut(nil)
            }
        }
    }

    /// 更新轨迹主开关（同时同步到所有屏幕 overlay）。
    func setTrackingEnabled(_ enabled: Bool) {
        isTrackingEnabled = enabled
        for overlay in overlays {
            overlay.view.setTrailEnabled(enabled)
        }
    }

    /// 设置放大镜激活状态（受全局配置开关约束）。
    func setMagnifierActive(_ active: Bool) {
        isMagnifierActive = settings.isMagnifierEnabled && active
        for overlay in overlays {
            overlay.view.setMagnifierActive(isMagnifierActive)
        }
    }

    /// 清空所有屏幕 overlay 的瞬态渲染缓存。
    func clear() {
        for overlay in overlays {
            overlay.view.clear()
        }
    }

    /// 下发最新设置到所有屏幕 overlay。
    func setSettings(_ settings: AppSettings) {
        self.settings = settings
        if !settings.isMagnifierEnabled {
            setMagnifierActive(false)
        }
        for overlay in overlays {
            overlay.view.applySettings(settings)
        }
    }

    /// 将输入信号分发到对应屏幕 overlay。
    func process(signal: MouseSignal) {
        guard isEnabled else { return }
        for overlay in overlays {
            overlay.view.process(signal: signal, in: overlay.window.frame)
        }
    }

    @objc
    private func handleScreenConfigurationChange() {
        rebuildOverlays()
    }

    private func rebuildOverlays() {
        for overlay in overlays {
            overlay.view.shutdown()
            overlay.window.orderOut(nil)
        }
        overlays.removeAll()

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = TrailOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            view.applySettings(settings)
            view.setTrailEnabled(isTrackingEnabled)
            view.setMagnifierActive(isMagnifierActive)
            window.contentView = view

            if isEnabled {
                window.orderFrontRegardless()
            }

            overlays.append(Overlay(window: window, view: view))
        }
    }
}
