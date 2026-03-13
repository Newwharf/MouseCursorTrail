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
    private let prefersDarkAppearanceKey = "app.appearance.dark"
    private let trailColorKey = "trail.color"
    private let trailEffectColorKey = "trail.effect.color"
    private let trailStyleKey = "trail.style"
    private let trailEffectStyleKey = "trail.effectStyle"
    private let trailRainbowColorsKey = "trail.rainbow.colors"
    private let trailNeonPrimaryColorKey = "trail.neon.primary.color"
    private let trailNeonSecondaryColorKey = "trail.neon.secondary.color"
    private let trailNeonPrimaryWidthRatioKey = "trail.neon.primaryWidthRatio"
    private let trailWaterHighlightColorKey = "trail.water.highlight.color"
    private let trailWaterPrimaryColorKey = "trail.water.primary.color"
    private let trailWaterShadowColorKey = "trail.water.shadow.color"
    private let trailWaterHighlightRatioKey = "trail.water.highlight.ratio"
    private let trailWaterPrimaryRatioKey = "trail.water.primary.ratio"
    private let trailWaterShadowRatioKey = "trail.water.shadow.ratio"
    private let trailWaterMixRandomnessKey = "trail.water.mix.randomness"
    private let trailWaterMixSeedLockedKey = "trail.water.mix.seedLocked"
    private let trailWaterSplashSizeKey = "trail.water.splash.size"
    private let trailWaterSplashSpeedKey = "trail.water.splash.speed"
    private let trailWaterSplashLifetimeKey = "trail.water.splash.lifetime.ms"
    private let trailWaterSplashDensityKey = "trail.water.splash.density"
    private let trailWaterSplashColorKey = "trail.water.splash.color"
    private let trailWidthKey = "trail.width"
    private let trailLengthMillisecondsKey = "trail.length.ms"
    private let clickVisualStyleKey = "click.visualStyle"
    private let clickRadiusKey = "click.radius"
    private let clickDurationMillisecondsKey = "click.duration.ms"
    private let clickWaterImpactDensityKey = "click.waterImpact.density"
    private let clickWaterImpactSpreadSpeedKey = "click.waterImpact.spreadSpeed"
    private let clickWaterImpactLifetimeKey = "click.waterImpact.lifetime.ms"
    private let clickWaterImpactDropletSizeKey = "click.waterImpact.dropletSize"
    private let clickParticleExplosionDensityKey = "click.particleExplosion.density"
    private let clickParticleExplosionSizeKey = "click.particleExplosion.size"
    private let clickParticleExplosionLifetimeKey = "click.particleExplosion.lifetime.ms"
    private let clickParticleExplosionSpeedKey = "click.particleExplosion.speed"
    private let clickParticleExplosionColorsKey = "click.particleExplosion.colors"
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
    private let persistentTrailShortcutKindKey = "trail.persistent.shortcut.kind"
    private let persistentTrailShortcutKeyCodeKey = "trail.persistent.shortcut.keyCode"
    private let persistentTrailShortcutMouseButtonKey = "trail.persistent.shortcut.mouseButton"
    private let persistentTrailShortcutModifiersKey = "trail.persistent.shortcut.modifiers"
    private let clearPersistentTrailShortcutKindKey = "trail.persistent.clear.shortcut.kind"
    private let clearPersistentTrailShortcutKeyCodeKey = "trail.persistent.clear.shortcut.keyCode"
    private let clearPersistentTrailShortcutMouseButtonKey = "trail.persistent.clear.shortcut.mouseButton"
    private let clearPersistentTrailShortcutModifiersKey = "trail.persistent.clear.shortcut.modifiers"
    private let trailEffectsEnabledKey = "trail.effects.enabled"
    private let trailFadeDisableKey = "trail.fade.disable"
    private let colorFadeDisabledKeysKey = "color.fade.disabled.keys"
    private let trailEffectIntensityKey = "trail.effect.intensity"
    private let trailIntensityKey = "trail.intensityPreset"
    private let trailEffectElectricDensityKey = "trail.effect.electric.density"
    private let trailEffectElectricLengthKey = "trail.effect.electric.length"
    private let trailEffectElectricWidthKey = "trail.effect.electric.width"
    private let trailEffectInkDensityKey = "trail.effect.ink.density"
    private let trailEffectInkSizeKey = "trail.effect.ink.size"
    private let trailEffectInkLifetimeKey = "trail.effect.ink.lifetime.ms"
    private let trailEffectInkColorsKey = "trail.effect.ink.colors"
    private let trailEffectParticleDensityKey = "trail.effect.particle.density"
    private let trailEffectParticleSizeKey = "trail.effect.particle.size"
    private let trailEffectParticleLifetimeKey = "trail.effect.particle.lifetime.ms"
    private let trailEffectParticleSpeedKey = "trail.effect.particle.speed"
    private let trailEffectParticleColorsKey = "trail.effect.particle.colors"
    private let speedBurstEnabledKey = "speedBurst.enabled"
    private let speedBurstTypeKey = "speedBurst.type"
    private let speedBurstVelocityThresholdKey = "speedBurst.velocityThreshold"
    private let speedBurstCooldownKey = "speedBurst.cooldown.ms"
    private let speedBurstDurationKey = "speedBurst.duration.ms"
    private let speedBurstDurationMinKey = "speedBurst.duration.min.ms"
    private let speedBurstDurationMaxKey = "speedBurst.duration.max.ms"
    private let speedBurstAfterglowKey = "speedBurst.afterglow.ms"
    private let speedBurstJitterKey = "speedBurst.jitter"
    private let speedBurstMinLengthKey = "speedBurst.minLength"
    private let speedBurstMaxLengthKey = "speedBurst.maxLength"
    private let speedBurstWidthMultiplierKey = "speedBurst.widthMultiplier"
    private let speedBurstTrailMinScaleKey = "speedBurst.waterSurge.trailScaleMin"
    private let speedBurstTrailMaxScaleKey = "speedBurst.waterSurge.trailScaleMax"
    private let speedBurstEffectMinScaleKey = "speedBurst.waterSurge.effectScaleMin"
    private let speedBurstEffectMaxScaleKey = "speedBurst.waterSurge.effectScaleMax"
    private let speedBurstSurgeScaleModeKey = "speedBurst.waterSurge.scaleMode"
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
        let prefersDarkAppearance = defaults.object(forKey: prefersDarkAppearanceKey) as? Bool ?? fallback.prefersDarkAppearance
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
        let rainbowTrailColors = decodeColorArray(defaults.array(forKey: trailRainbowColorsKey), minCount: 2) ?? fallback.rainbowTrailColors
        let neonPrimaryColor = decodeColor(defaults.data(forKey: trailNeonPrimaryColorKey)) ?? fallback.neonPrimaryColor
        let neonSecondaryColor = decodeColor(defaults.data(forKey: trailNeonSecondaryColorKey)) ?? fallback.neonSecondaryColor
        let neonPrimaryWidthRatio = clampNeonPrimaryWidthRatio(
            defaults.object(forKey: trailNeonPrimaryWidthRatioKey) as? Double ?? fallback.neonPrimaryWidthRatio
        )
        let waterHighlightColor = decodeColor(defaults.data(forKey: trailWaterHighlightColorKey)) ?? fallback.waterHighlightColor
        let waterPrimaryColor = decodeColor(defaults.data(forKey: trailWaterPrimaryColorKey)) ?? fallback.waterPrimaryColor
        let waterShadowColor = decodeColor(defaults.data(forKey: trailWaterShadowColorKey)) ?? fallback.waterShadowColor
        let waterHighlightRatio = clampWaterMixRatio(
            defaults.object(forKey: trailWaterHighlightRatioKey) as? Double ?? fallback.waterHighlightRatio
        )
        let waterPrimaryRatio = clampWaterMixRatio(
            defaults.object(forKey: trailWaterPrimaryRatioKey) as? Double ?? fallback.waterPrimaryRatio
        )
        let waterShadowRatio = clampWaterMixRatio(
            defaults.object(forKey: trailWaterShadowRatioKey) as? Double ?? fallback.waterShadowRatio
        )
        let waterMixRandomness = clampWaterMixRandomness(
            defaults.object(forKey: trailWaterMixRandomnessKey) as? Double ?? fallback.waterMixRandomness
        )
        let waterMixSeedLocked = defaults.object(forKey: trailWaterMixSeedLockedKey) as? Bool ?? fallback.waterMixSeedLocked
        let waterSplashSize = clampWaterSplashSize(
            defaults.object(forKey: trailWaterSplashSizeKey) as? Double ?? fallback.waterSplashSize
        )
        let waterSplashSpeed = clampWaterSplashSpeed(
            defaults.object(forKey: trailWaterSplashSpeedKey) as? Double ?? fallback.waterSplashSpeed
        )
        let waterSplashLifetimeMilliseconds = clampWaterSplashLifetimeMilliseconds(
            defaults.object(forKey: trailWaterSplashLifetimeKey) as? Double ?? fallback.waterSplashLifetimeMilliseconds
        )
        let waterSplashDensity = clampWaterSplashDensity(
            defaults.object(forKey: trailWaterSplashDensityKey) as? Double ?? fallback.waterSplashDensity
        )
        let waterSplashColor = decodeColor(defaults.data(forKey: trailWaterSplashColorKey)) ?? fallback.waterSplashColor
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
        let waterImpactDropletDensity = clampWaterImpactDropletDensity(
            defaults.object(forKey: clickWaterImpactDensityKey) as? Double ?? fallback.waterImpactDropletDensity
        )
        let waterImpactSpreadSpeed = clampWaterImpactSpreadSpeed(
            defaults.object(forKey: clickWaterImpactSpreadSpeedKey) as? Double ?? fallback.waterImpactSpreadSpeed
        )
        let waterImpactLifetimeMilliseconds = clampWaterImpactLifetimeMilliseconds(
            defaults.object(forKey: clickWaterImpactLifetimeKey) as? Double ?? fallback.waterImpactLifetimeMilliseconds
        )
        let waterImpactDropletSize = clampWaterImpactDropletSize(
            defaults.object(forKey: clickWaterImpactDropletSizeKey) as? Double ?? fallback.waterImpactDropletSize
        )
        let clickParticleExplosionDensity = clampClickParticleExplosionDensity(
            defaults.object(forKey: clickParticleExplosionDensityKey) as? Double ?? fallback.clickParticleExplosionDensity
        )
        let clickParticleExplosionSize = clampClickParticleExplosionSize(
            defaults.object(forKey: clickParticleExplosionSizeKey) as? Double ?? fallback.clickParticleExplosionSize
        )
        let clickParticleExplosionLifetimeMilliseconds = clampClickParticleExplosionLifetimeMilliseconds(
            defaults.object(forKey: clickParticleExplosionLifetimeKey) as? Double ?? fallback.clickParticleExplosionLifetimeMilliseconds
        )
        let clickParticleExplosionSpeed = clampClickParticleExplosionSpeed(
            defaults.object(forKey: clickParticleExplosionSpeedKey) as? Double ?? fallback.clickParticleExplosionSpeed
        )
        let clickParticleExplosionColors = decodeColorArray(defaults.array(forKey: clickParticleExplosionColorsKey), minCount: 1)
            ?? fallback.clickParticleExplosionColors
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
        var isTrailEffectsEnabled = defaults.object(forKey: trailEffectsEnabledKey) as? Bool ?? fallback.isTrailEffectsEnabled
        let disableTrailFadeAndForceSolid = defaults.object(forKey: trailFadeDisableKey) as? Bool
            ?? fallback.disableTrailFadeAndForceSolid
        let colorFadeDisabledKeys = Set(
            (defaults.array(forKey: colorFadeDisabledKeysKey) as? [String] ?? Array(fallback.colorFadeDisabledKeys))
                .filter { !$0.isEmpty }
        )
        let trailEffectIntensityObject = defaults.object(forKey: trailEffectIntensityKey)
        var trailEffectIntensity = clampTrailEffectIntensity(
            trailEffectIntensityObject as? Double ?? fallback.trailEffectIntensity
        )
        if trailEffectIntensityObject == nil,
           let raw = defaults.string(forKey: trailIntensityKey),
           let preset = EffectIntensityPreset(rawValue: raw)
        {
            switch preset {
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
        let electricArcDensity = clampElectricArcDensity(
            defaults.object(forKey: trailEffectElectricDensityKey) as? Double ?? fallback.electricArcDensity
        )
        let electricArcLength = clampElectricArcLength(
            defaults.object(forKey: trailEffectElectricLengthKey) as? Double ?? fallback.electricArcLength
        )
        let electricArcWidth = clampElectricArcWidth(
            defaults.object(forKey: trailEffectElectricWidthKey) as? Double ?? fallback.electricArcWidth
        )
        let inkDensity = clampInkDensity(
            defaults.object(forKey: trailEffectInkDensityKey) as? Double ?? fallback.inkDensity
        )
        let inkSize = clampInkSize(
            defaults.object(forKey: trailEffectInkSizeKey) as? Double ?? fallback.inkSize
        )
        let inkLifetimeMilliseconds = clampInkLifetimeMilliseconds(
            defaults.object(forKey: trailEffectInkLifetimeKey) as? Double ?? fallback.inkLifetimeMilliseconds
        )
        let inkColors = decodeColorArray(defaults.array(forKey: trailEffectInkColorsKey), minCount: 1) ?? fallback.inkColors
        let particleDensity = clampParticleDensity(
            defaults.object(forKey: trailEffectParticleDensityKey) as? Double ?? fallback.particleDensity
        )
        let particleSize = clampParticleSize(
            defaults.object(forKey: trailEffectParticleSizeKey) as? Double ?? fallback.particleSize
        )
        let particleLifetimeMilliseconds = clampParticleLifetimeMilliseconds(
            defaults.object(forKey: trailEffectParticleLifetimeKey) as? Double ?? fallback.particleLifetimeMilliseconds
        )
        let particleSpeed = clampParticleSpeed(
            defaults.object(forKey: trailEffectParticleSpeedKey) as? Double ?? fallback.particleSpeed
        )
        let particleColors = decodeColorArray(defaults.array(forKey: trailEffectParticleColorsKey), minCount: 1) ?? fallback.particleColors
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
        var speedBurstDurationMinMilliseconds = clampSpeedBurstDurationMilliseconds(
            defaults.object(forKey: speedBurstDurationMinKey) as? Double ?? speedBurstDurationMilliseconds
        )
        var speedBurstDurationMaxMilliseconds = clampSpeedBurstDurationMilliseconds(
            defaults.object(forKey: speedBurstDurationMaxKey) as? Double ?? speedBurstDurationMilliseconds
        )
        if speedBurstDurationMaxMilliseconds < speedBurstDurationMinMilliseconds {
            swap(&speedBurstDurationMinMilliseconds, &speedBurstDurationMaxMilliseconds)
        }
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
        var speedBurstTrailMinScale = clampSpeedSurgeTrailScale(
            defaults.object(forKey: speedBurstTrailMinScaleKey) as? Double ?? speedBurstWidthMultiplier
        )
        var speedBurstTrailMaxScale = clampSpeedSurgeTrailScale(
            defaults.object(forKey: speedBurstTrailMaxScaleKey) as? Double ?? speedBurstWidthMultiplier
        )
        if speedBurstTrailMaxScale < speedBurstTrailMinScale {
            swap(&speedBurstTrailMinScale, &speedBurstTrailMaxScale)
        }
        var speedBurstEffectMinScale = clampSpeedSurgeEffectScale(
            defaults.object(forKey: speedBurstEffectMinScaleKey) as? Double ?? speedBurstTrailMinScale
        )
        var speedBurstEffectMaxScale = clampSpeedSurgeEffectScale(
            defaults.object(forKey: speedBurstEffectMaxScaleKey) as? Double ?? speedBurstTrailMaxScale
        )
        if speedBurstEffectMaxScale < speedBurstEffectMinScale {
            swap(&speedBurstEffectMinScale, &speedBurstEffectMaxScale)
        }
        let speedSurgeScaleMode = defaults
            .string(forKey: speedBurstSurgeScaleModeKey)
            .flatMap(SpeedSurgeScaleMode.init(rawValue:))
            ?? fallback.speedSurgeScaleMode
        let speedBurstLineColor = decodeColor(defaults.data(forKey: speedBurstLineColorKey)) ?? fallback.speedBurstLineColor
        let speedBurstAccentColor = decodeColor(defaults.data(forKey: speedBurstAccentColorKey)) ?? fallback.speedBurstAccentColor
        let speedBurstAccentDurationMilliseconds = clampSpeedBurstAccentDurationMilliseconds(
            defaults.object(forKey: speedBurstAccentDurationKey) as? Double ?? fallback.speedBurstAccentDurationMilliseconds
        )
        let speedBurstAccentSize = clampSpeedBurstAccentSize(
            defaults.object(forKey: speedBurstAccentSizeKey) as? Double ?? fallback.speedBurstAccentSize
        )

        let magnifierShortcut = loadShortcut(
            kindKey: magnifierShortcutKindKey,
            keyCodeKey: magnifierShortcutKeyCodeKey,
            mouseButtonKey: magnifierShortcutMouseButtonKey,
            modifiersKey: magnifierShortcutModifiersKey,
            fallback: fallback.magnifierShortcut
        )
        let persistentTrailShortcut = loadShortcut(
            kindKey: persistentTrailShortcutKindKey,
            keyCodeKey: persistentTrailShortcutKeyCodeKey,
            mouseButtonKey: persistentTrailShortcutMouseButtonKey,
            modifiersKey: persistentTrailShortcutModifiersKey,
            fallback: fallback.persistentTrailShortcut
        )
        let clearPersistentTrailShortcut = loadShortcut(
            kindKey: clearPersistentTrailShortcutKindKey,
            keyCodeKey: clearPersistentTrailShortcutKeyCodeKey,
            mouseButtonKey: clearPersistentTrailShortcutMouseButtonKey,
            modifiersKey: clearPersistentTrailShortcutModifiersKey,
            fallback: fallback.clearPersistentTrailShortcut
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

        var loadedSettings = AppSettings(
            isLaunchAtLoginEnabled: isLaunchAtLoginEnabled,
            isLoggingEnabled: isLoggingEnabled,
            isStatusItemVisible: isStatusItemVisible,
            isTrackingEnabled: isTrackingEnabled,
            isClickEffectsEnabled: isClickEffectsEnabled,
            isMagnifierEnabled: isMagnifierEnabled,
            languageCode: languageCode,
            prefersDarkAppearance: prefersDarkAppearance,
            trailColor: decodeColor(defaults.data(forKey: trailColorKey)) ?? fallback.trailColor,
            trailEffectColor: decodeColor(defaults.data(forKey: trailEffectColorKey)) ?? fallback.trailEffectColor,
            trailStyle: trailStyle,
            trailEffectStyle: trailEffectStyle,
            rainbowTrailColors: rainbowTrailColors,
            neonPrimaryColor: neonPrimaryColor,
            neonSecondaryColor: neonSecondaryColor,
            neonPrimaryWidthRatio: neonPrimaryWidthRatio,
            waterHighlightColor: waterHighlightColor,
            waterPrimaryColor: waterPrimaryColor,
            waterShadowColor: waterShadowColor,
            waterHighlightRatio: waterHighlightRatio,
            waterPrimaryRatio: waterPrimaryRatio,
            waterShadowRatio: waterShadowRatio,
            waterMixRandomness: waterMixRandomness,
            waterMixSeedLocked: waterMixSeedLocked,
            waterSplashSize: waterSplashSize,
            waterSplashSpeed: waterSplashSpeed,
            waterSplashLifetimeMilliseconds: waterSplashLifetimeMilliseconds,
            waterSplashDensity: waterSplashDensity,
            waterSplashColor: waterSplashColor,
            trailWidth: trailWidth,
            trailLengthMilliseconds: trailLengthMilliseconds,
            clickVisualStyle: clickVisualStyle,
            clickEffectRadius: clickEffectRadius,
            clickEffectDurationMilliseconds: clickEffectDurationMilliseconds,
            waterImpactDropletDensity: waterImpactDropletDensity,
            waterImpactSpreadSpeed: waterImpactSpreadSpeed,
            waterImpactLifetimeMilliseconds: waterImpactLifetimeMilliseconds,
            waterImpactDropletSize: waterImpactDropletSize,
            clickParticleExplosionDensity: clickParticleExplosionDensity,
            clickParticleExplosionSize: clickParticleExplosionSize,
            clickParticleExplosionLifetimeMilliseconds: clickParticleExplosionLifetimeMilliseconds,
            clickParticleExplosionSpeed: clickParticleExplosionSpeed,
            clickParticleExplosionColors: clickParticleExplosionColors,
            magnifierRadius: magnifierRadius,
            magnifierZoom: magnifierZoom,
            magnifierBorderWidth: magnifierBorderWidth,
            magnifierBorderColor: decodeColor(defaults.data(forKey: magnifierBorderColorKey)) ?? fallback.magnifierBorderColor,
            magnifierShadowOpacity: magnifierShadowOpacity,
            showTrailEffectsWhileMagnifierActive: showTrailEffectsWhileMagnifierActive,
            magnifierShortcut: magnifierShortcut,
            persistentTrailShortcut: persistentTrailShortcut,
            clearPersistentTrailShortcut: clearPersistentTrailShortcut,
            isTrailEffectsEnabled: isTrailEffectsEnabled,
            disableTrailFadeAndForceSolid: disableTrailFadeAndForceSolid,
            colorFadeDisabledKeys: colorFadeDisabledKeys,
            trailEffectIntensity: trailEffectIntensity,
            electricArcDensity: electricArcDensity,
            electricArcLength: electricArcLength,
            electricArcWidth: electricArcWidth,
            inkDensity: inkDensity,
            inkSize: inkSize,
            inkLifetimeMilliseconds: inkLifetimeMilliseconds,
            inkColors: inkColors,
            particleDensity: particleDensity,
            particleSize: particleSize,
            particleLifetimeMilliseconds: particleLifetimeMilliseconds,
            particleSpeed: particleSpeed,
            particleColors: particleColors,
            speedBurstEnabled: speedBurstEnabled,
            speedBurstType: speedBurstType,
            speedBurstVelocityThreshold: speedBurstVelocityThreshold,
            speedBurstCooldownMilliseconds: speedBurstCooldownMilliseconds,
            speedBurstDurationMilliseconds: speedBurstDurationMilliseconds,
            speedBurstDurationMinMilliseconds: speedBurstDurationMinMilliseconds,
            speedBurstDurationMaxMilliseconds: speedBurstDurationMaxMilliseconds,
            speedBurstAfterglowMilliseconds: speedBurstAfterglowMilliseconds,
            speedBurstJitterAmplitude: speedBurstJitterAmplitude,
            speedBurstMinLength: speedBurstMinLength,
            speedBurstMaxLength: speedBurstMaxLength,
            speedBurstWidthMultiplier: speedBurstWidthMultiplier,
            speedBurstTrailMinScale: speedBurstTrailMinScale,
            speedBurstTrailMaxScale: speedBurstTrailMaxScale,
            speedBurstEffectMinScale: speedBurstEffectMinScale,
            speedBurstEffectMaxScale: speedBurstEffectMaxScale,
            speedSurgeScaleMode: speedSurgeScaleMode,
            speedBurstLineColor: speedBurstLineColor,
            speedBurstAccentColor: speedBurstAccentColor,
            speedBurstAccentDurationMilliseconds: speedBurstAccentDurationMilliseconds,
            speedBurstAccentSize: speedBurstAccentSize,
            clickEffects: clickEffects
        )
        loadedSettings.normalizeWaterMixRatios()
        loadedSettings.normalizeEffectStyleSettings()
        return loadedSettings
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
        defaults.set(settings.prefersDarkAppearance, forKey: prefersDarkAppearanceKey)
        defaults.set(Double(settings.trailWidth), forKey: trailWidthKey)
        defaults.set(settings.trailStyle.rawValue, forKey: trailStyleKey)
        defaults.set(settings.trailEffectStyle.rawValue, forKey: trailEffectStyleKey)
        defaults.set(settings.clickVisualStyle.rawValue, forKey: clickVisualStyleKey)
        defaults.set(settings.rainbowTrailColors.compactMap(encodeColor), forKey: trailRainbowColorsKey)
        defaults.set(encodeColor(settings.neonPrimaryColor), forKey: trailNeonPrimaryColorKey)
        defaults.set(encodeColor(settings.neonSecondaryColor), forKey: trailNeonSecondaryColorKey)
        defaults.set(Double(settings.neonPrimaryWidthRatio), forKey: trailNeonPrimaryWidthRatioKey)
        defaults.set(encodeColor(settings.waterHighlightColor), forKey: trailWaterHighlightColorKey)
        defaults.set(encodeColor(settings.waterPrimaryColor), forKey: trailWaterPrimaryColorKey)
        defaults.set(encodeColor(settings.waterShadowColor), forKey: trailWaterShadowColorKey)
        defaults.set(Double(settings.waterHighlightRatio), forKey: trailWaterHighlightRatioKey)
        defaults.set(Double(settings.waterPrimaryRatio), forKey: trailWaterPrimaryRatioKey)
        defaults.set(Double(settings.waterShadowRatio), forKey: trailWaterShadowRatioKey)
        defaults.set(Double(settings.waterMixRandomness), forKey: trailWaterMixRandomnessKey)
        defaults.set(settings.waterMixSeedLocked, forKey: trailWaterMixSeedLockedKey)
        defaults.set(Double(settings.waterSplashSize), forKey: trailWaterSplashSizeKey)
        defaults.set(Double(settings.waterSplashSpeed), forKey: trailWaterSplashSpeedKey)
        defaults.set(settings.waterSplashLifetimeMilliseconds, forKey: trailWaterSplashLifetimeKey)
        defaults.set(Double(settings.waterSplashDensity), forKey: trailWaterSplashDensityKey)
        defaults.set(encodeColor(settings.waterSplashColor), forKey: trailWaterSplashColorKey)
        defaults.set(settings.trailLengthMilliseconds, forKey: trailLengthMillisecondsKey)
        defaults.set(Double(settings.clickEffectRadius), forKey: clickRadiusKey)
        defaults.set(settings.clickEffectDurationMilliseconds, forKey: clickDurationMillisecondsKey)
        defaults.set(Double(settings.waterImpactDropletDensity), forKey: clickWaterImpactDensityKey)
        defaults.set(Double(settings.waterImpactSpreadSpeed), forKey: clickWaterImpactSpreadSpeedKey)
        defaults.set(settings.waterImpactLifetimeMilliseconds, forKey: clickWaterImpactLifetimeKey)
        defaults.set(Double(settings.waterImpactDropletSize), forKey: clickWaterImpactDropletSizeKey)
        defaults.set(Double(settings.clickParticleExplosionDensity), forKey: clickParticleExplosionDensityKey)
        defaults.set(Double(settings.clickParticleExplosionSize), forKey: clickParticleExplosionSizeKey)
        defaults.set(settings.clickParticleExplosionLifetimeMilliseconds, forKey: clickParticleExplosionLifetimeKey)
        defaults.set(Double(settings.clickParticleExplosionSpeed), forKey: clickParticleExplosionSpeedKey)
        defaults.set(settings.clickParticleExplosionColors.compactMap(encodeColor), forKey: clickParticleExplosionColorsKey)
        defaults.set(Double(settings.magnifierRadius), forKey: magnifierRadiusKey)
        defaults.set(Double(settings.magnifierZoom), forKey: magnifierZoomKey)
        defaults.set(Double(settings.magnifierBorderWidth), forKey: magnifierBorderWidthKey)
        defaults.set(encodeColor(settings.magnifierBorderColor), forKey: magnifierBorderColorKey)
        defaults.set(Double(settings.magnifierShadowOpacity), forKey: magnifierShadowOpacityKey)
        defaults.set(settings.showTrailEffectsWhileMagnifierActive, forKey: magnifierShowTrailEffectsKey)
        saveShortcut(
            settings.magnifierShortcut,
            kindKey: magnifierShortcutKindKey,
            keyCodeKey: magnifierShortcutKeyCodeKey,
            mouseButtonKey: magnifierShortcutMouseButtonKey,
            modifiersKey: magnifierShortcutModifiersKey
        )
        saveShortcut(
            settings.persistentTrailShortcut,
            kindKey: persistentTrailShortcutKindKey,
            keyCodeKey: persistentTrailShortcutKeyCodeKey,
            mouseButtonKey: persistentTrailShortcutMouseButtonKey,
            modifiersKey: persistentTrailShortcutModifiersKey
        )
        saveShortcut(
            settings.clearPersistentTrailShortcut,
            kindKey: clearPersistentTrailShortcutKindKey,
            keyCodeKey: clearPersistentTrailShortcutKeyCodeKey,
            mouseButtonKey: clearPersistentTrailShortcutMouseButtonKey,
            modifiersKey: clearPersistentTrailShortcutModifiersKey
        )
        defaults.set(settings.isTrailEffectsEnabled, forKey: trailEffectsEnabledKey)
        defaults.set(settings.disableTrailFadeAndForceSolid, forKey: trailFadeDisableKey)
        defaults.set(Array(settings.colorFadeDisabledKeys).sorted(), forKey: colorFadeDisabledKeysKey)
        defaults.set(Double(settings.trailEffectIntensity), forKey: trailEffectIntensityKey)
        defaults.set(Double(settings.electricArcDensity), forKey: trailEffectElectricDensityKey)
        defaults.set(Double(settings.electricArcLength), forKey: trailEffectElectricLengthKey)
        defaults.set(Double(settings.electricArcWidth), forKey: trailEffectElectricWidthKey)
        defaults.set(Double(settings.inkDensity), forKey: trailEffectInkDensityKey)
        defaults.set(Double(settings.inkSize), forKey: trailEffectInkSizeKey)
        defaults.set(settings.inkLifetimeMilliseconds, forKey: trailEffectInkLifetimeKey)
        defaults.set(settings.inkColors.compactMap(encodeColor), forKey: trailEffectInkColorsKey)
        defaults.set(Double(settings.particleDensity), forKey: trailEffectParticleDensityKey)
        defaults.set(Double(settings.particleSize), forKey: trailEffectParticleSizeKey)
        defaults.set(settings.particleLifetimeMilliseconds, forKey: trailEffectParticleLifetimeKey)
        defaults.set(Double(settings.particleSpeed), forKey: trailEffectParticleSpeedKey)
        defaults.set(settings.particleColors.compactMap(encodeColor), forKey: trailEffectParticleColorsKey)
        let legacyIntensityPreset: EffectIntensityPreset = if !settings.isTrailEffectsEnabled {
            .off
        } else if settings.trailEffectIntensity < 50 {
            .low
        } else if settings.trailEffectIntensity < 80 {
            .normal
        } else {
            .high
        }
        defaults.set(legacyIntensityPreset.rawValue, forKey: trailIntensityKey)
        defaults.set(settings.speedBurstEnabled, forKey: speedBurstEnabledKey)
        defaults.set(settings.speedBurstType.rawValue, forKey: speedBurstTypeKey)
        defaults.set(Double(settings.speedBurstVelocityThreshold), forKey: speedBurstVelocityThresholdKey)
        defaults.set(settings.speedBurstCooldownMilliseconds, forKey: speedBurstCooldownKey)
        defaults.set(settings.speedBurstDurationMilliseconds, forKey: speedBurstDurationKey)
        defaults.set(settings.speedBurstDurationMinMilliseconds, forKey: speedBurstDurationMinKey)
        defaults.set(settings.speedBurstDurationMaxMilliseconds, forKey: speedBurstDurationMaxKey)
        defaults.set(settings.speedBurstAfterglowMilliseconds, forKey: speedBurstAfterglowKey)
        defaults.set(Double(settings.speedBurstJitterAmplitude), forKey: speedBurstJitterKey)
        defaults.set(Double(settings.speedBurstMinLength), forKey: speedBurstMinLengthKey)
        defaults.set(Double(settings.speedBurstMaxLength), forKey: speedBurstMaxLengthKey)
        defaults.set(Double(settings.speedBurstWidthMultiplier), forKey: speedBurstWidthMultiplierKey)
        defaults.set(Double(settings.speedBurstTrailMinScale), forKey: speedBurstTrailMinScaleKey)
        defaults.set(Double(settings.speedBurstTrailMaxScale), forKey: speedBurstTrailMaxScaleKey)
        defaults.set(Double(settings.speedBurstEffectMinScale), forKey: speedBurstEffectMinScaleKey)
        defaults.set(Double(settings.speedBurstEffectMaxScale), forKey: speedBurstEffectMaxScaleKey)
        defaults.set(settings.speedSurgeScaleMode.rawValue, forKey: speedBurstSurgeScaleModeKey)
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

    private func decodeColorArray(_ value: [Any]?, minCount: Int = 2) -> [NSColor]? {
        guard let value else { return nil }
        let colors = value.compactMap { item -> NSColor? in
            guard let data = item as? Data else { return nil }
            return decodeColor(data)
        }
        return colors.count >= minCount ? colors : nil
    }

    private func loadShortcut(
        kindKey: String,
        keyCodeKey: String,
        mouseButtonKey: String,
        modifiersKey: String,
        fallback: MagnifierShortcut
    ) -> MagnifierShortcut {
        let kind = defaults
            .string(forKey: kindKey)
            .flatMap(ShortcutTriggerKind.init(rawValue:))
            ?? fallback.triggerKind
        let keyCode = defaults.object(forKey: keyCodeKey) as? UInt16
        let mouseButton = defaults
            .string(forKey: mouseButtonKey)
            .flatMap(MouseButtonKind.init(rawValue:))
        let modifiers = defaults.object(forKey: modifiersKey) as? UInt ?? fallback.modifiersRaw
        return MagnifierShortcut(
            triggerKind: kind,
            keyCode: kind == .keyboard ? (keyCode ?? fallback.keyCode) : nil,
            mouseButton: kind == .mouse ? (mouseButton ?? fallback.mouseButton ?? .right) : nil,
            modifiersRaw: modifiers
        )
    }

    private func saveShortcut(
        _ shortcut: MagnifierShortcut,
        kindKey: String,
        keyCodeKey: String,
        mouseButtonKey: String,
        modifiersKey: String
    ) {
        defaults.set(shortcut.triggerKind.rawValue, forKey: kindKey)
        defaults.set(shortcut.keyCode, forKey: keyCodeKey)
        defaults.set(shortcut.mouseButton?.rawValue, forKey: mouseButtonKey)
        defaults.set(shortcut.modifiersRaw, forKey: modifiersKey)
    }
}

/// 轻量异步文件日志器。
/// 注意：默认开启；是否记录由 `setEnabled(_:)` 动态控制。
