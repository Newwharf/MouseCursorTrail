//
// HotKeyManager.swift
// MVC: 系统服务（全局热键）
//
import Carbon

@MainActor
/// 应用级热键管理器（Control + Option + Command + T）。
final class HotKeyManager {
    private static let hotKeySignature = fourCharCode("CTRB")
    private static let hotKeyID: UInt32 = 1

    var onToggle: (() -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    var displayLabel: String {
        "⌃⌥⌘T"
    }

    /// 注册全局热键事件处理。
    /// - Returns: 注册是否成功。
    @discardableResult
    func registerHotKey() -> Bool {
        guard eventHandlerRef == nil, hotKeyRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return noErr }

                var hotKeyData = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyData
                )
                guard parameterStatus == noErr else { return parameterStatus }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                if hotKeyData.signature == HotKeyManager.hotKeySignature, hotKeyData.id == HotKeyManager.hotKeyID {
                    manager.onToggle?()
                }
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        let modifiers = UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            unregisterHotKey()
            return false
        }
        return true
    }

    /// 注销热键与事件处理器，释放系统资源。
    func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
