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
            return i18n("mouse.left", "左键")
        case .right:
            return i18n("mouse.right", "右键")
        case .middle:
            return i18n("mouse.middle", "中键")
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
            return i18n("effectIntensity.off", "关闭")
        case .low:
            return i18n("effectIntensity.low", "低（省资源）")
        case .normal:
            return i18n("effectIntensity.normal", "中（默认）")
        case .high:
            return i18n("effectIntensity.high", "高（炫彩）")
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
    case waterBlade

    var title: String {
        switch self {
        case .neon: return i18n("trailStyle.neon", "双层霓虹")
        case .ribbon: return i18n("trailStyle.ribbon", "渐隐丝带")
        case .rainbow: return i18n("trailStyle.rainbow", "彩虹拖尾")
        case .lightning: return i18n("trailStyle.lightning", "闪电轨迹")
        case .waterBlade: return i18n("trailStyle.waterBlade", "水刃流带")
        }
    }
}

/// 轨迹附加特效类型。
enum TrailEffectStyle: String, CaseIterable {
    case particles
    case ink
    case electric
    case waterSplash

    var title: String {
        switch self {
        case .particles: return i18n("trailEffect.particles", "粒子火花")
        case .ink: return i18n("trailEffect.ink", "墨迹扩散")
        case .electric: return i18n("trailEffect.electric", "电弧闪点")
        case .waterSplash: return i18n("trailEffect.waterSplash", "水花飞溅")
        }
    }
}

/// 加速爆发类型。
enum SpeedBurstEffectType: String, CaseIterable {
    case firstFlash
    case waterSurge

    var title: String {
        switch self {
        case .firstFlash:
            return i18n("speedBurstType.firstFlash", "一之闪")
        case .waterSurge:
            return i18n("speedBurstType.waterSurge", "水刃激涌")
        }
    }
}

/// 水刃激涌放大策略。
enum SpeedSurgeScaleMode: String, CaseIterable {
    case randomRange
    case velocityBased

    var title: String {
        switch self {
        case .randomRange:
            return i18n("speedSurgeMode.randomRange", "随机放大")
        case .velocityBased:
            return i18n("speedSurgeMode.velocityBased", "速度映射放大")
        }
    }
}

/// 点击可视化风格。
enum ClickVisualStyle: String, CaseIterable {
    case solidPulse
    case crossFlare
    case waterImpact
    case particleExplosion

    var title: String {
        switch self {
        case .solidPulse: return i18n("clickStyle.solidPulse", "实心脉冲")
        case .crossFlare: return i18n("clickStyle.crossFlare", "十字闪光")
        case .waterImpact: return i18n("clickStyle.waterImpact", "水击扩散")
        case .particleExplosion: return i18n("clickStyle.particleExplosion", "粒子爆炸")
        }
    }
}

/// 单个按键的点击特效配置。
struct ClickEffectStyle {
    var isEnabled: Bool
    var color: NSColor
}

struct CustomTrailPreset: Codable, Equatable {
    let id: String
    var name: String
    var updatedAt: Date

    init(id: String, name: String, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

enum PresetStorageValue: Codable {
    case bool(Bool)
    case double(Double)
    case string(String)
    case data(String)
    case dataArray([String])

    private enum CodingKeys: String, CodingKey {
        case type
        case boolValue
        case doubleValue
        case stringValue
        case dataValue
        case dataArrayValue
    }

    private enum ValueType: String, Codable {
        case bool
        case double
        case string
        case data
        case dataArray
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .boolValue))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .doubleValue))
        case .string:
            self = .string(try container.decode(String.self, forKey: .stringValue))
        case .data:
            self = .data(try container.decode(String.self, forKey: .dataValue))
        case .dataArray:
            self = .dataArray(try container.decode([String].self, forKey: .dataArrayValue))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .boolValue)
        case .double(let value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .doubleValue)
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .stringValue)
        case .data(let value):
            try container.encode(ValueType.data, forKey: .type)
            try container.encode(value, forKey: .dataValue)
        case .dataArray(let value):
            try container.encode(ValueType.dataArray, forKey: .type)
            try container.encode(value, forKey: .dataArrayValue)
        }
    }

    init?(rawObject: Any) {
        if let number = rawObject as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .double(number.doubleValue)
            }
            return
        }
        if let value = rawObject as? String {
            self = .string(value)
            return
        }
        if let value = rawObject as? Data {
            self = .data(value.base64EncodedString())
            return
        }
        if let values = rawObject as? [Any] {
            let encoded = values.compactMap { item -> String? in
                guard let data = item as? Data else { return nil }
                return data.base64EncodedString()
            }
            if encoded.count == values.count {
                self = .dataArray(encoded)
                return
            }
        }
        return nil
    }

    var rawObject: Any? {
        switch self {
        case .bool(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .data(let value):
            return Data(base64Encoded: value)
        case .dataArray(let values):
            let decoded = values.compactMap { Data(base64Encoded: $0) }
            return decoded.count == values.count ? decoded : nil
        }
    }
}

struct PresetTransferPayload: Codable {
    var formatVersion: Int
    var name: String
    var exportedAt: Date
    var updatedAt: Date?
    var snapshot: [String: PresetStorageValue]
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

/// 快捷键配置。
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

    static let persistentTrailDefault = MagnifierShortcut(
        triggerKind: .keyboard,
        keyCode: UInt16(kVK_ANSI_P),
        mouseButton: nil,
        modifiersRaw: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
    )

    static let clearPersistentTrailDefault = MagnifierShortcut(
        triggerKind: .keyboard,
        keyCode: UInt16(kVK_ANSI_C),
        mouseButton: nil,
        modifiersRaw: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
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
                i18n("mouse.left", "左键")
            case .right?:
                i18n("mouse.right", "右键")
            case .middle?:
                i18n("mouse.middle", "中键")
            case nil:
                i18n("mouse.button", "鼠标键")
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

enum ColorFadeSettingKey {
    static let trailColor = "trail.color"
    static let trailRainbowColors = "trail.rainbow.colors"
    static let trailNeonColors = "trail.neon.colors"
    static let trailWaterColors = "trail.water.colors"
    static let trailEffectColor = "trail.effect.color"
    static let trailInkColors = "trail.effect.ink.colors"
    static let trailParticleColors = "trail.effect.particle.colors"
    static let trailWaterSplashColor = "trail.water.splash.color"
    static let speedBurstLineColor = "speedBurst.line.color"
    static let speedBurstAccentColor = "speedBurst.accent.color"
    static let clickParticleExplosionColors = "click.particleExplosion.colors"

    static func clickColor(_ button: MouseButtonKind) -> String {
        "click.\(button.rawValue).color"
    }

    static var allKeys: [String] {
        [
            trailColor,
            trailRainbowColors,
            trailNeonColors,
            trailWaterColors,
            trailEffectColor,
            trailInkColors,
            trailParticleColors,
            trailWaterSplashColor,
            speedBurstLineColor,
            speedBurstAccentColor,
            clickParticleExplosionColors,
        ] + MouseButtonKind.allCases.map(clickColor)
    }
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
    var languageCode: String
    var prefersDarkAppearance: Bool
    var trailColor: NSColor
    var trailEffectColor: NSColor
    var trailStyle: TrailRenderStyle
    var trailEffectStyle: TrailEffectStyle
    var rainbowTrailColors: [NSColor]
    var neonPrimaryColor: NSColor
    var neonSecondaryColor: NSColor
    var neonPrimaryWidthRatio: CGFloat
    var waterHighlightColor: NSColor
    var waterPrimaryColor: NSColor
    var waterShadowColor: NSColor
    var waterHighlightRatio: CGFloat
    var waterPrimaryRatio: CGFloat
    var waterShadowRatio: CGFloat
    var waterMixRandomness: CGFloat
    var waterMixSeedLocked: Bool
    var waterSplashSize: CGFloat
    var waterSplashSpeed: CGFloat
    var waterSplashLifetimeMilliseconds: Double
    var waterSplashDensity: CGFloat
    var waterSplashColor: NSColor
    var trailWidth: CGFloat
    var trailLengthMilliseconds: Double
    var clickVisualStyle: ClickVisualStyle
    var clickEffectRadius: CGFloat
    var clickEffectDurationMilliseconds: Double
    var waterImpactDropletDensity: CGFloat
    var waterImpactSpreadSpeed: CGFloat
    var waterImpactLifetimeMilliseconds: Double
    var waterImpactDropletSize: CGFloat
    var clickParticleExplosionDensity: CGFloat
    var clickParticleExplosionSize: CGFloat
    var clickParticleExplosionLifetimeMilliseconds: Double
    var clickParticleExplosionSpeed: CGFloat
    var clickParticleExplosionColors: [NSColor]
    var magnifierRadius: CGFloat
    var magnifierZoom: CGFloat
    var magnifierBorderWidth: CGFloat
    var magnifierBorderColor: NSColor
    var magnifierShadowOpacity: CGFloat
    var showTrailEffectsWhileMagnifierActive: Bool
    var magnifierShortcut: MagnifierShortcut
    var persistentTrailShortcut: MagnifierShortcut
    var clearPersistentTrailShortcut: MagnifierShortcut
    var isTrailEffectsEnabled: Bool
    var disableTrailFadeAndForceSolid: Bool
    var colorFadeDisabledKeys: Set<String>
    var trailEffectIntensity: CGFloat
    var electricArcDensity: CGFloat
    var electricArcLength: CGFloat
    var electricArcWidth: CGFloat
    var inkDensity: CGFloat
    var inkSize: CGFloat
    var inkLifetimeMilliseconds: Double
    var inkColors: [NSColor]
    var particleDensity: CGFloat
    var particleSize: CGFloat
    var particleLifetimeMilliseconds: Double
    var particleSpeed: CGFloat
    var particleColors: [NSColor]
    var speedBurstEnabled: Bool
    var speedBurstType: SpeedBurstEffectType
    var speedBurstVelocityThreshold: CGFloat
    var speedBurstCooldownMilliseconds: Double
    var speedBurstDurationMilliseconds: Double
    var speedBurstDurationMinMilliseconds: Double
    var speedBurstDurationMaxMilliseconds: Double
    var speedBurstAfterglowMilliseconds: Double
    var speedBurstJitterAmplitude: CGFloat
    var speedBurstMinLength: CGFloat
    var speedBurstMaxLength: CGFloat
    var speedBurstWidthMultiplier: CGFloat
    var speedBurstTrailMinScale: CGFloat
    var speedBurstTrailMaxScale: CGFloat
    var speedBurstEffectMinScale: CGFloat
    var speedBurstEffectMaxScale: CGFloat
    var speedSurgeScaleMode: SpeedSurgeScaleMode
    var speedBurstLineColor: NSColor
    var speedBurstAccentColor: NSColor
    var speedBurstAccentDurationMilliseconds: Double
    var speedBurstAccentSize: CGFloat
    var clickEffects: [MouseButtonKind: ClickEffectStyle]

    func effectStyle(for button: MouseButtonKind) -> ClickEffectStyle {
        clickEffects[button] ?? ClickEffectStyle(isEnabled: true, color: .systemBlue)
    }

    private static let thunderPresetPrefix = "preset.thunder."
    private static let waterPresetPrefix = "preset.water."
    private static let customPresetPrefix = "preset.custom."
    private static let customPresetIndexKey = "preset.custom.index.v1"
    static let thunderPresetSeededKey = "preset.thunder.seeded"
    static let waterPresetSeededKey = "preset.water.seeded"

    private static func thunderPresetKey(_ suffix: String) -> String {
        thunderPresetPrefix + suffix
    }

    private static func waterPresetKey(_ suffix: String) -> String {
        waterPresetPrefix + suffix
    }

    private static func customPresetKey(id: String, suffix: String) -> String {
        customPresetPrefix + id + "." + suffix
    }

    private static let presetSnapshotSuffixes: [String] = [
        "tracking.enabled",
        "click.effects.enabled",
        "trail.style",
        "trail.effectStyle",
        "trail.color",
        "trail.effect.color",
        "trail.rainbow.colors",
        "trail.neon.primary.color",
        "trail.neon.secondary.color",
        "trail.neon.primaryWidthRatio",
        "trail.width",
        "trail.length.ms",
        "trail.effects.enabled",
        "trail.fade.disable",
        "color.fade.disabled.keys",
        "trail.effect.intensity",
        "trail.effect.electric.density",
        "trail.effect.electric.length",
        "trail.effect.electric.width",
        "trail.effect.ink.density",
        "trail.effect.ink.size",
        "trail.effect.ink.lifetime.ms",
        "trail.effect.ink.colors",
        "trail.effect.particle.density",
        "trail.effect.particle.size",
        "trail.effect.particle.lifetime.ms",
        "trail.effect.particle.speed",
        "trail.effect.particle.colors",
        "speedBurst.enabled",
        "speedBurst.type",
        "speedBurst.velocityThreshold",
        "speedBurst.cooldown.ms",
        "speedBurst.duration.ms",
        "speedBurst.duration.min.ms",
        "speedBurst.duration.max.ms",
        "speedBurst.jitter",
        "speedBurst.minLength",
        "speedBurst.maxLength",
        "speedBurst.widthMultiplier",
        "speedBurst.waterSurge.trailScaleMin",
        "speedBurst.waterSurge.trailScaleMax",
        "speedBurst.waterSurge.effectScaleMin",
        "speedBurst.waterSurge.effectScaleMax",
        "speedBurst.waterSurge.scaleMode",
        "speedBurst.line.color",
        "speedBurst.accent.color",
        "speedBurst.accent.duration.ms",
        "speedBurst.accent.size",
        "trail.water.splash.size",
        "trail.water.splash.speed",
        "trail.water.splash.lifetime.ms",
        "trail.water.splash.density",
        "trail.water.splash.color",
        "click.visualStyle",
        "click.radius",
        "click.duration.ms",
        "click.waterImpact.density",
        "click.waterImpact.spreadSpeed",
        "click.waterImpact.lifetime.ms",
        "click.waterImpact.dropletSize",
        "click.particleExplosion.density",
        "click.particleExplosion.size",
        "click.particleExplosion.lifetime.ms",
        "click.particleExplosion.speed",
        "click.particleExplosion.colors",
        "click.left.enabled",
        "click.left.color",
        "click.right.enabled",
        "click.right.color",
        "click.middle.enabled",
        "click.middle.color",
    ]

    static let `default` = AppSettings(
        isLaunchAtLoginEnabled: false,
        isLoggingEnabled: false,
        isStatusItemVisible: true,
        isTrackingEnabled: true,
        isClickEffectsEnabled: true,
        isMagnifierEnabled: true,
        languageCode: "zh-Hans",
        prefersDarkAppearance: true,
        trailColor: NSColor(calibratedRed: 1.0, green: 0.297347, blue: 0.002122, alpha: 1.0),
        trailEffectColor: NSColor(calibratedRed: 0.968974, green: 0.98594, blue: 0.988523, alpha: 1.0),
        trailStyle: .rainbow,
        trailEffectStyle: .particles,
        rainbowTrailColors: [
            NSColor(calibratedRed: 1.0, green: 0.233555, blue: 0.259244, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.591849, blue: 0.182268, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.826639, blue: 0.014795, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.998506, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 0.601502, blue: 1.0, alpha: 1.0),
            NSColor(calibratedRed: 0.538856, green: 0.0, blue: 1.0, alpha: 1.0),
        ],
        neonPrimaryColor: NSColor(calibratedRed: 0.992892, green: 0.506068, blue: 0.011686, alpha: 1.0),
        neonSecondaryColor: NSColor(calibratedRed: 0.983093, green: 0.140958, blue: 0.028378, alpha: 1.0),
        neonPrimaryWidthRatio: 90,
        waterHighlightColor: NSColor(calibratedRed: 0.883836, green: 0.974282, blue: 1.0, alpha: 1.0),
        waterPrimaryColor: NSColor(calibratedRed: 0.406684, green: 0.775007, blue: 1.0, alpha: 1.0),
        waterShadowColor: NSColor(calibratedRed: 0.02102, green: 0.308488, blue: 0.6295, alpha: 1.0),
        waterHighlightRatio: 18.37594696969697,
        waterPrimaryRatio: 36.75189393939394,
        waterShadowRatio: 44.87215909090909,
        waterMixRandomness: 78,
        waterMixSeedLocked: false,
        waterSplashSize: 0.4097265625000001,
        waterSplashSpeed: 1.6408984375,
        waterSplashLifetimeMilliseconds: 260,
        waterSplashDensity: 0.7521484375000002,
        waterSplashColor: NSColor(calibratedRed: 0.870729, green: 0.96812, blue: 1.0, alpha: 0.072431),
        trailWidth: 2.809681818181812,
        trailLengthMilliseconds: 191.682549102955,
        clickVisualStyle: .particleExplosion,
        clickEffectRadius: 30.5242684659091,
        clickEffectDurationMilliseconds: 126.5232954545455,
        waterImpactDropletDensity: 1.3514921875,
        waterImpactSpreadSpeed: 1.0,
        waterImpactLifetimeMilliseconds: 320,
        waterImpactDropletSize: 0.2631953125,
        clickParticleExplosionDensity: 0.3944687499999998,
        clickParticleExplosionSize: 0.4466619318181818,
        clickParticleExplosionLifetimeMilliseconds: 341.4514204545455,
        clickParticleExplosionSpeed: 0.7237421875,
        clickParticleExplosionColors: [
            NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.0, alpha: 0.95),
            NSColor(calibratedRed: 1.0, green: 0.478104, blue: 0.0, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.986542, blue: 0.0, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.86609, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 0.381889, blue: 1.0, alpha: 1.0),
            NSColor(calibratedRed: 0.498536, green: 0.0, blue: 1.0, alpha: 1.0),
        ],
        magnifierRadius: 120,
        magnifierZoom: 1.713835227272727,
        magnifierBorderWidth: 3.0,
        magnifierBorderColor: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        magnifierShadowOpacity: 0.28,
        showTrailEffectsWhileMagnifierActive: true,
        magnifierShortcut: .default,
        persistentTrailShortcut: .persistentTrailDefault,
        clearPersistentTrailShortcut: .clearPersistentTrailDefault,
        isTrailEffectsEnabled: true,
        disableTrailFadeAndForceSolid: false,
        colorFadeDisabledKeys: [
            "click.particleExplosion.colors",
            "speedBurst.accent.color",
            "speedBurst.line.color",
            "trail.color",
            "trail.effect.color",
            "trail.effect.ink.colors",
            "trail.effect.particle.colors",
            "trail.neon.colors",
            "trail.rainbow.colors",
            "trail.water.colors",
            "trail.water.splash.color",
        ],
        trailEffectIntensity: 100,
        electricArcDensity: 0.1,
        electricArcLength: 28.74048295454546,
        electricArcWidth: 0.4,
        inkDensity: 0.286609375,
        inkSize: 0.9109786931818181,
        inkLifetimeMilliseconds: 195.2687499999999,
        inkColors: [
            NSColor(calibratedRed: 0.151422, green: 0.164139, blue: 0.217928, alpha: 0.050781),
        ],
        particleDensity: 0.1906938907129456,
        particleSize: 0.3774772727272732,
        particleLifetimeMilliseconds: 382.5511363636363,
        particleSpeed: 0.6791640625000001,
        particleColors: [
            NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.552006, blue: 0.0, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.965127, blue: 0.0, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.917777, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 0.471017, blue: 1.0, alpha: 1.0),
            NSColor(calibratedRed: 0.609416, green: 0.0, blue: 1.0, alpha: 1.0),
        ],
        speedBurstEnabled: true,
        speedBurstType: .waterSurge,
        speedBurstVelocityThreshold: 10376.16548295454,
        speedBurstCooldownMilliseconds: 450,
        speedBurstDurationMilliseconds: 450,
        speedBurstDurationMinMilliseconds: 199.5890009380863,
        speedBurstDurationMaxMilliseconds: 450,
        speedBurstAfterglowMilliseconds: 0,
        speedBurstJitterAmplitude: 14.40887784090909,
        speedBurstMinLength: 1110.587144886364,
        speedBurstMaxLength: 1294.274431818182,
        speedBurstWidthMultiplier: 0.6157613636363639,
        speedBurstTrailMinScale: 0.6157613636363639,
        speedBurstTrailMaxScale: 3.155335413823981,
        speedBurstEffectMinScale: 0.6157613636363639,
        speedBurstEffectMaxScale: 3.11426922010916,
        speedSurgeScaleMode: .randomRange,
        speedBurstLineColor: NSColor(calibratedRed: 0.991227, green: 0.990452, blue: 0.973691, alpha: 1.0),
        speedBurstAccentColor: NSColor(calibratedRed: 0.977797, green: 0.978413, blue: 0.930802, alpha: 1.0),
        speedBurstAccentDurationMilliseconds: 190,
        speedBurstAccentSize: 40.2940625,
        clickEffects: [
            .left: ClickEffectStyle(isEnabled: true, color: NSColor(calibratedRed: 0.976705, green: 0.064781, blue: 0.018053, alpha: 0.114959)),
            .right: ClickEffectStyle(isEnabled: true, color: NSColor(calibratedRed: 1.0, green: 0.764198, blue: 0.371359, alpha: 1.0)),
            .middle: ClickEffectStyle(isEnabled: true, color: NSColor(calibratedRed: 1.0, green: 0.957181, blue: 0.742947, alpha: 1.0)),
        ]
    )

    /// 归一化“水刃流带”三色占比，确保总和稳定为 100。
    /// Note: 当三项均为 0 时，回退到 34/44/22 的基础配比。
    mutating func normalizeWaterMixRatios() {
        waterHighlightRatio = clampWaterMixRatio(Double(waterHighlightRatio))
        waterPrimaryRatio = clampWaterMixRatio(Double(waterPrimaryRatio))
        waterShadowRatio = clampWaterMixRatio(Double(waterShadowRatio))
        let sum = waterHighlightRatio + waterPrimaryRatio + waterShadowRatio
        if sum <= 0.001 {
            waterHighlightRatio = 34
            waterPrimaryRatio = 44
            waterShadowRatio = 22
            return
        }
        let scale = 100 / sum
        waterHighlightRatio *= scale
        waterPrimaryRatio *= scale
        waterShadowRatio *= scale
    }

    mutating func normalizeEffectStyleSettings() {
        neonPrimaryWidthRatio = clampNeonPrimaryWidthRatio(Double(neonPrimaryWidthRatio))
        electricArcDensity = clampElectricArcDensity(Double(electricArcDensity))
        electricArcLength = clampElectricArcLength(Double(electricArcLength))
        electricArcWidth = clampElectricArcWidth(Double(electricArcWidth))
        inkDensity = clampInkDensity(Double(inkDensity))
        inkSize = clampInkSize(Double(inkSize))
        inkLifetimeMilliseconds = clampInkLifetimeMilliseconds(inkLifetimeMilliseconds)
        particleDensity = clampParticleDensity(Double(particleDensity))
        particleSize = clampParticleSize(Double(particleSize))
        particleLifetimeMilliseconds = clampParticleLifetimeMilliseconds(particleLifetimeMilliseconds)
        particleSpeed = clampParticleSpeed(Double(particleSpeed))
        clickParticleExplosionDensity = clampClickParticleExplosionDensity(Double(clickParticleExplosionDensity))
        clickParticleExplosionSize = clampClickParticleExplosionSize(Double(clickParticleExplosionSize))
        clickParticleExplosionLifetimeMilliseconds = clampClickParticleExplosionLifetimeMilliseconds(clickParticleExplosionLifetimeMilliseconds)
        clickParticleExplosionSpeed = clampClickParticleExplosionSpeed(Double(clickParticleExplosionSpeed))

        let defaultInkColors = AppSettings.default.inkColors
        if inkColors.isEmpty {
            inkColors = defaultInkColors
        }
        inkColors = Array(inkColors.prefix(clampEffectPaletteCount(inkColors.count)))

        let defaultParticleColors = AppSettings.default.particleColors
        if particleColors.isEmpty {
            particleColors = defaultParticleColors
        }
        particleColors = Array(particleColors.prefix(clampEffectPaletteCount(particleColors.count)))
        let defaultClickParticleColors = AppSettings.default.clickParticleExplosionColors
        if clickParticleExplosionColors.isEmpty {
            clickParticleExplosionColors = defaultClickParticleColors
        }
        clickParticleExplosionColors = Array(clickParticleExplosionColors.prefix(clampClickParticleExplosionPaletteCount(clickParticleExplosionColors.count)))
        if disableTrailFadeAndForceSolid {
            colorFadeDisabledKeys.formUnion(ColorFadeSettingKey.allKeys)
            disableTrailFadeAndForceSolid = false
        }
        colorFadeDisabledKeys = Set(colorFadeDisabledKeys.filter { !$0.isEmpty })
    }

    func isFadeDisabled(forColorKey key: String) -> Bool {
        disableTrailFadeAndForceSolid || colorFadeDisabledKeys.contains(key)
    }

    mutating func setFadeDisabled(_ disabled: Bool, forColorKey key: String) {
        guard !key.isEmpty else { return }
        if disabled {
            colorFadeDisabledKeys.insert(key)
        } else {
            colorFadeDisabledKeys.remove(key)
        }
    }

    /// 应用“雷之呼吸·壹之型”预设。
    /// - Parameter applyStoredOverrides: 是否叠加用户保存的同名预设快照。
    mutating func applyThunderFirstFormPreset(applyStoredOverrides: Bool = true) {
        isTrackingEnabled = true
        isClickEffectsEnabled = true
        isMagnifierEnabled = true
        trailStyle = .lightning
        trailEffectStyle = .electric
        trailColor = colorFromHexRGB(0xFFD84A)
        trailEffectColor = colorFromHexRGB(0xFFB84D)
        neonPrimaryWidthRatio = 62
        trailWidth = 3.4
        trailLengthMilliseconds = 420
        isTrailEffectsEnabled = true
        disableTrailFadeAndForceSolid = false
        colorFadeDisabledKeys = []
        trailEffectIntensity = 86
        electricArcDensity = 2.1
        electricArcLength = 21
        electricArcWidth = 1.9
        inkDensity = 1.0
        inkSize = 1.0
        inkLifetimeMilliseconds = 560
        inkColors = AppSettings.default.inkColors
        particleDensity = 1.0
        particleSize = 1.0
        particleLifetimeMilliseconds = 360
        particleSpeed = 1.0
        particleColors = AppSettings.default.particleColors
        speedBurstEnabled = true
        speedBurstType = .firstFlash
        speedBurstVelocityThreshold = 1800
        speedBurstCooldownMilliseconds = 450
        speedBurstDurationMilliseconds = 450
        speedBurstDurationMinMilliseconds = 140
        speedBurstDurationMaxMilliseconds = 260
        speedBurstAfterglowMilliseconds = 0
        speedBurstJitterAmplitude = 5.0
        speedBurstMinLength = 110
        speedBurstMaxLength = 220
        speedBurstWidthMultiplier = 1.55
        speedBurstTrailMinScale = 1.0
        speedBurstTrailMaxScale = 1.45
        speedBurstEffectMinScale = 1.0
        speedBurstEffectMaxScale = 1.45
        speedSurgeScaleMode = .randomRange
        speedBurstLineColor = colorFromHexRGB(0xFFFDF5)
        speedBurstAccentColor = colorFromHexRGB(0xFFE9A746)
        speedBurstAccentDurationMilliseconds = 190
        speedBurstAccentSize = 32
        waterSplashSize = 1.0
        waterSplashSpeed = 1.0
        waterSplashLifetimeMilliseconds = 260
        waterSplashDensity = 1.0
        waterSplashColor = colorFromHexRGB(0xD7F5FF)
        clickVisualStyle = .crossFlare
        clickEffectRadius = 34
        clickEffectDurationMilliseconds = 300
        waterImpactDropletDensity = 1.0
        waterImpactSpreadSpeed = 1.0
        waterImpactLifetimeMilliseconds = 320
        waterImpactDropletSize = 1.0
        clickParticleExplosionDensity = 1.0
        clickParticleExplosionSize = 1.0
        clickParticleExplosionLifetimeMilliseconds = 320
        clickParticleExplosionSpeed = 1.0
        clickParticleExplosionColors = AppSettings.default.clickParticleExplosionColors
        clickEffects[.left] = ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0xFFE066))
        clickEffects[.right] = ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0xFFB74D))
        clickEffects[.middle] = ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0xFFF3B0))
        showTrailEffectsWhileMagnifierActive = true
        if applyStoredOverrides {
            applyStoredThunderPresetOverrides()
        }
        normalizeEffectStyleSettings()
    }

    /// 应用“水之呼吸·壹之型（夸张）”预设。
    /// - Parameter applyStoredOverrides: 是否叠加用户保存的同名预设快照。
    mutating func applyWaterFirstFormPreset(applyStoredOverrides: Bool = true) {
        isTrackingEnabled = true
        isClickEffectsEnabled = true
        isMagnifierEnabled = true
        trailStyle = .waterBlade
        trailEffectStyle = .waterSplash
        trailColor = colorFromHexRGB(0x5EB9FF)
        trailEffectColor = colorFromHexRGB(0xA7D9FF)
        neonPrimaryWidthRatio = 62
        waterHighlightColor = colorFromHexRGB(0xDBF7FF)
        waterPrimaryColor = colorFromHexRGB(0x58B8FF)
        waterShadowColor = colorFromHexRGB(0x0A3A8F)
        waterHighlightRatio = 26
        waterPrimaryRatio = 52
        waterShadowRatio = 22
        waterMixRandomness = 78
        waterMixSeedLocked = false
        waterSplashSize = 1.35
        waterSplashSpeed = 1.28
        waterSplashLifetimeMilliseconds = 360
        waterSplashDensity = 1.7
        waterSplashColor = colorFromHexRGB(0xE7FBFF)
        trailWidth = 4.8
        trailLengthMilliseconds = 520
        isTrailEffectsEnabled = true
        disableTrailFadeAndForceSolid = false
        colorFadeDisabledKeys = []
        trailEffectIntensity = 92
        electricArcDensity = 1.5
        electricArcLength = 16
        electricArcWidth = 1.6
        inkDensity = 1.0
        inkSize = 1.0
        inkLifetimeMilliseconds = 560
        inkColors = AppSettings.default.inkColors
        particleDensity = 1.0
        particleSize = 1.0
        particleLifetimeMilliseconds = 360
        particleSpeed = 1.0
        particleColors = AppSettings.default.particleColors

        speedBurstEnabled = true
        speedBurstType = .waterSurge
        speedBurstVelocityThreshold = 1650
        speedBurstCooldownMilliseconds = 420
        speedBurstDurationMilliseconds = 280
        speedBurstDurationMinMilliseconds = 180
        speedBurstDurationMaxMilliseconds = 380
        speedBurstAfterglowMilliseconds = 0
        speedBurstJitterAmplitude = 2.6
        speedBurstMinLength = 130
        speedBurstMaxLength = 260
        speedBurstWidthMultiplier = 2.0
        speedBurstTrailMinScale = 1.25
        speedBurstTrailMaxScale = 2.2
        speedBurstEffectMinScale = 1.35
        speedBurstEffectMaxScale = 2.4
        speedSurgeScaleMode = .velocityBased
        speedBurstLineColor = colorFromHexRGB(0xC4EEFF)
        speedBurstAccentColor = colorFromHexRGB(0x7BD1FF)
        speedBurstAccentDurationMilliseconds = 220
        speedBurstAccentSize = 42

        clickVisualStyle = .waterImpact
        clickEffectRadius = 38
        clickEffectDurationMilliseconds = 360
        waterImpactDropletDensity = 1.65
        waterImpactSpreadSpeed = 1.35
        waterImpactLifetimeMilliseconds = 430
        waterImpactDropletSize = 1.3
        clickParticleExplosionDensity = 1.0
        clickParticleExplosionSize = 1.0
        clickParticleExplosionLifetimeMilliseconds = 320
        clickParticleExplosionSpeed = 1.0
        clickParticleExplosionColors = AppSettings.default.clickParticleExplosionColors
        clickEffects[.left] = ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0x9EDCFF))
        clickEffects[.right] = ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0x66BDF3))
        clickEffects[.middle] = ClickEffectStyle(isEnabled: true, color: colorFromHexRGB(0xD5F4FF))
        showTrailEffectsWhileMagnifierActive = true
        if applyStoredOverrides {
            applyStoredWaterPresetOverrides()
        }
        normalizeEffectStyleSettings()
        normalizeWaterMixRatios()
    }

    /// 将当前设置快照保存为“雷之呼吸·壹之型”预设。
    mutating func saveAsThunderFirstFormPreset() {
        savePresetSnapshot(using: Self.thunderPresetKey)
        UserDefaults.standard.set(true, forKey: Self.thunderPresetSeededKey)
    }

    /// 将当前设置快照保存为“水之呼吸·壹之型”预设。
    mutating func saveAsWaterFirstFormPreset() {
        savePresetSnapshot(using: Self.waterPresetKey)
        UserDefaults.standard.set(true, forKey: Self.waterPresetSeededKey)
    }

    @discardableResult
    mutating func createCustomTrailPreset(named rawName: String) -> CustomTrailPreset {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = CustomTrailPreset(id: UUID().uuidString, name: name.isEmpty ? "New Preset" : name)
        savePresetSnapshot(using: { suffix in
            Self.customPresetKey(id: preset.id, suffix: suffix)
        })
        var entries = Self.loadCustomTrailPresets()
        entries.append(preset)
        Self.storeCustomTrailPresets(entries)
        return preset
    }

    mutating func updateCustomTrailPreset(id: String) {
        savePresetSnapshot(using: { suffix in
            Self.customPresetKey(id: id, suffix: suffix)
        })
        var entries = Self.loadCustomTrailPresets()
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].updatedAt = Date()
            Self.storeCustomTrailPresets(entries)
        }
    }

    mutating func applyCustomTrailPreset(id: String) {
        applyStoredPresetOverrides(using: { suffix in
            Self.customPresetKey(id: id, suffix: suffix)
        })
    }

    static func loadCustomTrailPresets() -> [CustomTrailPreset] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: customPresetIndexKey),
              let entries = try? JSONDecoder().decode([CustomTrailPreset].self, from: data)
        else {
            return []
        }
        return entries
    }

    @discardableResult
    static func renameCustomTrailPreset(id: String, newName rawName: String) -> Bool {
        let newName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return false }
        var entries = loadCustomTrailPresets()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries[index].name = newName
        entries[index].updatedAt = Date()
        storeCustomTrailPresets(entries)
        return true
    }

    static func deleteCustomTrailPreset(id: String) {
        let defaults = UserDefaults.standard
        let prefix = customPresetPrefix + id + "."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        let entries = loadCustomTrailPresets().filter { $0.id != id }
        storeCustomTrailPresets(entries)
    }

    static func thunderPresetUpdatedAt() -> Date? {
        UserDefaults.standard.object(forKey: thunderPresetKey("meta.updatedAt")) as? Date
    }

    static func waterPresetUpdatedAt() -> Date? {
        UserDefaults.standard.object(forKey: waterPresetKey("meta.updatedAt")) as? Date
    }

    static func customPresetUpdatedAt(id: String) -> Date? {
        if let value = loadCustomTrailPresets().first(where: { $0.id == id })?.updatedAt {
            return value
        }
        return UserDefaults.standard.object(forKey: customPresetKey(id: id, suffix: "meta.updatedAt")) as? Date
    }

    static func exportThunderPresetJSON() -> Data? {
        if snapshotEntries(using: thunderPresetKey).isEmpty {
            var fallback = AppSettings.default
            fallback.applyThunderFirstFormPreset(applyStoredOverrides: false)
            fallback.saveAsThunderFirstFormPreset()
        }
        return exportPresetJSON(name: "Thunder Breathing · First Form", updatedAt: thunderPresetUpdatedAt(), key: thunderPresetKey)
    }

    static func exportWaterPresetJSON() -> Data? {
        if snapshotEntries(using: waterPresetKey).isEmpty {
            var fallback = AppSettings.default
            fallback.applyWaterFirstFormPreset(applyStoredOverrides: false)
            fallback.saveAsWaterFirstFormPreset()
        }
        return exportPresetJSON(name: "Water Breathing · First Form", updatedAt: waterPresetUpdatedAt(), key: waterPresetKey)
    }

    static func exportCustomPresetJSON(id: String) -> Data? {
        let name = loadCustomTrailPresets().first(where: { $0.id == id })?.name ?? "Imported Preset"
        return exportPresetJSON(
            name: name,
            updatedAt: customPresetUpdatedAt(id: id),
            key: { suffix in customPresetKey(id: id, suffix: suffix) }
        )
    }

    static func importCustomPresetJSON(_ data: Data) throws -> CustomTrailPreset {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(PresetTransferPayload.self, from: data)
        let defaults = UserDefaults.standard
        let trimmedName = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = CustomTrailPreset(
            id: UUID().uuidString,
            name: trimmedName.isEmpty ? "Imported Preset" : trimmedName,
            updatedAt: payload.updatedAt ?? Date()
        )
        var entries = loadCustomTrailPresets()
        entries.append(preset)
        storeCustomTrailPresets(entries)
        storeSnapshotEntries(
            payload.snapshot,
            using: { suffix in customPresetKey(id: preset.id, suffix: suffix) }
        )
        defaults.set(preset.updatedAt, forKey: customPresetKey(id: preset.id, suffix: "meta.updatedAt"))
        return preset
    }

    /// 应用用户保存的“雷之呼吸·壹之型”预设覆盖值。
    private mutating func applyStoredThunderPresetOverrides() {
        applyStoredPresetOverrides(using: Self.thunderPresetKey)
    }

    /// 应用用户保存的“水之呼吸·壹之型”预设覆盖值。
    private mutating func applyStoredWaterPresetOverrides() {
        applyStoredPresetOverrides(using: Self.waterPresetKey)
    }

    private static func storeCustomTrailPresets(_ presets: [CustomTrailPreset]) {
        let defaults = UserDefaults.standard
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: customPresetIndexKey)
    }

    private static func exportPresetJSON(
        name: String,
        updatedAt: Date?,
        key: (String) -> String
    ) -> Data? {
        let snapshot = snapshotEntries(using: key)
        guard !snapshot.isEmpty else { return nil }
        let payload = PresetTransferPayload(
            formatVersion: 1,
            name: name,
            exportedAt: Date(),
            updatedAt: updatedAt,
            snapshot: snapshot
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(payload)
    }

    private static func snapshotEntries(using key: (String) -> String) -> [String: PresetStorageValue] {
        let defaults = UserDefaults.standard
        var values: [String: PresetStorageValue] = [:]
        for suffix in presetSnapshotSuffixes {
            guard let object = defaults.object(forKey: key(suffix)),
                  let encoded = PresetStorageValue(rawObject: object)
            else { continue }
            values[suffix] = encoded
        }
        return values
    }

    private static func storeSnapshotEntries(_ entries: [String: PresetStorageValue], using key: (String) -> String) {
        let defaults = UserDefaults.standard
        for (suffix, value) in entries {
            if let object = value.rawObject {
                defaults.set(object, forKey: key(suffix))
            }
        }
    }

    private mutating func savePresetSnapshot(using key: (String) -> String) {
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: key("meta.updatedAt"))
        defaults.set(isTrackingEnabled, forKey: key("tracking.enabled"))
        defaults.set(isClickEffectsEnabled, forKey: key("click.effects.enabled"))

        defaults.set(trailStyle.rawValue, forKey: key("trail.style"))
        defaults.set(trailEffectStyle.rawValue, forKey: key("trail.effectStyle"))
        defaults.set(encodeColorData(trailColor), forKey: key("trail.color"))
        defaults.set(encodeColorData(trailEffectColor), forKey: key("trail.effect.color"))
        defaults.set(rainbowTrailColors.compactMap(encodeColorData), forKey: key("trail.rainbow.colors"))
        defaults.set(encodeColorData(neonPrimaryColor), forKey: key("trail.neon.primary.color"))
        defaults.set(encodeColorData(neonSecondaryColor), forKey: key("trail.neon.secondary.color"))
        defaults.set(Double(neonPrimaryWidthRatio), forKey: key("trail.neon.primaryWidthRatio"))
        defaults.set(Double(trailWidth), forKey: key("trail.width"))
        defaults.set(trailLengthMilliseconds, forKey: key("trail.length.ms"))
        defaults.set(isTrailEffectsEnabled, forKey: key("trail.effects.enabled"))
        defaults.set(disableTrailFadeAndForceSolid, forKey: key("trail.fade.disable"))
        defaults.set(Array(colorFadeDisabledKeys).sorted(), forKey: key("color.fade.disabled.keys"))
        defaults.set(Double(trailEffectIntensity), forKey: key("trail.effect.intensity"))
        defaults.set(Double(electricArcDensity), forKey: key("trail.effect.electric.density"))
        defaults.set(Double(electricArcLength), forKey: key("trail.effect.electric.length"))
        defaults.set(Double(electricArcWidth), forKey: key("trail.effect.electric.width"))
        defaults.set(Double(inkDensity), forKey: key("trail.effect.ink.density"))
        defaults.set(Double(inkSize), forKey: key("trail.effect.ink.size"))
        defaults.set(inkLifetimeMilliseconds, forKey: key("trail.effect.ink.lifetime.ms"))
        defaults.set(inkColors.compactMap(encodeColorData), forKey: key("trail.effect.ink.colors"))
        defaults.set(Double(particleDensity), forKey: key("trail.effect.particle.density"))
        defaults.set(Double(particleSize), forKey: key("trail.effect.particle.size"))
        defaults.set(particleLifetimeMilliseconds, forKey: key("trail.effect.particle.lifetime.ms"))
        defaults.set(Double(particleSpeed), forKey: key("trail.effect.particle.speed"))
        defaults.set(particleColors.compactMap(encodeColorData), forKey: key("trail.effect.particle.colors"))

        defaults.set(speedBurstEnabled, forKey: key("speedBurst.enabled"))
        defaults.set(speedBurstType.rawValue, forKey: key("speedBurst.type"))
        defaults.set(Double(speedBurstVelocityThreshold), forKey: key("speedBurst.velocityThreshold"))
        defaults.set(speedBurstCooldownMilliseconds, forKey: key("speedBurst.cooldown.ms"))
        defaults.set(speedBurstDurationMilliseconds, forKey: key("speedBurst.duration.ms"))
        defaults.set(speedBurstDurationMinMilliseconds, forKey: key("speedBurst.duration.min.ms"))
        defaults.set(speedBurstDurationMaxMilliseconds, forKey: key("speedBurst.duration.max.ms"))
        defaults.set(Double(speedBurstJitterAmplitude), forKey: key("speedBurst.jitter"))
        defaults.set(Double(speedBurstMinLength), forKey: key("speedBurst.minLength"))
        defaults.set(Double(speedBurstMaxLength), forKey: key("speedBurst.maxLength"))
        defaults.set(Double(speedBurstWidthMultiplier), forKey: key("speedBurst.widthMultiplier"))
        defaults.set(Double(speedBurstTrailMinScale), forKey: key("speedBurst.waterSurge.trailScaleMin"))
        defaults.set(Double(speedBurstTrailMaxScale), forKey: key("speedBurst.waterSurge.trailScaleMax"))
        defaults.set(Double(speedBurstEffectMinScale), forKey: key("speedBurst.waterSurge.effectScaleMin"))
        defaults.set(Double(speedBurstEffectMaxScale), forKey: key("speedBurst.waterSurge.effectScaleMax"))
        defaults.set(speedSurgeScaleMode.rawValue, forKey: key("speedBurst.waterSurge.scaleMode"))
        defaults.set(encodeColorData(speedBurstLineColor), forKey: key("speedBurst.line.color"))
        defaults.set(encodeColorData(speedBurstAccentColor), forKey: key("speedBurst.accent.color"))
        defaults.set(speedBurstAccentDurationMilliseconds, forKey: key("speedBurst.accent.duration.ms"))
        defaults.set(Double(speedBurstAccentSize), forKey: key("speedBurst.accent.size"))
        defaults.set(Double(waterSplashSize), forKey: key("trail.water.splash.size"))
        defaults.set(Double(waterSplashSpeed), forKey: key("trail.water.splash.speed"))
        defaults.set(waterSplashLifetimeMilliseconds, forKey: key("trail.water.splash.lifetime.ms"))
        defaults.set(Double(waterSplashDensity), forKey: key("trail.water.splash.density"))
        defaults.set(encodeColorData(waterSplashColor), forKey: key("trail.water.splash.color"))

        defaults.set(clickVisualStyle.rawValue, forKey: key("click.visualStyle"))
        defaults.set(Double(clickEffectRadius), forKey: key("click.radius"))
        defaults.set(clickEffectDurationMilliseconds, forKey: key("click.duration.ms"))
        defaults.set(Double(waterImpactDropletDensity), forKey: key("click.waterImpact.density"))
        defaults.set(Double(waterImpactSpreadSpeed), forKey: key("click.waterImpact.spreadSpeed"))
        defaults.set(waterImpactLifetimeMilliseconds, forKey: key("click.waterImpact.lifetime.ms"))
        defaults.set(Double(waterImpactDropletSize), forKey: key("click.waterImpact.dropletSize"))
        defaults.set(Double(clickParticleExplosionDensity), forKey: key("click.particleExplosion.density"))
        defaults.set(Double(clickParticleExplosionSize), forKey: key("click.particleExplosion.size"))
        defaults.set(clickParticleExplosionLifetimeMilliseconds, forKey: key("click.particleExplosion.lifetime.ms"))
        defaults.set(Double(clickParticleExplosionSpeed), forKey: key("click.particleExplosion.speed"))
        defaults.set(clickParticleExplosionColors.compactMap(encodeColorData), forKey: key("click.particleExplosion.colors"))
        for button in MouseButtonKind.allCases {
            let style = effectStyle(for: button)
            defaults.set(style.isEnabled, forKey: key("click.\(button.rawValue).enabled"))
            defaults.set(encodeColorData(style.color), forKey: key("click.\(button.rawValue).color"))
        }
    }

    private mutating func applyStoredPresetOverrides(using key: (String) -> String) {
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: key("tracking.enabled")) as? Bool {
            isTrackingEnabled = value
        }
        if let value = defaults.object(forKey: key("click.effects.enabled")) as? Bool {
            isClickEffectsEnabled = value
        }

        if let raw = defaults.string(forKey: key("trail.style")),
           let value = TrailRenderStyle(rawValue: raw)
        {
            trailStyle = value
        }
        if let raw = defaults.string(forKey: key("trail.effectStyle")),
           let value = TrailEffectStyle(rawValue: raw)
        {
            trailEffectStyle = value
        }
        if let value = decodeColorData(defaults.data(forKey: key("trail.color"))) {
            trailColor = value
        }
        if let value = decodeColorData(defaults.data(forKey: key("trail.effect.color"))) {
            trailEffectColor = value
        }
        if let items = defaults.array(forKey: key("trail.rainbow.colors")) {
            let colors = items.compactMap { item -> NSColor? in
                guard let data = item as? Data else { return nil }
                return decodeColorData(data)
            }
            if colors.count >= 2 {
                rainbowTrailColors = colors
            }
        }
        if let value = decodeColorData(defaults.data(forKey: key("trail.neon.primary.color"))) {
            neonPrimaryColor = value
        }
        if let value = decodeColorData(defaults.data(forKey: key("trail.neon.secondary.color"))) {
            neonSecondaryColor = value
        }
        if let value = defaults.object(forKey: key("trail.neon.primaryWidthRatio")) as? Double {
            neonPrimaryWidthRatio = clampNeonPrimaryWidthRatio(value)
        }
        if let value = defaults.object(forKey: key("trail.width")) as? Double {
            trailWidth = clampTrailWidth(value)
        }
        if let value = defaults.object(forKey: key("trail.length.ms")) as? Double {
            trailLengthMilliseconds = clampTrailLengthMilliseconds(value)
        }
        if let value = defaults.object(forKey: key("trail.effects.enabled")) as? Bool {
            isTrailEffectsEnabled = value
        }
        if let value = defaults.object(forKey: key("trail.fade.disable")) as? Bool {
            disableTrailFadeAndForceSolid = value
        }
        if let values = defaults.array(forKey: key("color.fade.disabled.keys")) as? [String] {
            colorFadeDisabledKeys = Set(values.filter { !$0.isEmpty })
        }
        if let value = defaults.object(forKey: key("trail.effect.intensity")) as? Double {
            trailEffectIntensity = clampTrailEffectIntensity(value)
        } else if let raw = defaults.string(forKey: key("trail.intensityPreset")),
                  let value = EffectIntensityPreset(rawValue: raw)
        {
            switch value {
            case .off:
                isTrailEffectsEnabled = false
                trailEffectIntensity = 0
            case .low:
                isTrailEffectsEnabled = true
                trailEffectIntensity = 35
            case .normal:
                isTrailEffectsEnabled = true
                trailEffectIntensity = 65
            case .high:
                isTrailEffectsEnabled = true
                trailEffectIntensity = 100
            }
        }
        if let value = defaults.object(forKey: key("trail.effect.electric.density")) as? Double {
            electricArcDensity = clampElectricArcDensity(value)
        }
        if let value = defaults.object(forKey: key("trail.effect.electric.length")) as? Double {
            electricArcLength = clampElectricArcLength(value)
        }
        if let value = defaults.object(forKey: key("trail.effect.electric.width")) as? Double {
            electricArcWidth = clampElectricArcWidth(value)
        }
        if let value = defaults.object(forKey: key("trail.effect.ink.density")) as? Double {
            inkDensity = clampInkDensity(value)
        }
        if let value = defaults.object(forKey: key("trail.effect.ink.size")) as? Double {
            inkSize = clampInkSize(value)
        }
        if let value = defaults.object(forKey: key("trail.effect.ink.lifetime.ms")) as? Double {
            inkLifetimeMilliseconds = clampInkLifetimeMilliseconds(value)
        }
        if let items = defaults.array(forKey: key("trail.effect.ink.colors")) {
            let colors = items.compactMap { item -> NSColor? in
                guard let data = item as? Data else { return nil }
                return decodeColorData(data)
            }
            if !colors.isEmpty {
                inkColors = Array(colors.prefix(clampEffectPaletteCount(colors.count)))
            }
        }
        if let value = defaults.object(forKey: key("trail.effect.particle.density")) as? Double {
            particleDensity = clampParticleDensity(value)
        }
        if let value = defaults.object(forKey: key("trail.effect.particle.size")) as? Double {
            particleSize = clampParticleSize(value)
        }
        if let value = defaults.object(forKey: key("trail.effect.particle.lifetime.ms")) as? Double {
            particleLifetimeMilliseconds = clampParticleLifetimeMilliseconds(value)
        }
        if let value = defaults.object(forKey: key("trail.effect.particle.speed")) as? Double {
            particleSpeed = clampParticleSpeed(value)
        }
        if let items = defaults.array(forKey: key("trail.effect.particle.colors")) {
            let colors = items.compactMap { item -> NSColor? in
                guard let data = item as? Data else { return nil }
                return decodeColorData(data)
            }
            if !colors.isEmpty {
                particleColors = Array(colors.prefix(clampEffectPaletteCount(colors.count)))
            }
        }

        if let value = defaults.object(forKey: key("speedBurst.enabled")) as? Bool {
            speedBurstEnabled = value
        }
        if let raw = defaults.string(forKey: key("speedBurst.type")),
           let value = SpeedBurstEffectType(rawValue: raw)
        {
            speedBurstType = value
        }
        if let value = defaults.object(forKey: key("speedBurst.velocityThreshold")) as? Double {
            speedBurstVelocityThreshold = clampSpeedBurstVelocityThreshold(value)
        }
        if let value = defaults.object(forKey: key("speedBurst.cooldown.ms")) as? Double {
            speedBurstCooldownMilliseconds = clampSpeedBurstCooldownMilliseconds(value)
        }
        if let value = defaults.object(forKey: key("speedBurst.duration.ms")) as? Double {
            speedBurstDurationMilliseconds = clampSpeedBurstDurationMilliseconds(value)
        }
        speedBurstDurationMinMilliseconds = clampSpeedBurstDurationMilliseconds(
            defaults.object(forKey: key("speedBurst.duration.min.ms")) as? Double
                ?? speedBurstDurationMilliseconds
        )
        speedBurstDurationMaxMilliseconds = clampSpeedBurstDurationMilliseconds(
            defaults.object(forKey: key("speedBurst.duration.max.ms")) as? Double
                ?? speedBurstDurationMilliseconds
        )
        if speedBurstDurationMaxMilliseconds < speedBurstDurationMinMilliseconds {
            swap(&speedBurstDurationMinMilliseconds, &speedBurstDurationMaxMilliseconds)
        }
        if let value = defaults.object(forKey: key("speedBurst.jitter")) as? Double {
            speedBurstJitterAmplitude = clampSpeedBurstJitterAmplitude(value)
        }
        if let value = defaults.object(forKey: key("speedBurst.minLength")) as? Double {
            speedBurstMinLength = clampSpeedBurstMinLength(value)
        }
        if let value = defaults.object(forKey: key("speedBurst.maxLength")) as? Double {
            speedBurstMaxLength = clampSpeedBurstMaxLength(value)
        }
        if speedBurstMaxLength < speedBurstMinLength {
            swap(&speedBurstMinLength, &speedBurstMaxLength)
        }
        if let value = defaults.object(forKey: key("speedBurst.widthMultiplier")) as? Double {
            speedBurstWidthMultiplier = clampSpeedBurstWidthMultiplier(value)
        }
        speedBurstTrailMinScale = clampSpeedSurgeTrailScale(
            defaults.object(forKey: key("speedBurst.waterSurge.trailScaleMin")) as? Double
                ?? speedBurstWidthMultiplier
        )
        speedBurstTrailMaxScale = clampSpeedSurgeTrailScale(
            defaults.object(forKey: key("speedBurst.waterSurge.trailScaleMax")) as? Double
                ?? speedBurstWidthMultiplier
        )
        if speedBurstTrailMaxScale < speedBurstTrailMinScale {
            swap(&speedBurstTrailMinScale, &speedBurstTrailMaxScale)
        }
        speedBurstEffectMinScale = clampSpeedSurgeEffectScale(
            defaults.object(forKey: key("speedBurst.waterSurge.effectScaleMin")) as? Double
                ?? speedBurstTrailMinScale
        )
        speedBurstEffectMaxScale = clampSpeedSurgeEffectScale(
            defaults.object(forKey: key("speedBurst.waterSurge.effectScaleMax")) as? Double
                ?? speedBurstTrailMaxScale
        )
        if speedBurstEffectMaxScale < speedBurstEffectMinScale {
            swap(&speedBurstEffectMinScale, &speedBurstEffectMaxScale)
        }
        if let raw = defaults.string(forKey: key("speedBurst.waterSurge.scaleMode")),
           let value = SpeedSurgeScaleMode(rawValue: raw)
        {
            speedSurgeScaleMode = value
        }
        if let value = decodeColorData(defaults.data(forKey: key("speedBurst.line.color"))) {
            speedBurstLineColor = value
        }
        if let value = decodeColorData(defaults.data(forKey: key("speedBurst.accent.color"))) {
            speedBurstAccentColor = value
        }
        if let value = defaults.object(forKey: key("speedBurst.accent.duration.ms")) as? Double {
            speedBurstAccentDurationMilliseconds = clampSpeedBurstAccentDurationMilliseconds(value)
        }
        if let value = defaults.object(forKey: key("speedBurst.accent.size")) as? Double {
            speedBurstAccentSize = clampSpeedBurstAccentSize(value)
        }
        if let value = defaults.object(forKey: key("trail.water.splash.size")) as? Double {
            waterSplashSize = clampWaterSplashSize(value)
        }
        if let value = defaults.object(forKey: key("trail.water.splash.speed")) as? Double {
            waterSplashSpeed = clampWaterSplashSpeed(value)
        }
        if let value = defaults.object(forKey: key("trail.water.splash.lifetime.ms")) as? Double {
            waterSplashLifetimeMilliseconds = clampWaterSplashLifetimeMilliseconds(value)
        }
        if let value = defaults.object(forKey: key("trail.water.splash.density")) as? Double {
            waterSplashDensity = clampWaterSplashDensity(value)
        }
        if let value = decodeColorData(defaults.data(forKey: key("trail.water.splash.color"))) {
            waterSplashColor = value
        }

        if let raw = defaults.string(forKey: key("click.visualStyle")),
           let value = ClickVisualStyle(rawValue: raw)
        {
            clickVisualStyle = value
        }
        if let value = defaults.object(forKey: key("click.radius")) as? Double {
            clickEffectRadius = clampClickEffectRadius(value)
        }
        if let value = defaults.object(forKey: key("click.duration.ms")) as? Double {
            clickEffectDurationMilliseconds = clampClickEffectDurationMilliseconds(value)
        }
        if let value = defaults.object(forKey: key("click.waterImpact.density")) as? Double {
            waterImpactDropletDensity = clampWaterImpactDropletDensity(value)
        }
        if let value = defaults.object(forKey: key("click.waterImpact.spreadSpeed")) as? Double {
            waterImpactSpreadSpeed = clampWaterImpactSpreadSpeed(value)
        }
        if let value = defaults.object(forKey: key("click.waterImpact.lifetime.ms")) as? Double {
            waterImpactLifetimeMilliseconds = clampWaterImpactLifetimeMilliseconds(value)
        }
        if let value = defaults.object(forKey: key("click.waterImpact.dropletSize")) as? Double {
            waterImpactDropletSize = clampWaterImpactDropletSize(value)
        }
        if let value = defaults.object(forKey: key("click.particleExplosion.density")) as? Double {
            clickParticleExplosionDensity = clampClickParticleExplosionDensity(value)
        }
        if let value = defaults.object(forKey: key("click.particleExplosion.size")) as? Double {
            clickParticleExplosionSize = clampClickParticleExplosionSize(value)
        }
        if let value = defaults.object(forKey: key("click.particleExplosion.lifetime.ms")) as? Double {
            clickParticleExplosionLifetimeMilliseconds = clampClickParticleExplosionLifetimeMilliseconds(value)
        }
        if let value = defaults.object(forKey: key("click.particleExplosion.speed")) as? Double {
            clickParticleExplosionSpeed = clampClickParticleExplosionSpeed(value)
        }
        if let items = defaults.array(forKey: key("click.particleExplosion.colors")) {
            let colors = items.compactMap { item -> NSColor? in
                guard let data = item as? Data else { return nil }
                return decodeColorData(data)
            }
            if !colors.isEmpty {
                clickParticleExplosionColors = Array(colors.prefix(clampClickParticleExplosionPaletteCount(colors.count)))
            }
        }
        for button in MouseButtonKind.allCases {
            var style = effectStyle(for: button)
            if let enabled = defaults.object(forKey: key("click.\(button.rawValue).enabled")) as? Bool {
                style.isEnabled = enabled
            }
            if let color = decodeColorData(defaults.data(forKey: key("click.\(button.rawValue).color"))) {
                style.color = color
            }
            clickEffects[button] = style
        }
        normalizeEffectStyleSettings()
    }
}

/// 设置持久化存储层。
/// 职责：负责 UserDefaults 的读写、版本兼容兜底与参数钳制。
