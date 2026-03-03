//
// SettingsModels.swift
// MVC: Model 层（输入模型、配置模型、预设定义）
//
import AppKit
import Carbon

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
func shortcutInputEvent(from event: NSEvent) -> ShortcutInputEvent? {
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

func colorFromHexRGB(_ hex: Int, alpha: CGFloat = 1.0) -> NSColor {
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
