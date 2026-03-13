//
// TrailOverlayView.swift
// MVC: View 层（轨迹/特效/放大镜渲染）
//
import AppKit
import ApplicationServices
import QuartzCore

@MainActor
/// 轨迹与特效渲染视图。
/// 职责：维护瞬态粒子/脉冲/爆发状态，并按定时节拍重绘。
final class TrailOverlayView: NSView {
    private struct MovePoint {
        let point: NSPoint
        let timestamp: CFTimeInterval
        let trailScale: CGFloat
    }

    private struct PersistentTrailStroke {
        var points: [NSPoint]
    }

    private struct TrailSample {
        let point: NSPoint
        let alpha: CGFloat
        let index: Int
        let trailScale: CGFloat
    }

    private struct WaterRibbonNode {
        let point: NSPoint
        let normal: (x: CGFloat, y: CGFloat)
        let alpha: CGFloat
        let progress: CGFloat
        let curveSign: CGFloat
        let curveStrength: CGFloat
        let trailScale: CGFloat
    }

    private struct ActiveWaterSurge {
        let endTimestamp: CFTimeInterval
        let randomTrailScale: CGFloat
        let randomEffectScale: CGFloat
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
        let fadeKey: String
        let lifetime: CFTimeInterval
        let timestamp: CFTimeInterval
    }

    private struct Particle {
        let point: NSPoint
        let velocity: CGVector
        let size: CGFloat
        let color: NSColor
        let fadeKey: String
        let lifetime: CFTimeInterval
        let timestamp: CFTimeInterval
    }

    private struct ClickAccent {
        enum Kind {
            case cross
        }

        let point: NSPoint
        let color: NSColor
        let fadeKey: String
        let radius: CGFloat
        let kind: Kind
        let lifetime: CFTimeInterval
        let timestamp: CFTimeInterval
    }

    private struct WaterImpactDroplet {
        let point: NSPoint
        let velocity: CGVector
        let size: CGFloat
        let color: NSColor
        let fadeKey: String
        let lifetime: CFTimeInterval
        let timestamp: CFTimeInterval
        let seed: Int
    }

    private struct DashBurst {
        let start: NSPoint
        let end: NSPoint
        let coreColor: NSColor
        let fadeKey: String
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
    private var persistentTrailStrokes: [PersistentTrailStroke] = []
    private var pulses: [Pulse] = []
    private var particles: [Particle] = []
    private var clickExplosionParticles: [Particle] = []
    private var clickAccents: [ClickAccent] = []
    private var waterImpactDroplets: [WaterImpactDroplet] = []
    private var dashBursts: [DashBurst] = []
    private var cursorPoint: NSPoint?
    private var lastMovePoint: NSPoint?
    private var lastMoveTimestamp: CFTimeInterval?
    private var lastAcceptedMoveTimestamp: CFTimeInterval = 0
    private var lastDashBurstTimestamp: CFTimeInterval = -1
    private var pressedButton: PressedButton = .none
    private var isPersistentTrailCaptureActive = false
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
    private var neonPrimaryWidthRatio: CGFloat = AppSettings.default.neonPrimaryWidthRatio
    private var waterHighlightColor: NSColor = AppSettings.default.waterHighlightColor
    private var waterPrimaryColor: NSColor = AppSettings.default.waterPrimaryColor
    private var waterShadowColor: NSColor = AppSettings.default.waterShadowColor
    private var waterHighlightRatio: CGFloat = AppSettings.default.waterHighlightRatio
    private var waterPrimaryRatio: CGFloat = AppSettings.default.waterPrimaryRatio
    private var waterShadowRatio: CGFloat = AppSettings.default.waterShadowRatio
    private var waterMixRandomness: CGFloat = AppSettings.default.waterMixRandomness
    private var waterMixSeedLocked: Bool = AppSettings.default.waterMixSeedLocked
    private var waterSplashSize: CGFloat = AppSettings.default.waterSplashSize
    private var waterSplashSpeed: CGFloat = AppSettings.default.waterSplashSpeed
    private var waterSplashLifetimeSeconds: CFTimeInterval = AppSettings.default.waterSplashLifetimeMilliseconds / 1000
    private var waterSplashDensity: CGFloat = AppSettings.default.waterSplashDensity
    private var waterSplashColor: NSColor = AppSettings.default.waterSplashColor
    private var trailLineWidth: CGFloat = AppSettings.default.trailWidth
    private var trailLengthMilliseconds: Double = AppSettings.default.trailLengthMilliseconds
    private var clickVisualStyle: ClickVisualStyle = AppSettings.default.clickVisualStyle
    private var clickEffectRadius: CGFloat = AppSettings.default.clickEffectRadius
    private var clickEffectDurationSeconds: CFTimeInterval = AppSettings.default.clickEffectDurationMilliseconds / 1000
    private var waterImpactDropletDensity: CGFloat = AppSettings.default.waterImpactDropletDensity
    private var waterImpactSpreadSpeed: CGFloat = AppSettings.default.waterImpactSpreadSpeed
    private var waterImpactLifetimeSeconds: CFTimeInterval = AppSettings.default.waterImpactLifetimeMilliseconds / 1000
    private var waterImpactDropletSize: CGFloat = AppSettings.default.waterImpactDropletSize
    private var clickParticleExplosionDensity: CGFloat = AppSettings.default.clickParticleExplosionDensity
    private var clickParticleExplosionSize: CGFloat = AppSettings.default.clickParticleExplosionSize
    private var clickParticleExplosionLifetimeSeconds: CFTimeInterval = AppSettings.default.clickParticleExplosionLifetimeMilliseconds / 1000
    private var clickParticleExplosionSpeed: CGFloat = AppSettings.default.clickParticleExplosionSpeed
    private var clickParticleExplosionColors: [NSColor] = AppSettings.default.clickParticleExplosionColors
    private var magnifierRadius: CGFloat = AppSettings.default.magnifierRadius
    private var magnifierZoom: CGFloat = AppSettings.default.magnifierZoom
    private var configuredMagnifierZoom: CGFloat = AppSettings.default.magnifierZoom
    private var magnifierBorderWidth: CGFloat = AppSettings.default.magnifierBorderWidth
    private var magnifierBorderColor: NSColor = AppSettings.default.magnifierBorderColor
    private var magnifierShadowOpacity: CGFloat = AppSettings.default.magnifierShadowOpacity
    private var showTrailEffectsWhileMagnifierActive = AppSettings.default.showTrailEffectsWhileMagnifierActive
    private var isClickEffectsEnabled = AppSettings.default.isClickEffectsEnabled
    private var isMagnifierEnabled = AppSettings.default.isMagnifierEnabled
    private var isTrailEffectsEnabled = AppSettings.default.isTrailEffectsEnabled
    private var disableTrailFadeAndForceSolid = AppSettings.default.disableTrailFadeAndForceSolid
    private var colorFadeDisabledKeys: Set<String> = AppSettings.default.colorFadeDisabledKeys
    private var electricArcDensity: CGFloat = AppSettings.default.electricArcDensity
    private var electricArcLength: CGFloat = AppSettings.default.electricArcLength
    private var electricArcWidth: CGFloat = AppSettings.default.electricArcWidth
    private var inkDensity: CGFloat = AppSettings.default.inkDensity
    private var inkSize: CGFloat = AppSettings.default.inkSize
    private var inkLifetimeSeconds: CFTimeInterval = AppSettings.default.inkLifetimeMilliseconds / 1000
    private var inkColors: [NSColor] = AppSettings.default.inkColors
    private var particleDensity: CGFloat = AppSettings.default.particleDensity
    private var particleSize: CGFloat = AppSettings.default.particleSize
    private var particleLifetimeSeconds: CFTimeInterval = AppSettings.default.particleLifetimeMilliseconds / 1000
    private var particleSpeed: CGFloat = AppSettings.default.particleSpeed
    private var particleColors: [NSColor] = AppSettings.default.particleColors
    private var isMagnifierActive = false
    private var speedBurstEnabled = AppSettings.default.speedBurstEnabled
    private var speedBurstType: SpeedBurstEffectType = AppSettings.default.speedBurstType
    private var speedBurstVelocityThreshold: CGFloat = AppSettings.default.speedBurstVelocityThreshold
    private var speedBurstCooldownSeconds: CFTimeInterval = AppSettings.default.speedBurstCooldownMilliseconds / 1000
    private var speedBurstDurationSeconds: CFTimeInterval = AppSettings.default.speedBurstDurationMilliseconds / 1000
    private var speedBurstDurationMinSeconds: CFTimeInterval = AppSettings.default.speedBurstDurationMinMilliseconds / 1000
    private var speedBurstDurationMaxSeconds: CFTimeInterval = AppSettings.default.speedBurstDurationMaxMilliseconds / 1000
    private var speedBurstJitterAmplitude: CGFloat = AppSettings.default.speedBurstJitterAmplitude
    private var speedBurstMinLength: CGFloat = AppSettings.default.speedBurstMinLength
    private var speedBurstMaxLength: CGFloat = AppSettings.default.speedBurstMaxLength
    private var speedBurstWidthMultiplier: CGFloat = AppSettings.default.speedBurstWidthMultiplier
    private var speedBurstTrailMinScale: CGFloat = AppSettings.default.speedBurstTrailMinScale
    private var speedBurstTrailMaxScale: CGFloat = AppSettings.default.speedBurstTrailMaxScale
    private var speedBurstEffectMinScale: CGFloat = AppSettings.default.speedBurstEffectMinScale
    private var speedBurstEffectMaxScale: CGFloat = AppSettings.default.speedBurstEffectMaxScale
    private var speedSurgeScaleMode: SpeedSurgeScaleMode = AppSettings.default.speedSurgeScaleMode
    private var speedBurstLineColor: NSColor = AppSettings.default.speedBurstLineColor
    private var speedBurstAccentColor: NSColor = AppSettings.default.speedBurstAccentColor
    private var speedBurstAccentDurationSeconds: CFTimeInterval = AppSettings.default.speedBurstAccentDurationMilliseconds / 1000
    private var speedBurstAccentSize: CGFloat = AppSettings.default.speedBurstAccentSize
    private var clickEffects: [MouseButtonKind: ClickEffectStyle] = AppSettings.default.clickEffects
    private var activeWaterSurge: ActiveWaterSurge?
    private var hadAnimatedContentOnLastTick = false
    private var lastMagnifierZoomLogTimestamp: CFTimeInterval = 0
    private var lastMagnifierCenterLogTimestamp: CFTimeInterval = 0

    private var trailLengthSeconds: CFTimeInterval {
        trailLengthMilliseconds / 1000
    }

    private var activeEffectDensity: CGFloat {
        switch trailEffectStyle {
        case .particles:
            return particleDensity
        case .ink:
            return inkDensity
        case .electric:
            return electricArcDensity
        case .waterSplash:
            return waterSplashDensity
        }
    }

    private var effectSpawnMultiplier: CGFloat {
        guard isTrailEffectsEnabled else { return 0 }
        return max(0.06, pow(max(0.1, activeEffectDensity), 1.05))
    }

    private var effectParticleLifetime: CFTimeInterval {
        guard isTrailEffectsEnabled else { return 0.01 }
        switch trailEffectStyle {
        case .particles:
            return max(0.04, particleLifetimeSeconds)
        case .ink:
            return max(0.04, inkLifetimeSeconds)
        case .electric:
            return max(0.05, 0.08 + Double(electricArcLength / 120))
        case .waterSplash:
            return max(0.06, waterSplashLifetimeSeconds * 0.55)
        }
    }

    private var effectParticleSizeRange: ClosedRange<CGFloat> {
        guard isTrailEffectsEnabled else { return 0.1...0.1 }
        switch trailEffectStyle {
        case .particles:
            let minSize = 1.0 * particleSize
            let maxSize = 4.2 * particleSize
            return minSize...maxSize
        case .ink:
            let minSize = 2.0 * inkSize
            let maxSize = 6.6 * inkSize
            return minSize...maxSize
        case .electric:
            let minSize = 0.8 * electricArcWidth
            let maxSize = 2.6 * electricArcWidth
            return minSize...maxSize
        case .waterSplash:
            let minSize = 1.0 * waterSplashSize
            let maxSize = 5.6 * waterSplashSize
            return minSize...maxSize
        }
    }

    private var effectParticleSpeedRange: ClosedRange<CGFloat> {
        guard isTrailEffectsEnabled else { return 0...0 }
        switch trailEffectStyle {
        case .particles:
            let minSpeed = 14 * particleSpeed
            let maxSpeed = 66 * particleSpeed
            return minSpeed...maxSpeed
        case .ink:
            return 6...26
        case .electric:
            let base = max(6, electricArcLength)
            return (base * 2.2)...(base * 5.8)
        case .waterSplash:
            let minSpeed = 24 * waterSplashSpeed
            let maxSpeed = 130 * waterSplashSpeed
            return minSpeed...maxSpeed
        }
    }

    private var effectMaxParticleCount: Int {
        guard isTrailEffectsEnabled else { return 0 }
        let density = max(0.1, activeEffectDensity)
        return max(40, Int(130 + pow(density, 1.2) * 260))
    }

    private var effectGlowBoost: CGFloat {
        guard isTrailEffectsEnabled else { return 0 }
        return 0.55 + min(1.6, max(0.1, activeEffectDensity) * 0.28)
    }

    private let minimumMoveSampleInterval: CFTimeInterval = 1.0 / 120.0
    private let minimumMoveDistance: CGFloat = 1.2
    private let refreshInterval: CFTimeInterval = 1.0 / 45.0
    private let magnifierCaptureInterval: CFTimeInterval = 1.0 / 30.0
    private let maxPersistentStrokeCount = 120
    private let maxPersistentPointsPerStroke = 2400
    private let maxPersistentSamplesPerStroke = 4000

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
            persistentTrailStrokes.removeAll()
            dashBursts.removeAll()
            lastMoveTimestamp = nil
            isPersistentTrailCaptureActive = false
            lastDashBurstTimestamp = -1
            activeWaterSurge = nil
            needsDisplay = true
        }
    }

    func setPersistentTrailCaptureActive(_ active: Bool) {
        let nextActive = isTrailEnabled && active
        guard nextActive != isPersistentTrailCaptureActive else { return }
        isPersistentTrailCaptureActive = nextActive
        if nextActive {
            beginPersistentTrailStrokeIfNeeded()
        } else {
            pruneTrailingEmptyPersistentStroke()
        }
        needsDisplay = true
    }

    func clear() {
        movePoints.removeAll()
        persistentTrailStrokes.removeAll()
        pulses.removeAll()
        particles.removeAll()
        clickExplosionParticles.removeAll()
        clickAccents.removeAll()
        waterImpactDroplets.removeAll()
        dashBursts.removeAll()
        cursorPoint = nil
        lastMovePoint = nil
        lastMoveTimestamp = nil
        lastAcceptedMoveTimestamp = 0
        lastDashBurstTimestamp = -1
        activeWaterSurge = nil
        pressedButton = .none
        isPersistentTrailCaptureActive = false
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
        neonPrimaryWidthRatio = settings.neonPrimaryWidthRatio
        waterHighlightColor = settings.waterHighlightColor
        waterPrimaryColor = settings.waterPrimaryColor
        waterShadowColor = settings.waterShadowColor
        waterHighlightRatio = settings.waterHighlightRatio
        waterPrimaryRatio = settings.waterPrimaryRatio
        waterShadowRatio = settings.waterShadowRatio
        waterMixRandomness = settings.waterMixRandomness
        waterMixSeedLocked = settings.waterMixSeedLocked
        waterSplashSize = settings.waterSplashSize
        waterSplashSpeed = settings.waterSplashSpeed
        waterSplashLifetimeSeconds = settings.waterSplashLifetimeMilliseconds / 1000
        waterSplashDensity = settings.waterSplashDensity
        waterSplashColor = settings.waterSplashColor
        trailLineWidth = settings.trailWidth
        trailLengthMilliseconds = settings.trailLengthMilliseconds
        clickVisualStyle = settings.clickVisualStyle
        clickEffectRadius = settings.clickEffectRadius
        clickEffectDurationSeconds = settings.clickEffectDurationMilliseconds / 1000
        waterImpactDropletDensity = settings.waterImpactDropletDensity
        waterImpactSpreadSpeed = settings.waterImpactSpreadSpeed
        waterImpactLifetimeSeconds = settings.waterImpactLifetimeMilliseconds / 1000
        waterImpactDropletSize = settings.waterImpactDropletSize
        clickParticleExplosionDensity = settings.clickParticleExplosionDensity
        clickParticleExplosionSize = settings.clickParticleExplosionSize
        clickParticleExplosionLifetimeSeconds = settings.clickParticleExplosionLifetimeMilliseconds / 1000
        clickParticleExplosionSpeed = settings.clickParticleExplosionSpeed
        clickParticleExplosionColors = settings.clickParticleExplosionColors
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
        isTrailEffectsEnabled = settings.isTrailEffectsEnabled
        disableTrailFadeAndForceSolid = settings.disableTrailFadeAndForceSolid
        colorFadeDisabledKeys = settings.colorFadeDisabledKeys
        electricArcDensity = settings.electricArcDensity
        electricArcLength = settings.electricArcLength
        electricArcWidth = settings.electricArcWidth
        inkDensity = settings.inkDensity
        inkSize = settings.inkSize
        inkLifetimeSeconds = settings.inkLifetimeMilliseconds / 1000
        inkColors = settings.inkColors
        particleDensity = settings.particleDensity
        particleSize = settings.particleSize
        particleLifetimeSeconds = settings.particleLifetimeMilliseconds / 1000
        particleSpeed = settings.particleSpeed
        particleColors = settings.particleColors
        speedBurstEnabled = settings.speedBurstEnabled
        speedBurstType = settings.speedBurstType
        speedBurstVelocityThreshold = settings.speedBurstVelocityThreshold
        speedBurstCooldownSeconds = settings.speedBurstCooldownMilliseconds / 1000
        speedBurstDurationSeconds = settings.speedBurstDurationMilliseconds / 1000
        speedBurstDurationMinSeconds = settings.speedBurstDurationMinMilliseconds / 1000
        speedBurstDurationMaxSeconds = max(
            settings.speedBurstDurationMinMilliseconds,
            settings.speedBurstDurationMaxMilliseconds
        ) / 1000
        speedBurstJitterAmplitude = settings.speedBurstJitterAmplitude
        speedBurstMinLength = settings.speedBurstMinLength
        speedBurstMaxLength = max(settings.speedBurstMinLength, settings.speedBurstMaxLength)
        speedBurstWidthMultiplier = settings.speedBurstWidthMultiplier
        speedBurstTrailMinScale = settings.speedBurstTrailMinScale
        speedBurstTrailMaxScale = max(settings.speedBurstTrailMinScale, settings.speedBurstTrailMaxScale)
        speedBurstEffectMinScale = settings.speedBurstEffectMinScale
        speedBurstEffectMaxScale = max(settings.speedBurstEffectMinScale, settings.speedBurstEffectMaxScale)
        speedSurgeScaleMode = settings.speedSurgeScaleMode
        speedBurstLineColor = settings.speedBurstLineColor
        speedBurstAccentColor = settings.speedBurstAccentColor
        speedBurstAccentDurationSeconds = settings.speedBurstAccentDurationMilliseconds / 1000
        speedBurstAccentSize = settings.speedBurstAccentSize
        if !speedBurstEnabled || speedBurstType != .waterSurge {
            activeWaterSurge = nil
        }
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
            clickExplosionParticles.removeAll()
            clickAccents.removeAll()
            waterImpactDroplets.removeAll()
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
            let surgeScale = currentWaterSurgeScales(at: signal.timestamp, velocity: velocity)
            lastAcceptedMoveTimestamp = signal.timestamp
            if isPersistentTrailCaptureActive {
                appendPersistentTrailPoint(localPoint)
            } else {
                movePoints.append(MovePoint(point: localPoint, timestamp: signal.timestamp, trailScale: surgeScale.trail))
                if movePoints.count > maxMoveCount {
                    movePoints.removeFirst(movePoints.count - maxMoveCount)
                }
            }
            emitTrailEffects(
                from: lastMovePoint ?? localPoint,
                to: localPoint,
                timestamp: signal.timestamp,
                effectScale: surgeScale.effect
            )
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
            drawPersistentTrails(now: now)
            drawMoveTrail(now: now)
            drawDashBursts(now: now)
        }
        if canRenderOverlays && isTrailEffectsEnabled {
            drawParticles(now: now)
        }
        if canRenderOverlays && isClickEffectsEnabled {
            drawPulses(now: now)
            drawPressedState()
            drawClickExplosionParticles(now: now)
        }
        if canRenderOverlays {
            drawWaterImpactDroplets(now: now)
        }
        if canRenderOverlays {
            drawClickAccents(now: now)
        }
        drawMagnifier()
    }

    private func drawPersistentTrails(now: CFTimeInterval) {
        for stroke in persistentTrailStrokes {
            let samples = makePersistentTrailSamples(from: stroke)
            guard samples.count > 1 else { continue }
            drawTrailSamples(samples, now: now, includeElectricCoverage: false)
        }
    }

    private func drawMoveTrail(now: CFTimeInterval) {
        let samples = makeInterpolatedTrailSamples(now: now)
        guard samples.count > 1 else { return }
        drawTrailSamples(samples, now: now, includeElectricCoverage: true)
    }

    private func drawTrailSamples(_ samples: [TrailSample], now: CFTimeInterval, includeElectricCoverage: Bool) {
        switch trailStyle {
        case .ribbon:
            drawRibbonLikeTrail(samples: samples, now: now, style: .ribbon)
        case .neon:
            drawRibbonLikeTrail(samples: samples, now: now, style: .neon)
        case .rainbow:
            drawRibbonLikeTrail(samples: samples, now: now, style: .rainbow)
        case .lightning:
            drawLightningTrail(samples: samples, now: now)
        case .waterBlade:
            drawWaterBladeTrail(samples: samples, now: now)
        }
        if includeElectricCoverage, trailEffectStyle == .electric, isTrailEffectsEnabled {
            drawElectricTrailCoverage(samples: samples, now: now)
        }
    }

    private func drawRibbonLikeTrail(
        samples: [TrailSample],
        now: CFTimeInterval,
        style: TrailRenderStyle
    ) {
        guard samples.count > 3 else { return }

        let total = max(1, samples.count - 1)
        let styleFadeKey = trailColorFadeKey(for: style)
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
            let baseWidth: CGFloat = switch style {
            case .ribbon:
                max(0.42, trailLineWidth * (0.14 + 1.04 * pow(progress, 0.82)))
            case .neon:
                max(0.46, trailLineWidth * (0.18 + 1.16 * pow(progress, 0.82)))
            case .rainbow:
                max(0.44, trailLineWidth * (0.16 + 1.1 * pow(progress, 0.82)))
            case .lightning:
                max(0.4, trailLineWidth * (0.12 + 1.0 * pow(progress, 0.8)))
            case .waterBlade:
                max(0.44, trailLineWidth * (0.15 + 1.06 * pow(progress, 0.82)))
            }
            let segmentScale = max(0.1, (previous.trailScale + current.trailScale + next.trailScale) / 3.0)
            let width: CGFloat = baseWidth * segmentScale
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
            case .waterBlade:
                trailColor
            }
            resolvedAlphaColor(glowColor, opacity: (style == .neon ? 0.16 : 0.08) * segmentAlpha, fadeKey: styleFadeKey).setStroke()
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
            case .waterBlade:
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
            case .waterBlade:
                0.8 * segmentAlpha
            }
            if style == .neon {
                let ratio = max(0.1, min(0.9, neonPrimaryWidthRatio / 100))
                let secondaryPath = curve.copy() as! NSBezierPath
                secondaryPath.lineWidth = width
                let neonSecondary = neonSecondaryColor.blended(withFraction: 0.12 + 0.18 * progress, of: .white) ?? neonSecondaryColor
                resolvedAlphaColor(neonSecondary, opacity: 0.58 * segmentAlpha, fadeKey: styleFadeKey).setStroke()
                secondaryPath.stroke()

                let primaryPath = curve.copy() as! NSBezierPath
                primaryPath.lineWidth = max(0.26, width * ratio)
                resolvedAlphaColor(coreColor, opacity: coreAlpha, fadeKey: styleFadeKey).setStroke()
                primaryPath.stroke()
            } else {
                resolvedAlphaColor(coreColor, opacity: coreAlpha, fadeKey: styleFadeKey).setStroke()
                curve.stroke()
            }

            if style == .neon {
                let highlight = curve.copy() as! NSBezierPath
                let ratio = max(0.1, min(0.9, neonPrimaryWidthRatio / 100))
                highlight.lineWidth = max(0.22, width * max(0.18, ratio * 0.56))
                let highlightColor = (neonPrimaryColor.blended(withFraction: 0.35, of: .white) ?? neonPrimaryColor)
                resolvedAlphaColor(highlightColor, opacity: 0.32 * segmentAlpha, fadeKey: styleFadeKey).setStroke()
                highlight.stroke()
            }
        }
    }

    private func drawLightningTrail(samples: [TrailSample], now _: CFTimeInterval) {
        guard samples.count > 1 else { return }
        for index in 1..<samples.count {
            let first = samples[index - 1]
            let second = samples[index]
            let alpha = min(first.alpha, second.alpha)
            if alpha <= 0.001 { continue }

            let distance = hypot(second.point.x - first.point.x, second.point.y - first.point.y)
            guard distance >= 0.2 else { continue }

            let progress = CGFloat(index) / CGFloat(max(1, samples.count - 1))
            let segmentScale = max(0.1, (first.trailScale + second.trailScale) * 0.5)
            let lineWidth = max(0.6, trailLineWidth * (0.22 + 0.88 * pow(progress, 0.8)) * 0.92 * segmentScale)

            let lightningPath = makeLightningPath(from: first.point, to: second.point)
            lightningPath.lineWidth = lineWidth
            lightningPath.lineCapStyle = .butt
            lightningPath.lineJoinStyle = .round
            resolvedAlphaColor(
                trailColor.blended(withFraction: 0.45, of: .white) ?? trailColor,
                opacity: 0.95 * alpha,
                fadeKey: ColorFadeSettingKey.trailColor
            ).setStroke()
            lightningPath.stroke()

            if second.index % 10 == 0 {
                let branch = makeLightningBranch(from: second.point)
                branch.lineWidth = max(0.6, lineWidth * 0.75)
                resolvedAlphaColor(trailColor, opacity: 0.45 * alpha, fadeKey: ColorFadeSettingKey.trailColor).setStroke()
                branch.stroke()
            }
        }
    }

    private func drawWaterBladeTrail(samples: [TrailSample], now: CFTimeInterval) {
        let nodes = makeWaterRibbonNodes(samples: samples)
        guard nodes.count > 3 else { return }
        let ratios = normalizedWaterRatios()
        let randomness = max(0, min(1, waterMixRandomness / 100))
        let phaseSeed = waterMixSeedLocked ? 0 : Int(now * 24)
        let baseMixedColor = weightedWaterColor(
            highlightWeight: ratios.highlight,
            primaryWeight: ratios.primary,
            shadowWeight: ratios.shadow
        )
        let bandSpan = max(3, Int(round(12 - randomness * 8)))

        for index in 1..<nodes.count {
            let previous = nodes[index - 1]
            let current = nodes[index]
            let alpha = min(previous.alpha, current.alpha)
            if alpha < 0.01 { continue }
            let progress = current.progress
            let segmentAlpha = alpha * (0.1 + 0.9 * progress)
            let taper = 0.2 + 0.8 * pow(max(0.001, progress), 0.72)
            let curveBoost = 1 + current.curveStrength * 0.52
            let segmentScale = max(0.1, (previous.trailScale + current.trailScale) * 0.5)
            let baseHalfWidth = max(0.85, trailLineWidth * (0.34 + 2.18 * taper) * curveBoost * segmentScale)
            let waveOffsetStart = waterWaveOffset(
                index: index - 1,
                progress: previous.progress,
                randomness: randomness,
                phaseSeed: phaseSeed,
                trailScale: previous.trailScale
            )
            let waveOffsetEnd = waterWaveOffset(
                index: index,
                progress: current.progress,
                randomness: randomness,
                phaseSeed: phaseSeed,
                trailScale: current.trailScale
            )
            let startPoint = offset(previous.point, by: previous.normal, amount: waveOffsetStart)
            let endPoint = offset(current.point, by: current.normal, amount: waveOffsetEnd)

            let paletteColor = waterBladeSegmentColor(
                sampleIndex: index / bandSpan,
                phaseSeed: phaseSeed,
                baseColor: baseMixedColor,
                highlightWeight: ratios.highlight,
                primaryWeight: ratios.primary,
                randomness: randomness
            )
            let shadowColor = waterShadowColor.blended(withFraction: 0.22 + randomness * 0.3, of: paletteColor) ?? waterShadowColor
            let primaryColor = waterPrimaryColor.blended(withFraction: 0.3 + randomness * 0.5, of: paletteColor) ?? waterPrimaryColor
            let highlightColor = waterHighlightColor.blended(
                withFraction: 0.24 + randomness * 0.36,
                of: paletteColor.blended(withFraction: 0.22, of: .white) ?? paletteColor
            ) ?? waterHighlightColor
            let glowColor = (primaryColor.blended(withFraction: 0.42, of: .white) ?? primaryColor)

            let shadowHalfWidthStart = baseHalfWidth * (0.86 + ratios.shadow * 0.72)
            let shadowHalfWidthEnd = shadowHalfWidthStart * (0.95 + current.curveStrength * 0.1)
            let primaryHalfWidthStart = baseHalfWidth * (0.56 + ratios.primary * 0.64)
            let primaryHalfWidthEnd = primaryHalfWidthStart * (0.94 + current.curveStrength * 0.08)
            let highlightHalfWidthStart = baseHalfWidth * (0.28 + ratios.highlight * 0.54)
            let highlightHalfWidthEnd = highlightHalfWidthStart * (0.92 + current.curveStrength * 0.08)

            drawWaterRibbonQuad(
                start: startPoint,
                end: endPoint,
                startNormal: previous.normal,
                endNormal: current.normal,
                centerOffsetStart: 0,
                centerOffsetEnd: 0,
                halfWidthStart: shadowHalfWidthStart * 1.35,
                halfWidthEnd: shadowHalfWidthEnd * 1.35,
                color: glowColor,
                fadeKey: ColorFadeSettingKey.trailWaterColors,
                alpha: 0.09 * segmentAlpha * effectGlowBoost
            )

            drawWaterRibbonQuad(
                start: startPoint,
                end: endPoint,
                startNormal: previous.normal,
                endNormal: current.normal,
                centerOffsetStart: 0,
                centerOffsetEnd: 0,
                halfWidthStart: shadowHalfWidthStart,
                halfWidthEnd: shadowHalfWidthEnd,
                color: shadowColor,
                fadeKey: ColorFadeSettingKey.trailWaterColors,
                alpha: 0.48 * segmentAlpha
            )

            drawWaterRibbonQuad(
                start: startPoint,
                end: endPoint,
                startNormal: previous.normal,
                endNormal: current.normal,
                centerOffsetStart: 0,
                centerOffsetEnd: 0,
                halfWidthStart: primaryHalfWidthStart,
                halfWidthEnd: primaryHalfWidthEnd,
                color: primaryColor,
                fadeKey: ColorFadeSettingKey.trailWaterColors,
                alpha: 0.85 * segmentAlpha
            )

            let highlightOffset = current.curveSign * baseHalfWidth * (0.18 + current.curveStrength * 0.36)
            drawWaterRibbonQuad(
                start: startPoint,
                end: endPoint,
                startNormal: previous.normal,
                endNormal: current.normal,
                centerOffsetStart: highlightOffset * 0.86,
                centerOffsetEnd: highlightOffset,
                halfWidthStart: highlightHalfWidthStart,
                halfWidthEnd: highlightHalfWidthEnd,
                color: highlightColor,
                fadeKey: ColorFadeSettingKey.trailWaterColors,
                alpha: 0.9 * segmentAlpha
            )

            let sideBandHalfWidth = max(0.36, baseHalfWidth * (0.08 + randomness * 0.1))
            let sideBandOffset = baseHalfWidth * (0.82 + randomness * 0.14)
            let sideBandColorA = primaryColor.blended(withFraction: 0.58, of: waterHighlightColor) ?? primaryColor
            let sideBandColorB = primaryColor.blended(withFraction: 0.36, of: waterShadowColor) ?? primaryColor
            drawWaterRibbonQuad(
                start: startPoint,
                end: endPoint,
                startNormal: previous.normal,
                endNormal: current.normal,
                centerOffsetStart: sideBandOffset,
                centerOffsetEnd: sideBandOffset * 0.96,
                halfWidthStart: sideBandHalfWidth,
                halfWidthEnd: sideBandHalfWidth * 0.92,
                color: sideBandColorA,
                fadeKey: ColorFadeSettingKey.trailWaterColors,
                alpha: 0.36 * segmentAlpha
            )
            drawWaterRibbonQuad(
                start: startPoint,
                end: endPoint,
                startNormal: previous.normal,
                endNormal: current.normal,
                centerOffsetStart: -sideBandOffset,
                centerOffsetEnd: -sideBandOffset * 0.96,
                halfWidthStart: sideBandHalfWidth,
                halfWidthEnd: sideBandHalfWidth * 0.92,
                color: sideBandColorB,
                fadeKey: ColorFadeSettingKey.trailWaterColors,
                alpha: 0.31 * segmentAlpha
            )
        }
    }

    private func drawElectricTrailCoverage(samples: [TrailSample], now: CFTimeInterval) {
        guard samples.count > 6 else { return }

        let coverageFactor = max(0.2, pow(max(0.1, electricArcDensity), 0.95))
        let targetArcCount = max(8, min(160, Int(CGFloat(samples.count) * 0.2 * coverageFactor)))
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
            let baseArcLength = max(2.0, electricArcLength)
            let segmentLength = max(2.0, (baseArcLength * (0.44 + rand3 * 0.72)) * (0.55 + alpha * 0.55))

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
            arc.lineWidth = max(0.45, electricArcWidth * (0.72 + alpha * 0.46))

            let color = trailEffectColor.blended(withFraction: 0.56, of: .white) ?? trailEffectColor
            let glow = arc.copy() as! NSBezierPath
            glow.lineWidth = arc.lineWidth * 2.1
            resolvedAlphaColor(color, opacity: 0.14 * alpha * effectGlowBoost, fadeKey: ColorFadeSettingKey.trailEffectColor).setStroke()
            glow.stroke()

            resolvedAlphaColor(color, opacity: 0.78 * alpha, fadeKey: ColorFadeSettingKey.trailEffectColor).setStroke()
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
            resolvedAlphaColor(burst.coreColor, opacity: 0.22 * alpha * effectGlowBoost, fadeKey: burst.fadeKey).setStroke()
            glowPath.stroke()

            let corePath = makeThunderDashPath(
                from: burst.start,
                to: burst.end,
                jitter: speedBurstJitterAmplitude * 0.48 * (1 - progress)
            )
            corePath.lineWidth = burst.lineWidth
            corePath.lineCapStyle = .round
            corePath.lineJoinStyle = .round
            resolvedAlphaColor(burst.coreColor, opacity: 0.94 * alpha, fadeKey: burst.fadeKey).setStroke()
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

    private func thunderDashVelocityThreshold() -> CGFloat {
        speedBurstVelocityThreshold
    }

    private func currentWaterSurgeScales(
        at timestamp: CFTimeInterval,
        velocity: CGFloat
    ) -> (trail: CGFloat, effect: CGFloat) {
        guard speedBurstEnabled else { return (1, 1) }
        guard speedBurstType == .waterSurge else { return (1, 1) }
        guard let surge = activeWaterSurge else { return (1, 1) }
        if timestamp >= surge.endTimestamp {
            activeWaterSurge = nil
            return (1, 1)
        }

        let trailScale: CGFloat
        let effectScale: CGFloat
        switch speedSurgeScaleMode {
        case .randomRange:
            trailScale = surge.randomTrailScale
            effectScale = surge.randomEffectScale
        case .velocityBased:
            let minVelocity = max(1, thunderDashVelocityThreshold())
            let maxVelocity = max(minVelocity + 1, speedBurstVelocityThreshold * 3.2)
            let normalizedVelocity = max(0, min(1, (velocity - minVelocity) / (maxVelocity - minVelocity)))
            let easedVelocity = pow(normalizedVelocity, 0.72)
            trailScale = speedBurstTrailMinScale + (speedBurstTrailMaxScale - speedBurstTrailMinScale) * easedVelocity
            effectScale = speedBurstEffectMinScale + (speedBurstEffectMaxScale - speedBurstEffectMinScale) * easedVelocity
        }

        return (
            max(0.1, min(speedBurstTrailMaxScale, trailScale)),
            max(0.1, min(speedBurstEffectMaxScale, effectScale))
        )
    }

    /// 按速度阈值触发加速爆发。
    /// - Important: 受 `speedBurstEnabled`、冷却时间与强度预设共同约束。
    private func emitThunderDashIfNeeded(from start: NSPoint, to end: NSPoint, velocity: CGFloat, timestamp: CFTimeInterval) {
        guard isTrailEnabled else { return }
        guard speedBurstEnabled else { return }
        guard velocity >= thunderDashVelocityThreshold() else { return }
        guard timestamp - lastDashBurstTimestamp >= speedBurstCooldownSeconds else { return }

        switch speedBurstType {
        case .firstFlash:
            emitFirstFlashBurst(from: start, to: end, velocity: velocity, timestamp: timestamp)
        case .waterSurge:
            activateWaterSurge(at: end, velocity: velocity, timestamp: timestamp)
        }
    }

    private func emitFirstFlashBurst(from start: NSPoint, to end: NSPoint, velocity: CGFloat, timestamp: CFTimeInterval) {
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
                fadeKey: ColorFadeSettingKey.speedBurstLineColor,
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
            fadeKey: ColorFadeSettingKey.speedBurstAccentColor,
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
                fadeKey: ColorFadeSettingKey.speedBurstAccentColor,
                radius: accentSize,
                kind: .cross,
                lifetime: accentLifetime,
                timestamp: timestamp
            )
        )
        AppLogger.shared.log("thunder dash burst emitted: velocity=\(Int(velocity)) px/s")
    }

    private func activateWaterSurge(at point: NSPoint, velocity: CGFloat, timestamp: CFTimeInterval) {
        lastDashBurstTimestamp = timestamp
        let minDuration = max(0.04, min(speedBurstDurationMinSeconds, speedBurstDurationMaxSeconds))
        let maxDuration = max(minDuration, speedBurstDurationMaxSeconds)
        let duration = CFTimeInterval.random(in: minDuration...maxDuration)
        let randomTrailScale = CGFloat.random(in: speedBurstTrailMinScale...max(speedBurstTrailMinScale, speedBurstTrailMaxScale))
        let randomEffectScale = CGFloat.random(in: speedBurstEffectMinScale...max(speedBurstEffectMinScale, speedBurstEffectMaxScale))
        activeWaterSurge = ActiveWaterSurge(
            endTimestamp: timestamp + duration,
            randomTrailScale: randomTrailScale,
            randomEffectScale: randomEffectScale
        )

        let currentScale = switch speedSurgeScaleMode {
        case .randomRange:
            max(randomTrailScale, randomEffectScale)
        case .velocityBased:
            max(speedBurstTrailMaxScale, speedBurstEffectMaxScale)
        }
        AppLogger.shared.log(
            "water surge activated: mode=\(speedSurgeScaleMode.rawValue), velocity=\(Int(velocity)) px/s, duration=\(Int(duration * 1000)) ms, scale=\(rounded(Double(currentScale)))x"
        )
    }

    private func emitThunderDashParticles(
        start: NSPoint,
        end: NSPoint,
        timestamp: CFTimeInterval,
        coreColor: NSColor
    ) {
        guard isTrailEffectsEnabled else { return }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = max(0.001, hypot(dx, dy))
        let directionX = dx / distance
        let directionY = dy / distance
        let burstCount = max(16, min(44, Int(24 * effectSpawnMultiplier)))
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
            let speed = CGFloat.random(in: effectParticleSpeedRange.upperBound * 1.3 ... effectParticleSpeedRange.upperBound * 2.4)
            let colorPick = CGFloat.random(in: 0...1)
            let color: NSColor
            let fadeKey: String
            if colorPick < 0.72 {
                color = coreColor
                fadeKey = ColorFadeSettingKey.speedBurstLineColor
            } else {
                color = trailEffectColor.blended(withFraction: 0.45, of: colorFromHexRGB(0xFFFDF5)) ?? trailEffectColor
                fadeKey = ColorFadeSettingKey.trailEffectColor
            }
            particles.append(
                Particle(
                    point: origin,
                    velocity: CGVector(dx: rotatedX * speed, dy: rotatedY * speed),
                    size: CGFloat.random(in: 1.1...3.0),
                    color: color,
                    fadeKey: fadeKey,
                    lifetime: CFTimeInterval(CGFloat.random(in: 0.08...0.2)),
                    timestamp: timestamp
                )
            )
        }
    }

    private func beginPersistentTrailStrokeIfNeeded() {
        if persistentTrailStrokes.last?.points.isEmpty == true {
            return
        }
        var initialPoints: [NSPoint] = []
        if let cursorPoint {
            initialPoints.append(cursorPoint)
        }
        persistentTrailStrokes.append(PersistentTrailStroke(points: initialPoints))
        prunePersistentTrailStrokesIfNeeded()
    }

    private func appendPersistentTrailPoint(_ point: NSPoint) {
        if persistentTrailStrokes.isEmpty {
            beginPersistentTrailStrokeIfNeeded()
        }
        guard !persistentTrailStrokes.isEmpty else { return }
        let lastIndex = persistentTrailStrokes.count - 1
        if let lastPoint = persistentTrailStrokes[lastIndex].points.last {
            let distance = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
            if distance < minimumMoveDistance {
                return
            }
        }
        persistentTrailStrokes[lastIndex].points.append(point)
        if persistentTrailStrokes[lastIndex].points.count > maxPersistentPointsPerStroke {
            persistentTrailStrokes[lastIndex].points.removeFirst(
                persistentTrailStrokes[lastIndex].points.count - maxPersistentPointsPerStroke
            )
        }
    }

    private func prunePersistentTrailStrokesIfNeeded() {
        if persistentTrailStrokes.count > maxPersistentStrokeCount {
            persistentTrailStrokes.removeFirst(persistentTrailStrokes.count - maxPersistentStrokeCount)
        }
    }

    private func pruneTrailingEmptyPersistentStroke() {
        while let last = persistentTrailStrokes.last, last.points.count < 2 {
            persistentTrailStrokes.removeLast()
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
                let trailScale = first.trailScale + (second.trailScale - first.trailScale) * fraction
                samples.append(TrailSample(point: point, alpha: alpha, index: sampleIndex, trailScale: trailScale))
                sampleIndex += 1
            }
        }

        if samples.count > maxSamples {
            return Array(samples.suffix(maxSamples))
        }
        return samples
    }

    private func makePersistentTrailSamples(from stroke: PersistentTrailStroke) -> [TrailSample] {
        guard stroke.points.count > 1 else { return [] }
        var samples: [TrailSample] = []
        samples.reserveCapacity(min(maxPersistentSamplesPerStroke, stroke.points.count * 3))
        var sampleIndex = 0

        for segment in 1..<stroke.points.count {
            let first = stroke.points[segment - 1]
            let second = stroke.points[segment]
            let dx = second.x - first.x
            let dy = second.y - first.y
            let distance = hypot(dx, dy)
            let interpolationSteps = max(1, min(12, Int(ceil(distance / 5.0))))

            for step in 0...interpolationSteps {
                if segment > 1 && step == 0 { continue }
                let fraction = CGFloat(step) / CGFloat(interpolationSteps)
                let point = NSPoint(
                    x: first.x + dx * fraction,
                    y: first.y + dy * fraction
                )
                samples.append(TrailSample(point: point, alpha: 1, index: sampleIndex, trailScale: 1))
                sampleIndex += 1
            }
        }

        if samples.count > maxPersistentSamplesPerStroke {
            return Array(samples.suffix(maxPersistentSamplesPerStroke))
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
                            resolvedAlphaColor(pulse.color, opacity: 0.35 * alpha * effectGlowBoost, fadeKey: pulse.fadeKey),
                            resolvedAlphaColor(pulse.color, opacity: 0.06 * alpha, fadeKey: pulse.fadeKey),
                            .clear,
                        ]
                    )
                    gradient?.draw(in: path, relativeCenterPosition: .zero)
                    resolvedAlphaColor(pulse.color, opacity: 0.42 * alpha, fadeKey: pulse.fadeKey).setFill()
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
                    resolvedAlphaColor(pulse.color, opacity: 0.95 * alpha, fadeKey: pulse.fadeKey).setStroke()
                    path.stroke()
                    let gradient = NSGradient(
                        colors: [
                            resolvedAlphaColor(pulse.color, opacity: 0.28 * alpha * effectGlowBoost, fadeKey: pulse.fadeKey),
                            resolvedAlphaColor(pulse.color, opacity: 0.05 * alpha, fadeKey: pulse.fadeKey),
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
                resolvedAlphaColor(pulse.color, opacity: 0.95 * alpha, fadeKey: pulse.fadeKey).setStroke()
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
                if trailStyle == .waterBlade {
                    let length = particle.size * (2.2 + progress * 2.6)
                    let velocityLength = max(0.0001, hypot(particle.velocity.dx, particle.velocity.dy))
                    let dirX = particle.velocity.dx / velocityLength
                    let dirY = particle.velocity.dy / velocityLength
                    let start = NSPoint(x: x - dirX * length * 0.4, y: y - dirY * length * 0.4)
                    let end = NSPoint(x: x + dirX * length * 0.6, y: y + dirY * length * 0.6)
                    let streak = NSBezierPath()
                    streak.move(to: start)
                    streak.line(to: end)
                    streak.lineWidth = max(0.7, particle.size * 0.7)
                    streak.lineCapStyle = .round
                    let streakColor = particle.color.blended(withFraction: 0.38, of: .white) ?? particle.color
                    resolvedAlphaColor(streakColor, opacity: 0.66 * alpha, fadeKey: particle.fadeKey).setStroke()
                    streak.stroke()
                } else {
                    let radius = particle.size * (1 + progress * 0.45)
                    let rect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    let path = NSBezierPath(ovalIn: rect)
                    let gradient = NSGradient(
                        colors: [
                            resolvedAlphaColor(particle.color, opacity: 0.48 * alpha, fadeKey: particle.fadeKey),
                            resolvedAlphaColor(particle.color, opacity: 0.16 * alpha, fadeKey: particle.fadeKey),
                            .clear,
                        ]
                    )
                    gradient?.draw(in: path, relativeCenterPosition: .zero)
                }
            case .ink:
                let radius = particle.size * (1.2 + progress * 0.25)
                let rect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                let blob = NSBezierPath(ovalIn: rect)
                resolvedAlphaColor(particle.color, opacity: 0.2 * alpha, fadeKey: particle.fadeKey).setFill()
                blob.fill()
            case .electric:
                let arcJitter = max(1.4, electricArcLength * 0.22)
                let endX = x + CGFloat.random(in: -arcJitter...arcJitter)
                let endY = y + CGFloat.random(in: -arcJitter...arcJitter)
                let spark = NSBezierPath()
                spark.move(to: NSPoint(x: x, y: y))
                spark.line(to: NSPoint(x: endX, y: endY))
                spark.lineWidth = max(0.4, particle.size * 0.44 + electricArcWidth * 0.42)
                spark.lineCapStyle = .round
                resolvedAlphaColor(
                    particle.color.blended(withFraction: 0.45, of: .white) ?? particle.color,
                    opacity: 0.9 * alpha,
                    fadeKey: particle.fadeKey
                ).setStroke()
                spark.stroke()
            case .waterSplash:
                let velocityLength = max(0.0001, hypot(particle.velocity.dx, particle.velocity.dy))
                let directionAngle = atan2(particle.velocity.dy, particle.velocity.dx)
                let speedFactor = min(1.7, velocityLength / 120)
                let elongation = 1 + speedFactor * (0.25 + (1 - progress) * 0.9)
                let baseRadius = max(0.9, particle.size * (0.68 + progress * 0.38))
                let seed = particleShapeSeed(point: particle.point, timestamp: particle.timestamp)
                let blobPath = makeIrregularBlobPath(
                    center: NSPoint(x: x, y: y),
                    baseRadius: baseRadius,
                    seed: seed,
                    elongation: elongation,
                    rotation: directionAngle
                )
                let baseSplashColor = waterSplashColor.blended(withFraction: 0.42, of: particle.color) ?? particle.color
                let fillColor = baseSplashColor.blended(withFraction: 0.4, of: .white) ?? baseSplashColor
                resolvedAlphaColor(fillColor, opacity: 0.78 * alpha, fadeKey: particle.fadeKey).setFill()
                blobPath.fill()

                let outlineColor = waterShadowColor.blended(withFraction: 0.32, of: .black) ?? waterShadowColor
                blobPath.lineWidth = max(0.35, baseRadius * 0.18)
                resolvedAlphaColor(outlineColor, opacity: 0.45 * alpha, fadeKey: particle.fadeKey).setStroke()
                blobPath.stroke()
            }
        }
    }

    private func drawPressedState() {
        guard let cursorPoint else { return }
        guard pressedButton != .none else { return }
        if clickVisualStyle == .particleExplosion {
            return
        }
        let style = effectStyle(for: pressedButton)
        guard style.isEnabled else { return }
        let stateColor = style.color

        let radius: CGFloat = if clickVisualStyle == .waterImpact {
            max(6, trailLineWidth * (1.9 + max(0.1, waterImpactSpreadSpeed) * 1.8))
        } else {
            clickEffectRadius * 0.45
        }
        let rect = NSRect(
            x: cursorPoint.x - radius,
            y: cursorPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let path = NSBezierPath(ovalIn: rect)
        resolvedAlphaColor(stateColor, opacity: 0.22, fadeKey: clickColorFadeKey(for: pressedButton)).setFill()
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
                resolvedAlphaColor(accent.color, opacity: 0.9 * alpha, fadeKey: accent.fadeKey).setStroke()
                path.stroke()
            }
        }
    }

    private func drawClickExplosionParticles(now: CFTimeInterval) {
        guard !clickExplosionParticles.isEmpty else { return }
        for particle in clickExplosionParticles {
            let age = now - particle.timestamp
            if age < 0 || age > particle.lifetime { continue }
            let progress = CGFloat(age / particle.lifetime)
            let alpha = max(0, 1 - progress)
            let x = particle.point.x + particle.velocity.dx * CGFloat(age)
            let y = particle.point.y + particle.velocity.dy * CGFloat(age) - 18 * CGFloat(age * age)
            let velocityLength = max(0.0001, hypot(particle.velocity.dx, particle.velocity.dy))
            let dirX = particle.velocity.dx / velocityLength
            let dirY = particle.velocity.dy / velocityLength
            let streakLength = particle.size * (2.0 + (1 - progress) * 2.2)
            let start = NSPoint(x: x - dirX * streakLength * 0.35, y: y - dirY * streakLength * 0.35)
            let end = NSPoint(x: x + dirX * streakLength * 0.65, y: y + dirY * streakLength * 0.65)

            let streak = NSBezierPath()
            streak.move(to: start)
            streak.line(to: end)
            streak.lineCapStyle = .round
            streak.lineWidth = max(0.7, particle.size * 0.7)
            let streakColor = particle.color.blended(withFraction: 0.4, of: .white) ?? particle.color
            resolvedAlphaColor(streakColor, opacity: 0.82 * alpha, fadeKey: particle.fadeKey).setStroke()
            streak.stroke()

            let radius = particle.size * (0.8 + progress * 0.55)
            let rect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            let core = NSBezierPath(ovalIn: rect)
            let gradient = NSGradient(
                colors: [
                    resolvedAlphaColor(particle.color, opacity: 0.52 * alpha, fadeKey: particle.fadeKey),
                    resolvedAlphaColor(particle.color, opacity: 0.16 * alpha, fadeKey: particle.fadeKey),
                    .clear,
                ]
            )
            gradient?.draw(in: core, relativeCenterPosition: .zero)
        }
    }

    private func drawWaterImpactDroplets(now: CFTimeInterval) {
        guard !waterImpactDroplets.isEmpty else { return }
        for droplet in waterImpactDroplets {
            let age = now - droplet.timestamp
            if age < 0 || age > droplet.lifetime { continue }
            let progress = CGFloat(age / droplet.lifetime)
            let alpha = max(0, 1 - progress)
            let x = droplet.point.x + droplet.velocity.dx * CGFloat(age)
            let y = droplet.point.y + droplet.velocity.dy * CGFloat(age) - 20 * CGFloat(age * age)
            let direction = atan2(droplet.velocity.dy, droplet.velocity.dx)
            let speed = hypot(droplet.velocity.dx, droplet.velocity.dy)
            let elongation = 1 + min(1.5, speed / 140) * (0.2 + (1 - progress) * 0.95)
            let sizeExpansion = 1 + min(0.28, CGFloat(age) * 0.22)
            let baseRadius = max(0.8, droplet.size * sizeExpansion)
            let blobPath = makeIrregularBlobPath(
                center: NSPoint(x: x, y: y),
                baseRadius: baseRadius,
                seed: droplet.seed,
                elongation: elongation,
                rotation: direction
            )
            let fillColor = droplet.color.blended(withFraction: 0.42, of: .white) ?? droplet.color
            resolvedAlphaColor(fillColor, opacity: 0.86 * alpha, fadeKey: droplet.fadeKey).setFill()
            blobPath.fill()
            blobPath.lineWidth = max(0.4, baseRadius * 0.2)
            let strokeColor = waterShadowColor.blended(withFraction: 0.3, of: .black) ?? waterShadowColor
            resolvedAlphaColor(strokeColor, opacity: 0.5 * alpha, fadeKey: droplet.fadeKey).setStroke()
            blobPath.stroke()
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
        resolvedAlphaColor(magnifierBorderColor, opacity: 0.96, applyTrailFadeRule: false).setStroke()
        borderPath.stroke()

        let outerInset = max(1.5, magnifierBorderWidth * 0.8)
        let outerPath = NSBezierPath(ovalIn: circleRect.insetBy(dx: -outerInset, dy: -outerInset))
        outerPath.lineWidth = max(1, magnifierBorderWidth * 0.66)
        NSColor.black.withAlphaComponent(magnifierShadowOpacity).setStroke()
        outerPath.stroke()

        let innerPath = NSBezierPath(ovalIn: circleRect.insetBy(dx: max(0.8, magnifierBorderWidth * 0.55), dy: max(0.8, magnifierBorderWidth * 0.55)))
        innerPath.lineWidth = max(0.8, magnifierBorderWidth * 0.35)
        resolvedAlphaColor(
            magnifierBorderColor.blended(withFraction: 0.25, of: .white) ?? magnifierBorderColor,
            opacity: 0.75,
            applyTrailFadeRule: false
        ).setStroke()
        innerPath.stroke()
    }

    private func addPulse(
        at point: NSPoint,
        color: NSColor,
        fadeKey: String,
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
                fadeKey: fadeKey,
                lifetime: lifetime,
                timestamp: timestamp
            )
        )
    }

    private func scaledClickLifetime(_ base: CFTimeInterval) -> CFTimeInterval {
        let scale = max(0.1, clickEffectDurationSeconds / 0.3)
        return max(0.04, base * scale)
    }

    private func scaledWaterImpactLifetime(_ base: CFTimeInterval) -> CFTimeInterval {
        let scale = max(0.1, waterImpactLifetimeSeconds / 0.32)
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
        let clickFadeKey = clickColorFadeKey(for: button)
        switch clickVisualStyle {
        case .solidPulse:
            addPulse(
                at: point,
                color: style.color,
                fadeKey: clickFadeKey,
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
                fadeKey: clickFadeKey,
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
                    fadeKey: clickFadeKey,
                    radius: clickEffectRadius * 0.9,
                    kind: .cross,
                    lifetime: scaledClickLifetime(0.22),
                    timestamp: timestamp
                )
            )
        case .waterImpact:
            let spreadScale = max(0.1, waterImpactSpreadSpeed)
            let impactRadius = max(7, trailLineWidth * (2.3 + spreadScale * 3.1))
            addPulse(
                at: point,
                color: style.color,
                fadeKey: clickFadeKey,
                filled: true,
                kind: .circle,
                startRadius: max(3, impactRadius * 0.28),
                endRadius: max(9, impactRadius * 0.78),
                lineWidth: max(1.6, trailLineWidth * 0.58),
                lifetime: scaledWaterImpactLifetime(0.24),
                timestamp: timestamp
            )
            addPulse(
                at: point,
                color: waterHighlightColor.blended(withFraction: 0.45, of: style.color) ?? waterHighlightColor,
                fadeKey: clickFadeKey,
                filled: false,
                kind: .circle,
                startRadius: max(5, impactRadius * 0.42),
                endRadius: max(11, impactRadius * 1.02),
                lineWidth: max(1.4, trailLineWidth * 0.5),
                lifetime: scaledWaterImpactLifetime(0.3),
                timestamp: timestamp
            )
            emitWaterImpactDroplets(at: point, color: style.color, fadeKey: clickFadeKey, timestamp: timestamp, burstScale: 1.0)
        case .particleExplosion:
            emitClickParticleExplosion(at: point, timestamp: timestamp, burstScale: 1.0)
        }
        if clickVisualStyle != .particleExplosion {
            emitClickSpark(at: point, color: style.color, fadeKey: clickFadeKey, timestamp: timestamp)
        }
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
        let clickFadeKey = clickColorFadeKey(for: button)
        let brightColor = style.color.blended(withFraction: 0.2, of: .white) ?? style.color
        switch clickVisualStyle {
        case .solidPulse:
            addPulse(
                at: point,
                color: brightColor,
                fadeKey: clickFadeKey,
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
                fadeKey: clickFadeKey,
                filled: false,
                kind: .cross,
                startRadius: max(4, clickEffectRadius * 0.42),
                endRadius: max(9, clickEffectRadius * 1.1),
                lineWidth: 2.0,
                lifetime: scaledClickLifetime(0.3),
                timestamp: timestamp
            )
        case .waterImpact:
            let spreadScale = max(0.1, waterImpactSpreadSpeed)
            let impactRadius = max(8, trailLineWidth * (2.5 + spreadScale * 3.3))
            addPulse(
                at: point,
                color: brightColor,
                fadeKey: clickFadeKey,
                filled: false,
                kind: .circle,
                startRadius: max(5, impactRadius * 0.38),
                endRadius: max(12, impactRadius * 1.18),
                lineWidth: max(1.6, trailLineWidth * 0.62),
                lifetime: scaledWaterImpactLifetime(0.36),
                timestamp: timestamp
            )
            emitWaterImpactDroplets(at: point, color: brightColor, fadeKey: clickFadeKey, timestamp: timestamp, burstScale: 1.28)
        case .particleExplosion:
            emitClickParticleExplosion(at: point, timestamp: timestamp, burstScale: 1.28)
        }
        if clickVisualStyle != .particleExplosion {
            emitClickSpark(at: point, color: brightColor, fadeKey: clickFadeKey, timestamp: timestamp)
        }
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

    private func clickColorFadeKey(for button: MouseButtonKind) -> String {
        ColorFadeSettingKey.clickColor(button)
    }

    private func clickColorFadeKey(for pressedButton: PressedButton) -> String {
        switch pressedButton {
        case .left:
            return clickColorFadeKey(for: MouseButtonKind.left)
        case .right:
            return clickColorFadeKey(for: MouseButtonKind.right)
        case .middle:
            return clickColorFadeKey(for: MouseButtonKind.middle)
        case .none:
            return clickColorFadeKey(for: MouseButtonKind.left)
        }
    }

    private func trailColorFadeKey(for style: TrailRenderStyle) -> String {
        switch style {
        case .rainbow:
            return ColorFadeSettingKey.trailRainbowColors
        case .neon:
            return ColorFadeSettingKey.trailNeonColors
        case .waterBlade:
            return ColorFadeSettingKey.trailWaterColors
        case .ribbon, .lightning:
            return ColorFadeSettingKey.trailColor
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

    private func makeWaterRibbonNodes(samples: [TrailSample]) -> [WaterRibbonNode] {
        guard samples.count > 2 else { return [] }
        let strideStep = max(1, samples.count / 240)
        var reducedSamples: [TrailSample] = []
        reducedSamples.reserveCapacity(samples.count / strideStep + 2)
        for index in stride(from: 0, to: samples.count, by: strideStep) {
            reducedSamples.append(samples[index])
        }
        if let last = samples.last,
           reducedSamples.last?.index != last.index
        {
            reducedSamples.append(last)
        }
        guard reducedSamples.count > 2 else { return [] }

        var nodes: [WaterRibbonNode] = []
        nodes.reserveCapacity(reducedSamples.count)
        let total = max(1, reducedSamples.count - 1)

        for index in reducedSamples.indices {
            let previous = reducedSamples[max(0, index - 1)].point
            let current = reducedSamples[index].point
            let next = reducedSamples[min(reducedSamples.count - 1, index + 1)].point
            let tangent = normalizedVector(dx: next.x - previous.x, dy: next.y - previous.y)
            let normal = (x: -tangent.y, y: tangent.x)

            let curveSign: CGFloat
            let curveStrength: CGFloat
            if index == 0 || index == reducedSamples.count - 1 {
                curveSign = 0
                curveStrength = 0
            } else {
                let inVector = normalizedVector(dx: current.x - previous.x, dy: current.y - previous.y)
                let outVector = normalizedVector(dx: next.x - current.x, dy: next.y - current.y)
                let cross = inVector.x * outVector.y - inVector.y * outVector.x
                let dot = max(-1.0, min(1.0, inVector.x * outVector.x + inVector.y * outVector.y))
                let angle = atan2(abs(cross), dot)
                curveSign = cross == 0 ? 0 : (cross > 0 ? 1 : -1)
                curveStrength = min(1.0, angle / (.pi * 0.66))
            }

            nodes.append(
                WaterRibbonNode(
                    point: current,
                    normal: normal,
                    alpha: reducedSamples[index].alpha,
                    progress: CGFloat(index) / CGFloat(total),
                    curveSign: curveSign,
                    curveStrength: curveStrength,
                    trailScale: reducedSamples[index].trailScale
                )
            )
        }

        return nodes
    }

    private func normalizedVector(dx: CGFloat, dy: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let length = max(0.0001, hypot(dx, dy))
        return (dx / length, dy / length)
    }

    private func offset(_ point: NSPoint, by normal: (x: CGFloat, y: CGFloat), amount: CGFloat) -> NSPoint {
        NSPoint(x: point.x + normal.x * amount, y: point.y + normal.y * amount)
    }

    private func resolvedAlphaColor(
        _ color: NSColor,
        opacity: CGFloat,
        fadeKey: String? = nil,
        applyTrailFadeRule: Bool = true
    ) -> NSColor {
        let normalizedOpacity = max(0, min(1, opacity))
        let colorInRGB = color.usingColorSpace(.deviceRGB) ?? color
        let disableForKey = fadeKey.map { colorFadeDisabledKeys.contains($0) } ?? false
        if applyTrailFadeRule, (disableTrailFadeAndForceSolid || disableForKey) {
            return colorInRGB
        }
        return colorInRGB.withAlphaComponent(colorInRGB.alphaComponent * normalizedOpacity)
    }

    private func waterWaveOffset(
        index: Int,
        progress: CGFloat,
        randomness: CGFloat,
        phaseSeed: Int,
        trailScale: CGFloat
    ) -> CGFloat {
        guard randomness > 0.001 else { return 0 }
        let seed = index * 113 + phaseSeed * 31
        let primaryPhase = Double(progress) * 17.4 + Double(seed % 97) * 0.12
        let secondaryPhase = Double(progress) * 31.2 + Double(seed % 53) * 0.18
        let wave = sin(primaryPhase) * 0.72 + sin(secondaryPhase) * 0.28
        let amplitude = trailLineWidth * max(0.1, trailScale) * (0.06 + randomness * 0.28)
        return CGFloat(wave) * amplitude
    }

    private func drawWaterRibbonQuad(
        start: NSPoint,
        end: NSPoint,
        startNormal: (x: CGFloat, y: CGFloat),
        endNormal: (x: CGFloat, y: CGFloat),
        centerOffsetStart: CGFloat,
        centerOffsetEnd: CGFloat,
        halfWidthStart: CGFloat,
        halfWidthEnd: CGFloat,
        color: NSColor,
        fadeKey: String,
        alpha: CGFloat
    ) {
        guard alpha > 0.001 else { return }
        let startCenter = offset(start, by: startNormal, amount: centerOffsetStart)
        let endCenter = offset(end, by: endNormal, amount: centerOffsetEnd)
        let startLeft = offset(startCenter, by: startNormal, amount: halfWidthStart)
        let startRight = offset(startCenter, by: startNormal, amount: -halfWidthStart)
        let endLeft = offset(endCenter, by: endNormal, amount: halfWidthEnd)
        let endRight = offset(endCenter, by: endNormal, amount: -halfWidthEnd)
        let path = NSBezierPath()
        path.move(to: startLeft)
        path.line(to: endLeft)
        path.line(to: endRight)
        path.line(to: startRight)
        path.close()
        resolvedAlphaColor(color, opacity: alpha, fadeKey: fadeKey).setFill()
        path.fill()
    }

    private func particleShapeSeed(point: NSPoint, timestamp: CFTimeInterval) -> Int {
        let timePart = Int((timestamp * 1_000).rounded())
        let xPart = Int((point.x * 10).rounded())
        let yPart = Int((point.y * 10).rounded())
        return abs(timePart ^ (xPart << 2) ^ (yPart << 5))
    }

    private func makeIrregularBlobPath(
        center: NSPoint,
        baseRadius: CGFloat,
        seed: Int,
        elongation: CGFloat,
        rotation: CGFloat
    ) -> NSBezierPath {
        let path = NSBezierPath()
        let pointCount = 9
        var points: [NSPoint] = []
        points.reserveCapacity(pointCount)
        let adjustedElongation = max(0.65, min(2.8, elongation))

        for index in 0..<pointCount {
            let baseAngle = (CGFloat(index) / CGFloat(pointCount)) * (.pi * 2)
            let jitterAngle = (pseudoRandom01(seed + index * 11) - 0.5) * 0.24
            let angle = baseAngle + jitterAngle
            let radiusJitter = 0.72 + pseudoRandom01(seed + index * 19) * 0.56
            let radial = baseRadius * radiusJitter
            let localX = cos(angle) * radial * adjustedElongation
            let localY = sin(angle) * radial / max(0.72, adjustedElongation * 0.86)
            let rotatedX = localX * cos(rotation) - localY * sin(rotation)
            let rotatedY = localX * sin(rotation) + localY * cos(rotation)
            points.append(NSPoint(x: center.x + rotatedX, y: center.y + rotatedY))
        }

        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() {
                path.line(to: point)
            }
            path.close()
        }
        path.lineJoinStyle = .round
        return path
    }

    private func normalizedWaterRatios() -> (highlight: CGFloat, primary: CGFloat, shadow: CGFloat) {
        let highlight = max(0, waterHighlightRatio)
        let primary = max(0, waterPrimaryRatio)
        let shadow = max(0, waterShadowRatio)
        let sum = highlight + primary + shadow
        guard sum > 0.0001 else { return (0.34, 0.44, 0.22) }
        return (highlight / sum, primary / sum, shadow / sum)
    }

    private func waterBladeSegmentColor(
        sampleIndex: Int,
        phaseSeed: Int,
        baseColor: NSColor,
        highlightWeight: CGFloat,
        primaryWeight: CGFloat,
        randomness: CGFloat
    ) -> NSColor {
        let seed = sampleIndex * 131 + phaseSeed * 17
        let pick = pseudoRandom01(seed + 3)
        let selectedColor: NSColor
        if pick < highlightWeight {
            selectedColor = waterHighlightColor
        } else if pick < highlightWeight + primaryWeight {
            selectedColor = waterPrimaryColor
        } else {
            selectedColor = waterShadowColor
        }
        let blendFraction = 0.14 + randomness * 0.86
        let mixed = baseColor.blended(withFraction: blendFraction, of: selectedColor) ?? selectedColor
        let sparkle = pseudoRandom01(seed + 8)
        let whitenFraction = (0.04 + randomness * 0.18) * sparkle
        return mixed.blended(withFraction: whitenFraction, of: .white) ?? mixed
    }

    private func weightedWaterColor(
        highlightWeight: CGFloat,
        primaryWeight: CGFloat,
        shadowWeight: CGFloat
    ) -> NSColor {
        let highlightComp = rgbaComponents(of: waterHighlightColor)
        let primaryComp = rgbaComponents(of: waterPrimaryColor)
        let shadowComp = rgbaComponents(of: waterShadowColor)

        let r = highlightComp.r * highlightWeight + primaryComp.r * primaryWeight + shadowComp.r * shadowWeight
        let g = highlightComp.g * highlightWeight + primaryComp.g * primaryWeight + shadowComp.g * shadowWeight
        let b = highlightComp.b * highlightWeight + primaryComp.b * primaryWeight + shadowComp.b * shadowWeight
        let a = highlightComp.a * highlightWeight + primaryComp.a * primaryWeight + shadowComp.a * shadowWeight
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }

    private func rgbaComponents(of color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let converted = color.usingColorSpace(.deviceRGB) ?? color.usingColorSpace(.sRGB) ?? color
        return (
            converted.redComponent,
            converted.greenComponent,
            converted.blueComponent,
            converted.alphaComponent
        )
    }

    private func trailBaseColor(index: Int, now: CFTimeInterval) -> NSColor {
        switch trailStyle {
        case .rainbow:
            return rainbowColor(for: index, now: now)
        case .neon:
            return neonPrimaryColor.blended(withFraction: 0.5, of: neonSecondaryColor) ?? neonPrimaryColor
        case .waterBlade:
            let ratios = normalizedWaterRatios()
            let randomness = max(0, min(1, waterMixRandomness / 100))
            let phaseSeed = waterMixSeedLocked ? 0 : Int(now * 42)
            let baseColor = weightedWaterColor(
                highlightWeight: ratios.highlight,
                primaryWeight: ratios.primary,
                shadowWeight: ratios.shadow
            )
            return waterBladeSegmentColor(
                sampleIndex: index,
                phaseSeed: phaseSeed,
                baseColor: baseColor,
                highlightWeight: ratios.highlight,
                primaryWeight: ratios.primary,
                randomness: randomness
            )
        default:
            return trailColor
        }
    }

    /// 沿轨迹段发射附加粒子/墨迹/电弧效果。
    /// Note: 发射密度与寿命由各特效类型的专属参数驱动。
    private func emitTrailEffects(
        from start: NSPoint,
        to end: NSPoint,
        timestamp: CFTimeInterval,
        effectScale: CGFloat
    ) {
        guard isTrailEnabled else { return }
        if trailStyle == .ribbon { return }
        guard isTrailEffectsEnabled else { return }
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance > 0.1 else { return }
        let clampedEffectScale = max(0.1, effectScale)

        let baseCount = max(1, Int(distance / max(6, electricArcLength * 0.45)))
        let styleMultiplier: CGFloat = switch trailEffectStyle {
        case .particles: max(0.1, particleDensity)
        case .ink: max(0.1, inkDensity) * 0.78
        case .electric: max(0.1, electricArcDensity) * 1.06
        case .waterSplash: 1.15
        }
        let splashDensityScale: CGFloat = if trailEffectStyle == .waterSplash {
            max(0.08, pow(max(0.1, waterSplashDensity), 1.12))
        } else {
            1.0
        }
        let waterStyleDensityMultiplier: CGFloat = trailStyle == .waterBlade ? 0.42 : 1.0
        let spawnCount = min(
            Int(CGFloat(baseCount) * effectSpawnMultiplier * styleMultiplier * waterStyleDensityMultiplier * splashDensityScale) + 1,
            max(4, Int(12 * effectSpawnMultiplier))
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
            let fadeKey: String
            let baseColor = trailBaseColor(index: index, now: timestamp)
            let effectBaseColor = trailEffectColor.blended(withFraction: 0.2, of: baseColor) ?? trailEffectColor

            switch trailEffectStyle {
            case .particles:
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let speed = CGFloat.random(in: effectParticleSpeedRange)
                velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
                size = CGFloat.random(in: effectParticleSizeRange) * clampedEffectScale
                lifetime = max(0.04, particleLifetimeSeconds) * Double(CGFloat.random(in: 0.72...1.18))
                let palette = particleColors.isEmpty ? [effectBaseColor] : particleColors
                let picked = palette[Int.random(in: 0..<palette.count)]
                color = picked.blended(withFraction: 0.24, of: effectBaseColor) ?? picked
                fadeKey = ColorFadeSettingKey.trailParticleColors
            case .ink:
                velocity = CGVector(dx: CGFloat.random(in: -14...14), dy: CGFloat.random(in: -14...14))
                size = CGFloat.random(in: effectParticleSizeRange) * clampedEffectScale
                lifetime = max(0.04, inkLifetimeSeconds) * Double(CGFloat.random(in: 0.72...1.14))
                let palette = inkColors.isEmpty ? [effectBaseColor] : inkColors
                let picked = palette[Int.random(in: 0..<palette.count)]
                color = resolvedAlphaColor(
                    picked.blended(withFraction: 0.2, of: effectBaseColor) ?? picked,
                    opacity: 0.92,
                    fadeKey: ColorFadeSettingKey.trailInkColors
                )
                fadeKey = ColorFadeSettingKey.trailInkColors
            case .electric:
                let speed = CGFloat.random(in: effectParticleSpeedRange.upperBound ... effectParticleSpeedRange.upperBound * 1.8)
                let angle = CGFloat.random(in: -0.9...0.9)
                let rotatedX = normal.dx * cos(angle) - normal.dy * sin(angle)
                let rotatedY = normal.dx * sin(angle) + normal.dy * cos(angle)
                velocity = CGVector(dx: rotatedX * speed, dy: rotatedY * speed)
                size = CGFloat.random(in: 1.0...2.4) * clampedEffectScale * max(0.4, electricArcWidth)
                lifetime = max(0.04, 0.07 + Double(electricArcLength / 140))
                color = (effectBaseColor.blended(withFraction: 0.55, of: .white) ?? effectBaseColor)
                fadeKey = ColorFadeSettingKey.trailEffectColor
            case .waterSplash:
                let tangent = CGVector(dx: normal.dx, dy: normal.dy)
                let side = CGVector(dx: -tangent.dy, dy: tangent.dx)
                let spread = CGFloat.random(in: -1.25...1.25)
                let sprayX = tangent.dx + side.dx * spread
                let sprayY = tangent.dy + side.dy * spread
                let sprayLength = max(0.001, hypot(sprayX, sprayY))
                let sprayDirX = sprayX / sprayLength
                let sprayDirY = sprayY / sprayLength
                let speedScale = max(0.1, waterSplashSpeed)
                let speed = CGFloat.random(in: 28...125) * (0.65 + effectSpawnMultiplier * 0.5) * speedScale
                velocity = CGVector(dx: sprayDirX * speed, dy: sprayDirY * speed)
                let randomUnit = CGFloat.random(in: 0...1)
                size = (1.1 + pow(randomUnit, 2.4) * 10.5) * waterSplashSize * clampedEffectScale
                let lifetimeScale = max(0.1, waterSplashLifetimeSeconds / 0.26)
                lifetime = Double(CGFloat.random(in: 0.12...0.42)) * lifetimeScale
                let randomColor = CGFloat.random(in: 0...1)
                let baseColor = waterSplashColor.blended(withFraction: 0.32, of: effectBaseColor) ?? waterSplashColor
                if randomColor < 0.55 {
                    color = waterHighlightColor.blended(withFraction: 0.28, of: baseColor) ?? waterHighlightColor
                } else if randomColor < 0.87 {
                    color = waterPrimaryColor.blended(withFraction: 0.42, of: baseColor) ?? waterPrimaryColor
                } else {
                    color = waterShadowColor.blended(withFraction: 0.36, of: baseColor) ?? waterShadowColor
                }
                fadeKey = ColorFadeSettingKey.trailWaterSplashColor
            }

            particles.append(
                Particle(
                    point: NSPoint(x: x, y: y),
                    velocity: velocity,
                    size: size,
                    color: color,
                    fadeKey: fadeKey,
                    lifetime: lifetime,
                    timestamp: timestamp
                )
            )
        }
    }

    private func emitClickSpark(at point: NSPoint, color: NSColor, fadeKey: String, timestamp: CFTimeInterval) {
        guard isTrailEffectsEnabled else { return }
        let isWaterImpactClick = clickVisualStyle == .waterImpact
        let count: Int
        if isWaterImpactClick {
            let densityScale = max(0.03, pow(max(0.1, waterImpactDropletDensity), 1.25))
            count = max(1, Int((4 + 6 * effectSpawnMultiplier) * densityScale))
        } else {
            count = max(6, Int(10 * effectSpawnMultiplier))
        }
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: effectParticleSpeedRange.upperBound * 0.8 ... effectParticleSpeedRange.upperBound * 1.25)
            let velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
            let sizeBoost: CGFloat = if isWaterImpactClick {
                max(0.12, waterImpactDropletSize * 0.72)
            } else {
                max(0.8, clickEffectRadius / 24)
            }
            let size = CGFloat.random(in: effectParticleSizeRange.lowerBound ... effectParticleSizeRange.upperBound * 1.25) * sizeBoost
            let lifetime: CFTimeInterval = if isWaterImpactClick {
                scaledWaterImpactLifetime(effectParticleLifetime * Double(CGFloat.random(in: 0.6...1.05)))
            } else {
                scaledClickLifetime(effectParticleLifetime * Double(CGFloat.random(in: 0.6...1.05)))
            }
            particles.append(
                Particle(
                    point: point,
                    velocity: velocity,
                    size: size,
                    color: color,
                    fadeKey: fadeKey,
                    lifetime: lifetime,
                    timestamp: timestamp
                )
            )
        }
    }

    private func emitClickParticleExplosion(
        at point: NSPoint,
        timestamp: CFTimeInterval,
        burstScale: CGFloat
    ) {
        let density = max(0.1, clickParticleExplosionDensity)
        let speedScale = max(0.1, clickParticleExplosionSpeed)
        let sizeScale = max(0.1, clickParticleExplosionSize)
        let lifetimeScale = max(0.1, clickParticleExplosionLifetimeSeconds / 0.32)
        let densityCurve = max(0.1, pow(density, 1.2))
        let burstCount = max(6, min(240, Int((20 + 22 * burstScale) * densityCurve)))
        let palette = clickParticleExplosionColors.isEmpty ? AppSettings.default.clickParticleExplosionColors : clickParticleExplosionColors
        for _ in 0..<burstCount {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 42...220) * speedScale * (0.88 + burstScale * 0.45)
            let velocity = CGVector(
                dx: cos(angle) * speed,
                dy: sin(angle) * speed + CGFloat.random(in: 8...46) * burstScale
            )
            let size = CGFloat.random(in: 0.9...4.8) * sizeScale
            let lifetime = Double(CGFloat.random(in: 0.14...0.42)) * lifetimeScale
            let mixedColor = palette.randomElement() ?? AppSettings.default.clickParticleExplosionColors[0]
            clickExplosionParticles.append(
                Particle(
                    point: point,
                    velocity: velocity,
                    size: size,
                    color: mixedColor,
                    fadeKey: ColorFadeSettingKey.clickParticleExplosionColors,
                    lifetime: lifetime,
                    timestamp: timestamp
                )
            )
        }
    }

    private func emitWaterImpactDroplets(
        at point: NSPoint,
        color: NSColor,
        fadeKey: String,
        timestamp: CFTimeInterval,
        burstScale: CGFloat
    ) {
        let densityScale = max(0.1, waterImpactDropletDensity)
        let spreadScale = max(0.1, waterImpactSpreadSpeed)
        let densityCurve = max(0.03, pow(densityScale, 1.4))
        let baseBurstCount = (8 + 10 * effectSpawnMultiplier) * burstScale
        let burstCount = max(1, Int(baseBurstCount * densityCurve))
        for index in 0..<burstCount {
            let spread = CGFloat(index) / CGFloat(max(1, burstCount - 1))
            let baseAngle = spread * (.pi * 2)
            let randomAngle = (pseudoRandom01(Int(timestamp * 1_000) + index * 13) - 0.5) * 0.88
            let angle = baseAngle + randomAngle
            let speed = CGFloat.random(in: 32...150) * (0.65 + burstScale * 0.52) * spreadScale
            let velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed + CGFloat.random(in: 16...68))
            let randomUnit = CGFloat.random(in: 0...1)
            let baseSize = 1.2 + pow(randomUnit, 2.1) * (8.8 + burstScale * 3.2)
            let size = baseSize * max(0.1, waterImpactDropletSize)
            let lifetime = scaledWaterImpactLifetime(Double(CGFloat.random(in: 0.18...0.52)))
            let variant = CGFloat.random(in: 0...1)
            let dropletColor: NSColor
            if variant < 0.48 {
                dropletColor = waterHighlightColor
            } else if variant < 0.82 {
                dropletColor = color.blended(withFraction: 0.34, of: waterPrimaryColor) ?? color
            } else {
                dropletColor = waterPrimaryColor.blended(withFraction: 0.28, of: waterShadowColor) ?? waterPrimaryColor
            }
            waterImpactDroplets.append(
                WaterImpactDroplet(
                    point: point,
                    velocity: velocity,
                    size: size,
                    color: dropletColor,
                    fadeKey: fadeKey,
                    lifetime: lifetime,
                    timestamp: timestamp,
                    seed: particleShapeSeed(point: point, timestamp: timestamp + Double(index) * 0.007)
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
        trimExpiredPrefix(from: &clickExplosionParticles) { now - $0.timestamp > $0.lifetime }
        trimExpiredPrefix(from: &clickAccents) { now - $0.timestamp > $0.lifetime }
        trimExpiredPrefix(from: &waterImpactDroplets) { now - $0.timestamp > $0.lifetime }
        trimExpiredPrefix(from: &dashBursts) { now - $0.timestamp > $0.lifetime }
        if particles.count > effectMaxParticleCount {
            particles.removeFirst(particles.count - effectMaxParticleCount)
        }
        let clickExplosionLimit = max(80, min(800, Int(90 + clickParticleExplosionDensity * 65)))
        if clickExplosionParticles.count > clickExplosionLimit {
            clickExplosionParticles.removeFirst(clickExplosionParticles.count - clickExplosionLimit)
        }
        let hasAnimatedContent =
            !movePoints.isEmpty ||
            !pulses.isEmpty ||
            !particles.isEmpty ||
            !clickExplosionParticles.isEmpty ||
            !clickAccents.isEmpty ||
            !waterImpactDroplets.isEmpty ||
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
