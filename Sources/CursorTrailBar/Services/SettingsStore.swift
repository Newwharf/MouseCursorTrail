//
// SettingsStore.swift
// MVC: Model 持久化服务（UserDefaults）
//
import AppKit

final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let launchAtLoginEnabledKey = "launchAtLogin.enabled"
    private let loggingEnabledKey = "debug.logging.enabled"
    private let statusItemVisibleKey = "statusItem.visible"
    private let trackingEnabledKey = "tracking.enabled"
    private let clickEffectsEnabledKey = "click.effects.enabled"
    private let magnifierEnabledKey = "magnifier.enabled"
    private let languageCodeKey = "app.language.code"
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
        let languageCode = defaults.string(forKey: languageCodeKey) ?? fallback.languageCode
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
            languageCode: languageCode,
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
        defaults.set(settings.languageCode, forKey: languageCodeKey)
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
