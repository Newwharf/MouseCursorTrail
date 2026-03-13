//
// MouseMonitor.swift
// MVC: 输入服务（鼠标监听分发）
//
import AppKit
import QuartzCore

@MainActor
/// 鼠标事件收集器（同时挂载 global/local monitor，统一分发到主线程）。
final class MouseMonitor {
    var onEvent: ((MouseSignal) -> Void)?
    var onRawEvent: ((NSEvent) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let eventMask: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseUp,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
    ]

    /// 启动全局与本地鼠标监听。
    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.dispatchHandle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.dispatchHandle(event)
            return event
        }
    }

    /// 停止监听并移除已注册 monitor。
    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handle(event: NSEvent) {
        onRawEvent?(event)
        guard let kind = map(event: event) else { return }
        let location = NSEvent.mouseLocation
        let signal = MouseSignal(location: location, kind: kind, timestamp: CACurrentMediaTime())
        onEvent?(signal)
    }

    private func dispatchHandle(_ event: NSEvent) {
        if Thread.isMainThread {
            handle(event: event)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.handle(event: event)
            }
        }
    }

    private func map(event: NSEvent) -> MouseEventKind? {
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return .move
        case .leftMouseDown:
            return .leftDown
        case .leftMouseUp:
            return .leftUp
        case .rightMouseDown:
            return .rightDown
        case .rightMouseUp:
            return .rightUp
        case .otherMouseDown:
            return .otherDown
        case .otherMouseUp:
            return .otherUp
        default:
            return nil
        }
    }
}
