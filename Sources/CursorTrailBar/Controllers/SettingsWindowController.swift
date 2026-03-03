//
// SettingsWindowController.swift
// MVC: Controller 层（设置窗口 UI 与配置同步）
//
import AppKit
import ApplicationServices
import Carbon

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

    private enum TrailPresetOption: CaseIterable {
        case custom
        case thunderFirstForm

        var title: String {
            switch self {
            case .custom:
                return i18n("preset.custom", "自定义")
            case .thunderFirstForm:
                return i18n("preset.thunderFirstForm", "雷之呼吸·壹之型")
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
    private let rainbowColorWells: [NSColorWell] = (0..<6).map { _ in NSColorWell() }
    private var availableLanguageOptions: [LanguageOption] = []
    private var rowWrapperByRowIdentifier: [ObjectIdentifier: NSView] = [:]
    private lazy var trailPresetHeaderControl = makeTrailPresetHeaderControl()

    private lazy var trailTypeRow = makePopupRow(title: i18n("row.trail.type", "轨迹类型"), popup: trailStylePopup)
    private lazy var trailColorRow = makeColorRow(title: i18n("row.trail.color", "轨迹颜色"), control: trailColorWell)
    private lazy var trailEffectColorRow = makeColorRow(title: i18n("row.trail.effectColor", "特效颜色"), control: trailEffectColorWell)
    private lazy var neonColorsRow = makeNeonColorsRow()
    private lazy var rainbowColorsRow = makeRainbowColorsRow()
    private lazy var trailEffectTypeRow = makePopupRow(title: i18n("row.trail.effectType", "特效类型"), popup: trailEffectPopup)
    private lazy var trailWidthRow = makeSliderRow(title: i18n("row.trail.width", "轨迹粗细"), slider: trailWidthSlider, valueLabel: trailWidthValueLabel)
    private lazy var trailLengthRow = makeSliderRow(title: i18n("row.trail.lengthMs", "轨迹长度（毫秒）"), slider: trailLengthSlider, valueLabel: trailLengthValueLabel)
    private lazy var trailIntensityRow = makePopupRow(title: i18n("row.trail.intensity", "特效强度"), popup: intensityPopup)
    private lazy var speedBurstTypeRow = makePopupRow(title: i18n("row.speedBurst.type", "爆发类型"), popup: speedBurstTypePopup)
    private lazy var speedBurstLineColorRow = makeColorRow(title: i18n("row.speedBurst.lineColor", "爆发线颜色"), control: speedBurstLineColorWell)
    private lazy var speedBurstAccentColorRow = makeColorRow(title: i18n("row.speedBurst.accentColor", "端点爆发颜色"), control: speedBurstAccentColorWell)
    private lazy var speedBurstVelocityRow = makeSliderRow(title: i18n("row.speedBurst.velocity", "触发速度阈值"), slider: speedBurstVelocitySlider, valueLabel: speedBurstVelocityValueLabel)
    private lazy var speedBurstCooldownRow = makeSliderRow(title: i18n("row.speedBurst.cooldown", "冷却时间（毫秒）"), slider: speedBurstCooldownSlider, valueLabel: speedBurstCooldownValueLabel)
    private lazy var speedBurstDurationRow = makeSliderRow(title: i18n("row.speedBurst.duration", "爆发线时长（毫秒）"), slider: speedBurstDurationSlider, valueLabel: speedBurstDurationValueLabel)
    private lazy var speedBurstJitterRow = makeSliderRow(title: i18n("row.speedBurst.jitter", "爆发线抖动幅度"), slider: speedBurstJitterSlider, valueLabel: speedBurstJitterValueLabel)
    private lazy var speedBurstMinLengthRow = makeSliderRow(title: i18n("row.speedBurst.minLength", "爆发线最小长度"), slider: speedBurstMinLengthSlider, valueLabel: speedBurstMinLengthValueLabel)
    private lazy var speedBurstMaxLengthRow = makeSliderRow(title: i18n("row.speedBurst.maxLength", "爆发线最大长度"), slider: speedBurstMaxLengthSlider, valueLabel: speedBurstMaxLengthValueLabel)
    private lazy var speedBurstWidthMultiplierRow = makeSliderRow(title: i18n("row.speedBurst.widthMultiplier", "爆发线宽系数"), slider: speedBurstWidthMultiplierSlider, valueLabel: speedBurstWidthMultiplierValueLabel)
    private lazy var speedBurstAccentDurationRow = makeSliderRow(title: i18n("row.speedBurst.accentDuration", "端点爆发时长（毫秒）"), slider: speedBurstAccentDurationSlider, valueLabel: speedBurstAccentDurationValueLabel)
    private lazy var speedBurstAccentSizeRow = makeSliderRow(title: i18n("row.speedBurst.accentSize", "端点爆发大小"), slider: speedBurstAccentSizeSlider, valueLabel: speedBurstAccentSizeValueLabel)
    private lazy var clickDurationRow = makeSliderRow(title: i18n("row.click.duration", "点击效果时长（毫秒）"), slider: clickDurationSlider, valueLabel: clickDurationValueLabel)

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

        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        refreshLanguageOptions(reloadFromDisk: true)

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
        openLanguagePacksFolderButton.target = self
        openLanguagePacksFolderButton.action = #selector(openLanguagePacksFolder(_:))

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
            title: i18n("section.general.title", "常规"),
            subtitle: i18n("section.general.subtitle", "开机与常驻相关设置"),
            rows: [
                makeSwitchRow(title: i18n("row.launchAtLogin.title", "开机启动"), subtitleLabel: launchAtLoginStatusLabel, toggle: launchAtLoginSwitch),
                makeSwitchRow(title: i18n("row.logging.title", "启用日志输出"), subtitle: i18n("row.logging.subtitle", "写入日志文件以便排查问题"), toggle: loggingSwitch),
                makeButtonRow(title: i18n("row.logFolder.title", "日志目录"), button: openLogFolderButton),
                makeSwitchRow(title: i18n("row.statusItem.title", "菜单栏显示图标"), subtitle: i18n("row.statusItem.subtitle", "关闭后仅保留主界面与全局功能"), toggle: statusItemSwitch),
                makeLanguageRow(),
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
            title: i18n("section.speedBurst.title", "加速爆发"),
            subtitle: i18n("section.speedBurst.subtitle", "高速移动触发的额外爆发特效"),
            rows: [
                makeSwitchRow(title: i18n("row.speedBurst.enabled", "开启加速爆发"), subtitle: i18n("row.speedBurst.enabled.subtitle", "关闭后将不触发一之闪"), toggle: speedBurstSwitch),
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
            makeSwitchRow(title: i18n("row.click.enabled", "开启点击效果"), subtitle: i18n("row.click.enabled.subtitle", "关闭后不显示点击特效"), toggle: clickEffectsSwitch),
            makePopupRow(title: i18n("row.click.style", "点击样式"), popup: clickStylePopup),
            makeSliderRow(title: i18n("row.click.radius", "点击效果半径"), slider: clickRadiusSlider, valueLabel: clickRadiusValueLabel),
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

            let title = NSTextField(labelWithString: i18n("row.click.perButtonTitle", "%@ 点击效果", button.title))
            title.font = .systemFont(ofSize: 13, weight: .medium)

            let row = NSStackView(views: [title, NSView(), toggle, colorWell])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 8
            rows.append(row)
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
        window?.title = i18n("window.settings.title", "CursorTrailBar 设置")

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
        let px = i18n("unit.px", "px")
        let ms = i18n("unit.ms", "ms")
        let pxps = i18n("unit.pxps", "px/s")
        let multiplier = i18n("unit.multiplier", "x")
        trailWidthValueLabel.stringValue = "\(rounded(Double(settings.trailWidth))) \(px)"
        trailLengthValueLabel.stringValue = "\(Int(settings.trailLengthMilliseconds)) \(ms)"
        speedBurstVelocityValueLabel.stringValue = "\(Int(settings.speedBurstVelocityThreshold)) \(pxps)"
        speedBurstCooldownValueLabel.stringValue = "\(Int(settings.speedBurstCooldownMilliseconds)) \(ms)"
        speedBurstDurationValueLabel.stringValue = "\(Int(settings.speedBurstDurationMilliseconds)) \(ms)"
        speedBurstJitterValueLabel.stringValue = "\(rounded(Double(settings.speedBurstJitterAmplitude)))"
        speedBurstMinLengthValueLabel.stringValue = "\(Int(settings.speedBurstMinLength)) \(px)"
        speedBurstMaxLengthValueLabel.stringValue = "\(Int(settings.speedBurstMaxLength)) \(px)"
        speedBurstWidthMultiplierValueLabel.stringValue = "\(rounded(Double(settings.speedBurstWidthMultiplier))) \(multiplier)"
        speedBurstAccentDurationValueLabel.stringValue = "\(Int(settings.speedBurstAccentDurationMilliseconds)) \(ms)"
        speedBurstAccentSizeValueLabel.stringValue = "\(Int(settings.speedBurstAccentSize)) \(px)"
        clickRadiusValueLabel.stringValue = "\(Int(settings.clickEffectRadius)) \(px)"
        clickDurationValueLabel.stringValue = "\(Int(settings.clickEffectDurationMilliseconds)) \(ms)"
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
