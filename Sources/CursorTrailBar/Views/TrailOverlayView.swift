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
