//
// GlobalScrollInterceptor.swift
// MVC: 输入服务（滚轮拦截）
//
import AppKit
import ApplicationServices
import QuartzCore

final class GlobalScrollInterceptor {
    var onScroll: ((MouseSignal) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shouldConsumeScroll = false
    private var lastConsumedScrollLogTimestamp: CFTimeInterval = 0
    private var lastPassthroughScrollLogTimestamp: CFTimeInterval = 0

    func setConsumesScroll(_ consume: Bool) {
        if shouldConsumeScroll != consume {
            AppLogger.shared.log("scroll interceptor consume state changed: \(shouldConsumeScroll) -> \(consume)")
        }
        shouldConsumeScroll = consume
    }

    var isRunning: Bool {
        eventTap != nil
    }

    /// 启动全局滚轮拦截 tap。
    /// - Returns: 是否启动成功；失败通常由系统权限或 tap 创建失败导致。
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let listenGranted = CGPreflightListenEventAccess()
        guard listenGranted else {
            AppLogger.shared.log(
                "scroll interceptor start skipped due to permission: listenGranted=\(listenGranted)"
            )
            return false
        }

        let eventMask =
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<GlobalScrollInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            return interceptor.handle(proxy: proxy, type: type, event: event)
        }

        let attempts: [(CGEventTapLocation, CGEventTapPlacement, CGEventTapOptions, String)] = [
            (.cghidEventTap, .headInsertEventTap, .defaultTap, "cghid/head/default"),
            (.cghidEventTap, .tailAppendEventTap, .defaultTap, "cghid/tail/default"),
            (.cgSessionEventTap, .headInsertEventTap, .defaultTap, "session/head/default"),
            (.cgSessionEventTap, .tailAppendEventTap, .defaultTap, "session/tail/default"),
            (.cgAnnotatedSessionEventTap, .headInsertEventTap, .defaultTap, "annotated/head/default"),
            (.cgAnnotatedSessionEventTap, .tailAppendEventTap, .defaultTap, "annotated/tail/default"),
        ]

        var tapSource = "none"
        var tap: CFMachPort?
        for (location, placement, options, label) in attempts {
            if let created = CGEvent.tapCreate(
                tap: location,
                place: placement,
                options: options,
                eventsOfInterest: CGEventMask(eventMask),
                callback: callback,
                userInfo: userInfo
            ) {
                tapSource = label
                tap = created
                break
            }
            AppLogger.shared.log("scroll interceptor tap attempt failed: \(label)")
        }

        if tap == nil {
            for (location, placement, options, label) in attempts {
                if let created = CGEvent.tapCreate(
                    tap: location,
                    place: placement,
                    options: options,
                    eventsOfInterest: CGEventMask(eventMask),
                    callback: callback,
                    userInfo: userInfo
                ) {
                    tapSource = label + " (after-permission)"
                    tap = created
                    break
                }
                AppLogger.shared.log("scroll interceptor tap retry failed: \(label)")
            }
        }

        guard let tap else {
            let listen = CGPreflightListenEventAccess()
            let ax = AXIsProcessTrusted()
            AppLogger.shared.log("scroll interceptor failed to start. listenAccess=\(listen), accessibilityTrusted=\(ax)")
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        AppLogger.shared.log("scroll interceptor started with \(tapSource)")
        return true
    }

    /// 停止滚轮拦截并清理运行时资源。
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        AppLogger.shared.log("scroll interceptor stopped")
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        let lineDeltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let sourceDeltaY = lineDeltaY != 0 ? lineDeltaY : pointDeltaY
        let normalizedDeltaY = abs(sourceDeltaY) < 1 ? sourceDeltaY * 10 : sourceDeltaY
        let deltaY = CGFloat(normalizedDeltaY)
        let signal = MouseSignal(
            location: NSPoint(x: location.x, y: location.y),
            kind: .scroll(deltaY: deltaY),
            timestamp: CACurrentMediaTime()
        )

        onScroll?(signal)

        let now = CACurrentMediaTime()
        if shouldConsumeScroll {
            if now - lastConsumedScrollLogTimestamp > 0.22 {
                AppLogger.shared.log(
                    "scroll intercepted and consumed (line=\(rounded(lineDeltaY, scale: 10)), point=\(rounded(pointDeltaY, scale: 10)), normalized=\(rounded(Double(deltaY), scale: 10)))"
                )
                lastConsumedScrollLogTimestamp = now
            }
            return nil
        }
        if now - lastPassthroughScrollLogTimestamp > 0.8 {
            AppLogger.shared.log(
                "scroll passed through (line=\(rounded(lineDeltaY, scale: 10)), point=\(rounded(pointDeltaY, scale: 10)), normalized=\(rounded(Double(deltaY), scale: 10)))"
            )
            lastPassthroughScrollLogTimestamp = now
        }
        return Unmanaged.passUnretained(event)
    }
}
