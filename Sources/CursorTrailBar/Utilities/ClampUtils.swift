//
// ClampUtils.swift
// MVC: 公共工具（参数钳制与数学辅助）
//
import AppKit

func clampTrailWidth(_ value: Double) -> CGFloat {
    CGFloat(min(100.0, max(0.1, value)))
}

func clampTrailLengthMilliseconds(_ value: Double) -> Double {
    min(10_000, max(1, value))
}

func clampWaterMixRatio(_ value: Double) -> CGFloat {
    CGFloat(min(100.0, max(0.0, value)))
}

func clampWaterMixRandomness(_ value: Double) -> CGFloat {
    CGFloat(min(100.0, max(0.0, value)))
}

func clampNeonPrimaryWidthRatio(_ value: Double) -> CGFloat {
    CGFloat(min(90.0, max(10.0, value)))
}

func clampWaterSplashSize(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampWaterSplashSpeed(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampWaterSplashLifetimeMilliseconds(_ value: Double) -> Double {
    min(2_000.0, max(40.0, value))
}

func clampWaterSplashDensity(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampTrailEffectIntensity(_ value: Double) -> CGFloat {
    CGFloat(min(100.0, max(0.0, value)))
}

func clampElectricArcDensity(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampElectricArcLength(_ value: Double) -> CGFloat {
    CGFloat(min(80.0, max(2.0, value)))
}

func clampElectricArcWidth(_ value: Double) -> CGFloat {
    CGFloat(min(6.0, max(0.4, value)))
}

func clampInkDensity(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampInkSize(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.2, value)))
}

func clampInkLifetimeMilliseconds(_ value: Double) -> Double {
    min(2_000.0, max(40.0, value))
}

func clampParticleDensity(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampParticleSize(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.2, value)))
}

func clampParticleLifetimeMilliseconds(_ value: Double) -> Double {
    min(2_000.0, max(40.0, value))
}

func clampParticleSpeed(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampEffectPaletteCount(_ value: Int) -> Int {
    min(10, max(1, value))
}

func clampClickEffectRadius(_ value: Double) -> CGFloat {
    CGFloat(min(600.0, max(1.0, value)))
}

func clampClickEffectDurationMilliseconds(_ value: Double) -> Double {
    min(2_000.0, max(40.0, value))
}

func clampWaterImpactDropletDensity(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampWaterImpactSpreadSpeed(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampWaterImpactLifetimeMilliseconds(_ value: Double) -> Double {
    min(2_000.0, max(40.0, value))
}

func clampWaterImpactDropletSize(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampClickParticleExplosionDensity(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampClickParticleExplosionSize(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.2, value)))
}

func clampClickParticleExplosionLifetimeMilliseconds(_ value: Double) -> Double {
    min(2_000.0, max(40.0, value))
}

func clampClickParticleExplosionSpeed(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampClickParticleExplosionPaletteCount(_ value: Int) -> Int {
    min(7, max(1, value))
}

func clampMagnifierRadius(_ value: Double) -> CGFloat {
    CGFloat(min(1200.0, max(20.0, value)))
}

func clampMagnifierZoom(_ value: Double) -> CGFloat {
    CGFloat(min(8.0, max(1.0, value)))
}

func clampMagnifierBorderWidth(_ value: Double) -> CGFloat {
    CGFloat(min(30.0, max(0.0, value)))
}

func clampMagnifierShadowOpacity(_ value: Double) -> CGFloat {
    CGFloat(min(1.0, max(0.0, value)))
}

func clampSpeedBurstVelocityThreshold(_ value: Double) -> CGFloat {
    CGFloat(min(60_000.0, max(100.0, value)))
}

func clampSpeedBurstCooldownMilliseconds(_ value: Double) -> Double {
    min(3000.0, max(50.0, value))
}

func clampSpeedBurstDurationMilliseconds(_ value: Double) -> Double {
    min(800.0, max(40.0, value))
}

func clampSpeedBurstJitterAmplitude(_ value: Double) -> CGFloat {
    CGFloat(min(30.0, max(0.0, value)))
}

func clampSpeedBurstMinLength(_ value: Double) -> CGFloat {
    CGFloat(min(5000.0, max(10.0, value)))
}

func clampSpeedBurstMaxLength(_ value: Double) -> CGFloat {
    CGFloat(min(5000.0, max(10.0, value)))
}

func clampSpeedBurstWidthMultiplier(_ value: Double) -> CGFloat {
    CGFloat(min(4.0, max(0.2, value)))
}

func clampSpeedSurgeTrailScale(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampSpeedSurgeEffectScale(_ value: Double) -> CGFloat {
    CGFloat(min(10.0, max(0.1, value)))
}

func clampSpeedBurstAccentDurationMilliseconds(_ value: Double) -> Double {
    min(2_000.0, max(40.0, value))
}

func clampSpeedBurstAccentSize(_ value: Double) -> CGFloat {
    CGFloat(min(400.0, max(4.0, value)))
}

func rounded(_ value: Double, scale: Double = 100) -> Double {
    (value * scale).rounded() / scale
}

func pseudoRandom01(_ seed: Int) -> CGFloat {
    let value = sin(Double(seed) * 12.9898 + 78.233) * 43758.5453
    return CGFloat(value - floor(value))
}
