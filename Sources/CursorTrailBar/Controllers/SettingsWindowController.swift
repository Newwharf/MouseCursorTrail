//
// SettingsWindowController.swift
// MVC: Controller 层（设置窗口 UI 与配置同步）
//
import AppKit
import ApplicationServices
import Carbon
import UniformTypeIdentifiers

@MainActor
/// 翻转坐标系的容器视图，确保滚动内容从顶部开始布局。
private final class FlippedTopAlignedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
/// 设置窗口控制器。
/// 职责：构建设置 UI、同步控件状态，并对外发布设置变更。
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private enum SidebarTab: String, CaseIterable {
        case trailEffects
        case clickEffects
        case magnifier
        case general

        var title: String {
            switch self {
            case .trailEffects: return i18n("sidebar.trailEffects", "轨迹效果")
            case .clickEffects: return i18n("sidebar.clickEffects", "点击效果")
            case .magnifier: return i18n("sidebar.magnifier", "放大镜")
            case .general: return i18n("sidebar.general", "设置")
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

    private enum TrailPresetOption: Equatable {
        case custom
        case thunderFirstForm
        case waterFirstForm
        case userPreset(id: String)

        var isBuiltIn: Bool {
            switch self {
            case .custom, .thunderFirstForm, .waterFirstForm:
                true
            case .userPreset:
                false
            }
        }
    }

    private enum PresetManagerRowKind: Equatable {
        case thunderFirstForm
        case waterFirstForm
        case userPreset(id: String)
    }

    private struct PresetManagerRow {
        let kind: PresetManagerRowKind
        let name: String
        let updatedAt: Date?
    }

    var onSettingsChanged: ((AppSettings) -> Void)?
    var onRequestInputMonitoringPermission: (() -> Void)?
    var isRecordingShortcut: Bool { isShortcutRecording }

    private var settings: AppSettings
    private var isSyncingControls = false
    private var activeSidebarTab: SidebarTab = .trailEffects
    private var trailPresetOptions: [TrailPresetOption] = []
    private var customTrailPresets: [CustomTrailPreset] = []
    private var selectedTrailPresetOption: TrailPresetOption = .custom
    private var sidebarButtons: [SidebarTab: NSButton] = [:]
    private var sidebarButtonToTab: [ObjectIdentifier: SidebarTab] = [:]
    private var sidebarContentViews: [SidebarTab: NSView] = [:]
    private var contentScrollView: NSScrollView?

    private let launchAtLoginSwitch = NSSwitch()
    private let loggingSwitch = NSSwitch()
    private let statusItemSwitch = NSSwitch()
    private let trackingSwitch = NSSwitch()
    private let darkAppearanceSwitch = NSSwitch()
    private let clickEffectsSwitch = NSSwitch()
    private let magnifierEnabledSwitch = NSSwitch()
    private let magnifierShowEffectsSwitch = NSSwitch()
    private let speedBurstSwitch = NSSwitch()
    private let trailEffectsSwitch = NSSwitch()
    private let disableTrailFadeSwitch = NSSwitch()
    private let waterMixSeedLockSwitch = NSSwitch()

    private let trailColorWell = NSColorWell()
    private let trailEffectColorWell = NSColorWell()
    private let speedBurstLineColorWell = NSColorWell()
    private let speedBurstAccentColorWell = NSColorWell()
    private let neonPrimaryColorWell = NSColorWell()
    private let neonSecondaryColorWell = NSColorWell()
    private let waterHighlightColorWell = NSColorWell()
    private let waterPrimaryColorWell = NSColorWell()
    private let waterShadowColorWell = NSColorWell()
    private let waterSplashColorWell = NSColorWell()
    private let magnifierBorderColorWell = NSColorWell()
    private var inkEffectColorWells: [NSColorWell] = []
    private var particleEffectColorWells: [NSColorWell] = []

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
    private let speedBurstDurationMinSlider = NSSlider()
    private let speedBurstDurationMinValueLabel = NSTextField(labelWithString: "")
    private let speedBurstDurationMaxSlider = NSSlider()
    private let speedBurstDurationMaxValueLabel = NSTextField(labelWithString: "")
    private let speedBurstJitterSlider = NSSlider()
    private let speedBurstJitterValueLabel = NSTextField(labelWithString: "")
    private let speedBurstMinLengthSlider = NSSlider()
    private let speedBurstMinLengthValueLabel = NSTextField(labelWithString: "")
    private let speedBurstMaxLengthSlider = NSSlider()
    private let speedBurstMaxLengthValueLabel = NSTextField(labelWithString: "")
    private let speedBurstWidthMultiplierSlider = NSSlider()
    private let speedBurstWidthMultiplierValueLabel = NSTextField(labelWithString: "")
    private let speedBurstTrailMinScaleSlider = NSSlider()
    private let speedBurstTrailMinScaleValueLabel = NSTextField(labelWithString: "")
    private let speedBurstTrailMaxScaleSlider = NSSlider()
    private let speedBurstTrailMaxScaleValueLabel = NSTextField(labelWithString: "")
    private let speedBurstEffectMinScaleSlider = NSSlider()
    private let speedBurstEffectMinScaleValueLabel = NSTextField(labelWithString: "")
    private let speedBurstEffectMaxScaleSlider = NSSlider()
    private let speedBurstEffectMaxScaleValueLabel = NSTextField(labelWithString: "")
    private let speedBurstAccentDurationSlider = NSSlider()
    private let speedBurstAccentDurationValueLabel = NSTextField(labelWithString: "")
    private let speedBurstAccentSizeSlider = NSSlider()
    private let speedBurstAccentSizeValueLabel = NSTextField(labelWithString: "")
    private let waterHighlightRatioSlider = NSSlider()
    private let waterHighlightRatioValueLabel = NSTextField(labelWithString: "")
    private let neonPrimaryWidthRatioSlider = NSSlider()
    private let neonPrimaryWidthRatioValueLabel = NSTextField(labelWithString: "")
    private let waterPrimaryRatioSlider = NSSlider()
    private let waterPrimaryRatioValueLabel = NSTextField(labelWithString: "")
    private let waterShadowRatioSlider = NSSlider()
    private let waterShadowRatioValueLabel = NSTextField(labelWithString: "")
    private let waterMixRandomnessSlider = NSSlider()
    private let waterMixRandomnessValueLabel = NSTextField(labelWithString: "")
    private let waterSplashSizeSlider = NSSlider()
    private let waterSplashSizeValueLabel = NSTextField(labelWithString: "")
    private let waterSplashSpeedSlider = NSSlider()
    private let waterSplashSpeedValueLabel = NSTextField(labelWithString: "")
    private let waterSplashLifetimeSlider = NSSlider()
    private let waterSplashLifetimeValueLabel = NSTextField(labelWithString: "")
    private let waterSplashDensitySlider = NSSlider()
    private let waterSplashDensityValueLabel = NSTextField(labelWithString: "")
    private let trailEffectIntensitySlider = NSSlider()
    private let trailEffectIntensityValueLabel = NSTextField(labelWithString: "")
    private let electricArcDensitySlider = NSSlider()
    private let electricArcDensityValueLabel = NSTextField(labelWithString: "")
    private let electricArcLengthSlider = NSSlider()
    private let electricArcLengthValueLabel = NSTextField(labelWithString: "")
    private let electricArcWidthSlider = NSSlider()
    private let electricArcWidthValueLabel = NSTextField(labelWithString: "")
    private let inkDensitySlider = NSSlider()
    private let inkDensityValueLabel = NSTextField(labelWithString: "")
    private let inkSizeSlider = NSSlider()
    private let inkSizeValueLabel = NSTextField(labelWithString: "")
    private let inkLifetimeSlider = NSSlider()
    private let inkLifetimeValueLabel = NSTextField(labelWithString: "")
    private let particleDensitySlider = NSSlider()
    private let particleDensityValueLabel = NSTextField(labelWithString: "")
    private let particleSizeSlider = NSSlider()
    private let particleSizeValueLabel = NSTextField(labelWithString: "")
    private let particleLifetimeSlider = NSSlider()
    private let particleLifetimeValueLabel = NSTextField(labelWithString: "")
    private let particleSpeedSlider = NSSlider()
    private let particleSpeedValueLabel = NSTextField(labelWithString: "")
    private let clickRadiusSlider = NSSlider()
    private let clickRadiusValueLabel = NSTextField(labelWithString: "")
    private let clickDurationSlider = NSSlider()
    private let clickDurationValueLabel = NSTextField(labelWithString: "")
    private let waterImpactDensitySlider = NSSlider()
    private let waterImpactDensityValueLabel = NSTextField(labelWithString: "")
    private let waterImpactSpreadSpeedSlider = NSSlider()
    private let waterImpactSpreadSpeedValueLabel = NSTextField(labelWithString: "")
    private let waterImpactLifetimeSlider = NSSlider()
    private let waterImpactLifetimeValueLabel = NSTextField(labelWithString: "")
    private let waterImpactDropletSizeSlider = NSSlider()
    private let waterImpactDropletSizeValueLabel = NSTextField(labelWithString: "")
    private let clickParticleExplosionDensitySlider = NSSlider()
    private let clickParticleExplosionDensityValueLabel = NSTextField(labelWithString: "")
    private let clickParticleExplosionSizeSlider = NSSlider()
    private let clickParticleExplosionSizeValueLabel = NSTextField(labelWithString: "")
    private let clickParticleExplosionLifetimeSlider = NSSlider()
    private let clickParticleExplosionLifetimeValueLabel = NSTextField(labelWithString: "")
    private let clickParticleExplosionSpeedSlider = NSSlider()
    private let clickParticleExplosionSpeedValueLabel = NSTextField(labelWithString: "")
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
    private let speedSurgeScaleModePopup = NSPopUpButton()
    private let clickStylePopup = NSPopUpButton()
    private let trailPresetPopup = NSPopUpButton()
    private let presetManageButton = NSButton(title: "", target: nil, action: nil)
    private let languagePopup = NSPopUpButton()
    private let magnifierShortcutButton = NSButton(title: "", target: nil, action: nil)
    private let magnifierShortcutHint = NSTextField(labelWithString: "")
    private let launchAtLoginStatusLabel = NSTextField(labelWithString: "")

    private let inputMonitoringStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let screenCaptureStatusLabel = NSTextField(labelWithString: "")
    private let openInputMonitoringSettingsButton = NSButton(title: "", target: nil, action: nil)
    private let openAccessibilitySettingsButton = NSButton(title: "", target: nil, action: nil)
    private let openScreenCaptureSettingsButton = NSButton(title: "", target: nil, action: nil)
    private let openLogFolderButton = NSButton(title: "", target: nil, action: nil)
    private let openLanguagePacksFolderButton = NSButton(title: "", target: nil, action: nil)
    private let addRainbowColorButton = NSButton(title: "+", target: nil, action: nil)
    private let removeRainbowColorButton = NSButton(title: "−", target: nil, action: nil)
    private let addInkColorButton = NSButton(title: "+", target: nil, action: nil)
    private let removeInkColorButton = NSButton(title: "−", target: nil, action: nil)
    private let addParticleColorButton = NSButton(title: "+", target: nil, action: nil)
    private let removeParticleColorButton = NSButton(title: "−", target: nil, action: nil)
    private let addClickParticleExplosionColorButton = NSButton(title: "+", target: nil, action: nil)
    private let removeClickParticleExplosionColorButton = NSButton(title: "−", target: nil, action: nil)
    private let rainbowColorsStack = NSStackView()
    private let inkColorsStack = NSStackView()
    private let particleColorsStack = NSStackView()
    private let clickParticleExplosionColorsStack = NSStackView()
    private var rainbowColorWells: [NSColorWell] = []
    private var availableLanguageOptions: [LanguageOption] = []
    private var rowWrapperByRowIdentifier: [ObjectIdentifier: NSView] = [:]
    private var externalLinkByButtonIdentifier: [ObjectIdentifier: URL] = [:]
    private let aboutAuthorName = "lpp"
    private let aboutAuthorEmail = "ez7268@126.com"
    private let aboutHomepage = "https://github.com/Newwharf/MouseCursorTrail"
    private let aboutAppVersion = "V 1.0.0"
    private lazy var trailPresetHeaderControl = makeTrailPresetHeaderControl()

    private lazy var trailTypeRow = makePopupRow(title: i18n("row.trail.type", "轨迹类型"), popup: trailStylePopup)
    private lazy var trailColorRow = makeColorRow(title: i18n("row.trail.color", "轨迹颜色"), control: trailColorWell)
    private lazy var trailColorFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.trailColor)
    private lazy var waterColorsRow = makeWaterColorsRow()
    private lazy var waterColorsFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.trailWaterColors)
    private lazy var waterHighlightRatioRow = makeSliderRow(
        title: i18n("row.trail.waterHighlightRatio", "高光占比"),
        slider: waterHighlightRatioSlider,
        valueLabel: waterHighlightRatioValueLabel
    )
    private lazy var neonPrimaryWidthRatioRow = makeSliderRow(
        title: i18n("row.trail.neonPrimaryWidthRatio", "主色宽度占比"),
        slider: neonPrimaryWidthRatioSlider,
        valueLabel: neonPrimaryWidthRatioValueLabel
    )
    private lazy var waterPrimaryRatioRow = makeSliderRow(
        title: i18n("row.trail.waterPrimaryRatio", "主色占比"),
        slider: waterPrimaryRatioSlider,
        valueLabel: waterPrimaryRatioValueLabel
    )
    private lazy var waterShadowRatioRow = makeSliderRow(
        title: i18n("row.trail.waterShadowRatio", "阴影占比"),
        slider: waterShadowRatioSlider,
        valueLabel: waterShadowRatioValueLabel
    )
    private lazy var waterMixRandomnessRow = makeSliderRow(
        title: i18n("row.trail.waterMixRandomness", "随机混色强度"),
        slider: waterMixRandomnessSlider,
        valueLabel: waterMixRandomnessValueLabel
    )
    private lazy var waterMixSeedLockRow = makeSwitchRow(
        title: i18n("row.trail.waterSeedLock", "随机种子锁定"),
        subtitle: i18n("row.trail.waterSeedLock.subtitle", "锁定后每次效果风格稳定"),
        toggle: waterMixSeedLockSwitch
    )
    private lazy var trailEffectColorRow = makeColorRow(title: i18n("row.trail.effectColor", "特效颜色"), control: trailEffectColorWell)
    private lazy var trailEffectColorFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.trailEffectColor)
    private lazy var neonColorsRow = makeNeonColorsRow()
    private lazy var neonColorsFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.trailNeonColors)
    private lazy var rainbowColorsRow = makeDynamicPaletteRow(
        title: i18n("row.trail.rainbowColors", "彩虹颜色"),
        colorsStack: rainbowColorsStack,
        addButton: addRainbowColorButton,
        removeButton: removeRainbowColorButton
    )
    private lazy var rainbowColorsFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.trailRainbowColors)
    private lazy var trailEffectTypeRow = makePopupRow(title: i18n("row.trail.effectType", "特效类型"), popup: trailEffectPopup)
    private lazy var trailEffectsEnabledRow = makeSwitchRow(
        title: i18n("row.trail.effects.enabled", "开启特效"),
        subtitle: i18n("row.trail.effects.enabled.subtitle", "关闭后不渲染任何轨迹附加特效"),
        toggle: trailEffectsSwitch
    )
    private lazy var disableTrailFadeRow = makeSwitchRow(
        title: i18n("row.trail.disableFade", "禁用渐隐/强制实色"),
        subtitle: i18n("row.trail.disableFade.subtitle", "开启后轨迹与特效颜色不再渐隐，保持你设置的透明度"),
        toggle: disableTrailFadeSwitch
    )
    private lazy var electricArcDensityRow = makeSliderRow(
        title: i18n("row.trail.electricDensity", "电弧密度"),
        slider: electricArcDensitySlider,
        valueLabel: electricArcDensityValueLabel
    )
    private lazy var electricArcLengthRow = makeSliderRow(
        title: i18n("row.trail.electricLength", "电弧长度"),
        slider: electricArcLengthSlider,
        valueLabel: electricArcLengthValueLabel
    )
    private lazy var electricArcWidthRow = makeSliderRow(
        title: i18n("row.trail.electricWidth", "电弧宽度"),
        slider: electricArcWidthSlider,
        valueLabel: electricArcWidthValueLabel
    )
    private lazy var inkDensityRow = makeSliderRow(
        title: i18n("row.trail.inkDensity", "墨迹密度"),
        slider: inkDensitySlider,
        valueLabel: inkDensityValueLabel
    )
    private lazy var inkSizeRow = makeSliderRow(
        title: i18n("row.trail.inkSize", "墨迹大小"),
        slider: inkSizeSlider,
        valueLabel: inkSizeValueLabel
    )
    private lazy var inkLifetimeRow = makeSliderRow(
        title: i18n("row.trail.inkLifetime", "墨迹持续时间（毫秒）"),
        slider: inkLifetimeSlider,
        valueLabel: inkLifetimeValueLabel
    )
    private lazy var inkColorsRow = makeDynamicPaletteRow(
        title: i18n("row.trail.inkColors", "墨迹颜色"),
        colorsStack: inkColorsStack,
        addButton: addInkColorButton,
        removeButton: removeInkColorButton
    )
    private lazy var inkColorsFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.trailInkColors)
    private lazy var particleDensityRow = makeSliderRow(
        title: i18n("row.trail.particleDensity", "粒子密度"),
        slider: particleDensitySlider,
        valueLabel: particleDensityValueLabel
    )
    private lazy var particleSizeRow = makeSliderRow(
        title: i18n("row.trail.particleSize", "粒子大小"),
        slider: particleSizeSlider,
        valueLabel: particleSizeValueLabel
    )
    private lazy var particleLifetimeRow = makeSliderRow(
        title: i18n("row.trail.particleLifetime", "粒子持续时间（毫秒）"),
        slider: particleLifetimeSlider,
        valueLabel: particleLifetimeValueLabel
    )
    private lazy var particleSpeedRow = makeSliderRow(
        title: i18n("row.trail.particleSpeed", "粒子速度"),
        slider: particleSpeedSlider,
        valueLabel: particleSpeedValueLabel
    )
    private lazy var particleColorsRow = makeDynamicPaletteRow(
        title: i18n("row.trail.particleColors", "粒子颜色"),
        colorsStack: particleColorsStack,
        addButton: addParticleColorButton,
        removeButton: removeParticleColorButton
    )
    private lazy var particleColorsFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.trailParticleColors)
    private lazy var waterSplashSizeRow = makeSliderRow(
        title: i18n("row.trail.waterSplashSize", "水花大小"),
        slider: waterSplashSizeSlider,
        valueLabel: waterSplashSizeValueLabel
    )
    private lazy var waterSplashSpeedRow = makeSliderRow(
        title: i18n("row.trail.waterSplashSpeed", "水花速度"),
        slider: waterSplashSpeedSlider,
        valueLabel: waterSplashSpeedValueLabel
    )
    private lazy var waterSplashLifetimeRow = makeSliderRow(
        title: i18n("row.trail.waterSplashLifetime", "水花时间（毫秒）"),
        slider: waterSplashLifetimeSlider,
        valueLabel: waterSplashLifetimeValueLabel
    )
    private lazy var waterSplashDensityRow = makeSliderRow(
        title: i18n("row.trail.waterSplashDensity", "水花密度"),
        slider: waterSplashDensitySlider,
        valueLabel: waterSplashDensityValueLabel
    )
    private lazy var waterSplashColorRow = makeColorRow(
        title: i18n("row.trail.waterSplashColor", "水花颜色"),
        control: waterSplashColorWell
    )
    private lazy var waterSplashColorFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.trailWaterSplashColor)
    private lazy var trailWidthRow = makeSliderRow(title: i18n("row.trail.width", "轨迹粗细"), slider: trailWidthSlider, valueLabel: trailWidthValueLabel)
    private lazy var trailLengthRow = makeSliderRow(title: i18n("row.trail.lengthMs", "轨迹长度（毫秒）"), slider: trailLengthSlider, valueLabel: trailLengthValueLabel)
    private lazy var speedBurstTypeRow = makePopupRow(title: i18n("row.speedBurst.type", "爆发类型"), popup: speedBurstTypePopup)
    private lazy var speedBurstLineColorRow = makeColorRow(title: i18n("row.speedBurst.lineColor", "爆发线颜色"), control: speedBurstLineColorWell)
    private lazy var speedBurstLineColorFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.speedBurstLineColor)
    private lazy var speedBurstAccentColorRow = makeColorRow(title: i18n("row.speedBurst.accentColor", "端点爆发颜色"), control: speedBurstAccentColorWell)
    private lazy var speedBurstAccentColorFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.speedBurstAccentColor)
    private lazy var speedBurstVelocityRow = makeSliderRow(title: i18n("row.speedBurst.velocity", "触发速度阈值"), slider: speedBurstVelocitySlider, valueLabel: speedBurstVelocityValueLabel)
    private lazy var speedBurstCooldownRow = makeSliderRow(title: i18n("row.speedBurst.cooldown", "冷却时间（毫秒）"), slider: speedBurstCooldownSlider, valueLabel: speedBurstCooldownValueLabel)
    private lazy var speedBurstDurationRow = makeSliderRow(title: i18n("row.speedBurst.duration", "爆发线时长（毫秒）"), slider: speedBurstDurationSlider, valueLabel: speedBurstDurationValueLabel)
    private lazy var speedSurgeScaleModeRow = makePopupRow(
        title: i18n("row.speedBurst.surgeScaleMode", "放大逻辑"),
        popup: speedSurgeScaleModePopup
    )
    private lazy var speedBurstDurationMinRow = makeSliderRow(
        title: i18n("row.speedBurst.durationMin", "爆发最小时长（毫秒）"),
        slider: speedBurstDurationMinSlider,
        valueLabel: speedBurstDurationMinValueLabel
    )
    private lazy var speedBurstDurationMaxRow = makeSliderRow(
        title: i18n("row.speedBurst.durationMax", "爆发最大时长（毫秒）"),
        slider: speedBurstDurationMaxSlider,
        valueLabel: speedBurstDurationMaxValueLabel
    )
    private lazy var speedBurstJitterRow = makeSliderRow(title: i18n("row.speedBurst.jitter", "爆发线抖动幅度"), slider: speedBurstJitterSlider, valueLabel: speedBurstJitterValueLabel)
    private lazy var speedBurstMinLengthRow = makeSliderRow(title: i18n("row.speedBurst.minLength", "爆发线最小长度"), slider: speedBurstMinLengthSlider, valueLabel: speedBurstMinLengthValueLabel)
    private lazy var speedBurstMaxLengthRow = makeSliderRow(title: i18n("row.speedBurst.maxLength", "爆发线最大长度"), slider: speedBurstMaxLengthSlider, valueLabel: speedBurstMaxLengthValueLabel)
    private lazy var speedBurstWidthMultiplierRow = makeSliderRow(title: i18n("row.speedBurst.widthMultiplier", "爆发线宽系数"), slider: speedBurstWidthMultiplierSlider, valueLabel: speedBurstWidthMultiplierValueLabel)
    private lazy var speedBurstTrailMinScaleRow = makeSliderRow(
        title: i18n("row.speedBurst.trailScaleMin", "轨迹最小放大系数"),
        slider: speedBurstTrailMinScaleSlider,
        valueLabel: speedBurstTrailMinScaleValueLabel
    )
    private lazy var speedBurstTrailMaxScaleRow = makeSliderRow(
        title: i18n("row.speedBurst.trailScaleMax", "轨迹最大放大系数"),
        slider: speedBurstTrailMaxScaleSlider,
        valueLabel: speedBurstTrailMaxScaleValueLabel
    )
    private lazy var speedBurstEffectMinScaleRow = makeSliderRow(
        title: i18n("row.speedBurst.effectScaleMin", "最小特效放大系数"),
        slider: speedBurstEffectMinScaleSlider,
        valueLabel: speedBurstEffectMinScaleValueLabel
    )
    private lazy var speedBurstEffectMaxScaleRow = makeSliderRow(
        title: i18n("row.speedBurst.effectScaleMax", "最大特效放大系数"),
        slider: speedBurstEffectMaxScaleSlider,
        valueLabel: speedBurstEffectMaxScaleValueLabel
    )
    private lazy var speedBurstAccentDurationRow = makeSliderRow(title: i18n("row.speedBurst.accentDuration", "端点爆发时长（毫秒）"), slider: speedBurstAccentDurationSlider, valueLabel: speedBurstAccentDurationValueLabel)
    private lazy var speedBurstAccentSizeRow = makeSliderRow(title: i18n("row.speedBurst.accentSize", "端点爆发大小"), slider: speedBurstAccentSizeSlider, valueLabel: speedBurstAccentSizeValueLabel)
    private lazy var darkAppearanceRow = makeSwitchRow(
        title: i18n("row.appearance.darkMode", "深色模式"),
        subtitle: i18n("row.appearance.darkMode.subtitle", "关闭后使用浅色模式"),
        toggle: darkAppearanceSwitch
    )
    private lazy var clickRadiusRow = makeSliderRow(title: i18n("row.click.radius", "点击效果半径"), slider: clickRadiusSlider, valueLabel: clickRadiusValueLabel)
    private lazy var clickDurationRow = makeSliderRow(title: i18n("row.click.duration", "点击效果时长（毫秒）"), slider: clickDurationSlider, valueLabel: clickDurationValueLabel)
    private lazy var waterImpactDensityRow = makeSliderRow(
        title: i18n("row.click.waterImpact.density", "水滴密度"),
        slider: waterImpactDensitySlider,
        valueLabel: waterImpactDensityValueLabel
    )
    private lazy var waterImpactSpreadSpeedRow = makeSliderRow(
        title: i18n("row.click.waterImpact.spreadSpeed", "水滴扩散速度"),
        slider: waterImpactSpreadSpeedSlider,
        valueLabel: waterImpactSpreadSpeedValueLabel
    )
    private lazy var waterImpactLifetimeRow = makeSliderRow(
        title: i18n("row.click.waterImpact.lifetime", "水滴时长（毫秒）"),
        slider: waterImpactLifetimeSlider,
        valueLabel: waterImpactLifetimeValueLabel
    )
    private lazy var waterImpactDropletSizeRow = makeSliderRow(
        title: i18n("row.click.waterImpact.size", "水滴大小"),
        slider: waterImpactDropletSizeSlider,
        valueLabel: waterImpactDropletSizeValueLabel
    )
    private lazy var clickParticleExplosionDensityRow = makeSliderRow(
        title: i18n("row.click.particleExplosion.density", "粒子密度"),
        slider: clickParticleExplosionDensitySlider,
        valueLabel: clickParticleExplosionDensityValueLabel
    )
    private lazy var clickParticleExplosionSizeRow = makeSliderRow(
        title: i18n("row.click.particleExplosion.size", "粒子大小"),
        slider: clickParticleExplosionSizeSlider,
        valueLabel: clickParticleExplosionSizeValueLabel
    )
    private lazy var clickParticleExplosionLifetimeRow = makeSliderRow(
        title: i18n("row.click.particleExplosion.lifetime", "粒子持续时间（毫秒）"),
        slider: clickParticleExplosionLifetimeSlider,
        valueLabel: clickParticleExplosionLifetimeValueLabel
    )
    private lazy var clickParticleExplosionSpeedRow = makeSliderRow(
        title: i18n("row.click.particleExplosion.speed", "粒子速度"),
        slider: clickParticleExplosionSpeedSlider,
        valueLabel: clickParticleExplosionSpeedValueLabel
    )
    private lazy var clickParticleExplosionColorsRow = makeDynamicPaletteRow(
        title: i18n("row.click.particleExplosion.colors", "粒子颜色"),
        colorsStack: clickParticleExplosionColorsStack,
        addButton: addClickParticleExplosionColorButton,
        removeButton: removeClickParticleExplosionColorButton
    )
    private lazy var clickParticleExplosionColorsFadeRow = makeColorFadeRow(for: ColorFadeSettingKey.clickParticleExplosionColors)

    private var clickToggleButtons: [MouseButtonKind: NSSwitch] = [:]
    private var clickColorWells: [MouseButtonKind: NSColorWell] = [:]
    private var clickColorFadeRows: [MouseButtonKind: NSView] = [:]
    private var clickParticleExplosionColorWells: [NSColorWell] = []
    private var toggleButtonToKind: [ObjectIdentifier: MouseButtonKind] = [:]
    private var colorWellToKind: [ObjectIdentifier: MouseButtonKind] = [:]
    private var colorFadeSwitches: [String: NSSwitch] = [:]
    private var colorFadeRows: [String: NSView] = [:]
    private var colorFadeSwitchToKey: [ObjectIdentifier: String] = [:]
    private weak var rootBackgroundView: NSView?
    private weak var rightPanelContainerView: NSView?
    private weak var sidebarContainerView: NSView?
    private weak var sidebarBorderView: NSView?
    private var sectionCardContainers: [NSView] = []
    private var rowSeparatorViews: [NSView] = []

    private var shortcutCaptureMonitor: Any?
    private var isShortcutRecording = false
    private var presetManagerRows: [PresetManagerRow] = []
    private var presetManagerPanel: NSPanel?
    private weak var presetManagerTableView: NSTableView?

    init(initialSettings: AppSettings) {
        settings = initialSettings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = i18n("window.settings.title", "CursorTrailBar 设置")
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
        rootBackgroundView = backgroundView
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
        rightPanelContainerView = rightPanelContainer

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
        let aboutSection = buildAboutSection()
        let trailSection = buildTrailSection()
        let trailEffectSection = buildTrailEffectSection()
        let speedBurstSection = buildSpeedBurstSection()
        let clickSection = buildClickSection()
        let magnifierSection = buildMagnifierSection()
        let trailComposite = makeSidebarCompositeContent(sections: [trailSection, trailEffectSection, speedBurstSection])
        let generalComposite = makeSidebarCompositeContent(sections: [regularSection, aboutSection])
        let contentsByTab: [(SidebarTab, NSView)] = [
            (.trailEffects, trailComposite),
            (.clickEffects, clickSection),
            (.magnifier, magnifierSection),
            (.general, generalComposite),
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
        applyAppearanceColors()
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
        sidebarContainerView = sidebar

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
        sidebarBorderView = rightBorder
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
        let effectiveAppearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for (tab, button) in sidebarButtons {
            let isSelected = tab == activeSidebarTab
            let normalColor = isDark
                ? NSColor(calibratedWhite: 0.78, alpha: 1.0)
                : NSColor.labelColor
            let titleColor = isSelected ? NSColor.white : normalColor
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

        darkAppearanceSwitch.target = self
        darkAppearanceSwitch.action = #selector(darkAppearanceSwitchChanged(_:))

        speedBurstSwitch.target = self
        speedBurstSwitch.action = #selector(speedBurstSwitchChanged(_:))
        trailEffectsSwitch.target = self
        trailEffectsSwitch.action = #selector(trailEffectsSwitchChanged(_:))
        disableTrailFadeSwitch.target = self
        disableTrailFadeSwitch.action = #selector(disableTrailFadeSwitchChanged(_:))

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
        waterHighlightColorWell.target = self
        waterHighlightColorWell.action = #selector(waterHighlightColorChanged(_:))
        waterPrimaryColorWell.target = self
        waterPrimaryColorWell.action = #selector(waterPrimaryColorChanged(_:))
        waterShadowColorWell.target = self
        waterShadowColorWell.action = #selector(waterShadowColorChanged(_:))
        waterSplashColorWell.target = self
        waterSplashColorWell.action = #selector(waterSplashColorChanged(_:))
        magnifierBorderColorWell.target = self
        magnifierBorderColorWell.action = #selector(magnifierBorderColorChanged(_:))
        addInkColorButton.target = self
        addInkColorButton.action = #selector(addInkColorClicked(_:))
        removeInkColorButton.target = self
        removeInkColorButton.action = #selector(removeInkColorClicked(_:))
        addParticleColorButton.target = self
        addParticleColorButton.action = #selector(addParticleColorClicked(_:))
        removeParticleColorButton.target = self
        removeParticleColorButton.action = #selector(removeParticleColorClicked(_:))
        addClickParticleExplosionColorButton.target = self
        addClickParticleExplosionColorButton.action = #selector(addClickParticleExplosionColorClicked(_:))
        removeClickParticleExplosionColorButton.target = self
        removeClickParticleExplosionColorButton.action = #selector(removeClickParticleExplosionColorClicked(_:))

        trailStylePopup.target = self
        trailStylePopup.action = #selector(trailStyleChanged(_:))
        trailStylePopup.addItems(withTitles: TrailRenderStyle.allCases.map(\.title))

        trailEffectPopup.target = self
        trailEffectPopup.action = #selector(trailEffectStyleChanged(_:))
        trailEffectPopup.addItems(withTitles: TrailEffectStyle.allCases.map(\.title))

        speedBurstTypePopup.target = self
        speedBurstTypePopup.action = #selector(speedBurstTypeChanged(_:))
        speedBurstTypePopup.addItems(withTitles: SpeedBurstEffectType.allCases.map(\.title))

        speedSurgeScaleModePopup.target = self
        speedSurgeScaleModePopup.action = #selector(speedSurgeScaleModeChanged(_:))
        speedSurgeScaleModePopup.addItems(withTitles: SpeedSurgeScaleMode.allCases.map(\.title))

        clickStylePopup.target = self
        clickStylePopup.action = #selector(clickVisualStyleChanged(_:))
        clickStylePopup.addItems(withTitles: ClickVisualStyle.allCases.map(\.title))

        trailPresetPopup.target = self
        trailPresetPopup.action = #selector(trailPresetChanged(_:))
        reloadTrailPresetPopup(selecting: selectedTrailPresetOption)

        presetManageButton.target = self
        presetManageButton.action = #selector(openPresetManagerClicked(_:))
        presetManageButton.bezelStyle = .rounded
        presetManageButton.controlSize = .small
        presetManageButton.title = i18n("button.preset.manage", "管理")

        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        refreshLanguageOptions(reloadFromDisk: true)

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
        openLanguagePacksFolderButton.target = self
        openLanguagePacksFolderButton.action = #selector(openLanguagePacksFolder(_:))
        addRainbowColorButton.target = self
        addRainbowColorButton.action = #selector(addRainbowColorClicked(_:))
        removeRainbowColorButton.target = self
        removeRainbowColorButton.action = #selector(removeRainbowColorClicked(_:))
        waterMixSeedLockSwitch.target = self
        waterMixSeedLockSwitch.action = #selector(waterMixSeedLockSwitchChanged(_:))

        magnifierShortcutHint.stringValue = i18n("hint.magnifier.shortcut", "点击录制后按下按键/鼠标键，按住即可触发放大镜。")
        openInputMonitoringSettingsButton.title = i18n("button.permission.inputMonitoring", "前往输入监控设置")
        openAccessibilitySettingsButton.title = i18n("button.permission.accessibility", "前往辅助功能设置")
        openScreenCaptureSettingsButton.title = i18n("button.permission.screenCapture", "前往屏幕录制设置")
        openLogFolderButton.title = i18n("button.openLogFolder", "打开日志文件夹")
        openLanguagePacksFolderButton.title = i18n("button.openLanguagePackFolder", "打开目录")
    }

    private func refreshLanguageOptions(reloadFromDisk: Bool) {
        if reloadFromDisk {
            LocalizationManager.shared.reloadCustomLanguagePacks()
        }
        availableLanguageOptions = LocalizationManager.shared.availableLanguages()
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: availableLanguageOptions.map(\.displayName))
        if let index = availableLanguageOptions.firstIndex(where: { $0.code == settings.languageCode }) {
            languagePopup.selectItem(at: index)
        } else if let first = availableLanguageOptions.first {
            settings.languageCode = first.code
            languagePopup.selectItem(at: 0)
        }
    }

    private func presetTitle(for option: TrailPresetOption) -> String {
        switch option {
        case .custom:
            return i18n("preset.custom", "自定义")
        case .thunderFirstForm:
            return i18n("preset.thunderFirstForm", "雷之呼吸")
        case .waterFirstForm:
            return i18n("preset.waterFirstForm", "水之呼吸")
        case .userPreset(let id):
            return customTrailPresets.first(where: { $0.id == id })?.name ?? i18n("preset.custom", "自定义")
        }
    }

    private func reloadTrailPresetPopup(selecting option: TrailPresetOption?) {
        customTrailPresets = AppSettings.loadCustomTrailPresets()
        trailPresetOptions = [.custom]
        trailPresetOptions.append(contentsOf: customTrailPresets.map { .userPreset(id: $0.id) })

        trailPresetPopup.removeAllItems()
        trailPresetPopup.addItems(withTitles: trailPresetOptions.map(presetTitle(for:)))

        let targetOption = option ?? selectedTrailPresetOption
        if let index = trailPresetOptions.firstIndex(of: targetOption) {
            trailPresetPopup.selectItem(at: index)
            selectedTrailPresetOption = targetOption
        } else {
            trailPresetPopup.selectItem(at: 0)
            selectedTrailPresetOption = .custom
        }
    }

    private func promptPresetName(title: String, message: String, defaultValue: String = "", icon: NSImage? = nil) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        if let icon {
            alert.icon = icon
        }
        alert.addButton(withTitle: i18n("button.confirm", "确定"))
        alert.addButton(withTitle: i18n("button.cancel", "取消"))

        let input = NSTextField(string: defaultValue)
        input.placeholderString = i18n("placeholder.preset.name", "请输入预设名称")
        input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func configureSliders() {
        configureSlider(trailWidthSlider, min: 0.1, max: 100, value: 2.2, action: #selector(trailWidthSliderChanged(_:)))
        configureSlider(trailLengthSlider, min: 1, max: 10_000, value: 650, action: #selector(trailLengthSliderChanged(_:)))
        configureSlider(speedBurstVelocitySlider, min: 100, max: 60_000, value: 1800, action: #selector(speedBurstVelocitySliderChanged(_:)))
        configureSlider(speedBurstCooldownSlider, min: 50, max: 3000, value: 450, action: #selector(speedBurstCooldownSliderChanged(_:)))
        configureSlider(speedBurstDurationSlider, min: 40, max: 800, value: 450, action: #selector(speedBurstDurationSliderChanged(_:)))
        configureSlider(speedBurstDurationMinSlider, min: 40, max: 800, value: 120, action: #selector(speedBurstDurationMinSliderChanged(_:)))
        configureSlider(speedBurstDurationMaxSlider, min: 40, max: 800, value: 320, action: #selector(speedBurstDurationMaxSliderChanged(_:)))
        configureSlider(speedBurstJitterSlider, min: 0, max: 30, value: 5, action: #selector(speedBurstJitterSliderChanged(_:)))
        configureSlider(speedBurstMinLengthSlider, min: 10, max: 5000, value: 110, action: #selector(speedBurstMinLengthSliderChanged(_:)))
        configureSlider(speedBurstMaxLengthSlider, min: 10, max: 5000, value: 220, action: #selector(speedBurstMaxLengthSliderChanged(_:)))
        configureSlider(speedBurstWidthMultiplierSlider, min: 0.2, max: 4.0, value: 1.55, action: #selector(speedBurstWidthMultiplierSliderChanged(_:)))
        configureSlider(speedBurstTrailMinScaleSlider, min: 0.1, max: 10.0, value: 1.1, action: #selector(speedBurstTrailMinScaleSliderChanged(_:)))
        configureSlider(speedBurstTrailMaxScaleSlider, min: 0.1, max: 10.0, value: 1.9, action: #selector(speedBurstTrailMaxScaleSliderChanged(_:)))
        configureSlider(speedBurstEffectMinScaleSlider, min: 0.1, max: 10.0, value: 1.1, action: #selector(speedBurstEffectMinScaleSliderChanged(_:)))
        configureSlider(speedBurstEffectMaxScaleSlider, min: 0.1, max: 10.0, value: 2.0, action: #selector(speedBurstEffectMaxScaleSliderChanged(_:)))
        configureSlider(speedBurstAccentDurationSlider, min: 40, max: 2000, value: 190, action: #selector(speedBurstAccentDurationSliderChanged(_:)))
        configureSlider(speedBurstAccentSizeSlider, min: 4, max: 400, value: 32, action: #selector(speedBurstAccentSizeSliderChanged(_:)))
        configureSlider(neonPrimaryWidthRatioSlider, min: 10, max: 90, value: 62, action: #selector(neonPrimaryWidthRatioSliderChanged(_:)))
        configureSlider(waterHighlightRatioSlider, min: 0, max: 100, value: 22, action: #selector(waterHighlightRatioSliderChanged(_:)))
        configureSlider(waterPrimaryRatioSlider, min: 0, max: 100, value: 56, action: #selector(waterPrimaryRatioSliderChanged(_:)))
        configureSlider(waterShadowRatioSlider, min: 0, max: 100, value: 22, action: #selector(waterShadowRatioSliderChanged(_:)))
        configureSlider(waterMixRandomnessSlider, min: 0, max: 100, value: 58, action: #selector(waterMixRandomnessSliderChanged(_:)))
        configureSlider(electricArcDensitySlider, min: 0.1, max: 10, value: 1.5, action: #selector(electricArcDensitySliderChanged(_:)))
        configureSlider(electricArcLengthSlider, min: 2, max: 80, value: 16, action: #selector(electricArcLengthSliderChanged(_:)))
        configureSlider(electricArcWidthSlider, min: 0.4, max: 6, value: 1.6, action: #selector(electricArcWidthSliderChanged(_:)))
        configureSlider(inkDensitySlider, min: 0.1, max: 10, value: 1.0, action: #selector(inkDensitySliderChanged(_:)))
        configureSlider(inkSizeSlider, min: 0.2, max: 10, value: 1.0, action: #selector(inkSizeSliderChanged(_:)))
        configureSlider(inkLifetimeSlider, min: 40, max: 2000, value: 560, action: #selector(inkLifetimeSliderChanged(_:)))
        configureSlider(particleDensitySlider, min: 0.1, max: 10, value: 1.0, action: #selector(particleDensitySliderChanged(_:)))
        configureSlider(particleSizeSlider, min: 0.2, max: 10, value: 1.0, action: #selector(particleSizeSliderChanged(_:)))
        configureSlider(particleLifetimeSlider, min: 40, max: 2000, value: 360, action: #selector(particleLifetimeSliderChanged(_:)))
        configureSlider(particleSpeedSlider, min: 0.1, max: 10, value: 1.0, action: #selector(particleSpeedSliderChanged(_:)))
        configureSlider(waterSplashSizeSlider, min: 0.1, max: 10.0, value: 1.0, action: #selector(waterSplashSizeSliderChanged(_:)))
        configureSlider(waterSplashSpeedSlider, min: 0.1, max: 10.0, value: 1.0, action: #selector(waterSplashSpeedSliderChanged(_:)))
        configureSlider(waterSplashLifetimeSlider, min: 40, max: 2000, value: 260, action: #selector(waterSplashLifetimeSliderChanged(_:)))
        configureSlider(waterSplashDensitySlider, min: 0.1, max: 10.0, value: 1.0, action: #selector(waterSplashDensitySliderChanged(_:)))
        configureSlider(trailEffectIntensitySlider, min: 0, max: 100, value: 82, action: #selector(trailEffectIntensitySliderChanged(_:)))
        configureSlider(clickRadiusSlider, min: 1, max: 600, value: 24, action: #selector(clickRadiusSliderChanged(_:)))
        configureSlider(clickDurationSlider, min: 40, max: 2000, value: 300, action: #selector(clickDurationSliderChanged(_:)))
        configureSlider(waterImpactDensitySlider, min: 0.1, max: 10.0, value: 1.0, action: #selector(waterImpactDensitySliderChanged(_:)))
        configureSlider(waterImpactSpreadSpeedSlider, min: 0.1, max: 10.0, value: 1.0, action: #selector(waterImpactSpreadSpeedSliderChanged(_:)))
        configureSlider(waterImpactLifetimeSlider, min: 40, max: 2000, value: 320, action: #selector(waterImpactLifetimeSliderChanged(_:)))
        configureSlider(waterImpactDropletSizeSlider, min: 0.1, max: 10.0, value: 1.0, action: #selector(waterImpactDropletSizeSliderChanged(_:)))
        configureSlider(clickParticleExplosionDensitySlider, min: 0.1, max: 10.0, value: 1.0, action: #selector(clickParticleExplosionDensitySliderChanged(_:)))
        configureSlider(clickParticleExplosionSizeSlider, min: 0.2, max: 10.0, value: 1.0, action: #selector(clickParticleExplosionSizeSliderChanged(_:)))
        configureSlider(clickParticleExplosionLifetimeSlider, min: 40, max: 2000, value: 320, action: #selector(clickParticleExplosionLifetimeSliderChanged(_:)))
        configureSlider(clickParticleExplosionSpeedSlider, min: 0.1, max: 10.0, value: 1.0, action: #selector(clickParticleExplosionSpeedSliderChanged(_:)))
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
        NSColorPanel.shared.showsAlpha = true
        let switches: [NSSwitch] =
            [launchAtLoginSwitch, loggingSwitch, statusItemSwitch, trackingSwitch, darkAppearanceSwitch, speedBurstSwitch, trailEffectsSwitch, disableTrailFadeSwitch, clickEffectsSwitch, magnifierEnabledSwitch, magnifierShowEffectsSwitch, waterMixSeedLockSwitch]
            + Array(clickToggleButtons.values)
            + Array(colorFadeSwitches.values)
        for item in switches {
            item.controlSize = .mini
        }

        let colorWells: [NSColorWell] =
            [trailColorWell, trailEffectColorWell, speedBurstLineColorWell, speedBurstAccentColorWell, neonPrimaryColorWell, neonSecondaryColorWell, waterHighlightColorWell, waterPrimaryColorWell, waterShadowColorWell, waterSplashColorWell, magnifierBorderColorWell]
            + Array(clickColorWells.values)
            + rainbowColorWells
            + inkEffectColorWells
            + particleEffectColorWells
            + clickParticleExplosionColorWells
        for colorWell in colorWells {
            colorWell.controlSize = .small
            colorWell.translatesAutoresizingMaskIntoConstraints = false
            colorWell.widthAnchor.constraint(equalToConstant: 32).isActive = true
            colorWell.heightAnchor.constraint(equalToConstant: 20).isActive = true
        }
    }

    private func syncEffectPaletteControls() {
        settings.rainbowTrailColors = sanitizedEffectPalette(
            settings.rainbowTrailColors,
            fallback: AppSettings.default.rainbowTrailColors,
            minCount: 2,
            maxCount: 10
        )
        settings.inkColors = sanitizedEffectPalette(settings.inkColors, fallback: AppSettings.default.inkColors, maxCount: 10)
        settings.particleColors = sanitizedEffectPalette(settings.particleColors, fallback: AppSettings.default.particleColors, maxCount: 10)
        settings.clickParticleExplosionColors = sanitizedEffectPalette(
            settings.clickParticleExplosionColors,
            fallback: AppSettings.default.clickParticleExplosionColors,
            maxCount: 7
        )
        syncPaletteWells(
            colors: settings.rainbowTrailColors,
            wells: &rainbowColorWells,
            stack: rainbowColorsStack,
            action: #selector(rainbowColorChanged(_:)),
            minCount: 2,
            maxCount: 10
        )
        syncPaletteWells(
            colors: settings.inkColors,
            wells: &inkEffectColorWells,
            stack: inkColorsStack,
            action: #selector(inkEffectPaletteColorChanged(_:)),
            maxCount: 10
        )
        syncPaletteWells(
            colors: settings.particleColors,
            wells: &particleEffectColorWells,
            stack: particleColorsStack,
            action: #selector(particleEffectPaletteColorChanged(_:)),
            maxCount: 10
        )
        syncPaletteWells(
            colors: settings.clickParticleExplosionColors,
            wells: &clickParticleExplosionColorWells,
            stack: clickParticleExplosionColorsStack,
            action: #selector(clickParticleExplosionPaletteColorChanged(_:)),
            maxCount: 7
        )
        removeInkColorButton.isEnabled = settings.inkColors.count > 1
        addInkColorButton.isEnabled = settings.inkColors.count < 10
        removeParticleColorButton.isEnabled = settings.particleColors.count > 1
        addParticleColorButton.isEnabled = settings.particleColors.count < 10
        removeClickParticleExplosionColorButton.isEnabled = settings.clickParticleExplosionColors.count > 1
        addClickParticleExplosionColorButton.isEnabled = settings.clickParticleExplosionColors.count < 7
        removeRainbowColorButton.isEnabled = settings.rainbowTrailColors.count > 2
        addRainbowColorButton.isEnabled = settings.rainbowTrailColors.count < 10
    }

    private func sanitizedEffectPalette(
        _ colors: [NSColor],
        fallback: [NSColor],
        minCount: Int = 1,
        maxCount: Int
    ) -> [NSColor] {
        let source = colors.isEmpty ? fallback : colors
        let count = min(maxCount, max(minCount, source.count))
        return Array(source.prefix(count))
    }

    private func syncPaletteWells(
        colors: [NSColor],
        wells: inout [NSColorWell],
        stack: NSStackView,
        action: Selector,
        minCount: Int = 1,
        maxCount: Int
    ) {
        let targetCount = min(maxCount, max(minCount, colors.count))
        while wells.count > targetCount, let well = wells.popLast() {
            stack.removeArrangedSubview(well)
            well.removeFromSuperview()
        }
        while wells.count < targetCount {
            let well = NSColorWell()
            well.controlSize = .small
            well.target = self
            well.action = action
            well.translatesAutoresizingMaskIntoConstraints = false
            well.widthAnchor.constraint(equalToConstant: 32).isActive = true
            well.heightAnchor.constraint(equalToConstant: 20).isActive = true
            stack.addArrangedSubview(well)
            wells.append(well)
        }
        for (index, well) in wells.enumerated() where index < colors.count {
            well.tag = index
            well.color = colors[index]
        }
    }

    private func buildRegularSection() -> NSView {
        launchAtLoginStatusLabel.font = .systemFont(ofSize: 11)
        launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        return makeSectionCard(
            title: i18n("section.general.title", "常规"),
            subtitle: i18n("section.general.subtitle", "开机与常驻相关设置"),
            rows: [
                makeSwitchRow(title: i18n("row.launchAtLogin.title", "开机启动"), subtitleLabel: launchAtLoginStatusLabel, toggle: launchAtLoginSwitch),
                makeSwitchRow(title: i18n("row.logging.title", "启用日志输出"), subtitle: i18n("row.logging.subtitle", "写入日志文件以便排查问题"), toggle: loggingSwitch),
                makeButtonRow(title: i18n("row.logFolder.title", "日志目录"), button: openLogFolderButton),
                makeSwitchRow(title: i18n("row.statusItem.title", "菜单栏显示图标"), subtitle: i18n("row.statusItem.subtitle", "关闭后仅保留主界面与全局功能"), toggle: statusItemSwitch),
                darkAppearanceRow,
                makeLanguageRow(),
            ]
        )
    }

    private func buildAboutSection() -> NSView {
        return makeSectionCard(
            title: i18n("section.about.title", "关于 Mouse cursor Trail"),
            subtitle: i18n("section.about.subtitle", "作者与软件版本信息"),
            rows: [
                makeInfoRow(title: i18n("row.about.appName", "软件名称"), value: currentAppDisplayName()),
                makeInfoRow(title: i18n("row.about.author", "作者名称"), value: aboutAuthorName),
                makeLinkRow(
                    title: i18n("row.about.email", "作者邮箱"),
                    text: aboutAuthorEmail,
                    urlString: "mailto:\(aboutAuthorEmail)"
                ),
                makeLinkRow(
                    title: i18n("row.about.homepage", "主页"),
                    text: aboutHomepage,
                    urlString: aboutHomepage
                ),
                makeInfoRow(title: i18n("row.about.version", "软件版本号"), value: aboutAppVersion),
            ]
        )
    }

    private func buildTrailSection() -> NSView {
        return makeSectionCard(
            title: i18n("section.trail.title", "轨迹"),
            subtitle: i18n("section.trail.subtitle", "鼠标轨迹与基础特效参数"),
            headerTrailing: trailPresetHeaderControl,
            rows: [
                makeSwitchRow(title: i18n("row.tracking.title", "开启轨迹"), subtitle: i18n("row.tracking.subtitle", "关闭后不再绘制轨迹"), toggle: trackingSwitch),
                trailTypeRow,
                trailColorRow,
                trailColorFadeRow,
                waterColorsRow,
                waterColorsFadeRow,
                waterHighlightRatioRow,
                waterPrimaryRatioRow,
                waterShadowRatioRow,
                waterMixRandomnessRow,
                waterMixSeedLockRow,
                neonColorsRow,
                neonColorsFadeRow,
                neonPrimaryWidthRatioRow,
                rainbowColorsRow,
                rainbowColorsFadeRow,
                trailWidthRow,
                trailLengthRow,
            ]
        )
    }

    private func buildTrailEffectSection() -> NSView {
        return makeSectionCard(
            title: i18n("section.trailEffect.title", "特效"),
            subtitle: i18n("section.trailEffect.subtitle", "轨迹附加特效类型与相关参数"),
            rows: [
                trailEffectsEnabledRow,
                trailEffectTypeRow,
                electricArcDensityRow,
                electricArcLengthRow,
                electricArcWidthRow,
                trailEffectColorRow,
                trailEffectColorFadeRow,
                inkDensityRow,
                inkSizeRow,
                inkLifetimeRow,
                inkColorsRow,
                inkColorsFadeRow,
                particleDensityRow,
                particleSizeRow,
                particleLifetimeRow,
                particleSpeedRow,
                particleColorsRow,
                particleColorsFadeRow,
                waterSplashSizeRow,
                waterSplashSpeedRow,
                waterSplashLifetimeRow,
                waterSplashDensityRow,
                waterSplashColorRow,
                waterSplashColorFadeRow,
            ]
        )
    }

    private func buildSpeedBurstSection() -> NSView {
        return makeSectionCard(
            title: i18n("section.speedBurst.title", "加速爆发"),
            subtitle: i18n("section.speedBurst.subtitle", "高速移动触发的额外爆发特效"),
            rows: [
                makeSwitchRow(title: i18n("row.speedBurst.enabled", "开启加速爆发"), subtitle: i18n("row.speedBurst.enabled.subtitle", "关闭后将不触发任何加速爆发特效"), toggle: speedBurstSwitch),
                speedBurstTypeRow,
                speedBurstVelocityRow,
                speedBurstCooldownRow,
                speedSurgeScaleModeRow,
                speedBurstAccentColorRow,
                speedBurstAccentColorFadeRow,
                speedBurstAccentDurationRow,
                speedBurstAccentSizeRow,
                speedBurstLineColorRow,
                speedBurstLineColorFadeRow,
                speedBurstDurationRow,
                speedBurstDurationMinRow,
                speedBurstDurationMaxRow,
                speedBurstMinLengthRow,
                speedBurstMaxLengthRow,
                speedBurstWidthMultiplierRow,
                speedBurstTrailMinScaleRow,
                speedBurstTrailMaxScaleRow,
                speedBurstEffectMinScaleRow,
                speedBurstEffectMaxScaleRow,
                speedBurstJitterRow,
            ]
        )
    }

    private func buildClickSection() -> NSView {
        var rows: [NSView] = [
            makeSwitchRow(title: i18n("row.click.enabled", "开启点击效果"), subtitle: i18n("row.click.enabled.subtitle", "关闭后不显示点击特效"), toggle: clickEffectsSwitch),
            makePopupRow(title: i18n("row.click.style", "点击样式"), popup: clickStylePopup),
            clickRadiusRow,
            clickDurationRow,
            waterImpactDensityRow,
            waterImpactSpreadSpeedRow,
            waterImpactLifetimeRow,
            waterImpactDropletSizeRow,
            clickParticleExplosionDensityRow,
            clickParticleExplosionSizeRow,
            clickParticleExplosionLifetimeRow,
            clickParticleExplosionSpeedRow,
            clickParticleExplosionColorsRow,
            clickParticleExplosionColorsFadeRow,
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

            let title = NSTextField(labelWithString: i18n("row.click.perButtonTitle", "%@ 点击效果", button.title))
            title.font = .systemFont(ofSize: 13, weight: .medium)

            let row = NSStackView(views: [title, colorWell, NSView(), toggle])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 8
            rows.append(row)

            let fadeKey = ColorFadeSettingKey.clickColor(button)
            let fadeRow = makeColorFadeRow(for: fadeKey)
            clickColorFadeRows[button] = fadeRow
            rows.append(fadeRow)
        }

        return makeSectionCard(
            title: i18n("section.click.title", "点击"),
            subtitle: i18n("section.click.subtitle", "点击特效开关、半径与各键位配色"),
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
            title: i18n("section.magnifier.title", "放大镜"),
            subtitle: i18n("section.magnifier.subtitle", "快捷键放大、视觉参数与权限入口"),
            rows: [
                makeSwitchRow(title: i18n("row.magnifier.enabled", "开启放大镜"), subtitle: i18n("row.magnifier.enabled.subtitle", "关闭后快捷键不再触发放大镜"), toggle: magnifierEnabledSwitch),
                makeSwitchRow(title: i18n("row.magnifier.showEffects", "放大时显示轨迹与特效"), subtitle: i18n("row.magnifier.showEffects.subtitle", "关闭后放大时只显示放大内容"), toggle: magnifierShowEffectsSwitch),
                makeSliderRow(title: i18n("row.magnifier.radius", "放大镜半径"), slider: magnifierRadiusSlider, valueLabel: magnifierRadiusValueLabel),
                makeSliderRow(title: i18n("row.magnifier.zoom", "放大倍率"), slider: magnifierZoomSlider, valueLabel: magnifierZoomValueLabel),
                makeSliderRow(title: i18n("row.magnifier.borderWidth", "边框粗细"), slider: magnifierBorderWidthSlider, valueLabel: magnifierBorderWidthValueLabel),
                makeColorRow(title: i18n("row.magnifier.borderColor", "边框颜色"), control: magnifierBorderColorWell),
                makeSliderRow(title: i18n("row.magnifier.shadow", "阴影强度"), slider: magnifierShadowSlider, valueLabel: magnifierShadowValueLabel),
                makeShortcutRecordRow(),
                makeStatusActionRow(statusLabel: inputMonitoringStatusLabel, actionButton: openInputMonitoringSettingsButton),
                makeStatusActionRow(statusLabel: accessibilityStatusLabel, actionButton: openAccessibilitySettingsButton),
                makeStatusActionRow(statusLabel: screenCaptureStatusLabel, actionButton: openScreenCaptureSettingsButton),
            ]
        )
    }

    private func makeTrailPresetHeaderControl() -> NSView {
        let label = NSTextField(labelWithString: i18n("label.trailPreset", "风格预设"))
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)

        trailPresetPopup.controlSize = .small
        trailPresetPopup.translatesAutoresizingMaskIntoConstraints = false
        trailPresetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 148).isActive = true

        let controlRow = NSStackView(views: [trailPresetPopup, presetManageButton])
        controlRow.orientation = .horizontal
        controlRow.alignment = .centerY
        controlRow.spacing = 4
        controlRow.setCustomSpacing(8, after: trailPresetPopup)

        let stack = NSStackView(views: [label, controlRow])
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
        sectionCardContainers.append(container)

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
        let row = makeButtonRow(title: i18n("row.magnifier.shortcut", "放大镜快捷键"), button: magnifierShortcutButton)
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
        let label = NSTextField(labelWithString: i18n("row.trail.rainbowColors", "彩虹颜色"))
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
        let label = NSTextField(labelWithString: i18n("row.trail.neonColors", "霓虹颜色"))
        label.setContentHuggingPriority(.required, for: .horizontal)
        let first = labeledColorWell(i18n("row.trail.neonPrimary", "主色"), colorWell: neonPrimaryColorWell)
        let second = labeledColorWell(i18n("row.trail.neonSecondary", "辅色"), colorWell: neonSecondaryColorWell)
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

    private func makeWaterColorsRow() -> NSView {
        let label = NSTextField(labelWithString: i18n("row.trail.waterColors", "水刃三色"))
        label.setContentHuggingPriority(.required, for: .horizontal)
        let highlight = labeledColorWell(i18n("row.trail.waterHighlight", "高光"), colorWell: waterHighlightColorWell)
        let primary = labeledColorWell(i18n("row.trail.waterPrimary", "主色"), colorWell: waterPrimaryColorWell)
        let shadow = labeledColorWell(i18n("row.trail.waterShadow", "阴影"), colorWell: waterShadowColorWell)
        let colors = NSStackView(views: [highlight, primary, shadow])
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

    private func makeColorFadeRow(for key: String) -> NSView {
        let fadeSwitch: NSSwitch
        if let existing = colorFadeSwitches[key] {
            fadeSwitch = existing
        } else {
            let created = NSSwitch()
            created.target = self
            created.action = #selector(colorFadeSwitchChanged(_:))
            colorFadeSwitches[key] = created
            colorFadeSwitchToKey[ObjectIdentifier(created)] = key
            fadeSwitch = created
        }
        let row = makeSwitchRow(
            title: i18n("row.trail.disableFade", "禁用渐隐/强制实色"),
            subtitle: i18n("row.trail.disableFade.subtitle", "开启后轨迹与特效颜色不再渐隐，保持你设置的透明度"),
            toggle: fadeSwitch
        )
        colorFadeRows[key] = row
        return row
    }

    private func makeDynamicPaletteRow(
        title: String,
        colorsStack: NSStackView,
        addButton: NSButton,
        removeButton: NSButton
    ) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        colorsStack.orientation = .horizontal
        colorsStack.alignment = .centerY
        colorsStack.distribution = .fill
        colorsStack.spacing = 6
        colorsStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for button in [addButton, removeButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.setButtonType(.momentaryPushIn)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        }

        let controls = NSStackView(views: [colorsStack, addButton, removeButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.distribution = .fill
        controls.spacing = 6
        controls.setContentCompressionResistancePriority(.required, for: .horizontal)
        controls.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, NSView(), controls])
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

    private func makeLanguageRow() -> NSView {
        let label = NSTextField(labelWithString: i18n("row.language.title", "语言"))
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        languagePopup.setContentHuggingPriority(.required, for: .horizontal)
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        languagePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true

        openLanguagePacksFolderButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, NSView(), languagePopup, openLanguagePacksFolderButton])
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

    private func makeInfoRow(title: String, value: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, NSView(), valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makeLinkRow(title: String, text: String, urlString: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let linkButton = NSButton(title: text, target: self, action: #selector(openExternalLink(_:)))
        linkButton.isBordered = false
        linkButton.font = .systemFont(ofSize: 12)
        linkButton.setButtonType(.momentaryPushIn)
        linkButton.alignment = .right
        linkButton.lineBreakMode = .byTruncatingMiddle
        linkButton.setContentHuggingPriority(.required, for: .horizontal)
        linkButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        linkButton.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 12),
            ]
        )

        if let url = URL(string: urlString) {
            externalLinkByButtonIdentifier[ObjectIdentifier(linkButton)] = url
        }

        let row = NSStackView(views: [label, NSView(), linkButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func currentAppDisplayName() -> String {
        let displayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        let bundleName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bundleName, !bundleName.isEmpty {
            return bundleName
        }
        return "Mouse cursor Trail"
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
        rowSeparatorViews.append(line)
        return line
    }

    func refreshAppearanceTheme() {
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        let effectiveAppearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let windowBackground = isDark
            ? NSColor(calibratedWhite: 0.12, alpha: 1.0)
            : NSColor.windowBackgroundColor
        let sidebarBackground = isDark
            ? NSColor(calibratedWhite: 0.16, alpha: 1.0)
            : NSColor.controlBackgroundColor
        let cardBackground = isDark
            ? NSColor(calibratedWhite: 0.18, alpha: 1.0)
            : NSColor(calibratedWhite: 0.96, alpha: 1.0)
        let separatorAlpha: CGFloat = isDark ? 0.20 : 0.04
        let separatorColor = (isDark ? NSColor.white : NSColor.separatorColor)
            .withAlphaComponent(separatorAlpha)

        rootBackgroundView?.layer?.backgroundColor = windowBackground.cgColor
        rightPanelContainerView?.layer?.backgroundColor = windowBackground.cgColor
        sidebarContainerView?.layer?.backgroundColor = sidebarBackground.cgColor
        sidebarBorderView?.layer?.backgroundColor = separatorColor.cgColor
        for cardContainer in sectionCardContainers {
            cardContainer.layer?.backgroundColor = cardBackground.cgColor
        }
        for separator in rowSeparatorViews {
            separator.layer?.backgroundColor = separatorColor.cgColor
        }
        refreshSidebarSelectionState()
    }

    /// 将 `settings` 同步到所有 UI 控件。
    /// Important: 通过 `isSyncingControls` 避免同步过程触发二次回写。
    private func syncControlsFromSettings() {
        isSyncingControls = true
        window?.title = i18n("window.settings.title", "CursorTrailBar 设置")
        presetManageButton.title = i18n("button.preset.manage", "管理")
        reloadTrailPresetPopup(selecting: selectedTrailPresetOption)

        launchAtLoginSwitch.state = settings.isLaunchAtLoginEnabled ? .on : .off
        loggingSwitch.state = settings.isLoggingEnabled ? .on : .off
        statusItemSwitch.state = settings.isStatusItemVisible ? .on : .off
        trackingSwitch.state = settings.isTrackingEnabled ? .on : .off
        darkAppearanceSwitch.state = settings.prefersDarkAppearance ? .on : .off
        speedBurstSwitch.state = settings.speedBurstEnabled ? .on : .off
        trailEffectsSwitch.state = settings.isTrailEffectsEnabled ? .on : .off
        disableTrailFadeSwitch.state = settings.disableTrailFadeAndForceSolid ? .on : .off
        for (key, toggle) in colorFadeSwitches {
            toggle.state = settings.isFadeDisabled(forColorKey: key) ? .on : .off
        }
        clickEffectsSwitch.state = settings.isClickEffectsEnabled ? .on : .off
        magnifierEnabledSwitch.state = settings.isMagnifierEnabled ? .on : .off
        magnifierShowEffectsSwitch.state = settings.showTrailEffectsWhileMagnifierActive ? .on : .off
        waterMixSeedLockSwitch.state = settings.waterMixSeedLocked ? .on : .off

        trailColorWell.color = settings.trailColor
        trailEffectColorWell.color = settings.trailEffectColor
        speedBurstLineColorWell.color = settings.speedBurstLineColor
        speedBurstAccentColorWell.color = settings.speedBurstAccentColor
        neonPrimaryColorWell.color = settings.neonPrimaryColor
        neonSecondaryColorWell.color = settings.neonSecondaryColor
        waterHighlightColorWell.color = settings.waterHighlightColor
        waterPrimaryColorWell.color = settings.waterPrimaryColor
        waterShadowColorWell.color = settings.waterShadowColor
        waterSplashColorWell.color = settings.waterSplashColor
        magnifierBorderColorWell.color = settings.magnifierBorderColor
        for index in rainbowColorWells.indices {
            let color = settings.rainbowTrailColors.indices.contains(index)
                ? settings.rainbowTrailColors[index]
                : settings.rainbowTrailColors.last ?? .systemBlue
            rainbowColorWells[index].color = color
        }
        syncEffectPaletteControls()

        trailWidthSlider.doubleValue = settings.trailWidth
        trailLengthSlider.doubleValue = settings.trailLengthMilliseconds
        speedBurstVelocitySlider.doubleValue = settings.speedBurstVelocityThreshold
        speedBurstCooldownSlider.doubleValue = settings.speedBurstCooldownMilliseconds
        speedBurstDurationSlider.doubleValue = settings.speedBurstDurationMilliseconds
        speedBurstDurationMinSlider.doubleValue = settings.speedBurstDurationMinMilliseconds
        speedBurstDurationMaxSlider.doubleValue = settings.speedBurstDurationMaxMilliseconds
        speedBurstJitterSlider.doubleValue = settings.speedBurstJitterAmplitude
        speedBurstMinLengthSlider.doubleValue = settings.speedBurstMinLength
        speedBurstMaxLengthSlider.doubleValue = settings.speedBurstMaxLength
        speedBurstWidthMultiplierSlider.doubleValue = settings.speedBurstWidthMultiplier
        speedBurstTrailMinScaleSlider.doubleValue = settings.speedBurstTrailMinScale
        speedBurstTrailMaxScaleSlider.doubleValue = settings.speedBurstTrailMaxScale
        speedBurstEffectMinScaleSlider.doubleValue = settings.speedBurstEffectMinScale
        speedBurstEffectMaxScaleSlider.doubleValue = settings.speedBurstEffectMaxScale
        speedBurstAccentDurationSlider.doubleValue = settings.speedBurstAccentDurationMilliseconds
        speedBurstAccentSizeSlider.doubleValue = settings.speedBurstAccentSize
        neonPrimaryWidthRatioSlider.doubleValue = settings.neonPrimaryWidthRatio
        waterHighlightRatioSlider.doubleValue = settings.waterHighlightRatio
        waterPrimaryRatioSlider.doubleValue = settings.waterPrimaryRatio
        waterShadowRatioSlider.doubleValue = settings.waterShadowRatio
        waterMixRandomnessSlider.doubleValue = settings.waterMixRandomness
        electricArcDensitySlider.doubleValue = settings.electricArcDensity
        electricArcLengthSlider.doubleValue = settings.electricArcLength
        electricArcWidthSlider.doubleValue = settings.electricArcWidth
        inkDensitySlider.doubleValue = settings.inkDensity
        inkSizeSlider.doubleValue = settings.inkSize
        inkLifetimeSlider.doubleValue = settings.inkLifetimeMilliseconds
        particleDensitySlider.doubleValue = settings.particleDensity
        particleSizeSlider.doubleValue = settings.particleSize
        particleLifetimeSlider.doubleValue = settings.particleLifetimeMilliseconds
        particleSpeedSlider.doubleValue = settings.particleSpeed
        waterSplashSizeSlider.doubleValue = settings.waterSplashSize
        waterSplashSpeedSlider.doubleValue = settings.waterSplashSpeed
        waterSplashLifetimeSlider.doubleValue = settings.waterSplashLifetimeMilliseconds
        waterSplashDensitySlider.doubleValue = settings.waterSplashDensity
        trailEffectIntensitySlider.doubleValue = settings.trailEffectIntensity
        clickRadiusSlider.doubleValue = settings.clickEffectRadius
        clickDurationSlider.doubleValue = settings.clickEffectDurationMilliseconds
        waterImpactDensitySlider.doubleValue = settings.waterImpactDropletDensity
        waterImpactSpreadSpeedSlider.doubleValue = settings.waterImpactSpreadSpeed
        waterImpactLifetimeSlider.doubleValue = settings.waterImpactLifetimeMilliseconds
        waterImpactDropletSizeSlider.doubleValue = settings.waterImpactDropletSize
        clickParticleExplosionDensitySlider.doubleValue = settings.clickParticleExplosionDensity
        clickParticleExplosionSizeSlider.doubleValue = settings.clickParticleExplosionSize
        clickParticleExplosionLifetimeSlider.doubleValue = settings.clickParticleExplosionLifetimeMilliseconds
        clickParticleExplosionSpeedSlider.doubleValue = settings.clickParticleExplosionSpeed
        magnifierRadiusSlider.doubleValue = settings.magnifierRadius
        magnifierZoomSlider.doubleValue = settings.magnifierZoom
        magnifierBorderWidthSlider.doubleValue = settings.magnifierBorderWidth
        magnifierShadowSlider.doubleValue = settings.magnifierShadowOpacity

        updateSliderValueLabels()

        if let index = TrailRenderStyle.allCases.firstIndex(of: settings.trailStyle) {
            trailStylePopup.selectItem(at: index)
        }
        if let index = TrailEffectStyle.allCases.firstIndex(of: settings.trailEffectStyle) {
            trailEffectPopup.selectItem(at: index)
        }
        if let index = SpeedBurstEffectType.allCases.firstIndex(of: settings.speedBurstType) {
            speedBurstTypePopup.selectItem(at: index)
        }
        if let index = SpeedSurgeScaleMode.allCases.firstIndex(of: settings.speedSurgeScaleMode) {
            speedSurgeScaleModePopup.selectItem(at: index)
        }
        if let index = ClickVisualStyle.allCases.firstIndex(of: settings.clickVisualStyle) {
            clickStylePopup.selectItem(at: index)
        }
        if let index = availableLanguageOptions.firstIndex(where: { $0.code == settings.languageCode }) {
            languagePopup.selectItem(at: index)
        }

        magnifierShortcutButton.title = isShortcutRecording
            ? i18n("shortcut.recordingPrompt", "按下键盘/鼠标快捷键…(Esc取消)")
            : settings.magnifierShortcut.displayText

        for button in MouseButtonKind.allCases {
            let style = settings.effectStyle(for: button)
            clickToggleButtons[button]?.state = style.isEnabled ? .on : .off
            clickColorWells[button]?.color = style.color
            clickColorWells[button]?.isEnabled = settings.isClickEffectsEnabled && style.isEnabled
        }

        updateToggleAvailability()
        refreshLaunchAtLoginHint()
        if presetManagerPanel != nil {
            reloadPresetManagerRows()
        }
        applyAppearanceColors()
        isSyncingControls = false
        refreshPermissionIndicators()
    }

    private func refreshLaunchAtLoginHint() {
        guard #available(macOS 13.0, *) else {
            launchAtLoginStatusLabel.stringValue = i18n("status.launchAtLogin.unsupported", "当前系统版本不支持应用内开机启动控制。")
            launchAtLoginStatusLabel.textColor = .systemRed
            return
        }
        if settings.isLaunchAtLoginEnabled {
            launchAtLoginStatusLabel.stringValue = i18n("status.launchAtLogin.enabled", "已请求开机启动；若未生效，请将 App 放到“应用程序”目录。")
            launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        } else {
            launchAtLoginStatusLabel.stringValue = i18n("status.launchAtLogin.disabled", "开机启动已关闭。")
            launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        }
    }

    private func updateToggleAvailability() {
        let clickEnabled = settings.isClickEffectsEnabled
        let isWaterImpactClick = settings.clickVisualStyle == .waterImpact
        let isParticleExplosionClick = settings.clickVisualStyle == .particleExplosion
        clickRadiusSlider.isEnabled = clickEnabled && !isWaterImpactClick && !isParticleExplosionClick
        clickDurationSlider.isEnabled = clickEnabled && !isWaterImpactClick && !isParticleExplosionClick
        waterImpactDensitySlider.isEnabled = clickEnabled && isWaterImpactClick
        waterImpactSpreadSpeedSlider.isEnabled = clickEnabled && isWaterImpactClick
        waterImpactLifetimeSlider.isEnabled = clickEnabled && isWaterImpactClick
        waterImpactDropletSizeSlider.isEnabled = clickEnabled && isWaterImpactClick
        clickParticleExplosionDensitySlider.isEnabled = clickEnabled && isParticleExplosionClick
        clickParticleExplosionSizeSlider.isEnabled = clickEnabled && isParticleExplosionClick
        clickParticleExplosionLifetimeSlider.isEnabled = clickEnabled && isParticleExplosionClick
        clickParticleExplosionSpeedSlider.isEnabled = clickEnabled && isParticleExplosionClick
        clickStylePopup.isEnabled = clickEnabled
        setRowVisibility(clickRadiusRow, isVisible: !isWaterImpactClick && !isParticleExplosionClick)
        setRowVisibility(clickDurationRow, isVisible: !isWaterImpactClick && !isParticleExplosionClick)
        setRowVisibility(waterImpactDensityRow, isVisible: isWaterImpactClick)
        setRowVisibility(waterImpactSpreadSpeedRow, isVisible: isWaterImpactClick)
        setRowVisibility(waterImpactLifetimeRow, isVisible: isWaterImpactClick)
        setRowVisibility(waterImpactDropletSizeRow, isVisible: isWaterImpactClick)
        setRowVisibility(clickParticleExplosionDensityRow, isVisible: isParticleExplosionClick)
        setRowVisibility(clickParticleExplosionSizeRow, isVisible: isParticleExplosionClick)
        setRowVisibility(clickParticleExplosionLifetimeRow, isVisible: isParticleExplosionClick)
        setRowVisibility(clickParticleExplosionSpeedRow, isVisible: isParticleExplosionClick)
        setRowVisibility(clickParticleExplosionColorsRow, isVisible: isParticleExplosionClick)
        setRowVisibility(clickParticleExplosionColorsFadeRow, isVisible: isParticleExplosionClick)
        clickParticleExplosionColorWells.forEach { $0.isEnabled = clickEnabled && isParticleExplosionClick }
        addClickParticleExplosionColorButton.isEnabled =
            clickEnabled && isParticleExplosionClick && settings.clickParticleExplosionColors.count < 7
        removeClickParticleExplosionColorButton.isEnabled =
            clickEnabled && isParticleExplosionClick && settings.clickParticleExplosionColors.count > 1
        colorFadeSwitches[ColorFadeSettingKey.clickParticleExplosionColors]?.isEnabled = clickEnabled && isParticleExplosionClick
        for button in MouseButtonKind.allCases {
            let buttonEnabled = settings.effectStyle(for: button).isEnabled
            clickToggleButtons[button]?.isEnabled = clickEnabled
            let fadeKey = ColorFadeSettingKey.clickColor(button)
            let showButtonColorControls = !isParticleExplosionClick
            clickColorWells[button]?.isHidden = !showButtonColorControls
            clickColorWells[button]?.isEnabled = clickEnabled && buttonEnabled && showButtonColorControls
            if let fadeRow = clickColorFadeRows[button] {
                setRowVisibility(fadeRow, isVisible: showButtonColorControls)
            }
            colorFadeSwitches[fadeKey]?.isEnabled = clickEnabled && buttonEnabled && showButtonColorControls
        }

        let rainbowEnabled = settings.trailStyle == .rainbow
        rainbowColorWells.forEach { $0.isEnabled = rainbowEnabled }
        addRainbowColorButton.isEnabled = rainbowEnabled && settings.rainbowTrailColors.count < 10
        removeRainbowColorButton.isEnabled = rainbowEnabled && settings.rainbowTrailColors.count > 2
        let trailEffectsEnabled = settings.isTrailEffectsEnabled
        trailEffectPopup.isEnabled = trailEffectsEnabled
        let isWaterStyle = settings.trailStyle == .waterBlade
        setRowVisibility(
            trailColorRow,
            isVisible: settings.trailStyle != .rainbow && settings.trailStyle != .neon && !isWaterStyle
        )
        setRowVisibility(
            trailColorFadeRow,
            isVisible: settings.trailStyle != .rainbow && settings.trailStyle != .neon && !isWaterStyle
        )
        setRowVisibility(rainbowColorsRow, isVisible: settings.trailStyle == .rainbow)
        setRowVisibility(rainbowColorsFadeRow, isVisible: settings.trailStyle == .rainbow)
        setRowVisibility(neonColorsRow, isVisible: settings.trailStyle == .neon)
        setRowVisibility(neonColorsFadeRow, isVisible: settings.trailStyle == .neon)
        setRowVisibility(neonPrimaryWidthRatioRow, isVisible: settings.trailStyle == .neon)
        setRowVisibility(waterColorsRow, isVisible: isWaterStyle)
        setRowVisibility(waterColorsFadeRow, isVisible: isWaterStyle)
        setRowVisibility(waterHighlightRatioRow, isVisible: isWaterStyle)
        setRowVisibility(waterPrimaryRatioRow, isVisible: isWaterStyle)
        setRowVisibility(waterShadowRatioRow, isVisible: isWaterStyle)
        setRowVisibility(waterMixRandomnessRow, isVisible: isWaterStyle)
        setRowVisibility(waterMixSeedLockRow, isVisible: isWaterStyle)
        colorFadeSwitches[ColorFadeSettingKey.trailColor]?.isEnabled = settings.trailStyle != .rainbow && settings.trailStyle != .neon && !isWaterStyle
        colorFadeSwitches[ColorFadeSettingKey.trailRainbowColors]?.isEnabled = settings.trailStyle == .rainbow
        colorFadeSwitches[ColorFadeSettingKey.trailNeonColors]?.isEnabled = settings.trailStyle == .neon
        colorFadeSwitches[ColorFadeSettingKey.trailWaterColors]?.isEnabled = isWaterStyle
        waterHighlightColorWell.isEnabled = isWaterStyle
        waterPrimaryColorWell.isEnabled = isWaterStyle
        waterShadowColorWell.isEnabled = isWaterStyle
        waterHighlightRatioSlider.isEnabled = isWaterStyle
        waterPrimaryRatioSlider.isEnabled = isWaterStyle
        waterShadowRatioSlider.isEnabled = isWaterStyle
        waterMixRandomnessSlider.isEnabled = isWaterStyle
        waterMixSeedLockSwitch.isEnabled = isWaterStyle
        neonPrimaryWidthRatioSlider.isEnabled = settings.trailStyle == .neon
        let isElectricEffect = settings.trailEffectStyle == .electric
        let isInkEffect = settings.trailEffectStyle == .ink
        let isParticleEffect = settings.trailEffectStyle == .particles
        let isWaterSplashEffect = settings.trailEffectStyle == .waterSplash
        setRowVisibility(trailEffectColorRow, isVisible: isElectricEffect)
        setRowVisibility(trailEffectColorFadeRow, isVisible: isElectricEffect)
        trailEffectColorWell.isEnabled = trailEffectsEnabled && isElectricEffect
        colorFadeSwitches[ColorFadeSettingKey.trailEffectColor]?.isEnabled = trailEffectsEnabled && isElectricEffect
        setRowVisibility(electricArcDensityRow, isVisible: isElectricEffect)
        setRowVisibility(electricArcLengthRow, isVisible: isElectricEffect)
        setRowVisibility(electricArcWidthRow, isVisible: isElectricEffect)
        electricArcDensitySlider.isEnabled = trailEffectsEnabled && isElectricEffect
        electricArcLengthSlider.isEnabled = trailEffectsEnabled && isElectricEffect
        electricArcWidthSlider.isEnabled = trailEffectsEnabled && isElectricEffect

        setRowVisibility(inkDensityRow, isVisible: isInkEffect)
        setRowVisibility(inkSizeRow, isVisible: isInkEffect)
        setRowVisibility(inkLifetimeRow, isVisible: isInkEffect)
        setRowVisibility(inkColorsRow, isVisible: isInkEffect)
        setRowVisibility(inkColorsFadeRow, isVisible: isInkEffect)
        inkDensitySlider.isEnabled = trailEffectsEnabled && isInkEffect
        inkSizeSlider.isEnabled = trailEffectsEnabled && isInkEffect
        inkLifetimeSlider.isEnabled = trailEffectsEnabled && isInkEffect
        colorFadeSwitches[ColorFadeSettingKey.trailInkColors]?.isEnabled = trailEffectsEnabled && isInkEffect
        inkEffectColorWells.forEach { $0.isEnabled = trailEffectsEnabled && isInkEffect }
        addInkColorButton.isEnabled = trailEffectsEnabled && isInkEffect && settings.inkColors.count < 10
        removeInkColorButton.isEnabled = trailEffectsEnabled && isInkEffect && settings.inkColors.count > 1

        setRowVisibility(particleDensityRow, isVisible: isParticleEffect)
        setRowVisibility(particleSizeRow, isVisible: isParticleEffect)
        setRowVisibility(particleLifetimeRow, isVisible: isParticleEffect)
        setRowVisibility(particleSpeedRow, isVisible: isParticleEffect)
        setRowVisibility(particleColorsRow, isVisible: isParticleEffect)
        setRowVisibility(particleColorsFadeRow, isVisible: isParticleEffect)
        particleDensitySlider.isEnabled = trailEffectsEnabled && isParticleEffect
        particleSizeSlider.isEnabled = trailEffectsEnabled && isParticleEffect
        particleLifetimeSlider.isEnabled = trailEffectsEnabled && isParticleEffect
        particleSpeedSlider.isEnabled = trailEffectsEnabled && isParticleEffect
        colorFadeSwitches[ColorFadeSettingKey.trailParticleColors]?.isEnabled = trailEffectsEnabled && isParticleEffect
        particleEffectColorWells.forEach { $0.isEnabled = trailEffectsEnabled && isParticleEffect }
        addParticleColorButton.isEnabled = trailEffectsEnabled && isParticleEffect && settings.particleColors.count < 10
        removeParticleColorButton.isEnabled = trailEffectsEnabled && isParticleEffect && settings.particleColors.count > 1

        setRowVisibility(waterSplashSizeRow, isVisible: isWaterSplashEffect)
        setRowVisibility(waterSplashSpeedRow, isVisible: isWaterSplashEffect)
        setRowVisibility(waterSplashLifetimeRow, isVisible: isWaterSplashEffect)
        setRowVisibility(waterSplashDensityRow, isVisible: isWaterSplashEffect)
        setRowVisibility(waterSplashColorRow, isVisible: isWaterSplashEffect)
        setRowVisibility(waterSplashColorFadeRow, isVisible: isWaterSplashEffect)
        waterSplashSizeSlider.isEnabled = trailEffectsEnabled && isWaterSplashEffect
        waterSplashSpeedSlider.isEnabled = trailEffectsEnabled && isWaterSplashEffect
        waterSplashLifetimeSlider.isEnabled = trailEffectsEnabled && isWaterSplashEffect
        waterSplashDensitySlider.isEnabled = trailEffectsEnabled && isWaterSplashEffect
        waterSplashColorWell.isEnabled = trailEffectsEnabled && isWaterSplashEffect
        colorFadeSwitches[ColorFadeSettingKey.trailWaterSplashColor]?.isEnabled = trailEffectsEnabled && isWaterSplashEffect

        let speedBurstEnabled = settings.speedBurstEnabled
        let isFirstFlashBurst = settings.speedBurstType == .firstFlash
        let isWaterSurgeBurst = settings.speedBurstType == .waterSurge
        speedBurstTypePopup.isEnabled = speedBurstEnabled
        speedBurstVelocitySlider.isEnabled = speedBurstEnabled
        speedBurstCooldownSlider.isEnabled = speedBurstEnabled
        speedBurstDurationSlider.isEnabled = speedBurstEnabled && isFirstFlashBurst
        speedSurgeScaleModePopup.isEnabled = speedBurstEnabled && isWaterSurgeBurst
        speedBurstDurationMinSlider.isEnabled = speedBurstEnabled && isWaterSurgeBurst
        speedBurstDurationMaxSlider.isEnabled = speedBurstEnabled && isWaterSurgeBurst
        speedBurstJitterSlider.isEnabled = speedBurstEnabled && isFirstFlashBurst
        speedBurstMinLengthSlider.isEnabled = speedBurstEnabled && isFirstFlashBurst
        speedBurstMaxLengthSlider.isEnabled = speedBurstEnabled && isFirstFlashBurst
        speedBurstWidthMultiplierSlider.isEnabled = speedBurstEnabled && isFirstFlashBurst
        speedBurstTrailMinScaleSlider.isEnabled = speedBurstEnabled && isWaterSurgeBurst
        speedBurstTrailMaxScaleSlider.isEnabled = speedBurstEnabled && isWaterSurgeBurst
        speedBurstEffectMinScaleSlider.isEnabled = speedBurstEnabled && isWaterSurgeBurst
        speedBurstEffectMaxScaleSlider.isEnabled = speedBurstEnabled && isWaterSurgeBurst
        speedBurstAccentDurationSlider.isEnabled = speedBurstEnabled && isFirstFlashBurst
        speedBurstAccentSizeSlider.isEnabled = speedBurstEnabled && isFirstFlashBurst
        speedBurstLineColorWell.isEnabled = speedBurstEnabled && isFirstFlashBurst
        speedBurstAccentColorWell.isEnabled = speedBurstEnabled && isFirstFlashBurst
        colorFadeSwitches[ColorFadeSettingKey.speedBurstLineColor]?.isEnabled = speedBurstEnabled && isFirstFlashBurst
        colorFadeSwitches[ColorFadeSettingKey.speedBurstAccentColor]?.isEnabled = speedBurstEnabled && isFirstFlashBurst
        setRowVisibility(speedBurstTypeRow, isVisible: true)
        setRowVisibility(speedBurstLineColorRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstLineColorFadeRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstAccentColorRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstAccentColorFadeRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstVelocityRow, isVisible: true)
        setRowVisibility(speedBurstCooldownRow, isVisible: true)
        setRowVisibility(speedSurgeScaleModeRow, isVisible: isWaterSurgeBurst)
        setRowVisibility(speedBurstDurationRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstDurationMinRow, isVisible: isWaterSurgeBurst)
        setRowVisibility(speedBurstDurationMaxRow, isVisible: isWaterSurgeBurst)
        setRowVisibility(speedBurstAccentDurationRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstAccentSizeRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstJitterRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstMinLengthRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstMaxLengthRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstWidthMultiplierRow, isVisible: isFirstFlashBurst)
        setRowVisibility(speedBurstTrailMinScaleRow, isVisible: isWaterSurgeBurst)
        setRowVisibility(speedBurstTrailMaxScaleRow, isVisible: isWaterSurgeBurst)
        setRowVisibility(speedBurstEffectMinScaleRow, isVisible: isWaterSurgeBurst)
        setRowVisibility(speedBurstEffectMaxScaleRow, isVisible: isWaterSurgeBurst)

        for button in MouseButtonKind.allCases {
            if let row = clickColorFadeRows[button] {
                setRowVisibility(row, isVisible: !isParticleExplosionClick)
            }
        }

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
        let px = i18n("unit.px", "px")
        let ms = i18n("unit.ms", "ms")
        let pxps = i18n("unit.pxps", "px/s")
        let multiplier = i18n("unit.multiplier", "x")
        let percent = i18n("unit.percent", "%")
        trailWidthValueLabel.stringValue = "\(rounded(Double(settings.trailWidth))) \(px)"
        trailLengthValueLabel.stringValue = "\(Int(settings.trailLengthMilliseconds)) \(ms)"
        speedBurstVelocityValueLabel.stringValue = "\(Int(settings.speedBurstVelocityThreshold)) \(pxps)"
        speedBurstCooldownValueLabel.stringValue = "\(Int(settings.speedBurstCooldownMilliseconds)) \(ms)"
        speedBurstDurationValueLabel.stringValue = "\(Int(settings.speedBurstDurationMilliseconds)) \(ms)"
        speedBurstDurationMinValueLabel.stringValue = "\(Int(settings.speedBurstDurationMinMilliseconds)) \(ms)"
        speedBurstDurationMaxValueLabel.stringValue = "\(Int(settings.speedBurstDurationMaxMilliseconds)) \(ms)"
        speedBurstJitterValueLabel.stringValue = "\(rounded(Double(settings.speedBurstJitterAmplitude)))"
        speedBurstMinLengthValueLabel.stringValue = "\(Int(settings.speedBurstMinLength)) \(px)"
        speedBurstMaxLengthValueLabel.stringValue = "\(Int(settings.speedBurstMaxLength)) \(px)"
        speedBurstWidthMultiplierValueLabel.stringValue = "\(rounded(Double(settings.speedBurstWidthMultiplier))) \(multiplier)"
        speedBurstTrailMinScaleValueLabel.stringValue = "\(rounded(Double(settings.speedBurstTrailMinScale))) \(multiplier)"
        speedBurstTrailMaxScaleValueLabel.stringValue = "\(rounded(Double(settings.speedBurstTrailMaxScale))) \(multiplier)"
        speedBurstEffectMinScaleValueLabel.stringValue = "\(rounded(Double(settings.speedBurstEffectMinScale))) \(multiplier)"
        speedBurstEffectMaxScaleValueLabel.stringValue = "\(rounded(Double(settings.speedBurstEffectMaxScale))) \(multiplier)"
        speedBurstAccentDurationValueLabel.stringValue = "\(Int(settings.speedBurstAccentDurationMilliseconds)) \(ms)"
        speedBurstAccentSizeValueLabel.stringValue = "\(Int(settings.speedBurstAccentSize)) \(px)"
        neonPrimaryWidthRatioValueLabel.stringValue = "\(Int(settings.neonPrimaryWidthRatio.rounded()))\(percent)"
        waterHighlightRatioValueLabel.stringValue = "\(Int(settings.waterHighlightRatio.rounded()))\(percent)"
        waterPrimaryRatioValueLabel.stringValue = "\(Int(settings.waterPrimaryRatio.rounded()))\(percent)"
        waterShadowRatioValueLabel.stringValue = "\(Int(settings.waterShadowRatio.rounded()))\(percent)"
        waterMixRandomnessValueLabel.stringValue = "\(Int(settings.waterMixRandomness.rounded()))\(percent)"
        electricArcDensityValueLabel.stringValue = "\(rounded(Double(settings.electricArcDensity))) \(multiplier)"
        electricArcLengthValueLabel.stringValue = "\(rounded(Double(settings.electricArcLength))) \(px)"
        electricArcWidthValueLabel.stringValue = "\(rounded(Double(settings.electricArcWidth))) \(px)"
        inkDensityValueLabel.stringValue = "\(rounded(Double(settings.inkDensity))) \(multiplier)"
        inkSizeValueLabel.stringValue = "\(rounded(Double(settings.inkSize))) \(multiplier)"
        inkLifetimeValueLabel.stringValue = "\(Int(settings.inkLifetimeMilliseconds)) \(ms)"
        particleDensityValueLabel.stringValue = "\(rounded(Double(settings.particleDensity))) \(multiplier)"
        particleSizeValueLabel.stringValue = "\(rounded(Double(settings.particleSize))) \(multiplier)"
        particleLifetimeValueLabel.stringValue = "\(Int(settings.particleLifetimeMilliseconds)) \(ms)"
        particleSpeedValueLabel.stringValue = "\(rounded(Double(settings.particleSpeed))) \(multiplier)"
        waterSplashSizeValueLabel.stringValue = "\(rounded(Double(settings.waterSplashSize))) \(multiplier)"
        waterSplashSpeedValueLabel.stringValue = "\(rounded(Double(settings.waterSplashSpeed))) \(multiplier)"
        waterSplashLifetimeValueLabel.stringValue = "\(Int(settings.waterSplashLifetimeMilliseconds)) \(ms)"
        waterSplashDensityValueLabel.stringValue = "\(rounded(Double(settings.waterSplashDensity))) \(multiplier)"
        trailEffectIntensityValueLabel.stringValue = "\(Int(settings.trailEffectIntensity.rounded()))\(percent)"
        clickRadiusValueLabel.stringValue = "\(Int(settings.clickEffectRadius)) \(px)"
        clickDurationValueLabel.stringValue = "\(Int(settings.clickEffectDurationMilliseconds)) \(ms)"
        waterImpactDensityValueLabel.stringValue = "\(rounded(Double(settings.waterImpactDropletDensity))) \(multiplier)"
        waterImpactSpreadSpeedValueLabel.stringValue = "\(rounded(Double(settings.waterImpactSpreadSpeed))) \(multiplier)"
        waterImpactLifetimeValueLabel.stringValue = "\(Int(settings.waterImpactLifetimeMilliseconds)) \(ms)"
        waterImpactDropletSizeValueLabel.stringValue = "\(rounded(Double(settings.waterImpactDropletSize))) \(multiplier)"
        clickParticleExplosionDensityValueLabel.stringValue = "\(rounded(Double(settings.clickParticleExplosionDensity))) \(multiplier)"
        clickParticleExplosionSizeValueLabel.stringValue = "\(rounded(Double(settings.clickParticleExplosionSize))) \(multiplier)"
        clickParticleExplosionLifetimeValueLabel.stringValue = "\(Int(settings.clickParticleExplosionLifetimeMilliseconds)) \(ms)"
        clickParticleExplosionSpeedValueLabel.stringValue = "\(rounded(Double(settings.clickParticleExplosionSpeed))) \(multiplier)"
        magnifierRadiusValueLabel.stringValue = "\(Int(settings.magnifierRadius)) \(px)"
        magnifierZoomValueLabel.stringValue = "\(rounded(Double(settings.magnifierZoom))) \(multiplier)"
        magnifierBorderWidthValueLabel.stringValue = "\(rounded(Double(settings.magnifierBorderWidth))) \(px)"
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
    private func darkAppearanceSwitchChanged(_ sender: NSSwitch) {
        settings.prefersDarkAppearance = sender.state == .on
        publishChanges()
    }

    @objc
    private func speedBurstSwitchChanged(_ sender: NSSwitch) {
        settings.speedBurstEnabled = sender.state == .on
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func trailEffectsSwitchChanged(_ sender: NSSwitch) {
        settings.isTrailEffectsEnabled = sender.state == .on
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func disableTrailFadeSwitchChanged(_ sender: NSSwitch) {
        settings.disableTrailFadeAndForceSolid = sender.state == .on
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func colorFadeSwitchChanged(_ sender: NSSwitch) {
        guard let key = colorFadeSwitchToKey[ObjectIdentifier(sender)] else { return }
        settings.setFadeDisabled(sender.state == .on, forColorKey: key)
        syncControlsFromSettings()
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
    private func waterHighlightColorChanged(_ sender: NSColorWell) {
        settings.waterHighlightColor = sender.color
        publishChanges()
    }

    @objc
    private func waterPrimaryColorChanged(_ sender: NSColorWell) {
        settings.waterPrimaryColor = sender.color
        publishChanges()
    }

    @objc
    private func waterShadowColorChanged(_ sender: NSColorWell) {
        settings.waterShadowColor = sender.color
        publishChanges()
    }

    @objc
    private func waterSplashColorChanged(_ sender: NSColorWell) {
        settings.waterSplashColor = sender.color
        publishChanges()
    }

    @objc
    private func inkEffectPaletteColorChanged(_ sender: NSColorWell) {
        guard settings.inkColors.indices.contains(sender.tag) else { return }
        settings.inkColors[sender.tag] = sender.color
        publishChanges()
    }

    @objc
    private func particleEffectPaletteColorChanged(_ sender: NSColorWell) {
        guard settings.particleColors.indices.contains(sender.tag) else { return }
        settings.particleColors[sender.tag] = sender.color
        publishChanges()
    }

    @objc
    private func clickParticleExplosionPaletteColorChanged(_ sender: NSColorWell) {
        guard settings.clickParticleExplosionColors.indices.contains(sender.tag) else { return }
        settings.clickParticleExplosionColors[sender.tag] = sender.color
        publishChanges()
    }

    @objc
    private func waterHighlightRatioSliderChanged(_ sender: NSSlider) {
        applyWaterRatioChange(channel: .highlight, rawValue: sender.doubleValue)
    }

    @objc
    private func waterPrimaryRatioSliderChanged(_ sender: NSSlider) {
        applyWaterRatioChange(channel: .primary, rawValue: sender.doubleValue)
    }

    @objc
    private func waterShadowRatioSliderChanged(_ sender: NSSlider) {
        applyWaterRatioChange(channel: .shadow, rawValue: sender.doubleValue)
    }

    @objc
    private func waterMixRandomnessSliderChanged(_ sender: NSSlider) {
        settings.waterMixRandomness = clampWaterMixRandomness(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func neonPrimaryWidthRatioSliderChanged(_ sender: NSSlider) {
        settings.neonPrimaryWidthRatio = clampNeonPrimaryWidthRatio(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func electricArcDensitySliderChanged(_ sender: NSSlider) {
        settings.electricArcDensity = clampElectricArcDensity(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func electricArcLengthSliderChanged(_ sender: NSSlider) {
        settings.electricArcLength = clampElectricArcLength(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func electricArcWidthSliderChanged(_ sender: NSSlider) {
        settings.electricArcWidth = clampElectricArcWidth(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func inkDensitySliderChanged(_ sender: NSSlider) {
        settings.inkDensity = clampInkDensity(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func inkSizeSliderChanged(_ sender: NSSlider) {
        settings.inkSize = clampInkSize(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func inkLifetimeSliderChanged(_ sender: NSSlider) {
        settings.inkLifetimeMilliseconds = clampInkLifetimeMilliseconds(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func particleDensitySliderChanged(_ sender: NSSlider) {
        settings.particleDensity = clampParticleDensity(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func particleSizeSliderChanged(_ sender: NSSlider) {
        settings.particleSize = clampParticleSize(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func particleLifetimeSliderChanged(_ sender: NSSlider) {
        settings.particleLifetimeMilliseconds = clampParticleLifetimeMilliseconds(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func particleSpeedSliderChanged(_ sender: NSSlider) {
        settings.particleSpeed = clampParticleSpeed(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func waterSplashSizeSliderChanged(_ sender: NSSlider) {
        settings.waterSplashSize = clampWaterSplashSize(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func waterSplashSpeedSliderChanged(_ sender: NSSlider) {
        settings.waterSplashSpeed = clampWaterSplashSpeed(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func waterSplashLifetimeSliderChanged(_ sender: NSSlider) {
        settings.waterSplashLifetimeMilliseconds = clampWaterSplashLifetimeMilliseconds(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func waterSplashDensitySliderChanged(_ sender: NSSlider) {
        settings.waterSplashDensity = clampWaterSplashDensity(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func trailEffectIntensitySliderChanged(_ sender: NSSlider) {
        settings.trailEffectIntensity = clampTrailEffectIntensity(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func addInkColorClicked(_ sender: NSButton) {
        guard settings.inkColors.count < 10 else { return }
        let nextColor = settings.inkColors.last ?? settings.trailEffectColor
        settings.inkColors.append(nextColor)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func removeInkColorClicked(_ sender: NSButton) {
        guard settings.inkColors.count > 1 else { return }
        settings.inkColors.removeLast()
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func addParticleColorClicked(_ sender: NSButton) {
        guard settings.particleColors.count < 10 else { return }
        let nextColor = settings.particleColors.last ?? settings.trailEffectColor
        settings.particleColors.append(nextColor)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func removeParticleColorClicked(_ sender: NSButton) {
        guard settings.particleColors.count > 1 else { return }
        settings.particleColors.removeLast()
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func addClickParticleExplosionColorClicked(_ sender: NSButton) {
        guard settings.clickParticleExplosionColors.count < 7 else { return }
        let nextColor = settings.clickParticleExplosionColors.last ?? settings.trailEffectColor
        settings.clickParticleExplosionColors.append(nextColor)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func removeClickParticleExplosionColorClicked(_ sender: NSButton) {
        guard settings.clickParticleExplosionColors.count > 1 else { return }
        settings.clickParticleExplosionColors.removeLast()
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func waterMixSeedLockSwitchChanged(_ sender: NSSwitch) {
        settings.waterMixSeedLocked = sender.state == .on
        publishChanges()
    }

    private enum WaterRatioChannel {
        case highlight
        case primary
        case shadow
    }

    private func applyWaterRatioChange(channel: WaterRatioChannel, rawValue: Double) {
        let changedValue = clampWaterMixRatio(rawValue)
        var highlight = settings.waterHighlightRatio
        var primary = settings.waterPrimaryRatio
        var shadow = settings.waterShadowRatio

        switch channel {
        case .highlight:
            highlight = changedValue
            let remainder = max(0, 100 - highlight)
            let sumOthers = primary + shadow
            if sumOthers <= 0.0001 {
                primary = remainder * 0.5
                shadow = remainder * 0.5
            } else {
                primary = remainder * (primary / sumOthers)
                shadow = remainder * (shadow / sumOthers)
            }
        case .primary:
            primary = changedValue
            let remainder = max(0, 100 - primary)
            let sumOthers = highlight + shadow
            if sumOthers <= 0.0001 {
                highlight = remainder * 0.5
                shadow = remainder * 0.5
            } else {
                highlight = remainder * (highlight / sumOthers)
                shadow = remainder * (shadow / sumOthers)
            }
        case .shadow:
            shadow = changedValue
            let remainder = max(0, 100 - shadow)
            let sumOthers = highlight + primary
            if sumOthers <= 0.0001 {
                highlight = remainder * 0.5
                primary = remainder * 0.5
            } else {
                highlight = remainder * (highlight / sumOthers)
                primary = remainder * (primary / sumOthers)
            }
        }

        settings.waterHighlightRatio = clampWaterMixRatio(Double(highlight))
        settings.waterPrimaryRatio = clampWaterMixRatio(Double(primary))
        settings.waterShadowRatio = clampWaterMixRatio(Double(shadow))
        settings.normalizeWaterMixRatios()
        syncControlsFromSettings()
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
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstTypeChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard SpeedBurstEffectType.allCases.indices.contains(index) else { return }
        settings.speedBurstType = SpeedBurstEffectType.allCases[index]
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedSurgeScaleModeChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard SpeedSurgeScaleMode.allCases.indices.contains(index) else { return }
        settings.speedSurgeScaleMode = SpeedSurgeScaleMode.allCases[index]
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func clickVisualStyleChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard ClickVisualStyle.allCases.indices.contains(index) else { return }
        settings.clickVisualStyle = ClickVisualStyle.allCases[index]
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func rainbowColorChanged(_ sender: NSColorWell) {
        settings.rainbowTrailColors = rainbowColorWells.map(\.color)
        publishChanges()
    }

    @objc
    private func addRainbowColorClicked(_ sender: NSButton) {
        guard settings.rainbowTrailColors.count < 10 else { return }
        let nextColor = settings.rainbowTrailColors.last ?? settings.trailColor
        settings.rainbowTrailColors.append(nextColor)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func removeRainbowColorClicked(_ sender: NSButton) {
        guard settings.rainbowTrailColors.count > 2 else { return }
        settings.rainbowTrailColors.removeLast()
        syncControlsFromSettings()
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
    private func speedBurstDurationMinSliderChanged(_ sender: NSSlider) {
        settings.speedBurstDurationMinMilliseconds = clampSpeedBurstDurationMilliseconds(sender.doubleValue)
        if settings.speedBurstDurationMaxMilliseconds < settings.speedBurstDurationMinMilliseconds {
            settings.speedBurstDurationMaxMilliseconds = settings.speedBurstDurationMinMilliseconds
        }
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstDurationMaxSliderChanged(_ sender: NSSlider) {
        settings.speedBurstDurationMaxMilliseconds = clampSpeedBurstDurationMilliseconds(sender.doubleValue)
        if settings.speedBurstDurationMaxMilliseconds < settings.speedBurstDurationMinMilliseconds {
            settings.speedBurstDurationMinMilliseconds = settings.speedBurstDurationMaxMilliseconds
        }
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
    private func speedBurstTrailMinScaleSliderChanged(_ sender: NSSlider) {
        settings.speedBurstTrailMinScale = clampSpeedSurgeTrailScale(sender.doubleValue)
        if settings.speedBurstTrailMaxScale < settings.speedBurstTrailMinScale {
            settings.speedBurstTrailMaxScale = settings.speedBurstTrailMinScale
        }
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstTrailMaxScaleSliderChanged(_ sender: NSSlider) {
        settings.speedBurstTrailMaxScale = clampSpeedSurgeTrailScale(sender.doubleValue)
        if settings.speedBurstTrailMaxScale < settings.speedBurstTrailMinScale {
            settings.speedBurstTrailMinScale = settings.speedBurstTrailMaxScale
        }
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstEffectMinScaleSliderChanged(_ sender: NSSlider) {
        settings.speedBurstEffectMinScale = clampSpeedSurgeEffectScale(sender.doubleValue)
        if settings.speedBurstEffectMaxScale < settings.speedBurstEffectMinScale {
            settings.speedBurstEffectMaxScale = settings.speedBurstEffectMinScale
        }
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func speedBurstEffectMaxScaleSliderChanged(_ sender: NSSlider) {
        settings.speedBurstEffectMaxScale = clampSpeedSurgeEffectScale(sender.doubleValue)
        if settings.speedBurstEffectMaxScale < settings.speedBurstEffectMinScale {
            settings.speedBurstEffectMinScale = settings.speedBurstEffectMaxScale
        }
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
    private func waterImpactDensitySliderChanged(_ sender: NSSlider) {
        settings.waterImpactDropletDensity = clampWaterImpactDropletDensity(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func waterImpactSpreadSpeedSliderChanged(_ sender: NSSlider) {
        settings.waterImpactSpreadSpeed = clampWaterImpactSpreadSpeed(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func waterImpactLifetimeSliderChanged(_ sender: NSSlider) {
        settings.waterImpactLifetimeMilliseconds = clampWaterImpactLifetimeMilliseconds(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func waterImpactDropletSizeSliderChanged(_ sender: NSSlider) {
        settings.waterImpactDropletSize = clampWaterImpactDropletSize(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func clickParticleExplosionDensitySliderChanged(_ sender: NSSlider) {
        settings.clickParticleExplosionDensity = clampClickParticleExplosionDensity(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func clickParticleExplosionSizeSliderChanged(_ sender: NSSlider) {
        settings.clickParticleExplosionSize = clampClickParticleExplosionSize(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func clickParticleExplosionLifetimeSliderChanged(_ sender: NSSlider) {
        settings.clickParticleExplosionLifetimeMilliseconds = clampClickParticleExplosionLifetimeMilliseconds(sender.doubleValue)
        syncControlsFromSettings()
        publishChanges()
    }

    @objc
    private func clickParticleExplosionSpeedSliderChanged(_ sender: NSSlider) {
        settings.clickParticleExplosionSpeed = clampClickParticleExplosionSpeed(sender.doubleValue)
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
    private func trailPresetChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard trailPresetOptions.indices.contains(index) else { return }
        applyPresetOption(trailPresetOptions[index], source: "settings popup")
    }

    private func applyPresetOption(_ option: TrailPresetOption, source: String) {
        selectedTrailPresetOption = option
        switch option {
        case .custom:
            break
        case .thunderFirstForm:
            settings.applyThunderFirstFormPreset()
            syncControlsFromSettings()
            publishChanges()
            AppLogger.shared.log("thunder preset applied from \(source)")
        case .waterFirstForm:
            settings.applyWaterFirstFormPreset()
            syncControlsFromSettings()
            publishChanges()
            AppLogger.shared.log("water preset applied from \(source)")
        case .userPreset(let id):
            settings.applyCustomTrailPreset(id: id)
            syncControlsFromSettings()
            publishChanges()
            AppLogger.shared.log("custom preset applied: \(id) from \(source)")
        }
        presetManagerTableView?.reloadData()
    }

    @objc
    private func openPresetManagerClicked(_ sender: NSButton) {
        presentPresetManager()
    }

    private func presentPresetManager() {
        if presetManagerPanel == nil {
            presetManagerPanel = makePresetManagerPanel()
        }
        reloadPresetManagerRows()
        guard let panel = presetManagerPanel else { return }
        if let sheetParent = panel.sheetParent {
            sheetParent.makeKeyAndOrderFront(nil)
            return
        }
        if let window {
            window.beginSheet(panel)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func reloadPresetManagerRows() {
        customTrailPresets = AppSettings.loadCustomTrailPresets()
        var rows: [PresetManagerRow] = []
        rows.append(
            contentsOf: customTrailPresets.map { preset in
                PresetManagerRow(kind: .userPreset(id: preset.id), name: preset.name, updatedAt: preset.updatedAt)
            }
        )
        presetManagerRows = rows
        presetManagerTableView?.reloadData()
    }

    private func presetOption(for kind: PresetManagerRowKind) -> TrailPresetOption {
        switch kind {
        case .thunderFirstForm:
            .thunderFirstForm
        case .waterFirstForm:
            .waterFirstForm
        case .userPreset(let id):
            .userPreset(id: id)
        }
    }

    private func rowKind(for row: Int) -> PresetManagerRowKind? {
        guard presetManagerRows.indices.contains(row) else { return nil }
        return presetManagerRows[row].kind
    }

    private func updatePreset(kind: PresetManagerRowKind) {
        switch kind {
        case .thunderFirstForm:
            settings.saveAsThunderFirstFormPreset()
            AppLogger.shared.log("thunder preset updated from manager")
        case .waterFirstForm:
            settings.saveAsWaterFirstFormPreset()
            AppLogger.shared.log("water preset updated from manager")
        case .userPreset(let id):
            settings.updateCustomTrailPreset(id: id)
            AppLogger.shared.log("custom preset updated from manager: \(id)")
        }
        reloadTrailPresetPopup(selecting: selectedTrailPresetOption)
        reloadPresetManagerRows()
    }

    private func addPreset() {
        let addIcon = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil)
        guard let name = promptPresetName(
            title: i18n("dialog.preset.add.title", "新增预设"),
            message: i18n("dialog.preset.add.message", "请输入新预设名称"),
            icon: addIcon
        ) else { return }
        let preset = settings.createCustomTrailPreset(named: name)
        selectedTrailPresetOption = .userPreset(id: preset.id)
        reloadTrailPresetPopup(selecting: selectedTrailPresetOption)
        reloadPresetManagerRows()
        AppLogger.shared.log("custom preset created from manager: \(preset.id)")
    }

    private func renamePreset(id: String) {
        guard let old = customTrailPresets.first(where: { $0.id == id }),
              let name = promptPresetName(
                  title: i18n("dialog.preset.rename.title", "重命名预设"),
                  message: i18n("dialog.preset.rename.message", "请输入新的预设名称"),
                  defaultValue: old.name
              )
        else { return }
        guard AppSettings.renameCustomTrailPreset(id: id, newName: name) else { return }
        reloadTrailPresetPopup(selecting: .userPreset(id: id))
        reloadPresetManagerRows()
        AppLogger.shared.log("custom preset renamed from manager: \(id)")
    }

    private func deletePreset(id: String) {
        if case .userPreset(let selectedId) = selectedTrailPresetOption, selectedId == id {
            let alert = NSAlert()
            alert.messageText = i18n("dialog.preset.inUse.title", "无法删除")
            alert.informativeText = i18n("dialog.preset.inUse.message", "当前使用中的预设不允许删除，请先切换到其他预设。")
            alert.alertStyle = .warning
            alert.addButton(withTitle: i18n("button.confirm", "确定"))
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = i18n("dialog.preset.delete.title", "删除预设")
        alert.informativeText = i18n("dialog.preset.delete.message", "确定要删除该自定义预设吗？")
        alert.alertStyle = .warning
        alert.addButton(withTitle: i18n("button.confirm", "确定"))
        alert.addButton(withTitle: i18n("button.cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        AppSettings.deleteCustomTrailPreset(id: id)
        reloadTrailPresetPopup(selecting: selectedTrailPresetOption)
        reloadPresetManagerRows()
        AppLogger.shared.log("custom preset deleted from manager: \(id)")
    }

    private func exportPreset(kind: PresetManagerRowKind) {
        let data: Data?
        let fileName: String
        switch kind {
        case .thunderFirstForm:
            data = AppSettings.exportThunderPresetJSON()
            fileName = "thunder-first-form"
        case .waterFirstForm:
            data = AppSettings.exportWaterPresetJSON()
            fileName = "water-first-form"
        case .userPreset(let id):
            data = AppSettings.exportCustomPresetJSON(id: id)
            let presetName = customTrailPresets.first(where: { $0.id == id })?.name ?? "preset"
            fileName = presetName.replacingOccurrences(of: " ", with: "-")
        }
        guard let data else {
            let alert = NSAlert()
            alert.messageText = i18n("dialog.preset.export.empty.title", "导出失败")
            alert.informativeText = i18n("dialog.preset.export.empty.message", "该预设暂无可导出的快照数据，请先更新该预设。")
            alert.alertStyle = .warning
            alert.addButton(withTitle: i18n("button.confirm", "确定"))
            alert.runModal()
            return
        }
        let panel = NSSavePanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.json]
        } else {
            panel.allowedFileTypes = ["json"]
        }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(fileName).json"
        guard panel.runModal() == .OK, let saveURL = panel.url else { return }
        do {
            try data.write(to: saveURL, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func importPresetFromJSON() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.json]
        } else {
            panel.allowedFileTypes = ["json"]
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let imported = try AppSettings.importCustomPresetJSON(data)
            reloadTrailPresetPopup(selecting: .userPreset(id: imported.id))
            applyPresetOption(.userPreset(id: imported.id), source: "preset manager import")
            reloadPresetManagerRows()
            AppLogger.shared.log("custom preset imported from manager: \(imported.id)")
        } catch {
            let alert = NSAlert()
            alert.messageText = i18n("dialog.preset.import.failed.title", "导入失败")
            alert.informativeText = i18n("dialog.preset.import.failed.message", "JSON 文件格式无效或内容损坏。")
            alert.alertStyle = .warning
            alert.addButton(withTitle: i18n("button.confirm", "确定"))
            alert.runModal()
        }
    }

    private func makePresetManagerPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = i18n("dialog.preset.manager.title", "预设管理")
        panel.isReleasedWhenClosed = false

        let addButton = NSButton(title: i18n("button.preset.add", "新增"), target: self, action: #selector(presetManagerAddClicked(_:)))
        addButton.bezelStyle = .rounded
        addButton.controlSize = .small
        let importButton = NSButton(title: i18n("button.preset.import", "导入"), target: self, action: #selector(presetManagerImportClicked(_:)))
        importButton.bezelStyle = .rounded
        importButton.controlSize = .small
        let closeButton = NSButton(title: i18n("button.close", "关闭"), target: self, action: #selector(presetManagerCloseClicked(_:)))
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .small

        let topRow = NSStackView(views: [addButton, importButton, NSView()])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 6

        let tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 36
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .none

        let selectColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("select"))
        selectColumn.title = i18n("column.preset.active", "启用")
        selectColumn.width = 60
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = i18n("column.preset.name", "名称")
        nameColumn.width = 210
        let updatedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("updatedAt"))
        updatedColumn.title = i18n("column.preset.updatedAt", "最后更新时间")
        updatedColumn.width = 180
        let actionsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("actions"))
        actionsColumn.title = i18n("column.preset.actions", "操作")
        actionsColumn.width = 280
        tableView.addTableColumn(selectColumn)
        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(updatedColumn)
        tableView.addTableColumn(actionsColumn)

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        presetManagerTableView = tableView

        let bottomRow = NSStackView(views: [NSView(), closeButton])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 6

        let root = NSStackView(views: [topRow, scrollView, bottomRow])
        root.orientation = .vertical
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        panel.contentView = root
        return panel
    }

    private func makeCenteredLabelCell(_ text: String) -> NSView {
        let container = NSView()
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    @objc
    private func presetManagerCloseClicked(_ sender: NSButton) {
        guard let panel = presetManagerPanel else { return }
        if let parent = panel.sheetParent {
            parent.endSheet(panel)
        } else {
            panel.orderOut(nil)
        }
    }

    @objc
    private func presetManagerAddClicked(_ sender: NSButton) {
        addPreset()
    }

    @objc
    private func presetManagerImportClicked(_ sender: NSButton) {
        importPresetFromJSON()
    }

    @objc
    private func presetManagerSelectClicked(_ sender: NSButton) {
        guard let kind = rowKind(for: sender.tag) else { return }
        applyPresetOption(presetOption(for: kind), source: "preset manager")
    }

    @objc
    private func presetManagerUpdateClicked(_ sender: NSButton) {
        guard let kind = rowKind(for: sender.tag) else { return }
        updatePreset(kind: kind)
    }

    @objc
    private func presetManagerRenameClicked(_ sender: NSButton) {
        guard case .userPreset(let id) = rowKind(for: sender.tag) else { return }
        renamePreset(id: id)
    }

    @objc
    private func presetManagerDeleteClicked(_ sender: NSButton) {
        guard case .userPreset(let id) = rowKind(for: sender.tag) else { return }
        deletePreset(id: id)
    }

    @objc
    private func presetManagerExportClicked(_ sender: NSButton) {
        guard let kind = rowKind(for: sender.tag) else { return }
        exportPreset(kind: kind)
    }

    private func formatPresetUpdatedAt(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === presetManagerTableView {
            return presetManagerRows.count
        }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tableView === presetManagerTableView,
              presetManagerRows.indices.contains(row),
              let columnIdentifier = tableColumn?.identifier.rawValue
        else {
            return nil
        }
        let rowModel = presetManagerRows[row]
        switch columnIdentifier {
        case "select":
            let button = NSButton(radioButtonWithTitle: "", target: self, action: #selector(presetManagerSelectClicked(_:)))
            button.tag = row
            button.state = presetOption(for: rowModel.kind) == selectedTrailPresetOption ? .on : .off
            return button
        case "name":
            return makeCenteredLabelCell(rowModel.name)
        case "updatedAt":
            return makeCenteredLabelCell(formatPresetUpdatedAt(rowModel.updatedAt))
        case "actions":
            let updateButton = NSButton(title: i18n("button.preset.save", "更新"), target: self, action: #selector(presetManagerUpdateClicked(_:)))
            updateButton.bezelStyle = .rounded
            updateButton.controlSize = .small
            updateButton.tag = row

            let renameButton = NSButton(title: i18n("button.preset.rename", "重命名"), target: self, action: #selector(presetManagerRenameClicked(_:)))
            renameButton.bezelStyle = .rounded
            renameButton.controlSize = .small
            renameButton.tag = row

            let deleteButton = NSButton(title: i18n("button.preset.delete", "删除"), target: self, action: #selector(presetManagerDeleteClicked(_:)))
            deleteButton.bezelStyle = .rounded
            deleteButton.controlSize = .small
            deleteButton.tag = row

            let exportButton = NSButton(title: i18n("button.preset.export", "导出"), target: self, action: #selector(presetManagerExportClicked(_:)))
            exportButton.bezelStyle = .rounded
            exportButton.controlSize = .small
            exportButton.tag = row

            if case .userPreset = rowModel.kind {
                renameButton.isEnabled = true
                deleteButton.isEnabled = presetOption(for: rowModel.kind) != selectedTrailPresetOption
            } else {
                renameButton.isEnabled = false
                deleteButton.isEnabled = false
            }

            let stack = NSStackView(views: [updateButton, renameButton, deleteButton, exportButton])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 4
            return stack
        default:
            return nil
        }
    }

    @objc
    private func languageChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard availableLanguageOptions.indices.contains(index) else { return }
        settings.languageCode = availableLanguageOptions[index].code
        publishChanges()
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
            ? i18n("status.inputMonitoring.granted", "输入监控权限：已授权 ✅")
            : i18n("status.inputMonitoring.denied", "输入监控权限：未授权 ❌（全局快捷键可能无效）")
        inputMonitoringStatusLabel.textColor = listenGranted ? .systemGreen : .systemRed

        let accessibilityTrusted = AXIsProcessTrusted()
        accessibilityStatusLabel.stringValue = accessibilityTrusted
            ? i18n("status.accessibility.granted", "辅助功能权限：已授权 ✅")
            : i18n("status.accessibility.denied", "辅助功能权限：未授权 ❌（放大镜滚轮拦截会无效）")
        accessibilityStatusLabel.textColor = accessibilityTrusted ? .systemGreen : .systemRed

        let screenGranted = CGPreflightScreenCaptureAccess()
        screenCaptureStatusLabel.stringValue = screenGranted
            ? i18n("status.screenCapture.granted", "屏幕录制权限：已授权 ✅")
            : i18n("status.screenCapture.denied", "屏幕录制权限：未授权 ❌（放大镜可能无法取屏）")
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

    @objc
    private func openLanguagePacksFolder(_ sender: NSButton) {
        let url = LocalizationManager.shared.languagePacksDirectoryURL()
        NSWorkspace.shared.open(url)
        refreshLanguageOptions(reloadFromDisk: true)
        syncControlsFromSettings()
    }

    @objc
    private func openExternalLink(_ sender: NSButton) {
        guard let url = externalLinkByButtonIdentifier[ObjectIdentifier(sender)] else { return }
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
        refreshLanguageOptions(reloadFromDisk: true)
        syncControlsFromSettings()
        refreshPermissionIndicators()
    }

}
