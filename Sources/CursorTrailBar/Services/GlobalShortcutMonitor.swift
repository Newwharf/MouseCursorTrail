//
// GlobalShortcutMonitor.swift
// MVC: 输入服务（快捷键监听）
//
import AppKit
import ApplicationServices

@MainActor
/// 全局快捷键监听器（监听键盘 + 鼠标按压/释放，listenOnly 不拦截系统事件）。
final class GlobalShortcutMonitor {
    var onInput: ((ShortcutInputEvent) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// 启动监听 tap。
    /// - Returns: 是否成功创建并启用监听 tap。
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        if !CGPreflightListenEventAccess() {
            AppLogger.shared.log("global shortcut monitor start without input monitoring permission")
        }

        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { proxy, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                    monitor.handle(proxy: proxy, type: type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: userInfo
            )
        else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// 停止监听 tap 并移除 RunLoop source。
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        guard let input = mapInput(type: type, event: event) else { return }
        onInput?(input)
    }

    private func mapInput(type: CGEventType, event: CGEvent) -> ShortcutInputEvent? {
        let modifiers = modifierFlags(from: event.flags)

        switch type {
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return ShortcutInputEvent(kind: .keyDown, keyCode: keyCode, modifiers: modifiers)
        case .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return ShortcutInputEvent(kind: .keyUp, keyCode: keyCode, modifiers: modifiers)
        case .leftMouseDown:
            return ShortcutInputEvent(kind: .leftDown, modifiers: modifiers)
        case .leftMouseUp:
            return ShortcutInputEvent(kind: .leftUp, modifiers: modifiers)
        case .rightMouseDown:
            return ShortcutInputEvent(kind: .rightDown, modifiers: modifiers)
        case .rightMouseUp:
            return ShortcutInputEvent(kind: .rightUp, modifiers: modifiers)
        case .otherMouseDown:
            return ShortcutInputEvent(kind: .middleDown, modifiers: modifiers)
        case .otherMouseUp:
            return ShortcutInputEvent(kind: .middleUp, modifiers: modifiers)
        default:
            return nil
        }
    }

    private func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }
}

/// 全局滚轮拦截器。
/// 用于放大镜激活时优先消费滚轮输入，避免同时触发系统滚动。
