//
// CursorTrailBar.swift
// 负责：鼠标轨迹渲染、加速爆发/点击/放大镜特效，以及设置窗口与应用生命周期编排。
// 边界：配置持久化依赖 UserDefaults；核心逻辑按“数据模型/渲染/UI/AppDelegate”分区维护。
//
import AppKit
import ApplicationServices
import Carbon
import QuartzCore
import ServiceManagement

/// 鼠标输入事件的统一分类，用于驱动渲染与交互状态机。
enum MouseEventKind {
    case move
    case leftDown
    case leftUp
    case rightDown
    case rightUp
    case otherDown
    case otherUp
    case scroll(deltaY: CGFloat)
}

/// 单帧输入信号，包含位置、事件类型和时间戳。
struct MouseSignal {
    let location: NSPoint
    let kind: MouseEventKind
    let timestamp: CFTimeInterval
}

/// 鼠标按键枚举，用于点击特效与快捷键触发源映射。
enum MouseButtonKind: String, CaseIterable {
    case left
    case right
    case middle

    var title: String {
        switch self {
        case .left:
            return "左键"
        case .right:
            return "右键"
        case .middle:
            return "中键"
        }
    }
}

/// 特效强度预设，统一控制粒子数量、寿命和发光程度。
enum EffectIntensityPreset: String, CaseIterable {
    case off
    case low
    case normal
    case high

    var title: String {
        switch self {
        case .off:
            return "关闭"
        case .low:
            return "低（省资源）"
        case .normal:
            return "中（默认）"
        case .high:
            return "高（炫彩）"
        }
    }

    var particleSpawnMultiplier: CGFloat {
        switch self {
        case .off:
            return 0
        case .low:
            return 0.7
        case .normal:
            return 1.0
        case .high:
            return 1.6
        }
    }

    var particleLifetime: CFTimeInterval {
        switch self {
        case .off:
            return 0.01
        case .low:
            return 0.35
        case .normal:
            return 0.5
        case .high:
            return 0.65
        }
    }

    var particleSizeRange: ClosedRange<CGFloat> {
        switch self {
        case .off:
            return 0.1...0.1
        case .low:
            return 1.2...2.2
        case .normal:
            return 1.8...3.2
        case .high:
            return 2.2...4.2
        }
    }

    var particleSpeedRange: ClosedRange<CGFloat> {
        switch self {
        case .off:
            return 0...0
        case .low:
            return 12...35
        case .normal:
            return 20...55
        case .high:
            return 35...85
        }
    }

    var maxParticleCount: Int {
        switch self {
        case .off:
            return 0
        case .low:
            return 120
        case .normal:
            return 220
        case .high:
            return 360
        }
    }

    var glowBoost: CGFloat {
        switch self {
        case .off:
            return 0
        case .low:
            return 0.8
        case .normal:
            return 1.0
        case .high:
            return 1.35
        }
    }

    var effectsEnabled: Bool {
        self != .off
    }
}

/// 轨迹主渲染风格。
enum TrailRenderStyle: String, CaseIterable {
    case neon
    case ribbon
    case rainbow
    case lightning

    var title: String {
        switch self {
        case .neon: return "双层霓虹"
        case .ribbon: return "渐隐丝带"
        case .rainbow: return "彩虹拖尾"
        case .lightning: return "闪电轨迹"
        }
    }
}

/// 轨迹附加特效类型。
enum TrailEffectStyle: String, CaseIterable {
    case particles
    case ink
    case electric

    var title: String {
        switch self {
        case .particles: return "粒子火花"
        case .ink: return "墨迹扩散"
        case .electric: return "电弧闪点"
        }
    }
}

/// 加速爆发类型（当前仅保留“一之闪”）。
enum SpeedBurstEffectType: String, CaseIterable {
    case firstFlash

    var title: String {
        switch self {
        case .firstFlash:
            return "一之闪"
        }
    }
}

/// 点击可视化风格。
enum ClickVisualStyle: String, CaseIterable {
    case solidPulse
    case crossFlare

    var title: String {
        switch self {
        case .solidPulse: return "实心脉冲"
        case .crossFlare: return "十字闪光"
        }
    }
}

/// 单个按键的点击特效配置。
struct ClickEffectStyle {
    var isEnabled: Bool
    var color: NSColor
}

/// 放大镜快捷键触发源类型。
enum ShortcutTriggerKind: String {
    case keyboard
    case mouse
}

/// 快捷键输入的抽象事件类型，屏蔽 NSEvent/CGEvent 差异。
enum ShortcutInputKind {
    case keyDown
    case keyUp
    case leftDown
    case leftUp
    case rightDown
    case rightUp
    case middleDown
    case middleUp
}

/// 快捷键输入事件（类型 + 修饰键 + 可选键码）。
struct ShortcutInputEvent {
    let kind: ShortcutInputKind
    let keyCode: UInt16?
    let modifiers: NSEvent.ModifierFlags

    init(kind: ShortcutInputKind, keyCode: UInt16? = nil, modifiers: NSEvent.ModifierFlags) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift])
    }
}

/// 放大镜快捷键配置。
/// 注意：修饰键比较采用“包含关系”，允许用户额外按住其他修饰键。
struct MagnifierShortcut {
    var triggerKind: ShortcutTriggerKind
    var keyCode: UInt16?
    var mouseButton: MouseButtonKind?
    var modifiersRaw: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRaw).intersection([.command, .option, .control, .shift])
    }

    static let `default` = MagnifierShortcut(
        triggerKind: .keyboard,
        keyCode: UInt16(kVK_ANSI_M),
        mouseButton: nil,
        modifiersRaw: NSEvent.ModifierFlags([.command, .option]).rawValue
    )

    /// 从原始 NSEvent 捕获快捷键定义；过滤纯修饰键按下，避免录制无效快捷键。
    static func capture(from event: NSEvent) -> MagnifierShortcut? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.type {
        case .keyDown:
            let code = event.keyCode
            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 60, 58, 61, 59, 62, 57, 63]
            guard !modifierKeyCodes.contains(code) else { return nil }
            return MagnifierShortcut(
                triggerKind: .keyboard,
                keyCode: code,
                mouseButton: nil,
                modifiersRaw: modifiers.rawValue
            )
        case .leftMouseDown:
            return MagnifierShortcut(
                triggerKind: .mouse,
                keyCode: nil,
                mouseButton: .left,
                modifiersRaw: modifiers.rawValue
            )
        case .rightMouseDown:
            return MagnifierShortcut(
                triggerKind: .mouse,
                keyCode: nil,
                mouseButton: .right,
                modifiersRaw: modifiers.rawValue
            )
        case .otherMouseDown:
            return MagnifierShortcut(
                triggerKind: .mouse,
                keyCode: nil,
                mouseButton: .middle,
                modifiersRaw: modifiers.rawValue
            )
        default:
            return nil
        }
    }

    func matchesPress(event: NSEvent) -> Bool {
        guard let input = shortcutInputEvent(from: event) else { return false }
        return matchesPress(input: input)
    }

    func matchesRelease(event: NSEvent) -> Bool {
        guard let input = shortcutInputEvent(from: event) else { return false }
        return matchesRelease(input: input)
    }

    func matchesPress(input: ShortcutInputEvent) -> Bool {
        guard input.modifiers.isSuperset(of: modifiers) else { return false }
        switch triggerKind {
        case .keyboard:
            return input.kind == .keyDown && input.keyCode == keyCode
        case .mouse:
            guard let button = mouseButton else { return false }
            switch button {
            case .left:
                return input.kind == .leftDown
            case .right:
                return input.kind == .rightDown
            case .middle:
                return input.kind == .middleDown
            }
        }
    }

    func matchesRelease(input: ShortcutInputEvent) -> Bool {
        switch triggerKind {
        case .keyboard:
            return input.kind == .keyUp && input.keyCode == keyCode
        case .mouse:
            guard let button = mouseButton else { return false }
            switch button {
            case .left:
                return input.kind == .leftUp
            case .right:
                return input.kind == .rightUp
            case .middle:
                return input.kind == .middleUp
            }
        }
    }

    var displayText: String {
        let modifierText = modifiersDisplayString(modifiers)
        switch triggerKind {
        case .keyboard:
            let keyText = keyCodeDisplayName(keyCode ?? 0)
            return modifierText + keyText
        case .mouse:
            let mouseText = switch mouseButton {
            case .left?:
                "左键"
            case .right?:
                "右键"
            case .middle?:
                "中键"
            case nil:
                "鼠标键"
            }
            return modifierText + mouseText
        }
    }
}

/// 将 AppKit 事件统一映射为内部快捷键输入结构，便于复用匹配逻辑。
private func shortcutInputEvent(from event: NSEvent) -> ShortcutInputEvent? {
    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
    switch event.type {
    case .keyDown:
        return ShortcutInputEvent(kind: .keyDown, keyCode: event.keyCode, modifiers: modifiers)
    case .keyUp:
        return ShortcutInputEvent(kind: .keyUp, keyCode: event.keyCode, modifiers: modifiers)
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

private func modifiersDisplayString(_ modifiers: NSEvent.ModifierFlags) -> String {
    var text = ""
    if modifiers.contains(.control) { text += "⌃" }
    if modifiers.contains(.option) { text += "⌥" }
    if modifiers.contains(.shift) { text += "⇧" }
    if modifiers.contains(.command) { text += "⌘" }
    return text
}

private func keyCodeDisplayName(_ keyCode: UInt16) -> String {
    let map: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C", UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F", UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I", UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O", UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R", UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U", UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5", UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return", UInt16(kVK_Tab): "Tab", UInt16(kVK_Escape): "Esc",
    ]
    return map[keyCode] ?? "Key\(keyCode)"
}

private func colorFromHexRGB(_ hex: Int, alpha: CGFloat = 1.0) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255.0
    let green = CGFloat((hex >> 8) & 0xFF) / 255.0
    let blue = CGFloat(hex & 0xFF) / 255.0
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

private func encodeColorData(_ color: NSColor) -> Data? {
    try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false)
}

private func decodeColorData(_ data: Data?) -> NSColor? {
    guard let data else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
}

/// 应用全局设置模型。
/// 说明：既承载运行态配置，也承载“雷之呼吸·壹之型”预设快照读写能力。
struct AppSettings {
    var isLaunchAtLoginEnabled: Bool
    var isLoggingEnabled: Bool
    var isStatusItemVisible: Bool
    var isTrackingEnabled: Bool
    var isClickEffectsEnabled: Bool
    var isMagnifierEnabled: Bool
    var trailColor: NSColor
    var trailEffectColor: NSColor
    var trailStyle: TrailRenderStyle
    var trailEffectStyle: TrailEffectStyle
    var rainbowTrailColors: [NSColor]
    var neonPrimaryColor: NSColor
    var neonSecondaryColor: NSColor
    var trailWidth: CGFloat
    var trailLengthMilliseconds: Double
    var clickVisualStyle: ClickVisualStyle
    var clickEffectRadius: CGFloat
    var clickEffectDurationMilliseconds: Double
    var magnifierRadius: CGFloat
    var magnifierZoom: CGFloat
    var magnifierBorderWidth: CGFloat
    var magnifierBorderColor: NSColor
    var magnifierShadowOpacity: CGFloat
    var showTrailEffectsWhileMagnifierActive: Bool
    var magnifierShortcut: MagnifierShortcut
    var intensityPreset: EffectIntensityPreset
    var speedBurstEnabled: Bool
    var speedBurstType: SpeedBurstEffectType
    var speedBurstVelocityThreshold: CGFloat
    var speedBurstCooldownMilliseconds: Double
    var speedBurstDurationMilliseconds: Double
    var speedBurstAfterglowMilliseconds: Double
    var speedBurstJitterAmplitude: CGFloat
    var speedBurstMinLength: CGFloat
    var speedBurstMaxLength: CGFloat
    var speedBurstWidthMultiplier: CGFloat
    var speedBurstLineColor: NSColor
    var speedBurstAccentColor: NSColor
    var speedBurstAccentDurationMilliseconds: Double
    var speedBurstAccentSize: CGFloat
    var clickEffects: [MouseButtonKind: ClickEffectStyle]

    func effectStyle(for button: MouseButtonKind) -> ClickEffectStyle {
        clickEffects[button] ?? ClickEffectStyle(isEnabled: true, color: .systemBlue)
    }

    private static let thunderPresetPrefix = "preset.thunder."
    static let thunderPresetSeededKey = "preset.thunder.seeded"

    private static func thunderPresetKey(_ suffix: String) -> String {
        thunderPresetPrefix + suffix
    }

    static let `default` = AppSettings(
        isLaunchAtLoginEnabled: false,
        isLoggingEnabled: false,
        isStatusItemVisible: true,
        isTrackingEnabled: true,
        isClickEffectsEnabled: true,
        isMagnifierEnabled: true,
        trailColor: colorFromHexRGB(0xFFD84A),
        trailEffectColor: colorFromHexRGB(0xFFB84D),
        trailStyle: .lightning,
        trailEffectStyle: .electric,
        rainbowTrailColors: [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple],
        neonPrimaryColor: .systemCyan,
        neonSecondaryColor: .systemPink,
        trailWidth: 3.4,
        trailLengthMilliseconds: 420,
        clickVisualStyle: .crossFlare,
        clickEffectRadius: 34,
        clickEffectDurationMilliseconds: 300,
        magnifierRadius: 120,
        magnifierZoom: 2.0,
        magnifierBorderWidth: 3.0,
        magnifierBorderColor: .white,
        magnifierShadowOpacity: 0.28,
        showTrailEffectsWhileMagnifierActive: true,
        magnifierShortcut: .default,
        intensityPreset: .high,
        speedBurstEnabled: true,
        speedBurstType: .firstFlash,
        speedBurstVelocityThreshold: 1800,
        speedBurstCooldownMilliseconds: 450,
        speedBurstDurationMilliseconds: 170,
        speedBurstAfterglowMilliseconds: 0,
        speedBurstJitterAmplitude: 5.0,
        speedBurstMinLength: 110,
        speedBurstMaxLength: 220,
        speedBurstWidthMultiplier: 1.55,
        speedBurstLineColor: colorFromHexRGB(0xFFFDF5),
        speedBurstAccentColor: colorFromHexRGB(0xFFE9A746),
        speedBurstAccentDurationMilliseconds: 190,
        speedBurstAccentSize: 32,
        clickEffects: [
            .left: ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0xFFE066)),
            .right: ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0xFFB74D)),
            .middle: ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0xFFF3B0)),
        ]
    )

    /// 应用“雷之呼吸·壹之型”预设。
    /// Note: 会先加载内置默认值，再覆盖用户保存的同名预设快照。
    mutating func applyThunderFirstFormPreset() {
        isTrackingEnabled = true
        isClickEffectsEnabled = true
        isMagnifierEnabled = true
        trailStyle = .lightning
        trailEffectStyle = .electric
        trailColor = colorFromHexRGB(0xFFD84A)
        trailEffectColor = colorFromHexRGB(0xFFB84D)
        trailWidth = 3.4
        trailLengthMilliseconds = 420
        intensityPreset = .high
        speedBurstEnabled = true
        speedBurstType = .firstFlash
        speedBurstVelocityThreshold = 1800
        speedBurstCooldownMilliseconds = 450
        speedBurstDurationMilliseconds = 450
        speedBurstAfterglowMilliseconds = 0
        speedBurstJitterAmplitude = 5.0
        speedBurstMinLength = 110
        speedBurstMaxLength = 220
        speedBurstWidthMultiplier = 1.55
        speedBurstLineColor = colorFromHexRGB(0xFFFDF5)
        speedBurstAccentColor = colorFromHexRGB(0xFFE9A746)
        speedBurstAccentDurationMilliseconds = 190
        speedBurstAccentSize = 32
        clickVisualStyle = .crossFlare
        clickEffectRadius = 34
        clickEffectDurationMilliseconds = 300
        clickEffects[.left] = ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0xFFE066))
        clickEffects[.right] = ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0xFFB74D))
        clickEffects[.middle] = ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0xFFF3B0))
        showTrailEffectsWhileMagnifierActive = true
        applyStoredThunderPresetOverrides()
    }

    /// 将当前设置快照保存为“雷之呼吸·壹之型”预设。
    /// Important: 仅更新预设命名空间键，不影响当前普通设置键。
    mutating func saveAsThunderFirstFormPreset() {
        let defaults = UserDefaults.standard
        defaults.set(isTrackingEnabled, forKey: Self.thunderPresetKey("tracking.enabled"))
        defaults.set(isClickEffectsEnabled, forKey: Self.thunderPresetKey("click.effects.enabled"))

        defaults.set(trailStyle.rawValue, forKey: Self.thunderPresetKey("trail.style"))
        defaults.set(trailEffectStyle.rawValue, forKey: Self.thunderPresetKey("trail.effectStyle"))
        defaults.set(encodeColorData(trailColor), forKey: Self.thunderPresetKey("trail.color"))
        defaults.set(encodeColorData(trailEffectColor), forKey: Self.thunderPresetKey("trail.effect.color"))
        defaults.set(rainbowTrailColors.compactMap(encodeColorData), forKey: Self.thunderPresetKey("trail.rainbow.colors"))
        defaults.set(encodeColorData(neonPrimaryColor), forKey: Self.thunderPresetKey("trail.neon.primary.color"))
        defaults.set(encodeColorData(neonSecondaryColor), forKey: Self.thunderPresetKey("trail.neon.secondary.color"))
        defaults.set(Double(trailWidth), forKey: Self.thunderPresetKey("trail.width"))
        defaults.set(trailLengthMilliseconds, forKey: Self.thunderPresetKey("trail.length.ms"))
        defaults.set(intensityPreset.rawValue, forKey: Self.thunderPresetKey("trail.intensityPreset"))

        defaults.set(speedBurstEnabled, forKey: Self.thunderPresetKey("speedBurst.enabled"))
        defaults.set(speedBurstType.rawValue, forKey: Self.thunderPresetKey("speedBurst.type"))
        defaults.set(Double(speedBurstVelocityThreshold), forKey: Self.thunderPresetKey("speedBurst.velocityThreshold"))
        defaults.set(speedBurstCooldownMilliseconds, forKey: Self.thunderPresetKey("speedBurst.cooldown.ms"))
        defaults.set(speedBurstDurationMilliseconds, forKey: Self.thunderPresetKey("speedBurst.duration.ms"))
        defaults.set(Double(speedBurstJitterAmplitude), forKey: Self.thunderPresetKey("speedBurst.jitter"))
        defaults.set(Double(speedBurstMinLength), forKey: Self.thunderPresetKey("speedBurst.minLength"))
        defaults.set(Double(speedBurstMaxLength), forKey: Self.thunderPresetKey("speedBurst.maxLength"))
        defaults.set(Double(speedBurstWidthMultiplier), forKey: Self.thunderPresetKey("speedBurst.widthMultiplier"))
        defaults.set(encodeColorData(speedBurstLineColor), forKey: Self.thunderPresetKey("speedBurst.line.color"))
        defaults.set(encodeColorData(speedBurstAccentColor), forKey: Self.thunderPresetKey("speedBurst.accent.color"))
        defaults.set(speedBurstAccentDurationMilliseconds, forKey: Self.thunderPresetKey("speedBurst.accent.duration.ms"))
        defaults.set(Double(speedBurstAccentSize), forKey: Self.thunderPresetKey("speedBurst.accent.size"))

        defaults.set(clickVisualStyle.rawValue, forKey: Self.thunderPresetKey("click.visualStyle"))
        defaults.set(Double(clickEffectRadius), forKey: Self.thunderPresetKey("click.radius"))
        defaults.set(clickEffectDurationMilliseconds, forKey: Self.thunderPresetKey("click.duration.ms"))
        for button in MouseButtonKind.allCases {
            let style = effectStyle(for: button)
            defaults.set(style.isEnabled, forKey: Self.thunderPresetKey("click.\(button.rawValue).enabled"))
            defaults.set(encodeColorData(style.color), forKey: Self.thunderPresetKey("click.\(button.rawValue).color"))
        }
        defaults.set(true, forKey: Self.thunderPresetSeededKey)
    }

    /// 应用用户保存的“雷之呼吸·壹之型”预设覆盖值。
    /// Note: 仅覆盖命中键；未命中字段继续沿用内置预设默认值。
    private mutating func applyStoredThunderPresetOverrides() {
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: Self.thunderPresetKey("tracking.enabled")) as? Bool {
            isTrackingEnabled = value
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("click.effects.enabled")) as? Bool {
            isClickEffectsEnabled = value
        }

        if let raw = defaults.string(forKey: Self.thunderPresetKey("trail.style")),
           let value = TrailRenderStyle(rawValue: raw)
        {
            trailStyle = value
        }
        if let raw = defaults.string(forKey: Self.thunderPresetKey("trail.effectStyle")),
           let value = TrailEffectStyle(rawValue: raw)
        {
            trailEffectStyle = value
        }
        if let value = decodeColorData(defaults.data(forKey: Self.thunderPresetKey("trail.color"))) {
            trailColor = value
        }
        if let value = decodeColorData(defaults.data(forKey: Self.thunderPresetKey("trail.effect.color"))) {
            trailEffectColor = value
        }
        if let items = defaults.array(forKey: Self.thunderPresetKey("trail.rainbow.colors")) {
            let colors = items.compactMap { item -> NSColor? in
                guard let data = item as? Data else { return nil }
                return decodeColorData(data)
            }
            if colors.count >= 2 {
                rainbowTrailColors = colors
            }
        }
        if let value = decodeColorData(defaults.data(forKey: Self.thunderPresetKey("trail.neon.primary.color"))) {
            neonPrimaryColor = value
        }
        if let value = decodeColorData(defaults.data(forKey: Self.thunderPresetKey("trail.neon.secondary.color"))) {
            neonSecondaryColor = value
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("trail.width")) as? Double {
            trailWidth = clampTrailWidth(value)
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("trail.length.ms")) as? Double {
            trailLengthMilliseconds = clampTrailLengthMilliseconds(value)
        }
        if let raw = defaults.string(forKey: Self.thunderPresetKey("trail.intensityPreset")),
           let value = EffectIntensityPreset(rawValue: raw)
        {
            intensityPreset = value
        }

        if let value = defaults.object(forKey: Self.thunderPresetKey("speedBurst.enabled")) as? Bool {
            speedBurstEnabled = value
        }
        if let raw = defaults.string(forKey: Self.thunderPresetKey("speedBurst.type")),
           let value = SpeedBurstEffectType(rawValue: raw)
        {
            speedBurstType = value
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("speedBurst.velocityThreshold")) as? Double {
            speedBurstVelocityThreshold = clampSpeedBurstVelocityThreshold(value)
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("speedBurst.cooldown.ms")) as? Double {
            speedBurstCooldownMilliseconds = clampSpeedBurstCooldownMilliseconds(value)
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("speedBurst.duration.ms")) as? Double {
            speedBurstDurationMilliseconds = clampSpeedBurstDurationMilliseconds(value)
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("speedBurst.jitter")) as? Double {
            speedBurstJitterAmplitude = clampSpeedBurstJitterAmplitude(value)
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("speedBurst.minLength")) as? Double {
            speedBurstMinLength = clampSpeedBurstMinLength(value)
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("speedBurst.maxLength")) as? Double {
            speedBurstMaxLength = clampSpeedBurstMaxLength(value)
        }
        if speedBurstMaxLength < speedBurstMinLength {
            swap(&speedBurstMinLength, &speedBurstMaxLength)
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("speedBurst.widthMultiplier")) as? Double {
            speedBurstWidthMultiplier = clampSpeedBurstWidthMultiplier(value)
        }
        if let value = decodeColorData(defaults.data(forKey: Self.thunderPresetKey("speedBurst.line.color"))) {
            speedBurstLineColor = value
        }
        if let value = decodeColorData(defaults.data(forKey: Self.thunderPresetKey("speedBurst.accent.color"))) {
            speedBurstAccentColor = value
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("speedBurst.accent.duration.ms")) as? Double {
            speedBurstAccentDurationMilliseconds = clampSpeedBurstAccentDurationMilliseconds(value)
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("speedBurst.accent.size")) as? Double {
            speedBurstAccentSize = clampSpeedBurstAccentSize(value)
        }

        if let raw = defaults.string(forKey: Self.thunderPresetKey("click.visualStyle")),
           let value = ClickVisualStyle(rawValue: raw)
        {
            clickVisualStyle = value
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("click.radius")) as? Double {
            clickEffectRadius = clampClickEffectRadius(value)
        }
        if let value = defaults.object(forKey: Self.thunderPresetKey("click.duration.ms")) as? Double {
            clickEffectDurationMilliseconds = clampClickEffectDurationMilliseconds(value)
        }
        for button in MouseButtonKind.allCases {
            var style = effectStyle(for: button)
            if let enabled = defaults.object(forKey: Self.thunderPresetKey("click.\(button.rawValue).enabled")) as? Bool {
                style.isEnabled = enabled
            }
            if let color = decodeColorData(defaults.data(forKey: Self.thunderPresetKey("click.\(button.rawValue).color"))) {
                style.color = color
            }
            clickEffects[button] = style
        }
    }
}

/// 设置持久化存储层。
/// 职责：负责 UserDefaults 的读写、版本兼容兜底与参数钳制。
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let launchAtLoginEnabledKey = "launchAtLogin.enabled"
    private let loggingEnabledKey = "debug.logging.enabled"
    private let statusItemVisibleKey = "statusItem.visible"
    private let trackingEnabledKey = "tracking.enabled"
    private let clickEffectsEnabledKey = "click.effects.enabled"
    private let magnifierEnabledKey = "magnifier.enabled"
    private let trailColorKey = "trail.color"
    private let trailEffectColorKey = "trail.effect.color"
    private let trailStyleKey = "trail.style"
    private let trailEffectStyleKey = "trail.effectStyle"
    private let trailRainbowColorsKey = "trail.rainbow.colors"
    private let trailNeonPrimaryColorKey = "trail.neon.primary.color"
    private let trailNeonSecondaryColorKey = "trail.neon.secondary.color"
    private let trailWidthKey = "trail.width"
    private let trailLengthMillisecondsKey = "trail.length.ms"
    private let clickVisualStyleKey = "click.visualStyle"
    private let clickRadiusKey = "click.radius"
    private let clickDurationMillisecondsKey = "click.duration.ms"
    private let magnifierRadiusKey = "magnifier.radius"
    private let magnifierZoomKey = "magnifier.zoom"
    private let magnifierBorderWidthKey = "magnifier.border.width"
    private let magnifierBorderColorKey = "magnifier.border.color"
    private let magnifierShadowOpacityKey = "magnifier.shadow.opacity"
    private let magnifierShowTrailEffectsKey = "magnifier.showTrailEffects"
    private let magnifierShortcutKindKey = "magnifier.shortcut.kind"
    private let magnifierShortcutKeyCodeKey = "magnifier.shortcut.keyCode"
    private let magnifierShortcutMouseButtonKey = "magnifier.shortcut.mouseButton"
    private let magnifierShortcutModifiersKey = "magnifier.shortcut.modifiers"
    private let trailIntensityKey = "trail.intensityPreset"
    private let speedBurstEnabledKey = "speedBurst.enabled"
    private let speedBurstTypeKey = "speedBurst.type"
    private let speedBurstVelocityThresholdKey = "speedBurst.velocityThreshold"
    private let speedBurstCooldownKey = "speedBurst.cooldown.ms"
    private let speedBurstDurationKey = "speedBurst.duration.ms"
    private let speedBurstAfterglowKey = "speedBurst.afterglow.ms"
    private let speedBurstJitterKey = "speedBurst.jitter"
    private let speedBurstMinLengthKey = "speedBurst.minLength"
    private let speedBurstMaxLengthKey = "speedBurst.maxLength"
    private let speedBurstWidthMultiplierKey = "speedBurst.widthMultiplier"
    private let speedBurstLineColorKey = "speedBurst.line.color"
    private let speedBurstAccentColorKey = "speedBurst.accent.color"
    private let speedBurstAccentDurationKey = "speedBurst.accent.duration.ms"
    private let speedBurstAccentSizeKey = "speedBurst.accent.size"
    private let clickLeftEnabledKey = "click.left.enabled"
    private let clickRightEnabledKey = "click.right.enabled"
    private let clickMiddleEnabledKey = "click.middle.enabled"
    private let clickLeftColorKey = "click.left.color"
    private let clickRightColorKey = "click.right.color"
    private let clickMiddleColorKey = "click.middle.color"

    /// 读取设置并进行参数归一化。
    /// Note: 若历史值缺失/越界，会回退到默认值并做最小约束修正。
    func loadSettings() -> AppSettings {
        let fallback = AppSettings.default
        let isLaunchAtLoginEnabled = defaults.object(forKey: launchAtLoginEnabledKey) as? Bool ?? fallback.isLaunchAtLoginEnabled
        let isLoggingEnabled = defaults.object(forKey: loggingEnabledKey) as? Bool ?? fallback.isLoggingEnabled
        let isStatusItemVisible = defaults.object(forKey: statusItemVisibleKey) as? Bool ?? fallback.isStatusItemVisible
        let isTrackingEnabled = defaults.object(forKey: trackingEnabledKey) as? Bool ?? fallback.isTrackingEnabled
        let isClickEffectsEnabled = defaults.object(forKey: clickEffectsEnabledKey) as? Bool ?? fallback.isClickEffectsEnabled
        let isMagnifierEnabled = defaults.object(forKey: magnifierEnabledKey) as? Bool ?? fallback.isMagnifierEnabled
        let trailStyle = defaults
            .string(forKey: trailStyleKey)
            .flatMap(TrailRenderStyle.init(rawValue:))
            ?? fallback.trailStyle
        let trailEffectStyle = defaults
            .string(forKey: trailEffectStyleKey)
            .flatMap(TrailEffectStyle.init(rawValue:))
            ?? fallback.trailEffectStyle
        let clickVisualStyle = defaults
            .string(forKey: clickVisualStyleKey)
            .flatMap(ClickVisualStyle.init(rawValue:))
            ?? fallback.clickVisualStyle
        let rainbowTrailColors = decodeColorArray(defaults.array(forKey: trailRainbowColorsKey)) ?? fallback.rainbowTrailColors
        let neonPrimaryColor = decodeColor(defaults.data(forKey: trailNeonPrimaryColorKey)) ?? fallback.neonPrimaryColor
        let neonSecondaryColor = decodeColor(defaults.data(forKey: trailNeonSecondaryColorKey)) ?? fallback.neonSecondaryColor
        let trailWidth = clampTrailWidth(defaults.object(forKey: trailWidthKey) as? Double ?? fallback.trailWidth)
        let trailLengthMilliseconds = clampTrailLengthMilliseconds(
            defaults.object(forKey: trailLengthMillisecondsKey) as? Double ?? fallback.trailLengthMilliseconds
        )
        let clickEffectRadius = clampClickEffectRadius(
            defaults.object(forKey: clickRadiusKey) as? Double ?? fallback.clickEffectRadius
        )
        let clickEffectDurationMilliseconds = clampClickEffectDurationMilliseconds(
            defaults.object(forKey: clickDurationMillisecondsKey) as? Double ?? fallback.clickEffectDurationMilliseconds
        )
        let magnifierRadius = clampMagnifierRadius(
            defaults.object(forKey: magnifierRadiusKey) as? Double ?? fallback.magnifierRadius
        )
        let magnifierZoom = clampMagnifierZoom(
            defaults.object(forKey: magnifierZoomKey) as? Double ?? fallback.magnifierZoom
        )
        let magnifierBorderWidth = clampMagnifierBorderWidth(
            defaults.object(forKey: magnifierBorderWidthKey) as? Double ?? fallback.magnifierBorderWidth
        )
        let magnifierShadowOpacity = clampMagnifierShadowOpacity(
            defaults.object(forKey: magnifierShadowOpacityKey) as? Double ?? fallback.magnifierShadowOpacity
        )
        let showTrailEffectsWhileMagnifierActive = defaults.object(forKey: magnifierShowTrailEffectsKey) as? Bool
            ?? fallback.showTrailEffectsWhileMagnifierActive
        let intensityPreset = defaults
            .string(forKey: trailIntensityKey)
            .flatMap(EffectIntensityPreset.init(rawValue:))
            ?? fallback.intensityPreset
        let speedBurstEnabled = defaults.object(forKey: speedBurstEnabledKey) as? Bool ?? fallback.speedBurstEnabled
        let speedBurstType = defaults
            .string(forKey: speedBurstTypeKey)
            .flatMap(SpeedBurstEffectType.init(rawValue:))
            ?? fallback.speedBurstType
        let speedBurstVelocityThreshold = clampSpeedBurstVelocityThreshold(
            defaults.object(forKey: speedBurstVelocityThresholdKey) as? Double ?? fallback.speedBurstVelocityThreshold
        )
        let speedBurstCooldownMilliseconds = clampSpeedBurstCooldownMilliseconds(
            defaults.object(forKey: speedBurstCooldownKey) as? Double ?? fallback.speedBurstCooldownMilliseconds
        )
        let speedBurstDurationMilliseconds = clampSpeedBurstDurationMilliseconds(
            defaults.object(forKey: speedBurstDurationKey) as? Double ?? fallback.speedBurstDurationMilliseconds
        )
        let speedBurstAfterglowMilliseconds: Double = 0
        let speedBurstJitterAmplitude = clampSpeedBurstJitterAmplitude(
            defaults.object(forKey: speedBurstJitterKey) as? Double ?? fallback.speedBurstJitterAmplitude
        )
        var speedBurstMinLength = clampSpeedBurstMinLength(
            defaults.object(forKey: speedBurstMinLengthKey) as? Double ?? fallback.speedBurstMinLength
        )
        var speedBurstMaxLength = clampSpeedBurstMaxLength(
            defaults.object(forKey: speedBurstMaxLengthKey) as? Double ?? fallback.speedBurstMaxLength
        )
        if speedBurstMaxLength < speedBurstMinLength {
            swap(&speedBurstMinLength, &speedBurstMaxLength)
        }
        let speedBurstWidthMultiplier = clampSpeedBurstWidthMultiplier(
            defaults.object(forKey: speedBurstWidthMultiplierKey) as? Double ?? fallback.speedBurstWidthMultiplier
        )
        let speedBurstLineColor = decodeColor(defaults.data(forKey: speedBurstLineColorKey)) ?? fallback.speedBurstLineColor
        let speedBurstAccentColor = decodeColor(defaults.data(forKey: speedBurstAccentColorKey)) ?? fallback.speedBurstAccentColor
        let speedBurstAccentDurationMilliseconds = clampSpeedBurstAccentDurationMilliseconds(
            defaults.object(forKey: speedBurstAccentDurationKey) as? Double ?? fallback.speedBurstAccentDurationMilliseconds
        )
        let speedBurstAccentSize = clampSpeedBurstAccentSize(
            defaults.object(forKey: speedBurstAccentSizeKey) as? Double ?? fallback.speedBurstAccentSize
        )

        let shortcutKind = defaults
            .string(forKey: magnifierShortcutKindKey)
            .flatMap(ShortcutTriggerKind.init(rawValue:))
            ?? fallback.magnifierShortcut.triggerKind
        let shortcutKeyCode = defaults.object(forKey: magnifierShortcutKeyCodeKey) as? UInt16
        let shortcutMouseButton = defaults
            .string(forKey: magnifierShortcutMouseButtonKey)
            .flatMap(MouseButtonKind.init(rawValue:))
        let shortcutModifiers = defaults.object(forKey: magnifierShortcutModifiersKey) as? UInt
            ?? fallback.magnifierShortcut.modifiersRaw
        let magnifierShortcut = MagnifierShortcut(
            triggerKind: shortcutKind,
            keyCode: shortcutKind == .keyboard ? (shortcutKeyCode ?? fallback.magnifierShortcut.keyCode) : nil,
            mouseButton: shortcutKind == .mouse ? (shortcutMouseButton ?? .right) : nil,
            modifiersRaw: shortcutModifiers
        )

        var clickEffects: [MouseButtonKind: ClickEffectStyle] = [:]
        for button in MouseButtonKind.allCases {
            let (enabledKey, colorKey): (String, String) = switch button {
            case .left:
                (clickLeftEnabledKey, clickLeftColorKey)
            case .right:
                (clickRightEnabledKey, clickRightColorKey)
            case .middle:
                (clickMiddleEnabledKey, clickMiddleColorKey)
            }
            let defaultStyle = fallback.effectStyle(for: button)
            let enabled = defaults.object(forKey: enabledKey) as? Bool ?? defaultStyle.isEnabled
            let color = decodeColor(defaults.data(forKey: colorKey)) ?? defaultStyle.color
            clickEffects[button] = ClickEffectStyle(isEnabled: enabled, color: color)
        }

        return AppSettings(
            isLaunchAtLoginEnabled: isLaunchAtLoginEnabled,
            isLoggingEnabled: isLoggingEnabled,
            isStatusItemVisible: isStatusItemVisible,
            isTrackingEnabled: isTrackingEnabled,
            isClickEffectsEnabled: isClickEffectsEnabled,
            isMagnifierEnabled: isMagnifierEnabled,
            trailColor: decodeColor(defaults.data(forKey: trailColorKey)) ?? fallback.trailColor,
            trailEffectColor: decodeColor(defaults.data(forKey: trailEffectColorKey)) ?? fallback.trailEffectColor,
            trailStyle: trailStyle,
            trailEffectStyle: trailEffectStyle,
            rainbowTrailColors: rainbowTrailColors,
            neonPrimaryColor: neonPrimaryColor,
            neonSecondaryColor: neonSecondaryColor,
            trailWidth: trailWidth,
            trailLengthMilliseconds: trailLengthMilliseconds,
            clickVisualStyle: clickVisualStyle,
            clickEffectRadius: clickEffectRadius,
            clickEffectDurationMilliseconds: clickEffectDurationMilliseconds,
            magnifierRadius: magnifierRadius,
            magnifierZoom: magnifierZoom,
            magnifierBorderWidth: magnifierBorderWidth,
            magnifierBorderColor: decodeColor(defaults.data(forKey: magnifierBorderColorKey)) ?? fallback.magnifierBorderColor,
            magnifierShadowOpacity: magnifierShadowOpacity,
            showTrailEffectsWhileMagnifierActive: showTrailEffectsWhileMagnifierActive,
            magnifierShortcut: magnifierShortcut,
            intensityPreset: intensityPreset,
            speedBurstEnabled: speedBurstEnabled,
            speedBurstType: speedBurstType,
            speedBurstVelocityThreshold: speedBurstVelocityThreshold,
            speedBurstCooldownMilliseconds: speedBurstCooldownMilliseconds,
            speedBurstDurationMilliseconds: speedBurstDurationMilliseconds,
            speedBurstAfterglowMilliseconds: speedBurstAfterglowMilliseconds,
            speedBurstJitterAmplitude: speedBurstJitterAmplitude,
            speedBurstMinLength: speedBurstMinLength,
            speedBurstMaxLength: speedBurstMaxLength,
            speedBurstWidthMultiplier: speedBurstWidthMultiplier,
            speedBurstLineColor: speedBurstLineColor,
            speedBurstAccentColor: speedBurstAccentColor,
            speedBurstAccentDurationMilliseconds: speedBurstAccentDurationMilliseconds,
            speedBurstAccentSize: speedBurstAccentSize,
            clickEffects: clickEffects
        )
    }

    /// 保存设置到 UserDefaults。
    /// - Parameter settings: 已在上层完成约束校验的配置。
    func saveSettings(_ settings: AppSettings) {
        defaults.set(settings.isLaunchAtLoginEnabled, forKey: launchAtLoginEnabledKey)
        defaults.set(settings.isLoggingEnabled, forKey: loggingEnabledKey)
        defaults.set(settings.isStatusItemVisible, forKey: statusItemVisibleKey)
        defaults.set(settings.isTrackingEnabled, forKey: trackingEnabledKey)
        defaults.set(settings.isClickEffectsEnabled, forKey: clickEffectsEnabledKey)
        defaults.set(settings.isMagnifierEnabled, forKey: magnifierEnabledKey)
        defaults.set(Double(settings.trailWidth), forKey: trailWidthKey)
        defaults.set(settings.trailStyle.rawValue, forKey: trailStyleKey)
        defaults.set(settings.trailEffectStyle.rawValue, forKey: trailEffectStyleKey)
        defaults.set(settings.clickVisualStyle.rawValue, forKey: clickVisualStyleKey)
        defaults.set(settings.rainbowTrailColors.compactMap(encodeColor), forKey: trailRainbowColorsKey)
        defaults.set(encodeColor(settings.neonPrimaryColor), forKey: trailNeonPrimaryColorKey)
        defaults.set(encodeColor(settings.neonSecondaryColor), forKey: trailNeonSecondaryColorKey)
        defaults.set(settings.trailLengthMilliseconds, forKey: trailLengthMillisecondsKey)
        defaults.set(Double(settings.clickEffectRadius), forKey: clickRadiusKey)
        defaults.set(settings.clickEffectDurationMilliseconds, forKey: clickDurationMillisecondsKey)
        defaults.set(Double(settings.magnifierRadius), forKey: magnifierRadiusKey)
        defaults.set(Double(settings.magnifierZoom), forKey: magnifierZoomKey)
        defaults.set(Double(settings.magnifierBorderWidth), forKey: magnifierBorderWidthKey)
        defaults.set(encodeColor(settings.magnifierBorderColor), forKey: magnifierBorderColorKey)
        defaults.set(Double(settings.magnifierShadowOpacity), forKey: magnifierShadowOpacityKey)
        defaults.set(settings.showTrailEffectsWhileMagnifierActive, forKey: magnifierShowTrailEffectsKey)
        defaults.set(settings.magnifierShortcut.triggerKind.rawValue, forKey: magnifierShortcutKindKey)
        defaults.set(settings.magnifierShortcut.keyCode, forKey: magnifierShortcutKeyCodeKey)
        defaults.set(settings.magnifierShortcut.mouseButton?.rawValue, forKey: magnifierShortcutMouseButtonKey)
        defaults.set(settings.magnifierShortcut.modifiersRaw, forKey: magnifierShortcutModifiersKey)
        defaults.set(settings.intensityPreset.rawValue, forKey: trailIntensityKey)
        defaults.set(settings.speedBurstEnabled, forKey: speedBurstEnabledKey)
        defaults.set(settings.speedBurstType.rawValue, forKey: speedBurstTypeKey)
        defaults.set(Double(settings.speedBurstVelocityThreshold), forKey: speedBurstVelocityThresholdKey)
        defaults.set(settings.speedBurstCooldownMilliseconds, forKey: speedBurstCooldownKey)
        defaults.set(settings.speedBurstDurationMilliseconds, forKey: speedBurstDurationKey)
        defaults.set(settings.speedBurstAfterglowMilliseconds, forKey: speedBurstAfterglowKey)
        defaults.set(Double(settings.speedBurstJitterAmplitude), forKey: speedBurstJitterKey)
        defaults.set(Double(settings.speedBurstMinLength), forKey: speedBurstMinLengthKey)
        defaults.set(Double(settings.speedBurstMaxLength), forKey: speedBurstMaxLengthKey)
        defaults.set(Double(settings.speedBurstWidthMultiplier), forKey: speedBurstWidthMultiplierKey)
        defaults.set(encodeColor(settings.speedBurstLineColor), forKey: speedBurstLineColorKey)
        defaults.set(encodeColor(settings.speedBurstAccentColor), forKey: speedBurstAccentColorKey)
        defaults.set(settings.speedBurstAccentDurationMilliseconds, forKey: speedBurstAccentDurationKey)
        defaults.set(Double(settings.speedBurstAccentSize), forKey: speedBurstAccentSizeKey)
        defaults.set(encodeColor(settings.trailColor), forKey: trailColorKey)
        defaults.set(encodeColor(settings.trailEffectColor), forKey: trailEffectColorKey)

        defaults.set(settings.effectStyle(for: .left).isEnabled, forKey: clickLeftEnabledKey)
        defaults.set(settings.effectStyle(for: .right).isEnabled, forKey: clickRightEnabledKey)
        defaults.set(settings.effectStyle(for: .middle).isEnabled, forKey: clickMiddleEnabledKey)
        defaults.set(encodeColor(settings.effectStyle(for: .left).color), forKey: clickLeftColorKey)
        defaults.set(encodeColor(settings.effectStyle(for: .right).color), forKey: clickRightColorKey)
        defaults.set(encodeColor(settings.effectStyle(for: .middle).color), forKey: clickMiddleColorKey)
    }

    private func encodeColor(_ color: NSColor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false)
    }

    private func decodeColor(_ data: Data?) -> NSColor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    private func decodeColorArray(_ value: [Any]?) -> [NSColor]? {
        guard let value else { return nil }
        let colors = value.compactMap { item -> NSColor? in
            guard let data = item as? Data else { return nil }
            return decodeColor(data)
        }
        return colors.count >= 2 ? colors : nil
    }
}

/// 轻量异步文件日志器。
/// 注意：默认开启；是否记录由 `setEnabled(_:)` 动态控制。
final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.lihan.cursortrailbar.logger", qos: .utility)
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let logsDirectoryURL: URL
    private let logFileURL: URL
    private var isEnabled = true

    private init() {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        logsDirectoryURL = base.appendingPathComponent("Logs/CursorTrailBar", isDirectory: true)
        logFileURL = logsDirectoryURL.appendingPathComponent("app.log")
        queue.async { [logsDirectoryURL] in
            try? FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        queue.async {
            if self.isEnabled == enabled {
                return
            }
            self.isEnabled = enabled
            self.write("logger \(enabled ? "enabled" : "disabled")", force: true)
        }
    }

    func log(_ message: String) {
        queue.async {
            self.write(message, force: false)
        }
    }

    func logPath() -> String {
        logFileURL.path
    }

    private func write(_ message: String, force: Bool) {
        guard force || isEnabled else { return }
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if
                let handle = try? FileHandle(forWritingTo: logFileURL)
            {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    try? handle.close()
                }
            }
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }
}

@MainActor
/// 开机自启管理器（基于 `SMAppService.mainApp`）。
final class LaunchAtLoginManager {
    /// 设置是否开机自启。
    /// - Returns: 操作是否执行成功。
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// 读取系统层面的当前注册状态。
    func currentStatus() -> SMAppService.Status? {
        guard #available(macOS 13.0, *) else { return nil }
        return SMAppService.mainApp.status
    }

    /// 当前是否处于已启用开机自启状态。
    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}

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

private func clampTrailWidth(_ value: Double) -> CGFloat {
    CGFloat(min(100.0, max(0.1, value)))
}

private func clampTrailLengthMilliseconds(_ value: Double) -> Double {
    min(10_000, max(1, value))
}

private func clampClickEffectRadius(_ value: Double) -> CGFloat {
    CGFloat(min(600.0, max(1.0, value)))
}

private func clampClickEffectDurationMilliseconds(_ value: Double) -> Double {
    min(2_000.0, max(40.0, value))
}

private func clampMagnifierRadius(_ value: Double) -> CGFloat {
    CGFloat(min(1200.0, max(20.0, value)))
}

private func clampMagnifierZoom(_ value: Double) -> CGFloat {
    CGFloat(min(8.0, max(1.0, value)))
}

private func clampMagnifierBorderWidth(_ value: Double) -> CGFloat {
    CGFloat(min(30.0, max(0.0, value)))
}

private func clampMagnifierShadowOpacity(_ value: Double) -> CGFloat {
    CGFloat(min(1.0, max(0.0, value)))
}

private func clampSpeedBurstVelocityThreshold(_ value: Double) -> CGFloat {
    CGFloat(min(60_000.0, max(100.0, value)))
}

private func clampSpeedBurstCooldownMilliseconds(_ value: Double) -> Double {
    min(3000.0, max(50.0, value))
}

private func clampSpeedBurstDurationMilliseconds(_ value: Double) -> Double {
    min(800.0, max(40.0, value))
}

private func clampSpeedBurstJitterAmplitude(_ value: Double) -> CGFloat {
    CGFloat(min(30.0, max(0.0, value)))
}

private func clampSpeedBurstMinLength(_ value: Double) -> CGFloat {
    CGFloat(min(5000.0, max(10.0, value)))
}

private func clampSpeedBurstMaxLength(_ value: Double) -> CGFloat {
    CGFloat(min(5000.0, max(10.0, value)))
}

private func clampSpeedBurstWidthMultiplier(_ value: Double) -> CGFloat {
    CGFloat(min(4.0, max(0.2, value)))
}

private func clampSpeedBurstAccentDurationMilliseconds(_ value: Double) -> Double {
    min(2_000.0, max(40.0, value))
}

private func clampSpeedBurstAccentSize(_ value: Double) -> CGFloat {
    CGFloat(min(400.0, max(4.0, value)))
}

private func rounded(_ value: Double, scale: Double = 100) -> Double {
    (value * scale).rounded() / scale
}

private func pseudoRandom01(_ seed: Int) -> CGFloat {
    let value = sin(Double(seed) * 12.9898 + 78.233) * 43758.5453
    return CGFloat(value - floor(value))
}

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
        .keyDown,
        .keyUp,
        .flagsChanged,
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

@MainActor
/// 轨迹与特效渲染视图。
/// 职责：维护瞬态粒子/脉冲/爆发状态，并按定时节拍重绘。
final class TrailOverlayView: NSView {
    private struct MovePoint {
        let point: NSPoint
        let timestamp: CFTimeInterval
    }

    private struct TrailSample {
        let point: NSPoint
        let alpha: CGFloat
        let index: Int
    }

    private struct Pulse {
        enum Kind {
            case circle
            case cross
        }

        let point: NSPoint
        let color: NSColor
        let startRadius: CGFloat
        let endRadius: CGFloat
        let lineWidth: CGFloat
        let filled: Bool
        let kind: Kind
        let lifetime: CFTimeInterval
        let timestamp: CFTimeInterval
    }

    private struct Particle {
        let point: NSPoint
        let velocity: CGVector
        let size: CGFloat
        let color: NSColor
        let lifetime: CFTimeInterval
        let timestamp: CFTimeInterval
    }

    private struct ClickAccent {
        enum Kind {
            case cross
        }

        let point: NSPoint
        let color: NSColor
        let radius: CGFloat
        let kind: Kind
        let lifetime: CFTimeInterval
        let timestamp: CFTimeInterval
    }

    private struct DashBurst {
        let start: NSPoint
        let end: NSPoint
        let coreColor: NSColor
        let lineWidth: CGFloat
        let lifetime: CFTimeInterval
        let timestamp: CFTimeInterval
    }

    private enum PressedButton {
        case none
        case left
        case right
        case middle
    }

    private var movePoints: [MovePoint] = []
    private var pulses: [Pulse] = []
    private var particles: [Particle] = []
    private var clickAccents: [ClickAccent] = []
    private var dashBursts: [DashBurst] = []
    private var cursorPoint: NSPoint?
    private var lastMovePoint: NSPoint?
    private var lastMoveTimestamp: CFTimeInterval?
    private var lastAcceptedMoveTimestamp: CFTimeInterval = 0
    private var lastDashBurstTimestamp: CFTimeInterval = -1
    private var pressedButton: PressedButton = .none
    private var refreshTimer: Timer?
    private var cachedMagnifierImage: CGImage?
    private var lastMagnifierCaptureTimestamp: CFTimeInterval = 0
    private var isTrailEnabled = AppSettings.default.isTrackingEnabled
    private var trailColor: NSColor = AppSettings.default.trailColor
    private var trailEffectColor: NSColor = AppSettings.default.trailEffectColor
    private var trailStyle: TrailRenderStyle = AppSettings.default.trailStyle
    private var trailEffectStyle: TrailEffectStyle = AppSettings.default.trailEffectStyle
    private var rainbowTrailColors: [NSColor] = AppSettings.default.rainbowTrailColors
    private var neonPrimaryColor: NSColor = AppSettings.default.neonPrimaryColor
    private var neonSecondaryColor: NSColor = AppSettings.default.neonSecondaryColor
    private var trailLineWidth: CGFloat = AppSettings.default.trailWidth
    private var trailLengthMilliseconds: Double = AppSettings.default.trailLengthMilliseconds
    private var clickVisualStyle: ClickVisualStyle = AppSettings.default.clickVisualStyle
    private var clickEffectRadius: CGFloat = AppSettings.default.clickEffectRadius
    private var clickEffectDurationSeconds: CFTimeInterval = AppSettings.default.clickEffectDurationMilliseconds / 1000
    private var magnifierRadius: CGFloat = AppSettings.default.magnifierRadius
    private var magnifierZoom: CGFloat = AppSettings.default.magnifierZoom
    private var configuredMagnifierZoom: CGFloat = AppSettings.default.magnifierZoom
    private var magnifierBorderWidth: CGFloat = AppSettings.default.magnifierBorderWidth
    private var magnifierBorderColor: NSColor = AppSettings.default.magnifierBorderColor
    private var magnifierShadowOpacity: CGFloat = AppSettings.default.magnifierShadowOpacity
    private var showTrailEffectsWhileMagnifierActive = AppSettings.default.showTrailEffectsWhileMagnifierActive
    private var isClickEffectsEnabled = AppSettings.default.isClickEffectsEnabled
    private var isMagnifierEnabled = AppSettings.default.isMagnifierEnabled
    private var isMagnifierActive = false
    private var intensityPreset: EffectIntensityPreset = AppSettings.default.intensityPreset
    private var speedBurstEnabled = AppSettings.default.speedBurstEnabled
    private var speedBurstType: SpeedBurstEffectType = AppSettings.default.speedBurstType
    private var speedBurstVelocityThreshold: CGFloat = AppSettings.default.speedBurstVelocityThreshold
    private var speedBurstCooldownSeconds: CFTimeInterval = AppSettings.default.speedBurstCooldownMilliseconds / 1000
    private var speedBurstDurationSeconds: CFTimeInterval = AppSettings.default.speedBurstDurationMilliseconds / 1000
    private var speedBurstJitterAmplitude: CGFloat = AppSettings.default.speedBurstJitterAmplitude
    private var speedBurstMinLength: CGFloat = AppSettings.default.speedBurstMinLength
    private var speedBurstMaxLength: CGFloat = AppSettings.default.speedBurstMaxLength
    private var speedBurstWidthMultiplier: CGFloat = AppSettings.default.speedBurstWidthMultiplier
    private var speedBurstLineColor: NSColor = AppSettings.default.speedBurstLineColor
    private var speedBurstAccentColor: NSColor = AppSettings.default.speedBurstAccentColor
    private var speedBurstAccentDurationSeconds: CFTimeInterval = AppSettings.default.speedBurstAccentDurationMilliseconds / 1000
    private var speedBurstAccentSize: CGFloat = AppSettings.default.speedBurstAccentSize
    private var clickEffects: [MouseButtonKind: ClickEffectStyle] = AppSettings.default.clickEffects
    private var hadAnimatedContentOnLastTick = false
    private var lastMagnifierZoomLogTimestamp: CFTimeInterval = 0
    private var lastMagnifierCenterLogTimestamp: CFTimeInterval = 0

    private var trailLengthSeconds: CFTimeInterval {
        trailLengthMilliseconds / 1000
    }

    private let minimumMoveSampleInterval: CFTimeInterval = 1.0 / 120.0
    private let minimumMoveDistance: CGFloat = 1.2
    private let refreshInterval: CFTimeInterval = 1.0 / 45.0
    private let magnifierCaptureInterval: CFTimeInterval = 1.0 / 30.0

    private var maxMoveCount: Int {
        max(80, Int(trailLengthSeconds * 260))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        startRefreshLoop()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setTrailEnabled(_ enabled: Bool) {
        isTrailEnabled = enabled
        if !enabled {
            movePoints.removeAll()
            dashBursts.removeAll()
            lastMoveTimestamp = nil
            lastDashBurstTimestamp = -1
            needsDisplay = true
        }
    }

    func clear() {
        movePoints.removeAll()
        pulses.removeAll()
        particles.removeAll()
        clickAccents.removeAll()
        dashBursts.removeAll()
        cursorPoint = nil
        lastMovePoint = nil
        lastMoveTimestamp = nil
        lastAcceptedMoveTimestamp = 0
        lastDashBurstTimestamp = -1
        pressedButton = .none
        cachedMagnifierImage = nil
        hadAnimatedContentOnLastTick = false
        needsDisplay = true
    }

    func applySettings(_ settings: AppSettings) {
        trailColor = settings.trailColor
        trailEffectColor = settings.trailEffectColor
        trailStyle = settings.trailStyle
        trailEffectStyle = settings.trailEffectStyle
        rainbowTrailColors = settings.rainbowTrailColors
        neonPrimaryColor = settings.neonPrimaryColor
        neonSecondaryColor = settings.neonSecondaryColor
        trailLineWidth = settings.trailWidth
        trailLengthMilliseconds = settings.trailLengthMilliseconds
        clickVisualStyle = settings.clickVisualStyle
        clickEffectRadius = settings.clickEffectRadius
        clickEffectDurationSeconds = settings.clickEffectDurationMilliseconds / 1000
        magnifierRadius = settings.magnifierRadius
        configuredMagnifierZoom = settings.magnifierZoom
        if !isMagnifierActive {
            magnifierZoom = configuredMagnifierZoom
        }
        magnifierBorderWidth = settings.magnifierBorderWidth
        magnifierBorderColor = settings.magnifierBorderColor
        magnifierShadowOpacity = settings.magnifierShadowOpacity
        showTrailEffectsWhileMagnifierActive = settings.showTrailEffectsWhileMagnifierActive
        isClickEffectsEnabled = settings.isClickEffectsEnabled
        isMagnifierEnabled = settings.isMagnifierEnabled
        intensityPreset = settings.intensityPreset
        speedBurstEnabled = settings.speedBurstEnabled
        speedBurstType = settings.speedBurstType
        speedBurstVelocityThreshold = settings.speedBurstVelocityThreshold
        speedBurstCooldownSeconds = settings.speedBurstCooldownMilliseconds / 1000
        speedBurstDurationSeconds = settings.speedBurstDurationMilliseconds / 1000
        speedBurstJitterAmplitude = settings.speedBurstJitterAmplitude
        speedBurstMinLength = settings.speedBurstMinLength
        speedBurstMaxLength = max(settings.speedBurstMinLength, settings.speedBurstMaxLength)
        speedBurstWidthMultiplier = settings.speedBurstWidthMultiplier
        speedBurstLineColor = settings.speedBurstLineColor
        speedBurstAccentColor = settings.speedBurstAccentColor
        speedBurstAccentDurationSeconds = settings.speedBurstAccentDurationMilliseconds / 1000
        speedBurstAccentSize = settings.speedBurstAccentSize
        clickEffects = settings.clickEffects
        if !isMagnifierEnabled {
            isMagnifierActive = false
            cachedMagnifierImage = nil
        }
        if !effectStyle(for: pressedButton).isEnabled {
            pressedButton = .none
        }
        needsDisplay = true
    }

    func setMagnifierActive(_ active: Bool) {
        isMagnifierActive = isMagnifierEnabled && active
        magnifierZoom = configuredMagnifierZoom
        if !isMagnifierActive {
            cachedMagnifierImage = nil
            lastMagnifierCaptureTimestamp = 0
        }
        if active, !showTrailEffectsWhileMagnifierActive {
            movePoints.removeAll()
            pulses.removeAll()
            particles.removeAll()
            clickAccents.removeAll()
            pressedButton = .none
        }
        needsDisplay = true
    }

    func shutdown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        clear()
    }

    /// 处理单帧输入信号并更新渲染状态。
    /// - Note: 所有坐标会先转换为当前屏幕局部坐标系，再进行轨迹/特效计算。
    func process(signal: MouseSignal, in screenFrame: NSRect) {
        guard screenFrame.contains(signal.location) else { return }

        let localPoint = NSPoint(
            x: signal.location.x - screenFrame.origin.x,
            y: signal.location.y - screenFrame.origin.y
        )
        if case .scroll = signal.kind {
            // 滚轮仅用于临时缩放，不应导致放大镜中心抖动/跳动
        } else {
            cursorPoint = localPoint
        }

        if isMagnifierActive, !showTrailEffectsWhileMagnifierActive {
            switch signal.kind {
            case .move:
                lastMovePoint = localPoint
                lastMoveTimestamp = signal.timestamp
            case .scroll(let deltaY):
                applyTemporaryMagnifierZoom(deltaY: deltaY)
            default:
                pressedButton = .none
            }
            needsDisplay = true
            return
        }

        switch signal.kind {
        case .move:
            if !isTrailEnabled {
                lastMovePoint = localPoint
                lastMoveTimestamp = signal.timestamp
                break
            }
            let previous = lastMovePoint ?? localPoint
            let distance = hypot(localPoint.x - previous.x, localPoint.y - previous.y)
            let interval = signal.timestamp - lastAcceptedMoveTimestamp
            let previousTimestamp = lastMoveTimestamp ?? (signal.timestamp - minimumMoveSampleInterval)
            let deltaTime = max(1.0 / 600.0, signal.timestamp - previousTimestamp)
            let velocity = distance / CGFloat(deltaTime)
            if interval < minimumMoveSampleInterval, distance < minimumMoveDistance {
                return
            }
            lastAcceptedMoveTimestamp = signal.timestamp
            movePoints.append(MovePoint(point: localPoint, timestamp: signal.timestamp))
            if movePoints.count > maxMoveCount {
                movePoints.removeFirst(movePoints.count - maxMoveCount)
            }
            emitTrailEffects(from: lastMovePoint ?? localPoint, to: localPoint, timestamp: signal.timestamp)
            emitThunderDashIfNeeded(from: previous, to: localPoint, velocity: velocity, timestamp: signal.timestamp)
            lastMovePoint = localPoint
            lastMoveTimestamp = signal.timestamp
        case .leftDown:
            handleButtonDown(.left, point: localPoint, timestamp: signal.timestamp)
        case .leftUp:
            handleButtonUp(.left, point: localPoint, timestamp: signal.timestamp)
        case .rightDown:
            handleButtonDown(.right, point: localPoint, timestamp: signal.timestamp)
        case .rightUp:
            handleButtonUp(.right, point: localPoint, timestamp: signal.timestamp)
        case .otherDown:
            handleButtonDown(.middle, point: localPoint, timestamp: signal.timestamp)
        case .otherUp:
            handleButtonUp(.middle, point: localPoint, timestamp: signal.timestamp)
        case .scroll(let deltaY):
            applyTemporaryMagnifierZoom(deltaY: deltaY)
        }

        needsDisplay = true
    }

    private func applyTemporaryMagnifierZoom(deltaY: CGFloat) {
        guard isMagnifierActive else { return }
        let centerBefore = cursorPoint
        let sensitivity: CGFloat = 0.018 * 1.5
        let step = deltaY * sensitivity
        guard abs(step) > 0.0001 else { return }
        let before = magnifierZoom
        magnifierZoom = clampMagnifierZoom(Double(magnifierZoom + step))
        cachedMagnifierImage = nil
        lastMagnifierCaptureTimestamp = 0
        let now = CACurrentMediaTime()
        if now - lastMagnifierZoomLogTimestamp > 0.18 {
            AppLogger.shared.log(
                "magnifier temporary zoom updated by scroll: \(rounded(Double(before)))x -> \(rounded(Double(magnifierZoom)))x (deltaY=\(rounded(Double(deltaY), scale: 10)))"
            )
            lastMagnifierZoomLogTimestamp = now
        }
        if now - lastMagnifierCenterLogTimestamp > 0.18 {
            let beforeText = centerBefore.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "nil"
            let afterText = cursorPoint.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "nil"
            AppLogger.shared.log(
                "magnifier center on scroll: before=\(beforeText), after=\(afterText), moved=\(beforeText != afterText)"
            )
            lastMagnifierCenterLogTimestamp = now
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        dirtyRect.fill(using: .clear)

        let now = CACurrentMediaTime()
        let canRenderOverlays = !isMagnifierActive || showTrailEffectsWhileMagnifierActive
        if canRenderOverlays && isTrailEnabled {
            drawMoveTrail(now: now)
            drawDashBursts(now: now)
        }
        if canRenderOverlays && intensityPreset.effectsEnabled {
            drawParticles(now: now)
        }
        if canRenderOverlays && isClickEffectsEnabled {
            drawPulses(now: now)
            drawPressedState()
        }
        if canRenderOverlays {
            drawClickAccents(now: now)
        }
        drawMagnifier()
    }

    private func drawMoveTrail(now: CFTimeInterval) {
        let samples = makeInterpolatedTrailSamples(now: now)
        guard samples.count > 1 else { return }

        switch trailStyle {
        case .ribbon:
            drawRibbonLikeTrail(samples: samples, now: now, style: .ribbon)
        case .neon:
            drawRibbonLikeTrail(samples: samples, now: now, style: .neon)
        case .rainbow:
            drawRibbonLikeTrail(samples: samples, now: now, style: .rainbow)
        case .lightning:
            drawLightningTrail(samples: samples, now: now)
        }
        if trailEffectStyle == .electric, intensityPreset.effectsEnabled {
            drawElectricTrailCoverage(samples: samples, now: now)
        }
    }

    private func drawRibbonLikeTrail(samples: [TrailSample], now: CFTimeInterval, style: TrailRenderStyle) {
        guard samples.count > 3 else { return }

        let total = max(1, samples.count - 1)
        for index in 1..<(samples.count - 1) {
            let previous = samples[index - 1]
            let current = samples[index]
            let next = samples[index + 1]

            let start = NSPoint(
                x: (previous.point.x + current.point.x) * 0.5,
                y: (previous.point.y + current.point.y) * 0.5
            )
            let end = NSPoint(
                x: (current.point.x + next.point.x) * 0.5,
                y: (current.point.y + next.point.y) * 0.5
            )

            let baseAlpha = min(previous.alpha, min(current.alpha, next.alpha))
            if baseAlpha <= 0.001 { continue }

            let progress = CGFloat(index) / CGFloat(total)
            let width: CGFloat = switch style {
            case .ribbon:
                max(0.42, trailLineWidth * (0.14 + 1.04 * pow(progress, 0.82)))
            case .neon:
                max(0.46, trailLineWidth * (0.18 + 1.16 * pow(progress, 0.82)))
            case .rainbow:
                max(0.44, trailLineWidth * (0.16 + 1.1 * pow(progress, 0.82)))
            case .lightning:
                max(0.4, trailLineWidth * (0.12 + 1.0 * pow(progress, 0.8)))
            }
            let segmentAlpha = baseAlpha * (0.06 + 0.94 * progress)

            let curve = NSBezierPath()
            curve.move(to: start)
            curve.curve(to: end, controlPoint1: current.point, controlPoint2: current.point)
            curve.lineCapStyle = .butt
            curve.lineJoinStyle = .round

            let glow = curve.copy() as! NSBezierPath
            glow.lineWidth = width * (style == .neon ? 2.05 : 1.7)
            glow.lineCapStyle = .butt
            glow.lineJoinStyle = .round
            let glowColor: NSColor = switch style {
            case .ribbon:
                trailColor
            case .neon:
                neonSecondaryColor
            case .rainbow:
                rainbowColor(for: current.index, now: now)
            case .lightning:
                trailColor
            }
            glowColor.withAlphaComponent((style == .neon ? 0.16 : 0.08) * segmentAlpha).setStroke()
            glow.stroke()

            curve.lineWidth = width
            let rainbowBaseColor = style == .rainbow ? rainbowColor(for: current.index, now: now) : nil
            let coreColor: NSColor = switch style {
            case .ribbon:
                trailColor.blended(withFraction: 0.1 + 0.22 * progress, of: .white) ?? trailColor
            case .neon:
                neonPrimaryColor.blended(withFraction: 0.08 + 0.2 * progress, of: .white) ?? neonPrimaryColor
            case .rainbow:
                (rainbowBaseColor?.blended(withFraction: 0.08, of: .white)) ?? (rainbowBaseColor ?? trailColor)
            case .lightning:
                trailColor
            }
            let coreAlpha: CGFloat = switch style {
            case .ribbon:
                0.72 * segmentAlpha
            case .neon:
                0.9 * segmentAlpha
            case .rainbow:
                0.82 * segmentAlpha
            case .lightning:
                0.78 * segmentAlpha
            }
            coreColor.withAlphaComponent(coreAlpha).setStroke()
            curve.stroke()

            if style == .neon {
                let highlight = curve.copy() as! NSBezierPath
                highlight.lineWidth = max(0.22, width * 0.36)
                let highlightColor = (neonPrimaryColor.blended(withFraction: 0.35, of: .white) ?? neonPrimaryColor)
                highlightColor.withAlphaComponent(0.32 * segmentAlpha).setStroke()
                highlight.stroke()
            }
        }
    }

    private func drawLightningTrail(samples: [TrailSample], now: CFTimeInterval) {
        guard samples.count > 1 else { return }
        for index in 1..<samples.count {
            let first = samples[index - 1]
            let second = samples[index]
            let alpha = min(first.alpha, second.alpha)
            if alpha <= 0.001 { continue }

            let distance = hypot(second.point.x - first.point.x, second.point.y - first.point.y)
            guard distance >= 0.2 else { continue }

            let progress = CGFloat(index) / CGFloat(max(1, samples.count - 1))
            let lineWidth = max(0.6, trailLineWidth * (0.22 + 0.88 * pow(progress, 0.8)) * 0.92)

            let lightningPath = makeLightningPath(from: first.point, to: second.point)
            lightningPath.lineWidth = lineWidth
            lightningPath.lineCapStyle = .butt
            lightningPath.lineJoinStyle = .round
            (trailColor.blended(withFraction: 0.45, of: .white) ?? trailColor).withAlphaComponent(0.95 * alpha).setStroke()
            lightningPath.stroke()

            if second.index % 10 == 0 {
                let branch = makeLightningBranch(from: second.point)
                branch.lineWidth = max(0.6, lineWidth * 0.75)
                trailColor.withAlphaComponent(0.45 * alpha).setStroke()
                branch.stroke()
            }
        }
    }

    private func drawElectricTrailCoverage(samples: [TrailSample], now: CFTimeInterval) {
        guard samples.count > 6 else { return }

        let coverageFactor = max(0.5, intensityPreset.particleSpawnMultiplier)
        let targetArcCount = max(10, min(110, Int(CGFloat(samples.count) * 0.18 * coverageFactor)))
        let strideStep = max(1, samples.count / max(1, targetArcCount))
        let phase = Int(now * 36)
        let startOffset = phase % strideStep

        for sampleIndex in stride(from: 2 + startOffset, to: samples.count - 2, by: strideStep) {
            let previous = samples[sampleIndex - 1]
            let current = samples[sampleIndex]
            let next = samples[sampleIndex + 1]
            let alpha = min(current.alpha, min(previous.alpha, next.alpha))
            if alpha < 0.05 { continue }

            let tangentX = next.point.x - previous.point.x
            let tangentY = next.point.y - previous.point.y
            let tangentLength = max(0.001, hypot(tangentX, tangentY))
            let dirX = tangentX / tangentLength
            let dirY = tangentY / tangentLength
            let normalX = -dirY
            let normalY = dirX

            let seed = sampleIndex * 131 + phase * 17
            let rand0 = pseudoRandom01(seed)
            let rand1 = pseudoRandom01(seed + 1)
            let rand2 = pseudoRandom01(seed + 2)
            let rand3 = pseudoRandom01(seed + 3)

            let lateralOffset = (rand0 - 0.5) * 7.0
            let origin = NSPoint(
                x: current.point.x + normalX * lateralOffset,
                y: current.point.y + normalY * lateralOffset
            )

            let baseAngle = atan2(dirY, dirX)
            let firstAngle = baseAngle + (rand1 - 0.5) * 1.05
            let secondAngle = firstAngle + (rand2 - 0.5) * 1.45
            let segmentLength = max(3.0, (4.5 + rand3 * 6.0) * (0.55 + alpha * 0.55))

            let mid = NSPoint(
                x: origin.x + cos(firstAngle) * segmentLength,
                y: origin.y + sin(firstAngle) * segmentLength
            )
            let tip = NSPoint(
                x: mid.x + cos(secondAngle) * (segmentLength * 0.75),
                y: mid.y + sin(secondAngle) * (segmentLength * 0.75)
            )

            let arc = NSBezierPath()
            arc.move(to: origin)
            arc.line(to: mid)
            arc.line(to: tip)
            arc.lineCapStyle = .round
            arc.lineJoinStyle = .round
            arc.lineWidth = max(0.75, trailLineWidth * 0.33)

            let color = trailEffectColor.blended(withFraction: 0.56, of: .white) ?? trailEffectColor
            let glow = arc.copy() as! NSBezierPath
            glow.lineWidth = arc.lineWidth * 2.1
            color.withAlphaComponent(0.14 * alpha * intensityPreset.glowBoost).setStroke()
            glow.stroke()

            color.withAlphaComponent(0.78 * alpha).setStroke()
            arc.stroke()
        }
    }

    private func drawDashBursts(now: CFTimeInterval) {
        guard !dashBursts.isEmpty else { return }

        for burst in dashBursts {
            let age = now - burst.timestamp
            if age < 0 || age > burst.lifetime { continue }
            let progress = CGFloat(age / burst.lifetime)
            let alpha = max(0, 1 - progress)

            let glowPath = makeThunderDashPath(
                from: burst.start,
                to: burst.end,
                jitter: speedBurstJitterAmplitude * (1 - progress)
            )
            glowPath.lineWidth = burst.lineWidth * 2.1
            glowPath.lineCapStyle = .round
            glowPath.lineJoinStyle = .round
            burst.coreColor.withAlphaComponent(0.22 * alpha * intensityPreset.glowBoost).setStroke()
            glowPath.stroke()

            let corePath = makeThunderDashPath(
                from: burst.start,
                to: burst.end,
                jitter: speedBurstJitterAmplitude * 0.48 * (1 - progress)
            )
            corePath.lineWidth = burst.lineWidth
            corePath.lineCapStyle = .round
            corePath.lineJoinStyle = .round
            burst.coreColor.withAlphaComponent(0.94 * alpha).setStroke()
            corePath.stroke()
        }
    }

    private func makeThunderDashPath(from start: NSPoint, to end: NSPoint, jitter: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: start)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = max(0.01, hypot(dx, dy))
        let normalX = -dy / distance
        let normalY = dx / distance
        let segments = 6
        for segment in 1...segments {
            let t = CGFloat(segment) / CGFloat(segments)
            let jitterDistance = CGFloat.random(in: -jitter...jitter)
            let x = start.x + dx * t + normalX * jitterDistance
            let y = start.y + dy * t + normalY * jitterDistance
            path.line(to: NSPoint(x: x, y: y))
        }
        return path
    }

    private func thunderDashVelocityThreshold(for preset: EffectIntensityPreset) -> CGFloat {
        switch preset {
        case .off:
            return .greatestFiniteMagnitude
        case .low:
            return speedBurstVelocityThreshold * 1.2
        case .normal:
            return speedBurstVelocityThreshold
        case .high:
            return speedBurstVelocityThreshold * 0.9
        }
    }

    /// 按速度阈值触发“一之闪”爆发线与端点爆发。
    /// - Important: 受 `speedBurstEnabled`、冷却时间与强度预设共同约束。
    private func emitThunderDashIfNeeded(from start: NSPoint, to end: NSPoint, velocity: CGFloat, timestamp: CFTimeInterval) {
        guard isTrailEnabled else { return }
        guard speedBurstEnabled else { return }
        guard intensityPreset.effectsEnabled else { return }
        guard speedBurstType == .firstFlash else { return }
        guard velocity >= thunderDashVelocityThreshold(for: intensityPreset) else { return }
        guard timestamp - lastDashBurstTimestamp >= speedBurstCooldownSeconds else { return }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0.1 else { return }
        let directionX = dx / distance
        let directionY = dy / distance

        let burstLength = min(speedBurstMaxLength, max(speedBurstMinLength, velocity * 0.06))
        let burstStart = NSPoint(x: end.x - directionX * 18, y: end.y - directionY * 18)
        let burstEnd = NSPoint(x: end.x + directionX * burstLength, y: end.y + directionY * burstLength)
        let coreColor = speedBurstLineColor
        let lifetime = speedBurstDurationSeconds
        let width = max(1.2, trailLineWidth * speedBurstWidthMultiplier)

        dashBursts.append(
            DashBurst(
                start: burstStart,
                end: burstEnd,
                coreColor: coreColor,
                lineWidth: width,
                lifetime: lifetime,
                timestamp: timestamp
            )
        )
        lastDashBurstTimestamp = timestamp
        emitThunderDashParticles(start: burstStart, end: burstEnd, timestamp: timestamp, coreColor: coreColor)
        let accentSize = max(4, speedBurstAccentSize)
        let accentColor = speedBurstAccentColor
        let accentLifetime = max(0.04, speedBurstAccentDurationSeconds)
        addPulse(
            at: end,
            color: accentColor,
            filled: false,
            kind: .circle,
            startRadius: max(4, accentSize * 0.48),
            endRadius: max(12, accentSize * 1.32),
            lineWidth: max(1.4, trailLineWidth * 0.68),
            lifetime: accentLifetime,
            timestamp: timestamp
        )
        clickAccents.append(
            ClickAccent(
                point: end,
                color: accentColor,
                radius: accentSize,
                kind: .cross,
                lifetime: accentLifetime,
                timestamp: timestamp
            )
        )
        AppLogger.shared.log("thunder dash burst emitted: velocity=\(Int(velocity)) px/s")
    }

    private func emitThunderDashParticles(
        start: NSPoint,
        end: NSPoint,
        timestamp: CFTimeInterval,
        coreColor: NSColor
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = max(0.001, hypot(dx, dy))
        let directionX = dx / distance
        let directionY = dy / distance
        let burstCount = max(16, min(44, Int(24 * intensityPreset.particleSpawnMultiplier)))
        for index in 0..<burstCount {
            let interpolation = CGFloat(index) / CGFloat(max(1, burstCount - 1))
            let jitter = CGFloat.random(in: -6...6)
            let origin = NSPoint(
                x: start.x + dx * interpolation + (-directionY) * jitter,
                y: start.y + dy * interpolation + directionX * jitter
            )
            let spread = CGFloat.random(in: -0.75...0.75)
            let rotatedX = directionX * cos(spread) - directionY * sin(spread)
            let rotatedY = directionX * sin(spread) + directionY * cos(spread)
            let speed = CGFloat.random(in: intensityPreset.particleSpeedRange.upperBound * 1.3 ... intensityPreset.particleSpeedRange.upperBound * 2.4)
            let colorPick = CGFloat.random(in: 0...1)
            let color: NSColor
            if colorPick < 0.72 {
                color = coreColor
            } else {
                color = trailEffectColor.blended(withFraction: 0.45, of: colorFromHexRGB(0xFFFDF5)) ?? trailEffectColor
            }
            particles.append(
                Particle(
                    point: origin,
                    velocity: CGVector(dx: rotatedX * speed, dy: rotatedY * speed),
                    size: CGFloat.random(in: 1.1...3.0),
                    color: color,
                    lifetime: CFTimeInterval(CGFloat.random(in: 0.08...0.2)),
                    timestamp: timestamp
                )
            )
        }
    }

    private func makeInterpolatedTrailSamples(now: CFTimeInterval) -> [TrailSample] {
        guard movePoints.count > 1 else { return [] }
        let lifetime = max(0.01, trailLengthSeconds)
        let maxSamples = 900
        var samples: [TrailSample] = []
        samples.reserveCapacity(min(maxSamples, movePoints.count * 3))
        var sampleIndex = 0

        for segment in 1..<movePoints.count {
            let first = movePoints[segment - 1]
            let second = movePoints[segment]
            let dx = second.point.x - first.point.x
            let dy = second.point.y - first.point.y
            let distance = hypot(dx, dy)
            let interpolationSteps = max(1, min(10, Int(ceil(distance / 5.0))))

            for step in 0...interpolationSteps {
                if segment > 1 && step == 0 { continue }

                let fraction = CGFloat(step) / CGFloat(interpolationSteps)
                let timestamp = first.timestamp + (second.timestamp - first.timestamp) * Double(fraction)
                let age = now - timestamp
                if age < 0 || age > lifetime { continue }

                let point = NSPoint(
                    x: first.point.x + dx * fraction,
                    y: first.point.y + dy * fraction
                )
                let alpha = max(0, 1 - CGFloat(age / lifetime))
                samples.append(TrailSample(point: point, alpha: alpha, index: sampleIndex))
                sampleIndex += 1
            }
        }

        if samples.count > maxSamples {
            return Array(samples.suffix(maxSamples))
        }
        return samples
    }

    private func drawPulses(now: CFTimeInterval) {
        for pulse in pulses {
            let age = now - pulse.timestamp
            if age < 0 || age > pulse.lifetime { continue }

            let progress = CGFloat(age / pulse.lifetime)
            let radius = pulse.startRadius + (pulse.endRadius - pulse.startRadius) * progress
            let alpha = max(0, 1 - progress)
            let rect = NSRect(
                x: pulse.point.x - radius,
                y: pulse.point.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            switch pulse.kind {
            case .circle:
                let path = NSBezierPath(ovalIn: rect)
                if pulse.filled {
                    let gradient = NSGradient(
                        colors: [
                            pulse.color.withAlphaComponent(0.35 * alpha * intensityPreset.glowBoost),
                            pulse.color.withAlphaComponent(0.06 * alpha),
                            .clear,
                        ]
                    )
                    gradient?.draw(in: path, relativeCenterPosition: .zero)
                    pulse.color.withAlphaComponent(0.42 * alpha).setFill()
                    NSBezierPath(
                        ovalIn: NSRect(
                            x: pulse.point.x - radius * 0.28,
                            y: pulse.point.y - radius * 0.28,
                            width: radius * 0.56,
                            height: radius * 0.56
                        )
                    ).fill()
                } else {
                    path.lineWidth = pulse.lineWidth
                    pulse.color.withAlphaComponent(0.95 * alpha).setStroke()
                    path.stroke()
                    let gradient = NSGradient(
                        colors: [
                            pulse.color.withAlphaComponent(0.28 * alpha * intensityPreset.glowBoost),
                            pulse.color.withAlphaComponent(0.05 * alpha),
                            .clear,
                        ]
                    )
                    gradient?.draw(in: path, relativeCenterPosition: .zero)
                }
            case .cross:
                let half = radius
                let path = NSBezierPath()
                path.move(to: NSPoint(x: pulse.point.x - half, y: pulse.point.y))
                path.line(to: NSPoint(x: pulse.point.x + half, y: pulse.point.y))
                path.move(to: NSPoint(x: pulse.point.x, y: pulse.point.y - half))
                path.line(to: NSPoint(x: pulse.point.x, y: pulse.point.y + half))
                path.lineCapStyle = .round
                path.lineWidth = pulse.lineWidth
                pulse.color.withAlphaComponent(0.95 * alpha).setStroke()
                path.stroke()
            }
        }
    }

    private func drawParticles(now: CFTimeInterval) {
        guard !particles.isEmpty else { return }

        for particle in particles {
            let age = now - particle.timestamp
            if age < 0 || age > particle.lifetime { continue }

            let progress = CGFloat(age / particle.lifetime)
            let alpha = max(0, 1 - progress)

            let x = particle.point.x + particle.velocity.dx * CGFloat(age)
            let y = particle.point.y + particle.velocity.dy * CGFloat(age)
            switch trailEffectStyle {
            case .particles:
                let radius = particle.size * (1 + progress * 0.45)
                let rect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                let path = NSBezierPath(ovalIn: rect)
                let gradient = NSGradient(
                    colors: [
                        particle.color.withAlphaComponent(0.48 * alpha),
                        particle.color.withAlphaComponent(0.16 * alpha),
                        .clear,
                    ]
                )
                gradient?.draw(in: path, relativeCenterPosition: .zero)
            case .ink:
                let radius = particle.size * (1.2 + progress * 0.25)
                let rect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                let blob = NSBezierPath(ovalIn: rect)
                particle.color.withAlphaComponent(0.2 * alpha).setFill()
                blob.fill()
            case .electric:
                let endX = x + CGFloat.random(in: -3...3)
                let endY = y + CGFloat.random(in: -3...3)
                let spark = NSBezierPath()
                spark.move(to: NSPoint(x: x, y: y))
                spark.line(to: NSPoint(x: endX, y: endY))
                spark.lineWidth = max(0.8, particle.size * 0.6)
                spark.lineCapStyle = .round
                (particle.color.blended(withFraction: 0.45, of: .white) ?? particle.color)
                    .withAlphaComponent(0.9 * alpha)
                    .setStroke()
                spark.stroke()
            }
        }
    }

    private func drawPressedState() {
        guard let cursorPoint else { return }
        guard pressedButton != .none else { return }
        let style = effectStyle(for: pressedButton)
        guard style.isEnabled else { return }
        let stateColor = style.color

        let radius: CGFloat = clickEffectRadius * 0.45
        let rect = NSRect(
            x: cursorPoint.x - radius,
            y: cursorPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let path = NSBezierPath(ovalIn: rect)
        stateColor.withAlphaComponent(0.22).setFill()
        path.fill()
    }

    private func drawClickAccents(now: CFTimeInterval) {
        for accent in clickAccents {
            let age = now - accent.timestamp
            if age < 0 || age > accent.lifetime { continue }
            let progress = CGFloat(age / accent.lifetime)
            let alpha = max(0, 1 - progress)
            let radius = accent.radius * (0.7 + progress * 0.7)
            switch accent.kind {
            case .cross:
                let path = NSBezierPath()
                path.move(to: NSPoint(x: accent.point.x - radius, y: accent.point.y))
                path.line(to: NSPoint(x: accent.point.x + radius, y: accent.point.y))
                path.move(to: NSPoint(x: accent.point.x, y: accent.point.y - radius))
                path.line(to: NSPoint(x: accent.point.x, y: accent.point.y + radius))
                path.lineWidth = max(1.2, trailLineWidth)
                path.lineCapStyle = .round
                accent.color.withAlphaComponent(0.9 * alpha).setStroke()
                path.stroke()
            }
        }
    }

    private func drawMagnifier() {
        guard isMagnifierActive, let cursorPoint else { return }
        let radius = max(20, magnifierRadius)
        let diameter = radius * 2
        let zoom = max(1.0, magnifierZoom)
        let sourceSize = diameter / zoom
        let now = CACurrentMediaTime()

        if now - lastMagnifierCaptureTimestamp >= magnifierCaptureInterval || cachedMagnifierImage == nil {
            guard let quartzPoint = CGEvent(source: nil)?.location else { return }
            let captureRect = CGRect(
                x: quartzPoint.x - sourceSize / 2,
                y: quartzPoint.y - sourceSize / 2,
                width: sourceSize,
                height: sourceSize
            )
            cachedMagnifierImage = {
                if let currentWindowID = window.map({ CGWindowID($0.windowNumber) }) {
                    return CGWindowListCreateImage(
                        captureRect,
                        .optionOnScreenBelowWindow,
                        currentWindowID,
                        [.bestResolution, .boundsIgnoreFraming]
                    )
                }
                return nil
            }() ?? CGWindowListCreateImage(
                captureRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution, .boundsIgnoreFraming]
            )
            lastMagnifierCaptureTimestamp = now
        }

        guard let cgImage = cachedMagnifierImage else { return }

        let circleRect = NSRect(
            x: cursorPoint.x - radius,
            y: cursorPoint.y - radius,
            width: diameter,
            height: diameter
        )

        NSGraphicsContext.saveGraphicsState()
        let clipPath = NSBezierPath(ovalIn: circleRect)
        clipPath.addClip()

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        image.draw(
            in: circleRect,
            from: NSRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height),
            operation: .sourceOver,
            fraction: 1
        )

        NSColor.black.withAlphaComponent(0.08).setFill()
        clipPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let borderPath = NSBezierPath(ovalIn: circleRect)
        borderPath.lineWidth = max(0.5, magnifierBorderWidth)
        magnifierBorderColor.withAlphaComponent(0.96).setStroke()
        borderPath.stroke()

        let outerInset = max(1.5, magnifierBorderWidth * 0.8)
        let outerPath = NSBezierPath(ovalIn: circleRect.insetBy(dx: -outerInset, dy: -outerInset))
        outerPath.lineWidth = max(1, magnifierBorderWidth * 0.66)
        NSColor.black.withAlphaComponent(magnifierShadowOpacity).setStroke()
        outerPath.stroke()

        let innerPath = NSBezierPath(ovalIn: circleRect.insetBy(dx: max(0.8, magnifierBorderWidth * 0.55), dy: max(0.8, magnifierBorderWidth * 0.55)))
        innerPath.lineWidth = max(0.8, magnifierBorderWidth * 0.35)
        (magnifierBorderColor.blended(withFraction: 0.25, of: .white) ?? magnifierBorderColor)
            .withAlphaComponent(0.75)
            .setStroke()
        innerPath.stroke()
    }

    private func addPulse(
        at point: NSPoint,
        color: NSColor,
        filled: Bool,
        kind: Pulse.Kind = .circle,
        startRadius: CGFloat,
        endRadius: CGFloat,
        lineWidth: CGFloat,
        lifetime: CFTimeInterval,
        timestamp: CFTimeInterval
    ) {
        pulses.append(
            Pulse(
                point: point,
                color: color,
                startRadius: startRadius,
                endRadius: endRadius,
                lineWidth: lineWidth,
                filled: filled,
                kind: kind,
                lifetime: lifetime,
                timestamp: timestamp
            )
        )
    }

    private func scaledClickLifetime(_ base: CFTimeInterval) -> CFTimeInterval {
        let scale = max(0.1, clickEffectDurationSeconds / 0.3)
        return max(0.04, base * scale)
    }

    /// 处理按键按下：生成按下态视觉反馈与点击火花。
    private func handleButtonDown(_ button: MouseButtonKind, point: NSPoint, timestamp: CFTimeInterval) {
        guard isClickEffectsEnabled else {
            pressedButton = .none
            AppLogger.shared.log("click effect ignored: global click effects disabled (\(button.rawValue) down)")
            return
        }
        let style = clickEffects[button] ?? ClickEffectStyle(isEnabled: true, color: .systemBlue)
        guard style.isEnabled else {
            pressedButton = .none
            AppLogger.shared.log("click effect ignored: \(button.rawValue) style disabled")
            return
        }
        pressedButton = pressedButton(from: button)
        switch clickVisualStyle {
        case .solidPulse:
            addPulse(
                at: point,
                color: style.color,
                filled: true,
                kind: .circle,
                startRadius: max(2, clickEffectRadius * 0.34),
                endRadius: max(6, clickEffectRadius * 0.9),
                lineWidth: 2.0 + trailLineWidth * 0.15,
                lifetime: scaledClickLifetime(0.28),
                timestamp: timestamp
            )
        case .crossFlare:
            addPulse(
                at: point,
                color: style.color,
                filled: false,
                kind: .cross,
                startRadius: max(4, clickEffectRadius * 0.4),
                endRadius: max(9, clickEffectRadius * 1.05),
                lineWidth: 2.1,
                lifetime: scaledClickLifetime(0.26),
                timestamp: timestamp
            )
            clickAccents.append(
                ClickAccent(
                    point: point,
                    color: style.color,
                    radius: clickEffectRadius * 0.9,
                    kind: .cross,
                    lifetime: scaledClickLifetime(0.22),
                    timestamp: timestamp
                )
            )
        }
        emitClickSpark(at: point, color: style.color, timestamp: timestamp)
        AppLogger.shared.log("click effect emitted: \(button.rawValue) down")
    }

    /// 处理按键抬起：结束按压态并补充释放脉冲。
    private func handleButtonUp(_ button: MouseButtonKind, point: NSPoint, timestamp: CFTimeInterval) {
        guard isClickEffectsEnabled else {
            pressedButton = .none
            AppLogger.shared.log("click effect ignored: global click effects disabled (\(button.rawValue) up)")
            return
        }
        if pressedButton == pressedButton(from: button) {
            pressedButton = .none
        }
        let style = clickEffects[button] ?? ClickEffectStyle(isEnabled: true, color: .systemBlue)
        guard style.isEnabled else {
            AppLogger.shared.log("click effect ignored: \(button.rawValue) style disabled on up")
            return
        }
        let brightColor = style.color.blended(withFraction: 0.2, of: .white) ?? style.color
        switch clickVisualStyle {
        case .solidPulse:
            addPulse(
                at: point,
                color: brightColor,
                filled: false,
                kind: .circle,
                startRadius: max(3, clickEffectRadius * 0.4),
                endRadius: max(8, clickEffectRadius * 1.25),
                lineWidth: 2.2 + trailLineWidth * 0.2,
                lifetime: scaledClickLifetime(0.38),
                timestamp: timestamp
            )
        case .crossFlare:
            addPulse(
                at: point,
                color: brightColor,
                filled: false,
                kind: .cross,
                startRadius: max(4, clickEffectRadius * 0.42),
                endRadius: max(9, clickEffectRadius * 1.1),
                lineWidth: 2.0,
                lifetime: scaledClickLifetime(0.3),
                timestamp: timestamp
            )
        }
        emitClickSpark(at: point, color: brightColor, timestamp: timestamp)
        AppLogger.shared.log("click effect emitted: \(button.rawValue) up")
    }

    private func pressedButton(from button: MouseButtonKind) -> PressedButton {
        switch button {
        case .left:
            return .left
        case .right:
            return .right
        case .middle:
            return .middle
        }
    }

    private func effectStyle(for button: PressedButton) -> ClickEffectStyle {
        guard isClickEffectsEnabled else {
            return ClickEffectStyle(isEnabled: false, color: .clear)
        }
        switch button {
        case .left:
            return clickEffects[.left] ?? ClickEffectStyle(isEnabled: true, color: .systemRed)
        case .right:
            return clickEffects[.right] ?? ClickEffectStyle(isEnabled: true, color: .systemOrange)
        case .middle:
            return clickEffects[.middle] ?? ClickEffectStyle(isEnabled: true, color: .systemPurple)
        case .none:
            return ClickEffectStyle(isEnabled: false, color: .clear)
        }
    }

    private func rainbowColor(for index: Int, now: CFTimeInterval) -> NSColor {
        let colors = rainbowTrailColors.isEmpty ? AppSettings.default.rainbowTrailColors : rainbowTrailColors
        if colors.count == 1 { return colors[0] }
        let progress = CGFloat((Double(index) * 0.22 + now * 1.8).truncatingRemainder(dividingBy: Double(colors.count)))
        let base = Int(progress) % colors.count
        let next = (base + 1) % colors.count
        let fraction = progress - CGFloat(base)
        return colors[base].blended(withFraction: fraction, of: colors[next]) ?? colors[base]
    }

    private func makeLightningPath(from start: NSPoint, to end: NSPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: start)
        let segments = 4
        for segment in 1...segments {
            let t = CGFloat(segment) / CGFloat(segments)
            let x = start.x + (end.x - start.x) * t + CGFloat.random(in: -2.6...2.6)
            let y = start.y + (end.y - start.y) * t + CGFloat.random(in: -2.6...2.6)
            path.line(to: NSPoint(x: x, y: y))
        }
        return path
    }

    private func makeLightningBranch(from origin: NSPoint) -> NSBezierPath {
        let branch = NSBezierPath()
        branch.move(to: origin)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let length = CGFloat.random(in: 5...12)
        branch.line(to: NSPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length))
        return branch
    }

    private func trailBaseColor(index: Int, now: CFTimeInterval) -> NSColor {
        switch trailStyle {
        case .rainbow:
            return rainbowColor(for: index, now: now)
        case .neon:
            return neonPrimaryColor.blended(withFraction: 0.5, of: neonSecondaryColor) ?? neonPrimaryColor
        default:
            return trailColor
        }
    }

    /// 沿轨迹段发射附加粒子/墨迹/电弧效果。
    /// Note: 发射密度同时受“特效密度（强度预设）”和轨迹段长度影响。
    private func emitTrailEffects(from start: NSPoint, to end: NSPoint, timestamp: CFTimeInterval) {
        guard isTrailEnabled else { return }
        if trailStyle == .ribbon { return }
        guard intensityPreset.effectsEnabled else { return }
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance > 0.1 else { return }

        let baseCount = max(1, Int(distance / 10))
        let styleMultiplier: CGFloat = switch trailEffectStyle {
        case .particles: 1.0
        case .ink: 0.55
        case .electric: 1.15
        }
        let spawnCount = min(
            Int(CGFloat(baseCount) * intensityPreset.particleSpawnMultiplier * styleMultiplier) + 1,
            max(4, Int(12 * intensityPreset.particleSpawnMultiplier))
        )
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let directionLength = max(0.001, hypot(direction.dx, direction.dy))
        let normal = CGVector(dx: direction.dx / directionLength, dy: direction.dy / directionLength)

        for index in 0..<spawnCount {
            let interpolation = CGFloat(index) / CGFloat(max(1, spawnCount))
            let jitter = CGFloat.random(in: -2...2)
            let x = start.x + (end.x - start.x) * interpolation + jitter
            let y = start.y + (end.y - start.y) * interpolation + CGFloat.random(in: -2...2)

            let velocity: CGVector
            let size: CGFloat
            let lifetime: CFTimeInterval
            let color: NSColor
            let baseColor = trailBaseColor(index: index, now: timestamp)
            let effectBaseColor = trailEffectColor.blended(withFraction: 0.2, of: baseColor) ?? trailEffectColor

            switch trailEffectStyle {
            case .particles:
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let speed = CGFloat.random(in: intensityPreset.particleSpeedRange)
                velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
                size = CGFloat.random(in: intensityPreset.particleSizeRange)
                lifetime = intensityPreset.particleLifetime * Double(CGFloat.random(in: 0.75...1.15))
                color = effectBaseColor.blended(withFraction: 0.18, of: .white) ?? effectBaseColor
            case .ink:
                velocity = CGVector(dx: CGFloat.random(in: -12...12), dy: CGFloat.random(in: -12...12))
                size = CGFloat.random(in: 2.5...6.5)
                lifetime = 0.55
                color = effectBaseColor.withAlphaComponent(0.55)
            case .electric:
                let speed = CGFloat.random(in: intensityPreset.particleSpeedRange.upperBound ... intensityPreset.particleSpeedRange.upperBound * 1.8)
                let angle = CGFloat.random(in: -0.9...0.9)
                let rotatedX = normal.dx * cos(angle) - normal.dy * sin(angle)
                let rotatedY = normal.dx * sin(angle) + normal.dy * cos(angle)
                velocity = CGVector(dx: rotatedX * speed, dy: rotatedY * speed)
                size = CGFloat.random(in: 1.0...2.4)
                lifetime = 0.14
                color = (effectBaseColor.blended(withFraction: 0.55, of: .white) ?? effectBaseColor)
            }

            particles.append(
                Particle(
                    point: NSPoint(x: x, y: y),
                    velocity: velocity,
                    size: size,
                    color: color,
                    lifetime: lifetime,
                    timestamp: timestamp
                )
            )
        }
    }

    private func emitClickSpark(at point: NSPoint, color: NSColor, timestamp: CFTimeInterval) {
        guard intensityPreset.effectsEnabled else { return }
        let count = max(6, Int(10 * intensityPreset.particleSpawnMultiplier))
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: intensityPreset.particleSpeedRange.upperBound * 0.8 ... intensityPreset.particleSpeedRange.upperBound * 1.25)
            let velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
            let sizeBoost = max(0.8, clickEffectRadius / 24)
            let size = CGFloat.random(in: intensityPreset.particleSizeRange.lowerBound ... intensityPreset.particleSizeRange.upperBound * 1.25) * sizeBoost
            let lifetime = scaledClickLifetime(intensityPreset.particleLifetime * Double(CGFloat.random(in: 0.6...1.05)))
            particles.append(
                Particle(
                    point: point,
                    velocity: velocity,
                    size: size,
                    color: color,
                    lifetime: lifetime,
                    timestamp: timestamp
                )
            )
        }
    }

    private func startRefreshLoop() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.tick()
            }
        }
        timer.tolerance = refreshInterval * 0.5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        syncPressedButtonState()
        trimExpiredPrefix(from: &movePoints) { now - $0.timestamp > trailLengthSeconds }
        trimExpiredPrefix(from: &pulses) { now - $0.timestamp > $0.lifetime }
        trimExpiredPrefix(from: &particles) { now - $0.timestamp > $0.lifetime }
        trimExpiredPrefix(from: &clickAccents) { now - $0.timestamp > $0.lifetime }
        trimExpiredPrefix(from: &dashBursts) { now - $0.timestamp > $0.lifetime }
        if particles.count > intensityPreset.maxParticleCount {
            particles.removeFirst(particles.count - intensityPreset.maxParticleCount)
        }
        let hasAnimatedContent =
            !movePoints.isEmpty ||
            !pulses.isEmpty ||
            !particles.isEmpty ||
            !clickAccents.isEmpty ||
            !dashBursts.isEmpty ||
            pressedButton != .none ||
            isMagnifierActive
        if hasAnimatedContent || hadAnimatedContentOnLastTick {
            needsDisplay = true
        }
        hadAnimatedContentOnLastTick = hasAnimatedContent
    }

    private func trimExpiredPrefix<T>(from array: inout [T], isExpired: (T) -> Bool) {
        guard !array.isEmpty else { return }
        if let firstAliveIndex = array.firstIndex(where: { !isExpired($0) }) {
            if firstAliveIndex > 0 {
                array.removeFirst(firstAliveIndex)
            }
        } else {
            array.removeAll(keepingCapacity: true)
        }
    }

    private func syncPressedButtonState() {
        switch pressedButton {
        case .none:
            return
        case .left:
            if !CGEventSource.buttonState(.combinedSessionState, button: .left) {
                pressedButton = .none
            }
        case .right:
            if !CGEventSource.buttonState(.combinedSessionState, button: .right) {
                pressedButton = .none
            }
        case .middle:
            if !CGEventSource.buttonState(.combinedSessionState, button: .center) {
                pressedButton = .none
            }
        }
    }
}

@MainActor
/// 多屏覆盖层窗口管理器。
/// 职责：为每块屏幕构建一层透明渲染窗口，并在屏幕拓扑变化时重建。
final class OverlayWindowManager {
    private struct Overlay {
        let window: NSWindow
        let view: TrailOverlayView
    }

    private var overlays: [Overlay] = []
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

            window.orderFrontRegardless()

            overlays.append(Overlay(window: window, view: view))
        }
    }
}

@MainActor
/// 翻转坐标系的容器视图，确保滚动内容从顶部开始布局。
private final class FlippedTopAlignedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
/// 设置窗口控制器。
/// 职责：构建设置 UI、同步控件状态，并对外发布设置变更。
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum SidebarTab: String, CaseIterable {
        case trailEffects
        case clickEffects
        case magnifier
        case general

        var title: String {
            switch self {
            case .trailEffects: return "轨迹效果"
            case .clickEffects: return "点击效果"
            case .magnifier: return "放大镜"
            case .general: return "设置"
            }
        }

        var symbolName: String {
            switch self {
            case .trailEffects: return "scribble"
            case .clickEffects: return "cursorarrow.click"
            case .magnifier: return "plus.magnifyingglass"
            case .general: return "gearshape"
            }
        }
    }

    private enum TrailPresetOption: CaseIterable {
        case custom
        case thunderFirstForm

        var title: String {
            switch self {
            case .custom:
                return "自定义"
            case .thunderFirstForm:
                return "雷之呼吸·壹之型"
            }
        }
    }

    var onSettingsChanged: ((AppSettings) -> Void)?
    var onRequestInputMonitoringPermission: (() -> Void)?
    var isRecordingShortcut: Bool { isShortcutRecording }

    private var settings: AppSettings
    private var isSyncingControls = false
    private var activeSidebarTab: SidebarTab = .trailEffects
    private var sidebarButtons: [SidebarTab: NSButton] = [:]
    private var sidebarButtonToTab: [ObjectIdentifier: SidebarTab] = [:]
    private var sidebarContentViews: [SidebarTab: NSView] = [:]
    private var contentScrollView: NSScrollView?

    private let launchAtLoginSwitch = NSSwitch()
    private let loggingSwitch = NSSwitch()
    private let statusItemSwitch = NSSwitch()
    private let trackingSwitch = NSSwitch()
    private let clickEffectsSwitch = NSSwitch()
    private let magnifierEnabledSwitch = NSSwitch()
    private let magnifierShowEffectsSwitch = NSSwitch()
    private let speedBurstSwitch = NSSwitch()

    private let trailColorWell = NSColorWell()
    private let trailEffectColorWell = NSColorWell()
    private let speedBurstLineColorWell = NSColorWell()
    private let speedBurstAccentColorWell = NSColorWell()
    private let neonPrimaryColorWell = NSColorWell()
    private let neonSecondaryColorWell = NSColorWell()
    private let magnifierBorderColorWell = NSColorWell()

    private let trailWidthSlider = NSSlider()
    private let trailWidthValueLabel = NSTextField(labelWithString: "")
    private let trailLengthSlider = NSSlider()
    private let trailLengthValueLabel = NSTextField(labelWithString: "")
    private let speedBurstVelocitySlider = NSSlider()
    private let speedBurstVelocityValueLabel = NSTextField(labelWithString: "")
    private let speedBurstCooldownSlider = NSSlider()
    private let speedBurstCooldownValueLabel = NSTextField(labelWithString: "")
    private let speedBurstDurationSlider = NSSlider()
    private let speedBurstDurationValueLabel = NSTextField(labelWithString: "")
    private let speedBurstJitterSlider = NSSlider()
    private let speedBurstJitterValueLabel = NSTextField(labelWithString: "")
    private let speedBurstMinLengthSlider = NSSlider()
    private let speedBurstMinLengthValueLabel = NSTextField(labelWithString: "")
    private let speedBurstMaxLengthSlider = NSSlider()
    private let speedBurstMaxLengthValueLabel = NSTextField(labelWithString: "")
    private let speedBurstWidthMultiplierSlider = NSSlider()
    private let speedBurstWidthMultiplierValueLabel = NSTextField(labelWithString: "")
    private let speedBurstAccentDurationSlider = NSSlider()
    private let speedBurstAccentDurationValueLabel = NSTextField(labelWithString: "")
    private let speedBurstAccentSizeSlider = NSSlider()
    private let speedBurstAccentSizeValueLabel = NSTextField(labelWithString: "")
    private let clickRadiusSlider = NSSlider()
    private let clickRadiusValueLabel = NSTextField(labelWithString: "")
    private let clickDurationSlider = NSSlider()
    private let clickDurationValueLabel = NSTextField(labelWithString: "")
    private let magnifierRadiusSlider = NSSlider()
    private let magnifierRadiusValueLabel = NSTextField(labelWithString: "")
    private let magnifierZoomSlider = NSSlider()
    private let magnifierZoomValueLabel = NSTextField(labelWithString: "")
    private let magnifierBorderWidthSlider = NSSlider()
    private let magnifierBorderWidthValueLabel = NSTextField(labelWithString: "")
    private let magnifierShadowSlider = NSSlider()
    private let magnifierShadowValueLabel = NSTextField(labelWithString: "")

    private let trailStylePopup = NSPopUpButton()
    private let trailEffectPopup = NSPopUpButton()
    private let speedBurstTypePopup = NSPopUpButton()
    private let clickStylePopup = NSPopUpButton()
    private let intensityPopup = NSPopUpButton()
    private let trailPresetPopup = NSPopUpButton()
    private let magnifierShortcutButton = NSButton(title: "", target: nil, action: nil)
    private let magnifierShortcutHint = NSTextField(labelWithString: "点击录制后按下按键/鼠标键，按住即可触发放大镜。")
    private let launchAtLoginStatusLabel = NSTextField(labelWithString: "")

    private let inputMonitoringStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let screenCaptureStatusLabel = NSTextField(labelWithString: "")
    private let openInputMonitoringSettingsButton = NSButton(title: "前往输入监控设置", target: nil, action: nil)
    private let openAccessibilitySettingsButton = NSButton(title: "前往辅助功能设置", target: nil, action: nil)
    private let openScreenCaptureSettingsButton = NSButton(title: "前往屏幕录制设置", target: nil, action: nil)
    private let openLogFolderButton = NSButton(title: "打开日志文件夹", target: nil, action: nil)
    private let rainbowColorWells: [NSColorWell] = (0..<6).map { _ in NSColorWell() }
    private var rowWrapperByRowIdentifier: [ObjectIdentifier: NSView] = [:]
    private lazy var trailPresetHeaderControl = makeTrailPresetHeaderControl()

    private lazy var trailTypeRow = makePopupRow(title: "轨迹类型", popup: trailStylePopup)
    private lazy var trailColorRow = makeColorRow(title: "轨迹颜色", control: trailColorWell)
    private lazy var trailEffectColorRow = makeColorRow(title: "特效颜色", control: trailEffectColorWell)
    private lazy var neonColorsRow = makeNeonColorsRow()
    private lazy var rainbowColorsRow = makeRainbowColorsRow()
    private lazy var trailEffectTypeRow = makePopupRow(title: "特效类型", popup: trailEffectPopup)
    private lazy var trailWidthRow = makeSliderRow(title: "轨迹粗细", slider: trailWidthSlider, valueLabel: trailWidthValueLabel)
    private lazy var trailLengthRow = makeSliderRow(title: "轨迹长度（毫秒）", slider: trailLengthSlider, valueLabel: trailLengthValueLabel)
    private lazy var trailIntensityRow = makePopupRow(title: "特效强度", popup: intensityPopup)
    private lazy var speedBurstTypeRow = makePopupRow(title: "爆发类型", popup: speedBurstTypePopup)
    private lazy var speedBurstLineColorRow = makeColorRow(title: "爆发线颜色", control: speedBurstLineColorWell)
    private lazy var speedBurstAccentColorRow = makeColorRow(title: "端点爆发颜色", control: speedBurstAccentColorWell)
    private lazy var speedBurstVelocityRow = makeSliderRow(title: "触发速度阈值", slider: speedBurstVelocitySlider, valueLabel: speedBurstVelocityValueLabel)
    private lazy var speedBurstCooldownRow = makeSliderRow(title: "冷却时间（毫秒）", slider: speedBurstCooldownSlider, valueLabel: speedBurstCooldownValueLabel)
    private lazy var speedBurstDurationRow = makeSliderRow(title: "爆发线时长（毫秒）", slider: speedBurstDurationSlider, valueLabel: speedBurstDurationValueLabel)
    private lazy var speedBurstJitterRow = makeSliderRow(title: "爆发线抖动幅度", slider: speedBurstJitterSlider, valueLabel: speedBurstJitterValueLabel)
    private lazy var speedBurstMinLengthRow = makeSliderRow(title: "爆发线最小长度", slider: speedBurstMinLengthSlider, valueLabel: speedBurstMinLengthValueLabel)
    private lazy var speedBurstMaxLengthRow = makeSliderRow(title: "爆发线最大长度", slider: speedBurstMaxLengthSlider, valueLabel: speedBurstMaxLengthValueLabel)
    private lazy var speedBurstWidthMultiplierRow = makeSliderRow(title: "爆发线宽系数", slider: speedBurstWidthMultiplierSlider, valueLabel: speedBurstWidthMultiplierValueLabel)
    private lazy var speedBurstAccentDurationRow = makeSliderRow(title: "端点爆发时长（毫秒）", slider: speedBurstAccentDurationSlider, valueLabel: speedBurstAccentDurationValueLabel)
    private lazy var speedBurstAccentSizeRow = makeSliderRow(title: "端点爆发大小", slider: speedBurstAccentSizeSlider, valueLabel: speedBurstAccentSizeValueLabel)
    private lazy var clickDurationRow = makeSliderRow(title: "点击效果时长（毫秒）", slider: clickDurationSlider, valueLabel: clickDurationValueLabel)

    private var clickToggleButtons: [MouseButtonKind: NSSwitch] = [:]
    private var clickColorWells: [MouseButtonKind: NSColorWell] = [:]
    private var toggleButtonToKind: [ObjectIdentifier: MouseButtonKind] = [:]
    private var colorWellToKind: [ObjectIdentifier: MouseButtonKind] = [:]

    private var shortcutCaptureMonitor: Any?
    private var isShortcutRecording = false

    init(initialSettings: AppSettings) {
        settings = initialSettings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CursorTrailBar 设置"
        window.center()
        window.minSize = NSSize(width: 820, height: 740)
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        configureUI()
        syncControlsFromSettings()
    }

    required init?(coder: NSCoder) { nil }

    /// 展示并激活设置窗口。
    func present() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 用外部最新配置刷新窗口控件。
    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        syncControlsFromSettings()
    }

    /// 组装主界面结构（侧边菜单 + 右侧滚动内容区）。
    /// Note: 采用一次构建、多 Tab 切换显隐的方式，避免频繁重建控件。
    private func configureUI() {
        guard let contentView = window?.contentView else { return }

        let backgroundView = NSView()
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let splitStack = NSStackView()
        splitStack.orientation = .horizontal
        splitStack.alignment = .top
        splitStack.distribution = .fill
        splitStack.spacing = 0
        splitStack.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(splitStack)
        NSLayoutConstraint.activate([
            splitStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            splitStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            splitStack.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            splitStack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
        ])

        let sidebarView = makeSidebarView()
        splitStack.addArrangedSubview(sidebarView)
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.widthAnchor.constraint(equalToConstant: 190).isActive = true

        let rightPanelContainer = NSView()
        rightPanelContainer.wantsLayer = true
        rightPanelContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        rightPanelContainer.translatesAutoresizingMaskIntoConstraints = false
        splitStack.addArrangedSubview(rightPanelContainer)

        let contentRightInset: CGFloat = 18
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        rightPanelContainer.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rightPanelContainer.leadingAnchor, constant: 18),
            scrollView.trailingAnchor.constraint(equalTo: rightPanelContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rightPanelContainer.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: rightPanelContainer.bottomAnchor, constant: -16),
        ])
        contentScrollView = scrollView

        let documentView = FlippedTopAlignedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill
        contentStack.detachesHiddenViews = true
        contentStack.spacing = 14
        contentStack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -contentRightInset),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -contentRightInset),
        ])

        let regularSection = buildRegularSection()
        let trailSection = buildTrailSection()
        let speedBurstSection = buildSpeedBurstSection()
        let clickSection = buildClickSection()
        let magnifierSection = buildMagnifierSection()
        let trailComposite = makeSidebarCompositeContent(sections: [trailSection, speedBurstSection])
        let contentsByTab: [(SidebarTab, NSView)] = [
            (.trailEffects, trailComposite),
            (.clickEffects, clickSection),
            (.magnifier, magnifierSection),
            (.general, regularSection),
        ]

        contentsByTab.forEach { tab, section in
            section.translatesAutoresizingMaskIntoConstraints = false
            section.setContentHuggingPriority(.defaultLow, for: .horizontal)
            section.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            contentStack.addArrangedSubview(section)
            NSLayoutConstraint.activate([
                section.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
                section.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
                section.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -contentRightInset),
            ])
            sidebarContentViews[tab] = section
        }
        contentStack.addArrangedSubview(NSView())
        activateSidebarTab(.trailEffects, scrollToTop: true)

        applyCompactControlSizes()
        configureTargets()
        configureSliders()
        refreshPermissionIndicators()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activateSidebarTab(self.activeSidebarTab, scrollToTop: true)
        }
    }

    /// 构建左侧菜单区域及其分隔边线。
    private func makeSidebarView() -> NSView {
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 12, bottom: 14, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
        ])

        for tab in SidebarTab.allCases {
            let button = makeSidebarButton(for: tab)
            sidebarButtons[tab] = button
            sidebarButtonToTab[ObjectIdentifier(button)] = tab
            stack.addArrangedSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -26).isActive = true
        }

        stack.addArrangedSubview(NSView())

        let rightBorder = NSView()
        rightBorder.wantsLayer = true
        rightBorder.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.04).cgColor
        rightBorder.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(rightBorder)
        NSLayoutConstraint.activate([
            rightBorder.topAnchor.constraint(equalTo: sidebar.topAnchor),
            rightBorder.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            rightBorder.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            rightBorder.widthAnchor.constraint(equalToConstant: 1),
        ])

        return sidebar
    }

    private func makeSidebarButton(for tab: SidebarTab) -> NSButton {
        let button = NSButton(title: tab.title, target: self, action: #selector(sidebarTabClicked(_:)))
        button.font = .systemFont(ofSize: 13, weight: .regular)
        button.alignment = .left
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = makeSidebarIcon(for: tab, tintColor: .labelColor)
        button.imagePosition = .imageLeading
        button.contentTintColor = nil
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.masksToBounds = true
        button.setButtonType(.momentaryPushIn)
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    /// 生成带左右内边距的单色 SF Symbol 图标，避免侧边菜单高亮时出现多色视觉干扰。
    private func makePaddedSidebarSymbolImage(
        systemName: String,
        leftPadding: CGFloat,
        rightPadding: CGFloat,
        symbolPointSize: CGFloat,
        tintColor: NSColor
    ) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
        let baseSymbol =
            NSImage(systemSymbolName: systemName, accessibilityDescription: nil) ??
            NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil)
        guard let symbol = baseSymbol?.withSymbolConfiguration(config) else {
            return nil
        }
        let symbolSize = symbol.size
        let imageSize = NSSize(width: symbolSize.width + leftPadding + rightPadding, height: max(symbolSize.height, 16))
        let image = NSImage(size: imageSize)
        image.lockFocus()
        let symbolRect = NSRect(
            x: leftPadding,
            y: (imageSize.height - symbolSize.height) * 0.5,
            width: symbolSize.width,
            height: symbolSize.height
        )
        symbol.draw(
            at: symbolRect.origin,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        tintColor.setFill()
        let graphicsContext = NSGraphicsContext.current
        let previousCompositing = graphicsContext?.compositingOperation
        graphicsContext?.compositingOperation = .sourceAtop
        NSBezierPath(rect: symbolRect).fill()
        graphicsContext?.compositingOperation = previousCompositing ?? .sourceOver
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func makeSidebarIcon(for tab: SidebarTab, tintColor: NSColor) -> NSImage? {
        return makePaddedSidebarSymbolImage(
            systemName: tab.symbolName,
            leftPadding: 12,
            rightPadding: 9,
            symbolPointSize: 14,
            tintColor: tintColor
        )
    }

    private func makeSidebarCompositeContent(sections: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        sections.forEach { section in
            stack.addArrangedSubview(section)
            section.translatesAutoresizingMaskIntoConstraints = false
            section.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            section.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        return stack
    }

    @objc
    private func sidebarTabClicked(_ sender: NSButton) {
        guard let tab = sidebarButtonToTab[ObjectIdentifier(sender)] else { return }
        activateSidebarTab(tab, scrollToTop: true)
    }

    /// 激活侧边菜单项并切换右侧内容可见性。
    /// - Parameter scrollToTop: 切换后是否重置右侧滚动位置到顶部。
    private func activateSidebarTab(_ tab: SidebarTab, scrollToTop: Bool) {
        activeSidebarTab = tab
        for (key, view) in sidebarContentViews {
            view.isHidden = key != tab
        }
        refreshSidebarSelectionState()
        if scrollToTop, let scrollView = contentScrollView {
            scrollView.documentView?.layoutSubtreeIfNeeded()
            scrollContentToTop(scrollView)
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.scrollContentToTop(scrollView)
            }
        }
    }

    private func refreshSidebarSelectionState() {
        for (tab, button) in sidebarButtons {
            let isSelected = tab == activeSidebarTab
            let titleColor = isSelected ? NSColor.white : NSColor.labelColor
            let titleWeight: NSFont.Weight = isSelected ? .semibold : .regular
            button.attributedTitle = NSAttributedString(
                string: tab.title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: titleWeight),
                    .foregroundColor: titleColor,
                ]
            )
            button.image = makeSidebarIcon(for: tab, tintColor: titleColor)
            button.layer?.backgroundColor = isSelected
                ? colorFromHexRGB(0x0165E1).cgColor
                : NSColor.clear.cgColor
        }
    }

    /// 将右侧滚动区域复位到顶部。
    /// Note: 包含一次异步复位，避免首帧布局未完成时滚动位置被覆盖。
    private func scrollContentToTop(_ scrollView: NSScrollView) {
        let clipView = scrollView.contentView
        guard let documentView = scrollView.documentView else { return }
        documentView.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        let topY: CGFloat = if documentView.isFlipped {
            0
        } else {
            max(0, documentView.bounds.height - clipView.bounds.height)
        }
        clipView.scroll(to: NSPoint(x: 0, y: topY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func configureTargets() {
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginSwitchChanged(_:))

        loggingSwitch.target = self
        loggingSwitch.action = #selector(loggingSwitchChanged(_:))

        statusItemSwitch.target = self
        statusItemSwitch.action = #selector(statusItemSwitchChanged(_:))

        trackingSwitch.target = self
        trackingSwitch.action = #selector(trackingSwitchChanged(_:))

        speedBurstSwitch.target = self
        speedBurstSwitch.action = #selector(speedBurstSwitchChanged(_:))

        clickEffectsSwitch.target = self
        clickEffectsSwitch.action = #selector(clickEffectsSwitchChanged(_:))

        magnifierEnabledSwitch.target = self
        magnifierEnabledSwitch.action = #selector(magnifierEnabledSwitchChanged(_:))

        magnifierShowEffectsSwitch.target = self
        magnifierShowEffectsSwitch.action = #selector(magnifierShowEffectsSwitchChanged(_:))

        trailColorWell.target = self
        trailColorWell.action = #selector(trailColorChanged(_:))
        trailEffectColorWell.target = self
        trailEffectColorWell.action = #selector(trailEffectColorChanged(_:))
        speedBurstLineColorWell.target = self
        speedBurstLineColorWell.action = #selector(speedBurstLineColorChanged(_:))
        speedBurstAccentColorWell.target = self
        speedBurstAccentColorWell.action = #selector(speedBurstAccentColorChanged(_:))
        neonPrimaryColorWell.target = self
        neonPrimaryColorWell.action = #selector(neonPrimaryColorChanged(_:))
        neonSecondaryColorWell.target = self
        neonSecondaryColorWell.action = #selector(neonSecondaryColorChanged(_:))
        magnifierBorderColorWell.target = self
        magnifierBorderColorWell.action = #selector(magnifierBorderColorChanged(_:))

        trailStylePopup.target = self
        trailStylePopup.action = #selector(trailStyleChanged(_:))
        trailStylePopup.addItems(withTitles: TrailRenderStyle.allCases.map(\.title))

        trailEffectPopup.target = self
        trailEffectPopup.action = #selector(trailEffectStyleChanged(_:))
        trailEffectPopup.addItems(withTitles: TrailEffectStyle.allCases.map(\.title))

        speedBurstTypePopup.target = self
        speedBurstTypePopup.action = #selector(speedBurstTypeChanged(_:))
        speedBurstTypePopup.addItems(withTitles: SpeedBurstEffectType.allCases.map(\.title))

        clickStylePopup.target = self
        clickStylePopup.action = #selector(clickVisualStyleChanged(_:))
        clickStylePopup.addItems(withTitles: ClickVisualStyle.allCases.map(\.title))

        intensityPopup.target = self
        intensityPopup.action = #selector(intensityChanged(_:))
        intensityPopup.addItems(withTitles: EffectIntensityPreset.allCases.map(\.title))

        trailPresetPopup.target = self
        trailPresetPopup.action = #selector(trailPresetChanged(_:))
        trailPresetPopup.addItems(withTitles: TrailPresetOption.allCases.map(\.title))
        trailPresetPopup.selectItem(at: 0)

        for (index, colorWell) in rainbowColorWells.enumerated() {
            colorWell.tag = index
            colorWell.target = self
            colorWell.action = #selector(rainbowColorChanged(_:))
        }

        magnifierShortcutButton.target = self
        magnifierShortcutButton.action = #selector(toggleShortcutRecording(_:))
        magnifierShortcutButton.bezelStyle = .rounded

        openInputMonitoringSettingsButton.target = self
        openInputMonitoringSettingsButton.action = #selector(openInputMonitoringSettings(_:))
        openAccessibilitySettingsButton.target = self
        openAccessibilitySettingsButton.action = #selector(openAccessibilitySettings(_:))
        openScreenCaptureSettingsButton.target = self
        openScreenCaptureSettingsButton.action = #selector(openScreenCaptureSettings(_:))
        openLogFolderButton.target = self
        openLogFolderButton.action = #selector(openLogFolder(_:))

    }

    private func configureSliders() {
        configureSlider(trailWidthSlider, min: 0.1, max: 100, value: 2.2, action: #selector(trailWidthSliderChanged(_:)))
        configureSlider(trailLengthSlider, min: 1, max: 10_000, value: 650, action: #selector(trailLengthSliderChanged(_:)))
        configureSlider(speedBurstVelocitySlider, min: 100, max: 60_000, value: 1800, action: #selector(speedBurstVelocitySliderChanged(_:)))
        configureSlider(speedBurstCooldownSlider, min: 50, max: 3000, value: 450, action: #selector(speedBurstCooldownSliderChanged(_:)))
        configureSlider(speedBurstDurationSlider, min: 40, max: 800, value: 450, action: #selector(speedBurstDurationSliderChanged(_:)))
        configureSlider(speedBurstJitterSlider, min: 0, max: 30, value: 5, action: #selector(speedBurstJitterSliderChanged(_:)))
        configureSlider(speedBurstMinLengthSlider, min: 10, max: 5000, value: 110, action: #selector(speedBurstMinLengthSliderChanged(_:)))
        configureSlider(speedBurstMaxLengthSlider, min: 10, max: 5000, value: 220, action: #selector(speedBurstMaxLengthSliderChanged(_:)))
        configureSlider(speedBurstWidthMultiplierSlider, min: 0.2, max: 4.0, value: 1.55, action: #selector(speedBurstWidthMultiplierSliderChanged(_:)))
        configureSlider(speedBurstAccentDurationSlider, min: 40, max: 2000, value: 190, action: #selector(speedBurstAccentDurationSliderChanged(_:)))
        configureSlider(speedBurstAccentSizeSlider, min: 4, max: 400, value: 32, action: #selector(speedBurstAccentSizeSliderChanged(_:)))
        configureSlider(clickRadiusSlider, min: 1, max: 600, value: 24, action: #selector(clickRadiusSliderChanged(_:)))
        configureSlider(clickDurationSlider, min: 40, max: 2000, value: 300, action: #selector(clickDurationSliderChanged(_:)))
        configureSlider(magnifierRadiusSlider, min: 20, max: 1200, value: 120, action: #selector(magnifierRadiusSliderChanged(_:)))
        configureSlider(magnifierZoomSlider, min: 1.0, max: 8.0, value: 2.0, action: #selector(magnifierZoomSliderChanged(_:)))
        configureSlider(magnifierBorderWidthSlider, min: 0, max: 30, value: 3, action: #selector(magnifierBorderWidthSliderChanged(_:)))
        configureSlider(magnifierShadowSlider, min: 0, max: 1, value: 0.28, action: #selector(magnifierShadowSliderChanged(_:)))

    }

    private func configureSlider(_ slider: NSSlider, min: Double, max: Double, value: Double, action: Selector) {
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = value
        slider.isContinuous = true
        slider.target = self
        slider.action = action
    }

    private func applyCompactControlSizes() {
        let switches: [NSSwitch] =
            [launchAtLoginSwitch, loggingSwitch, statusItemSwitch, trackingSwitch, speedBurstSwitch, clickEffectsSwitch, magnifierEnabledSwitch, magnifierShowEffectsSwitch]
            + Array(clickToggleButtons.values)
        for item in switches {
            item.controlSize = .mini
        }

        let colorWells: [NSColorWell] =
            [trailColorWell, trailEffectColorWell, speedBurstLineColorWell, speedBurstAccentColorWell, neonPrimaryColorWell, neonSecondaryColorWell, magnifierBorderColorWell]
            + Array(clickColorWells.values)
            + rainbowColorWells
        for colorWell in colorWells {
            colorWell.controlSize = .small
            colorWell.translatesAutoresizingMaskIntoConstraints = false
            colorWell.widthAnchor.constraint(equalToConstant: 32).isActive = true
            colorWell.heightAnchor.constraint(equalToConstant: 20).isActive = true
        }
    }

    private func buildRegularSection() -> NSView {
        launchAtLoginStatusLabel.font = .systemFont(ofSize: 11)
        launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        return makeSectionCard(
            title: "常规",
            subtitle: "开机与常驻相关设置",
            rows: [
                makeSwitchRow(title: "开机启动", subtitleLabel: launchAtLoginStatusLabel, toggle: launchAtLoginSwitch),
                makeSwitchRow(title: "启用日志输出", subtitle: "写入日志文件以便排查问题", toggle: loggingSwitch),
                makeButtonRow(title: "日志目录", button: openLogFolderButton),
                makeSwitchRow(title: "菜单栏显示图标", subtitle: "关闭后仅保留主界面与全局功能", toggle: statusItemSwitch),
            ]
        )
    }

    private func buildTrailSection() -> NSView {
        return makeSectionCard(
            title: "轨迹",
            subtitle: "鼠标轨迹与基础特效参数",
            headerTrailing: trailPresetHeaderControl,
            rows: [
                makeSwitchRow(title: "开启轨迹", subtitle: "关闭后不再绘制轨迹", toggle: trackingSwitch),
                trailTypeRow,
                trailColorRow,
                neonColorsRow,
                rainbowColorsRow,
                trailEffectTypeRow,
                trailEffectColorRow,
                trailWidthRow,
                trailLengthRow,
                trailIntensityRow,
            ]
        )
    }

    private func buildSpeedBurstSection() -> NSView {
        return makeSectionCard(
            title: "加速爆发",
            subtitle: "高速移动触发的额外爆发特效",
            rows: [
                makeSwitchRow(title: "开启加速爆发", subtitle: "关闭后将不触发一之闪", toggle: speedBurstSwitch),
                speedBurstTypeRow,
                speedBurstVelocityRow,
                speedBurstCooldownRow,
                speedBurstAccentColorRow,
                speedBurstAccentDurationRow,
                speedBurstAccentSizeRow,
                speedBurstLineColorRow,
                speedBurstDurationRow,
                speedBurstMinLengthRow,
                speedBurstMaxLengthRow,
                speedBurstWidthMultiplierRow,
                speedBurstJitterRow,
            ]
        )
    }

    private func buildClickSection() -> NSView {
        var rows: [NSView] = [
            makeSwitchRow(title: "开启点击效果", subtitle: "关闭后不显示点击特效", toggle: clickEffectsSwitch),
            makePopupRow(title: "点击样式", popup: clickStylePopup),
            makeSliderRow(title: "点击效果半径", slider: clickRadiusSlider, valueLabel: clickRadiusValueLabel),
            clickDurationRow,
        ]

        for button in MouseButtonKind.allCases {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(clickToggleChanged(_:))
            clickToggleButtons[button] = toggle
            toggleButtonToKind[ObjectIdentifier(toggle)] = button

            let colorWell = NSColorWell()
            colorWell.target = self
            colorWell.action = #selector(clickColorChanged(_:))
            clickColorWells[button] = colorWell
            colorWellToKind[ObjectIdentifier(colorWell)] = button

            let title = NSTextField(labelWithString: "\(button.title) 点击效果")
            title.font = .systemFont(ofSize: 13, weight: .medium)

            let row = NSStackView(views: [title, NSView(), toggle, colorWell])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 8
            rows.append(row)
        }

        return makeSectionCard(
            title: "点击",
            subtitle: "点击特效开关、半径与各键位配色",
            rows: rows
        )
    }

    private func buildMagnifierSection() -> NSView {
        inputMonitoringStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        accessibilityStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        screenCaptureStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        magnifierShortcutHint.textColor = .secondaryLabelColor
        magnifierShortcutHint.font = .systemFont(ofSize: 12)

        return makeSectionCard(
            title: "放大镜",
            subtitle: "快捷键放大、视觉参数与权限入口",
            rows: [
                makeSwitchRow(title: "开启放大镜", subtitle: "关闭后快捷键不再触发放大镜", toggle: magnifierEnabledSwitch),
                makeSwitchRow(title: "放大时显示轨迹与特效", subtitle: "关闭后放大时只显示放大内容", toggle: magnifierShowEffectsSwitch),
                makeSliderRow(title: "放大镜半径", slider: magnifierRadiusSlider, valueLabel: magnifierRadiusValueLabel),
                makeSliderRow(title: "放大倍率", slider: magnifierZoomSlider, valueLabel: magnifierZoomValueLabel),
                makeSliderRow(title: "边框粗细", slider: magnifierBorderWidthSlider, valueLabel: magnifierBorderWidthValueLabel),
                makeColorRow(title: "边框颜色", control: magnifierBorderColorWell),
                makeSliderRow(title: "阴影强度", slider: magnifierShadowSlider, valueLabel: magnifierShadowValueLabel),
                makeShortcutRecordRow(),
                makeStatusActionRow(statusLabel: inputMonitoringStatusLabel, actionButton: openInputMonitoringSettingsButton),
                makeStatusActionRow(statusLabel: accessibilityStatusLabel, actionButton: openAccessibilitySettingsButton),
                makeStatusActionRow(statusLabel: screenCaptureStatusLabel, actionButton: openScreenCaptureSettingsButton),
            ]
        )
    }

    private func makeTrailPresetHeaderControl() -> NSView {
        let label = NSTextField(labelWithString: "风格预设")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)

        trailPresetPopup.translatesAutoresizingMaskIntoConstraints = false
        trailPresetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 148).isActive = true

        let stack = NSStackView(views: [label, trailPresetPopup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    /// 构建统一的“分组卡片”容器。
    /// - Parameters:
    ///   - title: 分组标题。
    ///   - subtitle: 分组说明文案。
    ///   - headerTrailing: 标题行右侧附加控件（可选）。
    ///   - rows: 分组内行控件。
    private func makeSectionCard(title: String, subtitle: String, headerTrailing: NSView? = nil, rows: [NSView]) -> NSStackView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.distribution = .fill
        section.spacing = 8

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.distribution = .fill
        container.detachesHiddenViews = true
        container.spacing = 0
        container.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 0
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1.0).cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        let headerTextStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 6
        headerTextStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .top
        header.distribution = .fill
        header.spacing = 8
        header.addArrangedSubview(headerTextStack)
        header.addArrangedSubview(NSView())
        if let headerTrailing {
            header.addArrangedSubview(headerTrailing)
            headerTrailing.setContentHuggingPriority(.required, for: .horizontal)
            headerTrailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        section.addArrangedSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        header.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        for (index, rowView) in rows.enumerated() {
            let rowWrapper = NSStackView()
            rowWrapper.orientation = .vertical
            rowWrapper.alignment = .leading
            rowWrapper.distribution = .fill
            rowWrapper.spacing = 10
            rowWrapper.edgeInsets = NSEdgeInsets(top: index == 0 ? 0 : 10, left: 0, bottom: 0, right: 0)
            rowWrapper.addArrangedSubview(rowView)
            rowView.translatesAutoresizingMaskIntoConstraints = false
            rowView.leadingAnchor.constraint(equalTo: rowWrapper.leadingAnchor).isActive = true
            rowView.trailingAnchor.constraint(equalTo: rowWrapper.trailingAnchor).isActive = true
            if index < rows.count - 1 {
                let separator = makeRowSeparator()
                rowWrapper.addArrangedSubview(separator)
                separator.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    separator.leadingAnchor.constraint(equalTo: rowWrapper.leadingAnchor),
                    separator.trailingAnchor.constraint(equalTo: rowWrapper.trailingAnchor),
                ])
            }
            rowWrapperByRowIdentifier[ObjectIdentifier(rowView)] = rowWrapper
            container.addArrangedSubview(rowWrapper)
            constrainCardRow(rowWrapper, in: container)
        }

        section.addArrangedSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func makeSwitchRow(title: String, subtitle: String, toggle: NSSwitch) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.spacing = 3
        let row = NSStackView(views: [textStack, NSView(), toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makeSwitchRow(title: String, subtitleLabel: NSTextField, toggle: NSSwitch) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.spacing = 3
        let row = NSStackView(views: [textStack, NSView(), toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makeShortcutRecordRow() -> NSView {
        let row = makeButtonRow(title: "放大镜快捷键", button: magnifierShortcutButton)
        let stack = NSStackView(views: [row, magnifierShortcutHint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private func makeStatusActionRow(statusLabel: NSTextField, actionButton: NSButton) -> NSView {
        let row = NSStackView(views: [statusLabel, NSView(), actionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makeRainbowColorsRow() -> NSView {
        let label = NSTextField(labelWithString: "彩虹颜色")
        label.setContentHuggingPriority(.required, for: .horizontal)
        let wellsStack = NSStackView(views: rainbowColorWells)
        wellsStack.orientation = .horizontal
        wellsStack.alignment = .centerY
        wellsStack.spacing = 6
        let row = NSStackView(views: [label, NSView(), wellsStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makeNeonColorsRow() -> NSView {
        let label = NSTextField(labelWithString: "霓虹颜色")
        label.setContentHuggingPriority(.required, for: .horizontal)
        let first = labeledColorWell("主色", colorWell: neonPrimaryColorWell)
        let second = labeledColorWell("辅色", colorWell: neonSecondaryColorWell)
        let colors = NSStackView(views: [first, second])
        colors.orientation = .horizontal
        colors.alignment = .centerY
        colors.spacing = 8
        let row = NSStackView(views: [label, NSView(), colors])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func labeledColorWell(_ title: String, colorWell: NSColorWell) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, colorWell])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        return stack
    }

    private func makeColorRow(title: String, control: NSColorWell) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makePopupRow(title: String, popup: NSPopUpButton) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popup.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, NSView(), popup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makeButtonRow(title: String, button: NSButton) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, NSView(), button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makeSliderRow(title: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 92).isActive = true
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [titleLabel, NSView(), valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 6

        let stack = NSStackView(views: [row, slider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private func constrainCardRow(_ row: NSView, in container: NSStackView) {
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: container.edgeInsets.left),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -container.edgeInsets.right),
        ])
    }

    private func setRowVisibility(_ row: NSView, isVisible: Bool) {
        rowWrapperByRowIdentifier[ObjectIdentifier(row)]?.isHidden = !isVisible
    }

    private func makeRowSeparator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.04).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    /// 将 `settings` 同步到所有 UI 控件。
    /// Important: 通过 `isSyncingControls` 避免同步过程触发二次回写。
    private func syncControlsFromSettings() {
        isSyncingControls = true

        launchAtLoginSwitch.state = settings.isLaunchAtLoginEnabled ? .on : .off
        loggingSwitch.state = settings.isLoggingEnabled ? .on : .off
        statusItemSwitch.state = settings.isStatusItemVisible ? .on : .off
        trackingSwitch.state = settings.isTrackingEnabled ? .on : .off
        speedBurstSwitch.state = settings.speedBurstEnabled ? .on : .off
        clickEffectsSwitch.state = settings.isClickEffectsEnabled ? .on : .off
        magnifierEnabledSwitch.state = settings.isMagnifierEnabled ? .on : .off
        magnifierShowEffectsSwitch.state = settings.showTrailEffectsWhileMagnifierActive ? .on : .off

        trailColorWell.color = settings.trailColor
        trailEffectColorWell.color = settings.trailEffectColor
        speedBurstLineColorWell.color = settings.speedBurstLineColor
        speedBurstAccentColorWell.color = settings.speedBurstAccentColor
        neonPrimaryColorWell.color = settings.neonPrimaryColor
        neonSecondaryColorWell.color = settings.neonSecondaryColor
        magnifierBorderColorWell.color = settings.magnifierBorderColor
        for index in rainbowColorWells.indices {
            let color = settings.rainbowTrailColors.indices.contains(index)
                ? settings.rainbowTrailColors[index]
                : settings.rainbowTrailColors.last ?? .systemBlue
            rainbowColorWells[index].color = color
        }

        trailWidthSlider.doubleValue = settings.trailWidth
        trailLengthSlider.doubleValue = settings.trailLengthMilliseconds
        speedBurstVelocitySlider.doubleValue = settings.speedBurstVelocityThreshold
        speedBurstCooldownSlider.doubleValue = settings.speedBurstCooldownMilliseconds
        speedBurstDurationSlider.doubleValue = settings.speedBurstDurationMilliseconds
        speedBurstJitterSlider.doubleValue = settings.speedBurstJitterAmplitude
        speedBurstMinLengthSlider.doubleValue = settings.speedBurstMinLength
        speedBurstMaxLengthSlider.doubleValue = settings.speedBurstMaxLength
        speedBurstWidthMultiplierSlider.doubleValue = settings.speedBurstWidthMultiplier
        speedBurstAccentDurationSlider.doubleValue = settings.speedBurstAccentDurationMilliseconds
        speedBurstAccentSizeSlider.doubleValue = settings.speedBurstAccentSize
        clickRadiusSlider.doubleValue = settings.clickEffectRadius
        clickDurationSlider.doubleValue = settings.clickEffectDurationMilliseconds
        magnifierRadiusSlider.doubleValue = settings.magnifierRadius
        magnifierZoomSlider.doubleValue = settings.magnifierZoom
        magnifierBorderWidthSlider.doubleValue = settings.magnifierBorderWidth
        magnifierShadowSlider.doubleValue = settings.magnifierShadowOpacity

        updateSliderValueLabels()

        if let index = EffectIntensityPreset.allCases.firstIndex(of: settings.intensityPreset) {
            intensityPopup.selectItem(at: index)
        }
        if let index = TrailRenderStyle.allCases.firstIndex(of: settings.trailStyle) {
            trailStylePopup.selectItem(at: index)
        }
        if let index = TrailEffectStyle.allCases.firstIndex(of: settings.trailEffectStyle) {
            trailEffectPopup.selectItem(at: index)
        }
        if let index = SpeedBurstEffectType.allCases.firstIndex(of: settings.speedBurstType) {
            speedBurstTypePopup.selectItem(at: index)
        }
        if let index = ClickVisualStyle.allCases.firstIndex(of: settings.clickVisualStyle) {
            clickStylePopup.selectItem(at: index)
        }

        magnifierShortcutButton.title = isShortcutRecording
            ? "按下键盘/鼠标快捷键…(Esc取消)"
            : settings.magnifierShortcut.displayText

        for button in MouseButtonKind.allCases {
            let style = settings.effectStyle(for: button)
            clickToggleButtons[button]?.state = style.isEnabled ? .on : .off
            clickColorWells[button]?.color = style.color
            clickColorWells[button]?.isEnabled = settings.isClickEffectsEnabled && style.isEnabled
        }

        updateToggleAvailability()
        refreshLaunchAtLoginHint()
        isSyncingControls = false
        refreshPermissionIndicators()
    }

    private func refreshLaunchAtLoginHint() {
        guard #available(macOS 13.0, *) else {
            launchAtLoginStatusLabel.stringValue = "当前系统版本不支持应用内开机启动控制。"
            launchAtLoginStatusLabel.textColor = .systemRed
            return
        }
        if settings.isLaunchAtLoginEnabled {
            launchAtLoginStatusLabel.stringValue = "已请求开机启动；若未生效，请将 App 放到“应用程序”目录。"
            launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        } else {
            launchAtLoginStatusLabel.stringValue = "开机启动已关闭。"
            launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        }
    }

    private func updateToggleAvailability() {
        let clickEnabled = settings.isClickEffectsEnabled
        clickRadiusSlider.isEnabled = clickEnabled
        clickDurationSlider.isEnabled = clickEnabled
        clickStylePopup.isEnabled = clickEnabled
        for button in MouseButtonKind.allCases {
            let buttonEnabled = settings.effectStyle(for: button).isEnabled
            clickToggleButtons[button]?.isEnabled = clickEnabled
            clickColorWells[button]?.isEnabled = clickEnabled && buttonEnabled
        }

        let rainbowEnabled = settings.trailStyle == .rainbow
        rainbowColorWells.forEach { $0.isEnabled = rainbowEnabled }
        setRowVisibility(trailColorRow, isVisible: settings.trailStyle != .rainbow && settings.trailStyle != .neon)
        setRowVisibility(rainbowColorsRow, isVisible: settings.trailStyle == .rainbow)
        setRowVisibility(neonColorsRow, isVisible: settings.trailStyle == .neon)

        let speedBurstEnabled = settings.speedBurstEnabled
        speedBurstTypePopup.isEnabled = speedBurstEnabled
        speedBurstVelocitySlider.isEnabled = speedBurstEnabled
        speedBurstCooldownSlider.isEnabled = speedBurstEnabled
        speedBurstDurationSlider.isEnabled = speedBurstEnabled
        speedBurstJitterSlider.isEnabled = speedBurstEnabled
        speedBurstMinLengthSlider.isEnabled = speedBurstEnabled
        speedBurstMaxLengthSlider.isEnabled = speedBurstEnabled
        speedBurstWidthMultiplierSlider.isEnabled = speedBurstEnabled
        speedBurstAccentDurationSlider.isEnabled = speedBurstEnabled
        speedBurstAccentSizeSlider.isEnabled = speedBurstEnabled
        speedBurstLineColorWell.isEnabled = speedBurstEnabled
        speedBurstAccentColorWell.isEnabled = speedBurstEnabled
        setRowVisibility(speedBurstTypeRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstLineColorRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstAccentColorRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstVelocityRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstCooldownRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstDurationRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstAccentDurationRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstAccentSizeRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstJitterRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstMinLengthRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstMaxLengthRow, isVisible: speedBurstEnabled)
        setRowVisibility(speedBurstWidthMultiplierRow, isVisible: speedBurstEnabled)

        let magnifierEnabled = settings.isMagnifierEnabled
        magnifierShowEffectsSwitch.isEnabled = magnifierEnabled
        magnifierRadiusSlider.isEnabled = magnifierEnabled
        magnifierZoomSlider.isEnabled = magnifierEnabled
        magnifierBorderWidthSlider.isEnabled = magnifierEnabled
        magnifierBorderColorWell.isEnabled = magnifierEnabled
        magnifierShadowSlider.isEnabled = magnifierEnabled
        magnifierShortcutButton.isEnabled = magnifierEnabled
        magnifierShortcutHint.textColor = magnifierEnabled ? .secondaryLabelColor : .tertiaryLabelColor
    }

    private func updateSliderValueLabels() {
        trailWidthValueLabel.stringValue = "\(rounded(Double(settings.trailWidth))) px"
        trailLengthValueLabel.stringValue = "\(Int(settings.trailLengthMilliseconds)) ms"
        speedBurstVelocityValueLabel.stringValue = "\(Int(settings.speedBurstVelocityThreshold)) px/s"
        speedBurstCooldownValueLabel.stringValue = "\(Int(settings.speedBurstCooldownMilliseconds)) ms"
        speedBurstDurationValueLabel.stringValue = "\(Int(settings.speedBurstDurationMilliseconds)) ms"
        speedBurstJitterValueLabel.stringValue = "\(rounded(Double(settings.speedBurstJitterAmplitude)))"
        speedBurstMinLengthValueLabel.stringValue = "\(Int(settings.speedBurstMinLength)) px"
        speedBurstMaxLengthValueLabel.stringValue = "\(Int(settings.speedBurstMaxLength)) px"
        speedBurstWidthMultiplierValueLabel.stringValue = "\(rounded(Double(settings.speedBurstWidthMultiplier))) x"
        speedBurstAccentDurationValueLabel.stringValue = "\(Int(settings.speedBurstAccentDurationMilliseconds)) ms"
        speedBurstAccentSizeValueLabel.stringValue = "\(Int(settings.speedBurstAccentSize)) px"
        clickRadiusValueLabel.stringValue = "\(Int(settings.clickEffectRadius)) px"
        clickDurationValueLabel.stringValue = "\(Int(settings.clickEffectDurationMilliseconds)) ms"
        magnifierRadiusValueLabel.stringValue = "\(Int(settings.magnifierRadius)) px"
        magnifierZoomValueLabel.stringValue = "\(rounded(Double(settings.magnifierZoom))) x"
        magnifierBorderWidthValueLabel.stringValue = "\(rounded(Double(settings.magnifierBorderWidth))) px"
        magnifierShadowValueLabel.stringValue = "\(rounded(Double(settings.magnifierShadowOpacity)))"
    }

    private func publishChanges() {
        guard !isSyncingControls else { return }
        onSettingsChanged?(settings)
    }

    @objc
    private func launchAtLoginSwitchChanged(_ sender: NSSwitch) {
        settings.isLaunchAtLoginEnabled = sender.state == .on
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func loggingSwitchChanged(_ sender: NSSwitch) {
        settings.isLoggingEnabled = sender.state == .on
        publishChanges()
    }

    @objc
    private func statusItemSwitchChanged(_ sender: NSSwitch) {
        settings.isStatusItemVisible = sender.state == .on
        publishChanges()
    }

    @objc
    private func trackingSwitchChanged(_ sender: NSSwitch) {
        settings.isTrackingEnabled = sender.state == .on
        publishChanges()
    }

    @objc
    private func speedBurstSwitchChanged(_ sender: NSSwitch) {
        settings.speedBurstEnabled = sender.state == .on
        syncControlsFromSettings()
        if let scrollView = contentScrollView, activeSidebarTab == .trailEffects {
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.scrollContentToTop(scrollView)
            }
        }
        publishChanges()
    }

    @objc
    private func clickEffectsSwitchChanged(_ sender: NSSwitch) {
        settings.isClickEffectsEnabled = sender.state == .on
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func magnifierEnabledSwitchChanged(_ sender: NSSwitch) {
        settings.isMagnifierEnabled = sender.state == .on
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func trailColorChanged(_ sender: NSColorWell) {
        settings.trailColor = sender.color
        publishChanges()
    }

    @objc
    private func trailEffectColorChanged(_ sender: NSColorWell) {
        settings.trailEffectColor = sender.color
        publishChanges()
    }

    @objc
    private func speedBurstLineColorChanged(_ sender: NSColorWell) {
        settings.speedBurstLineColor = sender.color
        publishChanges()
    }

    @objc
    private func speedBurstAccentColorChanged(_ sender: NSColorWell) {
        settings.speedBurstAccentColor = sender.color
        publishChanges()
    }

    @objc
    private func neonPrimaryColorChanged(_ sender: NSColorWell) {
        settings.neonPrimaryColor = sender.color
        publishChanges()
    }

    @objc
    private func neonSecondaryColorChanged(_ sender: NSColorWell) {
        settings.neonSecondaryColor = sender.color
        publishChanges()
    }

    @objc
    private func trailStyleChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard TrailRenderStyle.allCases.indices.contains(index) else { return }
        settings.trailStyle = TrailRenderStyle.allCases[index]
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func trailEffectStyleChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard TrailEffectStyle.allCases.indices.contains(index) else { return }
        settings.trailEffectStyle = TrailEffectStyle.allCases[index]
        publishChanges()
    }

    @objc
    private func speedBurstTypeChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard SpeedBurstEffectType.allCases.indices.contains(index) else { return }
        settings.speedBurstType = SpeedBurstEffectType.allCases[index]
        publishChanges()
    }

    @objc
    private func clickVisualStyleChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard ClickVisualStyle.allCases.indices.contains(index) else { return }
        settings.clickVisualStyle = ClickVisualStyle.allCases[index]
        publishChanges()
    }

    @objc
    private func rainbowColorChanged(_ sender: NSColorWell) {
        settings.rainbowTrailColors = rainbowColorWells.map(\.color)
        publishChanges()
    }

    @objc
    private func trailWidthSliderChanged(_ sender: NSSlider) {
        settings.trailWidth = clampTrailWidth(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func trailLengthSliderChanged(_ sender: NSSlider) {
        settings.trailLengthMilliseconds = clampTrailLengthMilliseconds(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstVelocitySliderChanged(_ sender: NSSlider) {
        settings.speedBurstVelocityThreshold = clampSpeedBurstVelocityThreshold(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstCooldownSliderChanged(_ sender: NSSlider) {
        settings.speedBurstCooldownMilliseconds = clampSpeedBurstCooldownMilliseconds(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstDurationSliderChanged(_ sender: NSSlider) {
        settings.speedBurstDurationMilliseconds = clampSpeedBurstDurationMilliseconds(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstJitterSliderChanged(_ sender: NSSlider) {
        settings.speedBurstJitterAmplitude = clampSpeedBurstJitterAmplitude(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstMinLengthSliderChanged(_ sender: NSSlider) {
        settings.speedBurstMinLength = clampSpeedBurstMinLength(sender.doubleValue)
        if settings.speedBurstMaxLength < settings.speedBurstMinLength {
            settings.speedBurstMaxLength = settings.speedBurstMinLength
        }
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstMaxLengthSliderChanged(_ sender: NSSlider) {
        settings.speedBurstMaxLength = clampSpeedBurstMaxLength(sender.doubleValue)
        if settings.speedBurstMaxLength < settings.speedBurstMinLength {
            settings.speedBurstMinLength = settings.speedBurstMaxLength
        }
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstWidthMultiplierSliderChanged(_ sender: NSSlider) {
        settings.speedBurstWidthMultiplier = clampSpeedBurstWidthMultiplier(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstAccentDurationSliderChanged(_ sender: NSSlider) {
        settings.speedBurstAccentDurationMilliseconds = clampSpeedBurstAccentDurationMilliseconds(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstAccentSizeSliderChanged(_ sender: NSSlider) {
        settings.speedBurstAccentSize = clampSpeedBurstAccentSize(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func clickRadiusSliderChanged(_ sender: NSSlider) {
        settings.clickEffectRadius = clampClickEffectRadius(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func clickDurationSliderChanged(_ sender: NSSlider) {
        settings.clickEffectDurationMilliseconds = clampClickEffectDurationMilliseconds(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func magnifierRadiusSliderChanged(_ sender: NSSlider) {
        settings.magnifierRadius = clampMagnifierRadius(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func magnifierZoomSliderChanged(_ sender: NSSlider) {
        settings.magnifierZoom = clampMagnifierZoom(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func magnifierBorderWidthSliderChanged(_ sender: NSSlider) {
        settings.magnifierBorderWidth = clampMagnifierBorderWidth(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func magnifierShadowSliderChanged(_ sender: NSSlider) {
        settings.magnifierShadowOpacity = clampMagnifierShadowOpacity(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func magnifierShowEffectsSwitchChanged(_ sender: NSSwitch) {
        settings.showTrailEffectsWhileMagnifierActive = sender.state == .on
        publishChanges()
    }

    @objc
    private func intensityChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard EffectIntensityPreset.allCases.indices.contains(index) else { return }
        settings.intensityPreset = EffectIntensityPreset.allCases[index]
        publishChanges()
    }

    @objc
    private func trailPresetChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard TrailPresetOption.allCases.indices.contains(index) else { return }
        let option = TrailPresetOption.allCases[index]
        switch option {
        case .custom:
            break
        case .thunderFirstForm:
            settings.applyThunderFirstFormPreset()
            syncControlsFromSettings()
            publishChanges()
            AppLogger.shared.log("thunder preset applied from settings popup")
        }
    }

    @objc
    private func clickToggleChanged(_ sender: NSSwitch) {
        guard let button = toggleButtonToKind[ObjectIdentifier(sender)] else { return }
        var style = settings.effectStyle(for: button)
        style.isEnabled = sender.state == .on
        settings.clickEffects[button] = style
        clickColorWells[button]?.isEnabled = settings.isClickEffectsEnabled && style.isEnabled
        publishChanges()
    }

    @objc
    private func clickColorChanged(_ sender: NSColorWell) {
        guard let button = colorWellToKind[ObjectIdentifier(sender)] else { return }
        var style = settings.effectStyle(for: button)
        style.color = sender.color
        settings.clickEffects[button] = style
        publishChanges()
    }

    @objc
    private func magnifierBorderColorChanged(_ sender: NSColorWell) {
        settings.magnifierBorderColor = sender.color
        publishChanges()
    }

    @objc
    private func toggleShortcutRecording(_ sender: NSButton) {
        if isShortcutRecording {
            stopShortcutRecording()
        } else {
            startShortcutRecording()
        }
    }

    private func startShortcutRecording() {
        guard !isShortcutRecording else { return }
        isShortcutRecording = true
        syncControlsFromSettings()

        shortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
                self.stopShortcutRecording()
                return nil
            }

            guard let shortcut = MagnifierShortcut.capture(from: event) else { return nil }
            self.settings.magnifierShortcut = shortcut
            self.publishChanges()
            self.stopShortcutRecording()
            return nil
        }
    }

    private func stopShortcutRecording() {
        if let shortcutCaptureMonitor {
            NSEvent.removeMonitor(shortcutCaptureMonitor)
            self.shortcutCaptureMonitor = nil
        }
        isShortcutRecording = false
        syncControlsFromSettings()
    }

    private func refreshPermissionIndicators() {
        let listenGranted = CGPreflightListenEventAccess()
        inputMonitoringStatusLabel.stringValue = listenGranted
            ? "输入监控权限：已授权 ✅"
            : "输入监控权限：未授权 ❌（全局快捷键可能无效）"
        inputMonitoringStatusLabel.textColor = listenGranted ? .systemGreen : .systemRed

        let accessibilityTrusted = AXIsProcessTrusted()
        accessibilityStatusLabel.stringValue = accessibilityTrusted
            ? "辅助功能权限：已授权 ✅"
            : "辅助功能权限：未授权 ❌（放大镜滚轮拦截会无效）"
        accessibilityStatusLabel.textColor = accessibilityTrusted ? .systemGreen : .systemRed

        let screenGranted = CGPreflightScreenCaptureAccess()
        screenCaptureStatusLabel.stringValue = screenGranted
            ? "屏幕录制权限：已授权 ✅"
            : "屏幕录制权限：未授权 ❌（放大镜可能无法取屏）"
        screenCaptureStatusLabel.textColor = screenGranted ? .systemGreen : .systemRed
    }

    @objc
    private func openInputMonitoringSettings(_ sender: NSButton) {
        let before = CGPreflightListenEventAccess()
        if !before {
            let requested = CGRequestListenEventAccess()
            AppLogger.shared.log("input monitoring permission requested, result=\(requested)")
        }
        onRequestInputMonitoringPermission?()
        refreshPermissionIndicators()
        openSystemSettings(urlStrings: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security",
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshPermissionIndicators()
        }
    }


    @objc
    private func openAccessibilitySettings(_ sender: NSButton) {
        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            let trustedAfterPrompt = AXIsProcessTrustedWithOptions(options)
            AppLogger.shared.log("accessibility permission requested from settings button, trustedAfterPrompt=\(trustedAfterPrompt)")
        }
        refreshPermissionIndicators()
        openSystemSettings(urlStrings: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security",
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshPermissionIndicators()
        }
    }

    @objc
    private func openScreenCaptureSettings(_ sender: NSButton) {
        let before = CGPreflightScreenCaptureAccess()
        if !before {
            let requested = CGRequestScreenCaptureAccess()
            AppLogger.shared.log("screen capture permission requested, result=\(requested)")
        }
        refreshPermissionIndicators()
        openSystemSettings(urlStrings: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security",
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshPermissionIndicators()
        }
    }

    @objc
    private func openLogFolder(_ sender: NSButton) {
        let url = URL(fileURLWithPath: AppLogger.shared.logPath()).deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }

    private func openSystemSettings(urlStrings: [String]) {
        for item in urlStrings {
            guard let url = URL(string: item) else { continue }
            if NSWorkspace.shared.open(url) { break }
        }
    }

    func windowWillClose(_ notification: Notification) {
        stopShortcutRecording()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshPermissionIndicators()
    }

}

@MainActor
/// 应用主委托。
/// 职责：串联监听器、覆盖层、设置窗口与状态栏菜单。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayManager = OverlayWindowManager()
    private let mouseMonitor = MouseMonitor()
    private let hotKeyManager = HotKeyManager()
    private let globalShortcutMonitor = GlobalShortcutMonitor()
    private let globalScrollInterceptor = GlobalScrollInterceptor()
    private let settingsStore = SettingsStore()
    private let launchAtLoginManager = LaunchAtLoginManager()

    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var settingsWindowController: SettingsWindowController?
    private var settings: AppSettings = .default
    private var isMagnifierShortcutHeld = false
    private var isGlobalShortcutMonitorActive = false
    private var lastAppliedLaunchAtLoginState: Bool?
    private var lastLoggedScrollConsumeState: Bool?
    private var hasPromptedAccessibilityForScrollInterception = false

    /// 应用启动入口：加载配置、启动监听器并应用初始状态。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings = settingsStore.loadSettings()
        seedThunderPresetIfNeeded()
        AppLogger.shared.setEnabled(settings.isLoggingEnabled)
        AppLogger.shared.log("application did finish launching")
        let launchEnabled = launchAtLoginManager.isEnabled()
        if launchEnabled != settings.isLaunchAtLoginEnabled {
            settings.isLaunchAtLoginEnabled = launchEnabled
            settingsStore.saveSettings(settings)
            AppLogger.shared.log("launch at login state synchronized to \(launchEnabled)")
        }
        if settings.isStatusItemVisible {
            setupStatusItem()
        }

        mouseMonitor.onEvent = { [weak self] signal in
            self?.overlayManager.process(signal: signal)
        }
        mouseMonitor.onRawEvent = { [weak self] event in
            self?.handleRawEvent(event)
        }
        mouseMonitor.start()

        globalScrollInterceptor.onScroll = { [weak self] signal in
            DispatchQueue.main.async { [weak self] in
                self?.overlayManager.process(signal: signal)
            }
        }
        AppLogger.shared.log("global scroll interceptor configured (lazy start)")

        globalShortcutMonitor.onInput = { [weak self] input in
            self?.handleShortcutInput(input)
        }
        isGlobalShortcutMonitorActive = globalShortcutMonitor.start()

        hotKeyManager.onToggle = { [weak self] in
            self?.toggleTracking()
        }
        _ = hotKeyManager.registerHotKey()

        applySettings(persist: false, syncWindow: false)
        DispatchQueue.main.async { [weak self] in
            self?.openSettingsWindow()
        }
    }

    private func seedThunderPresetIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppSettings.thunderPresetSeededKey) == false else { return }
        settings.saveAsThunderFirstFormPreset()
        AppLogger.shared.log("thunder preset snapshot saved from current settings")
    }

    /// 应用退出前释放监听资源。
    func applicationWillTerminate(_ notification: Notification) {
        mouseMonitor.stop()
        hotKeyManager.unregisterHotKey()
        globalShortcutMonitor.stop()
        globalScrollInterceptor.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 启动或激活时不再自动弹设置窗口；仅由用户显式打开。
    }

    /// Dock 重新激活时的窗口恢复策略。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettingsWindow()
        }
        return true
    }

    /// 保持应用常驻，不因关闭最后窗口退出。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.title = ""
            button.image = makeStatusBarTemplateIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "Cursor Trail"
            button.setAccessibilityLabel("CursorTrailBar")
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: settings.isTrackingEnabled ? "关闭轨迹显示" : "开启轨迹显示",
            action: #selector(toggleTracking),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        toggleMenuItem = toggleItem

        let settingsItem = NSMenuItem(title: "打开设置…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let clearItem = NSMenuItem(title: "清空当前轨迹", action: #selector(clearTrail), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        let hotkeyHintItem = NSMenuItem(
            title: "快捷键开关：\(hotKeyManager.displayLabel)",
            action: nil,
            keyEquivalent: ""
        )
        hotkeyHintItem.isEnabled = false
        menu.addItem(hotkeyHintItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    private func makeStatusBarTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let trail = NSBezierPath()
            trail.move(to: NSPoint(x: 1.8, y: 6.2))
            trail.curve(
                to: NSPoint(x: 10.0, y: 8.2),
                controlPoint1: NSPoint(x: 3.8, y: 4.2),
                controlPoint2: NSPoint(x: 7.2, y: 7.5)
            )
            trail.lineWidth = 1.8
            trail.lineCapStyle = .round
            trail.lineJoinStyle = .round
            NSColor.labelColor.setStroke()
            trail.stroke()

            let pointer = NSBezierPath()
            pointer.move(to: NSPoint(x: 7.3, y: 2.7))
            pointer.line(to: NSPoint(x: 14.8, y: 8.5))
            pointer.line(to: NSPoint(x: 11.1, y: 9.2))
            pointer.line(to: NSPoint(x: 12.8, y: 14.7))
            pointer.line(to: NSPoint(x: 10.7, y: 15.5))
            pointer.line(to: NSPoint(x: 9.0, y: 10.2))
            pointer.line(to: NSPoint(x: 6.8, y: 11.8))
            pointer.close()
            NSColor.labelColor.setFill()
            pointer.fill()

            return true
        }
        image.isTemplate = true
        image.size = size
        return image
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        toggleMenuItem = nil
    }

    private func syncStatusItemVisibility() {
        if settings.isStatusItemVisible {
            setupStatusItem()
            statusItem?.button?.image = makeStatusBarTemplateIcon()
        } else {
            removeStatusItem()
        }
    }

    @objc
    private func toggleTracking() {
        settings.isTrackingEnabled.toggle()
        applySettings(persist: true)
    }

    @objc
    private func openSettingsWindow() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(initialSettings: settings)
            controller.onSettingsChanged = { [weak self] newSettings in
                self?.settings = newSettings
                self?.applySettings(persist: true, syncWindow: false)
            }
            controller.onRequestInputMonitoringPermission = { [weak self] in
                self?.requestInputMonitoringPermissionAndRegister()
            }
            settingsWindowController = controller
        }
        settingsWindowController?.updateSettings(settings)
        settingsWindowController?.present()
    }

    /// 请求输入监控权限后，重启全局快捷键监听器以尽快生效。
    private func requestInputMonitoringPermissionAndRegister() {
        NSApp.activate(ignoringOtherApps: true)
        probeInputMonitoringEventTap()
        probeInputMonitoringEventTap()

        globalShortcutMonitor.stop()
        isGlobalShortcutMonitorActive = globalShortcutMonitor.start()
        let after = CGPreflightListenEventAccess()
        AppLogger.shared.log("global shortcut monitor restarted after permission request: \(isGlobalShortcutMonitorActive), listenGranted=\(after)")
    }

    private func probeInputMonitoringEventTap() {
        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(eventMask),
                callback: callback,
                userInfo: nil
            )
        else {
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
    }

    @objc
    private func clearTrail() {
        overlayManager.clear()
    }

    /// 将当前设置应用到运行时模块。
    /// - Parameters:
    ///   - persist: 是否持久化到本地存储。
    ///   - syncWindow: 是否反向同步设置窗口控件显示。
    private func applySettings(persist: Bool, syncWindow: Bool = true) {
        AppLogger.shared.setEnabled(settings.isLoggingEnabled)
        settings.trailWidth = clampTrailWidth(Double(settings.trailWidth))
        settings.trailLengthMilliseconds = clampTrailLengthMilliseconds(settings.trailLengthMilliseconds)
        settings.clickEffectRadius = clampClickEffectRadius(Double(settings.clickEffectRadius))
        settings.clickEffectDurationMilliseconds = clampClickEffectDurationMilliseconds(settings.clickEffectDurationMilliseconds)
        settings.magnifierRadius = clampMagnifierRadius(Double(settings.magnifierRadius))
        settings.magnifierZoom = clampMagnifierZoom(Double(settings.magnifierZoom))
        settings.magnifierBorderWidth = clampMagnifierBorderWidth(Double(settings.magnifierBorderWidth))
        settings.magnifierShadowOpacity = clampMagnifierShadowOpacity(Double(settings.magnifierShadowOpacity))
        settings.speedBurstVelocityThreshold = clampSpeedBurstVelocityThreshold(Double(settings.speedBurstVelocityThreshold))
        settings.speedBurstCooldownMilliseconds = clampSpeedBurstCooldownMilliseconds(settings.speedBurstCooldownMilliseconds)
        settings.speedBurstDurationMilliseconds = clampSpeedBurstDurationMilliseconds(settings.speedBurstDurationMilliseconds)
        settings.speedBurstAfterglowMilliseconds = 0
        settings.speedBurstJitterAmplitude = clampSpeedBurstJitterAmplitude(Double(settings.speedBurstJitterAmplitude))
        settings.speedBurstMinLength = clampSpeedBurstMinLength(Double(settings.speedBurstMinLength))
        settings.speedBurstMaxLength = clampSpeedBurstMaxLength(Double(settings.speedBurstMaxLength))
        if settings.speedBurstMaxLength < settings.speedBurstMinLength {
            let temp = settings.speedBurstMaxLength
            settings.speedBurstMaxLength = settings.speedBurstMinLength
            settings.speedBurstMinLength = temp
        }
        settings.speedBurstWidthMultiplier = clampSpeedBurstWidthMultiplier(Double(settings.speedBurstWidthMultiplier))
        settings.speedBurstAccentDurationMilliseconds = clampSpeedBurstAccentDurationMilliseconds(settings.speedBurstAccentDurationMilliseconds)
        settings.speedBurstAccentSize = clampSpeedBurstAccentSize(Double(settings.speedBurstAccentSize))
        if settings.rainbowTrailColors.count < 2 {
            settings.rainbowTrailColors = AppSettings.default.rainbowTrailColors
        }
        syncLaunchAtLoginIfNeeded()
        syncStatusItemVisibility()
        overlayManager.setSettings(settings)
        overlayManager.setTrackingEnabled(settings.isTrackingEnabled)
        if !settings.isMagnifierEnabled {
            isMagnifierShortcutHeld = false
            overlayManager.setMagnifierActive(false)
        }
        syncScrollInterceptionState()

        toggleMenuItem?.title = settings.isTrackingEnabled ? "关闭轨迹显示" : "开启轨迹显示"

        if persist {
            settingsStore.saveSettings(settings)
            AppLogger.shared.log("settings saved: tracking=\(settings.isTrackingEnabled), clickEffects=\(settings.isClickEffectsEnabled), magnifier=\(settings.isMagnifierEnabled), intensity=\(settings.intensityPreset.rawValue)")
        }
        if syncWindow {
            settingsWindowController?.updateSettings(settings)
        }
    }

    private func handleRawEvent(_ event: NSEvent) {
        if isGlobalShortcutMonitorActive {
            return
        }
        if settingsWindowController?.isRecordingShortcut == true {
            return
        }
        guard let input = shortcutInputEvent(from: event) else { return }
        handleShortcutInput(input)
    }

    private func handleShortcutInput(_ input: ShortcutInputEvent) {
        if settingsWindowController?.isRecordingShortcut == true {
            return
        }
        guard settings.isMagnifierEnabled else {
            if isMagnifierShortcutHeld {
                isMagnifierShortcutHeld = false
                overlayManager.setMagnifierActive(false)
            }
            syncScrollInterceptionState()
            return
        }
        let shortcut = settings.magnifierShortcut
        if shortcut.matchesPress(input: input) {
            if !isMagnifierShortcutHeld {
                isMagnifierShortcutHeld = true
                overlayManager.setMagnifierActive(true)
                AppLogger.shared.log("magnifier shortcut pressed")
                syncScrollInterceptionState()
            }
        } else if shortcut.matchesRelease(input: input) {
            if isMagnifierShortcutHeld {
                isMagnifierShortcutHeld = false
                overlayManager.setMagnifierActive(false)
                AppLogger.shared.log("magnifier shortcut released")
                syncScrollInterceptionState()
            }
        }
    }

    /// 同步滚轮拦截状态。
    /// Note: 仅在“放大镜快捷键按住且放大镜功能开启”时尝试消费滚轮事件。
    private func syncScrollInterceptionState() {
        let wantsConsume = isMagnifierShortcutHeld && settings.isMagnifierEnabled
        if wantsConsume {
            if !globalScrollInterceptor.isRunning {
                let started = globalScrollInterceptor.start()
                AppLogger.shared.log("global scroll interceptor restarted: \(started)")
                if !started {
                    requestAccessibilityPermissionForScrollInterceptionIfNeeded()
                }
            }
            let canConsume = globalScrollInterceptor.isRunning
            globalScrollInterceptor.setConsumesScroll(canConsume)
            if wantsConsume, !canConsume {
                AppLogger.shared.log("scroll interception degraded: magnifier active but interceptor unavailable; wheel may pass through")
            }
        } else {
            globalScrollInterceptor.setConsumesScroll(false)
            if globalScrollInterceptor.isRunning {
                globalScrollInterceptor.stop()
                AppLogger.shared.log("global scroll interceptor paused")
            }
        }
        let effectiveConsume = wantsConsume && globalScrollInterceptor.isRunning
        if lastLoggedScrollConsumeState != effectiveConsume {
            AppLogger.shared.log(
                "sync scroll interception: requested=\(wantsConsume), effective=\(effectiveConsume), shortcutHeld=\(isMagnifierShortcutHeld), magnifierEnabled=\(settings.isMagnifierEnabled), trackingEnabled=\(settings.isTrackingEnabled)"
            )
            lastLoggedScrollConsumeState = effectiveConsume
        }
    }

    private func requestAccessibilityPermissionForScrollInterceptionIfNeeded() {
        guard !hasPromptedAccessibilityForScrollInterception else { return }
        guard !AXIsProcessTrusted() else { return }
        hasPromptedAccessibilityForScrollInterception = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trustedAfterPrompt = AXIsProcessTrustedWithOptions(options)
        AppLogger.shared.log("scroll interception requested accessibility permission, trustedAfterPrompt=\(trustedAfterPrompt)")
    }

    private func syncLaunchAtLoginIfNeeded() {
        guard lastAppliedLaunchAtLoginState != settings.isLaunchAtLoginEnabled else { return }
        _ = launchAtLoginManager.setEnabled(settings.isLaunchAtLoginEnabled)
        lastAppliedLaunchAtLoginState = settings.isLaunchAtLoginEnabled
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

@main
/// 应用入口类型。
enum CursorTrailBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
