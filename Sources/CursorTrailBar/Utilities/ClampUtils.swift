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

func clampClickEffectRadius(_ value: Double) -> CGFloat {
    CGFloat(min(600.0, max(1.0, value)))
}

func clampClickEffectDurationMilliseconds(_ value: Double) -> Double {
    min(2_000.0, max(40.0, value))
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
