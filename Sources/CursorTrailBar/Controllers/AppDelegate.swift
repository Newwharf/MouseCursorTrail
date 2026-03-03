//
// AppDelegate.swift
// MVC: Controller 层（应用生命周期与模块编排）
//
import AppKit
import ApplicationServices

@MainActor
/// 应用主委托。
/// 职责：串联监听器、覆盖层、设置窗口与状态栏菜单。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let waterPresetSyncMigrationKey = "preset.water.synced.fromCurrent.v1"
    private let overlayManager = OverlayWindowManager()
    private let mouseMonitor = MouseMonitor()
    private let hotKeyManager = HotKeyManager()
    private let globalShortcutMonitor = GlobalShortcutMonitor()
    private let globalScrollInterceptor = GlobalScrollInterceptor()
    private let settingsStore = SettingsStore()
    private let launchAtLoginManager = LaunchAtLoginManager()

    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var settingsWindowController: SettingsWindowController?
    private var settings: AppSettings = .default
    private var isMagnifierShortcutHeld = false
    private var isGlobalShortcutMonitorActive = false
    private var lastAppliedLaunchAtLoginState: Bool?
    private var lastAppliedLanguageCode: String?
    private var lastLoggedScrollConsumeState: Bool?
    private var hasPromptedAccessibilityForScrollInterception = false

    /// 应用启动入口：加载配置、启动监听器并应用初始状态。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings = settingsStore.loadSettings()
        LocalizationManager.shared.reloadCustomLanguagePacks()
        LocalizationManager.shared.setLanguage(code: settings.languageCode)
        settings.languageCode = LocalizationManager.shared.currentLanguageCode
        lastAppliedLanguageCode = settings.languageCode
        setupKeyboardShortcutMenu()
        seedThunderPresetIfNeeded()
        seedWaterPresetIfNeeded()
        syncWaterPresetFromCurrentSettingsIfNeeded()
        AppLogger.shared.setEnabled(settings.isLoggingEnabled)
        AppLogger.shared.log("application did finish launching")
        let launchEnabled = launchAtLoginManager.isEnabled()
        if launchEnabled != settings.isLaunchAtLoginEnabled {
            settings.isLaunchAtLoginEnabled = launchEnabled
            settingsStore.saveSettings(settings)
            AppLogger.shared.log("launch at login state synchronized to \(launchEnabled)")
        }
        if settings.isStatusItemVisible {
            setupStatusItem()
        }

        mouseMonitor.onEvent = { [weak self] signal in
            self?.overlayManager.process(signal: signal)
        }
        mouseMonitor.onRawEvent = { [weak self] event in
            self?.handleRawEvent(event)
        }
        mouseMonitor.start()

        globalScrollInterceptor.onScroll = { [weak self] signal in
            DispatchQueue.main.async { [weak self] in
                self?.overlayManager.process(signal: signal)
            }
        }
        AppLogger.shared.log("global scroll interceptor configured (lazy start)")

        globalShortcutMonitor.onInput = { [weak self] input in
            self?.handleShortcutInput(input)
        }
        isGlobalShortcutMonitorActive = globalShortcutMonitor.start()

        hotKeyManager.onToggle = { [weak self] in
            self?.toggleTracking()
        }
        _ = hotKeyManager.registerHotKey()

        applySettings(persist: false, syncWindow: false)
        DispatchQueue.main.async { [weak self] in
            self?.openSettingsWindow()
        }
    }

    private func seedThunderPresetIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppSettings.thunderPresetSeededKey) == false else { return }
        settings.saveAsThunderFirstFormPreset()
        AppLogger.shared.log("thunder preset snapshot saved from current settings")
    }

    private func seedWaterPresetIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppSettings.waterPresetSeededKey) == false else { return }
        settings.saveAsWaterFirstFormPreset()
        AppLogger.shared.log("water preset snapshot saved from current settings")
    }

    private func syncWaterPresetFromCurrentSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: waterPresetSyncMigrationKey) == false else { return }
        settings.saveAsWaterFirstFormPreset()
        defaults.set(true, forKey: waterPresetSyncMigrationKey)
        AppLogger.shared.log("water preset synced from current settings (one-time migration)")
    }

    /// 应用退出前释放监听资源。
    func applicationWillTerminate(_ notification: Notification) {
        mouseMonitor.stop()
        hotKeyManager.unregisterHotKey()
        globalShortcutMonitor.stop()
        globalScrollInterceptor.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 启动或激活时不再自动弹设置窗口；仅由用户显式打开。
    }

    /// Dock 重新激活时的窗口恢复策略。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettingsWindow()
        }
        return true
    }

    /// 保持应用常驻，不因关闭最后窗口退出。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 注册主菜单快捷键：
    /// - ⌘W：关闭当前主界面窗口
    /// - ⌘Q：退出应用
    private func setupKeyboardShortcutMenu() {
        let mainMenu = NSMenu()

        let appRootItem = NSMenuItem()
        let appMenu = NSMenu(title: "CursorTrailBar")
        let quitItem = NSMenuItem(
            title: i18n("menu.quitApp", "退出 CursorTrailBar"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        appMenu.addItem(quitItem)
        appRootItem.submenu = appMenu
        mainMenu.addItem(appRootItem)

        let windowRootItem = NSMenuItem()
        let windowMenu = NSMenu(title: i18n("menu.window", "窗口"))
        let closeItem = NSMenuItem(title: i18n("menu.close", "关闭"), action: #selector(closeMainWindow), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = [.command]
        closeItem.target = self
        windowMenu.addItem(closeItem)
        windowRootItem.submenu = windowMenu
        mainMenu.addItem(windowRootItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.title = ""
            button.image = makeStatusBarTemplateIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "Cursor Trail"
            button.setAccessibilityLabel("CursorTrailBar")
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: settings.isTrackingEnabled
                ? i18n("menu.toggleTrail.on", "关闭轨迹显示")
                : i18n("menu.toggleTrail.off", "开启轨迹显示"),
            action: #selector(toggleTracking),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        toggleMenuItem = toggleItem

        let settingsItem = NSMenuItem(
            title: i18n("menu.openSettings", "打开设置…"),
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let clearItem = NSMenuItem(title: i18n("menu.clearTrail", "清空当前轨迹"), action: #selector(clearTrail), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        let hotkeyHintItem = NSMenuItem(
            title: i18n("menu.hotkeyToggle", "快捷键开关：%@", hotKeyManager.displayLabel),
            action: nil,
            keyEquivalent: ""
        )
        hotkeyHintItem.isEnabled = false
        menu.addItem(hotkeyHintItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: i18n("menu.quit", "退出"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    private func makeStatusBarTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let trail = NSBezierPath()
            trail.move(to: NSPoint(x: 1.8, y: 6.2))
            trail.curve(
                to: NSPoint(x: 10.0, y: 8.2),
                controlPoint1: NSPoint(x: 3.8, y: 4.2),
                controlPoint2: NSPoint(x: 7.2, y: 7.5)
            )
            trail.lineWidth = 1.8
            trail.lineCapStyle = .round
            trail.lineJoinStyle = .round
            NSColor.labelColor.setStroke()
            trail.stroke()

            let pointer = NSBezierPath()
            pointer.move(to: NSPoint(x: 7.3, y: 2.7))
            pointer.line(to: NSPoint(x: 14.8, y: 8.5))
            pointer.line(to: NSPoint(x: 11.1, y: 9.2))
            pointer.line(to: NSPoint(x: 12.8, y: 14.7))
            pointer.line(to: NSPoint(x: 10.7, y: 15.5))
            pointer.line(to: NSPoint(x: 9.0, y: 10.2))
            pointer.line(to: NSPoint(x: 6.8, y: 11.8))
            pointer.close()
            NSColor.labelColor.setFill()
            pointer.fill()

            return true
        }
        image.isTemplate = true
        image.size = size
        return image
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        toggleMenuItem = nil
    }

    private func syncStatusItemVisibility() {
        if settings.isStatusItemVisible {
            setupStatusItem()
            statusItem?.button?.image = makeStatusBarTemplateIcon()
        } else {
            removeStatusItem()
        }
    }

    @objc
    private func toggleTracking() {
        settings.isTrackingEnabled.toggle()
        applySettings(persist: true)
    }

    @objc
    private func openSettingsWindow() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(initialSettings: settings)
            controller.onSettingsChanged = { [weak self] newSettings in
                self?.settings = newSettings
                self?.applySettings(persist: true, syncWindow: false)
            }
            controller.onRequestInputMonitoringPermission = { [weak self] in
                self?.requestInputMonitoringPermissionAndRegister()
            }
            settingsWindowController = controller
        }
        settingsWindowController?.updateSettings(settings)
        settingsWindowController?.present()
    }

    /// 请求输入监控权限后，重启全局快捷键监听器以尽快生效。
    private func requestInputMonitoringPermissionAndRegister() {
        NSApp.activate(ignoringOtherApps: true)
        probeInputMonitoringEventTap()
        probeInputMonitoringEventTap()

        globalShortcutMonitor.stop()
        isGlobalShortcutMonitorActive = globalShortcutMonitor.start()
        let after = CGPreflightListenEventAccess()
        AppLogger.shared.log("global shortcut monitor restarted after permission request: \(isGlobalShortcutMonitorActive), listenGranted=\(after)")
    }

    private func probeInputMonitoringEventTap() {
        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(eventMask),
                callback: callback,
                userInfo: nil
            )
        else {
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
    }

    @objc
    private func clearTrail() {
        overlayManager.clear()
    }

    /// 将当前设置应用到运行时模块。
    /// - Parameters:
    ///   - persist: 是否持久化到本地存储。
    ///   - syncWindow: 是否反向同步设置窗口控件显示。
    private func applySettings(persist: Bool, syncWindow: Bool = true) {
        let languageBefore = LocalizationManager.shared.currentLanguageCode
        if settings.languageCode != languageBefore {
            LocalizationManager.shared.setLanguage(code: settings.languageCode)
            settings.languageCode = LocalizationManager.shared.currentLanguageCode
        }
        let languageChanged = lastAppliedLanguageCode != settings.languageCode
        lastAppliedLanguageCode = settings.languageCode

        AppLogger.shared.setEnabled(settings.isLoggingEnabled)
        settings.trailWidth = clampTrailWidth(Double(settings.trailWidth))
        settings.trailLengthMilliseconds = clampTrailLengthMilliseconds(settings.trailLengthMilliseconds)
        settings.clickEffectRadius = clampClickEffectRadius(Double(settings.clickEffectRadius))
        settings.clickEffectDurationMilliseconds = clampClickEffectDurationMilliseconds(settings.clickEffectDurationMilliseconds)
        settings.waterImpactDropletDensity = clampWaterImpactDropletDensity(Double(settings.waterImpactDropletDensity))
        settings.waterImpactSpreadSpeed = clampWaterImpactSpreadSpeed(Double(settings.waterImpactSpreadSpeed))
        settings.waterImpactLifetimeMilliseconds = clampWaterImpactLifetimeMilliseconds(settings.waterImpactLifetimeMilliseconds)
        settings.waterImpactDropletSize = clampWaterImpactDropletSize(Double(settings.waterImpactDropletSize))
        settings.magnifierRadius = clampMagnifierRadius(Double(settings.magnifierRadius))
        settings.magnifierZoom = clampMagnifierZoom(Double(settings.magnifierZoom))
        settings.magnifierBorderWidth = clampMagnifierBorderWidth(Double(settings.magnifierBorderWidth))
        settings.magnifierShadowOpacity = clampMagnifierShadowOpacity(Double(settings.magnifierShadowOpacity))
        settings.speedBurstVelocityThreshold = clampSpeedBurstVelocityThreshold(Double(settings.speedBurstVelocityThreshold))
        settings.speedBurstCooldownMilliseconds = clampSpeedBurstCooldownMilliseconds(settings.speedBurstCooldownMilliseconds)
        settings.speedBurstDurationMilliseconds = clampSpeedBurstDurationMilliseconds(settings.speedBurstDurationMilliseconds)
        settings.speedBurstDurationMinMilliseconds = clampSpeedBurstDurationMilliseconds(settings.speedBurstDurationMinMilliseconds)
        settings.speedBurstDurationMaxMilliseconds = clampSpeedBurstDurationMilliseconds(settings.speedBurstDurationMaxMilliseconds)
        if settings.speedBurstDurationMaxMilliseconds < settings.speedBurstDurationMinMilliseconds {
            let temp = settings.speedBurstDurationMaxMilliseconds
            settings.speedBurstDurationMaxMilliseconds = settings.speedBurstDurationMinMilliseconds
            settings.speedBurstDurationMinMilliseconds = temp
        }
        settings.speedBurstAfterglowMilliseconds = 0
        settings.speedBurstJitterAmplitude = clampSpeedBurstJitterAmplitude(Double(settings.speedBurstJitterAmplitude))
        settings.speedBurstMinLength = clampSpeedBurstMinLength(Double(settings.speedBurstMinLength))
        settings.speedBurstMaxLength = clampSpeedBurstMaxLength(Double(settings.speedBurstMaxLength))
        if settings.speedBurstMaxLength < settings.speedBurstMinLength {
            let temp = settings.speedBurstMaxLength
            settings.speedBurstMaxLength = settings.speedBurstMinLength
            settings.speedBurstMinLength = temp
        }
        settings.speedBurstWidthMultiplier = clampSpeedBurstWidthMultiplier(Double(settings.speedBurstWidthMultiplier))
        settings.speedBurstTrailMinScale = clampSpeedSurgeTrailScale(Double(settings.speedBurstTrailMinScale))
        settings.speedBurstTrailMaxScale = clampSpeedSurgeTrailScale(Double(settings.speedBurstTrailMaxScale))
        if settings.speedBurstTrailMaxScale < settings.speedBurstTrailMinScale {
            let temp = settings.speedBurstTrailMaxScale
            settings.speedBurstTrailMaxScale = settings.speedBurstTrailMinScale
            settings.speedBurstTrailMinScale = temp
        }
        settings.speedBurstEffectMinScale = clampSpeedSurgeEffectScale(Double(settings.speedBurstEffectMinScale))
        settings.speedBurstEffectMaxScale = clampSpeedSurgeEffectScale(Double(settings.speedBurstEffectMaxScale))
        if settings.speedBurstEffectMaxScale < settings.speedBurstEffectMinScale {
            let temp = settings.speedBurstEffectMaxScale
            settings.speedBurstEffectMaxScale = settings.speedBurstEffectMinScale
            settings.speedBurstEffectMinScale = temp
        }
        settings.speedBurstAccentDurationMilliseconds = clampSpeedBurstAccentDurationMilliseconds(settings.speedBurstAccentDurationMilliseconds)
        settings.speedBurstAccentSize = clampSpeedBurstAccentSize(Double(settings.speedBurstAccentSize))
        settings.waterHighlightRatio = clampWaterMixRatio(Double(settings.waterHighlightRatio))
        settings.waterPrimaryRatio = clampWaterMixRatio(Double(settings.waterPrimaryRatio))
        settings.waterShadowRatio = clampWaterMixRatio(Double(settings.waterShadowRatio))
        settings.waterMixRandomness = clampWaterMixRandomness(Double(settings.waterMixRandomness))
        settings.waterSplashSize = clampWaterSplashSize(Double(settings.waterSplashSize))
        settings.waterSplashSpeed = clampWaterSplashSpeed(Double(settings.waterSplashSpeed))
        settings.waterSplashLifetimeMilliseconds = clampWaterSplashLifetimeMilliseconds(settings.waterSplashLifetimeMilliseconds)
        settings.waterSplashDensity = clampWaterSplashDensity(Double(settings.waterSplashDensity))
        settings.trailEffectIntensity = clampTrailEffectIntensity(Double(settings.trailEffectIntensity))
        settings.normalizeWaterMixRatios()
        if settings.rainbowTrailColors.count < 2 {
            settings.rainbowTrailColors = AppSettings.default.rainbowTrailColors
        }
        syncLaunchAtLoginIfNeeded()
        syncStatusItemVisibility()
        overlayManager.setSettings(settings)
        overlayManager.setTrackingEnabled(settings.isTrackingEnabled)
        if !settings.isMagnifierEnabled {
            isMagnifierShortcutHeld = false
            overlayManager.setMagnifierActive(false)
        }
        syncScrollInterceptionState()

        toggleMenuItem?.title = settings.isTrackingEnabled
            ? i18n("menu.toggleTrail.on", "关闭轨迹显示")
            : i18n("menu.toggleTrail.off", "开启轨迹显示")

        if persist {
            settingsStore.saveSettings(settings)
            AppLogger.shared.log("settings saved: tracking=\(settings.isTrackingEnabled), clickEffects=\(settings.isClickEffectsEnabled), magnifier=\(settings.isMagnifierEnabled), effectsEnabled=\(settings.isTrailEffectsEnabled), effectIntensity=\(Int(settings.trailEffectIntensity))")
        }
        if syncWindow {
            settingsWindowController?.updateSettings(settings)
        }
        if languageChanged {
            DispatchQueue.main.async { [weak self] in
                self?.refreshLocalizedInterface()
            }
        }
    }

    private func handleRawEvent(_ event: NSEvent) {
        if isGlobalShortcutMonitorActive {
            return
        }
        if settingsWindowController?.isRecordingShortcut == true {
            return
        }
        guard let input = shortcutInputEvent(from: event) else { return }
        handleShortcutInput(input)
    }

    private func handleShortcutInput(_ input: ShortcutInputEvent) {
        if settingsWindowController?.isRecordingShortcut == true {
            return
        }
        guard settings.isMagnifierEnabled else {
            if isMagnifierShortcutHeld {
                isMagnifierShortcutHeld = false
                overlayManager.setMagnifierActive(false)
            }
            syncScrollInterceptionState()
            return
        }
        let shortcut = settings.magnifierShortcut
        if shortcut.matchesPress(input: input) {
            if !isMagnifierShortcutHeld {
                isMagnifierShortcutHeld = true
                overlayManager.setMagnifierActive(true)
                AppLogger.shared.log("magnifier shortcut pressed")
                syncScrollInterceptionState()
            }
        } else if shortcut.matchesRelease(input: input) {
            if isMagnifierShortcutHeld {
                isMagnifierShortcutHeld = false
                overlayManager.setMagnifierActive(false)
                AppLogger.shared.log("magnifier shortcut released")
                syncScrollInterceptionState()
            }
        }
    }

    /// 同步滚轮拦截状态。
    /// Note: 仅在“放大镜快捷键按住且放大镜功能开启”时尝试消费滚轮事件。
    private func syncScrollInterceptionState() {
        let wantsConsume = isMagnifierShortcutHeld && settings.isMagnifierEnabled
        if wantsConsume {
            if !globalScrollInterceptor.isRunning {
                let started = globalScrollInterceptor.start()
                AppLogger.shared.log("global scroll interceptor restarted: \(started)")
                if !started {
                    requestAccessibilityPermissionForScrollInterceptionIfNeeded()
                }
            }
            let canConsume = globalScrollInterceptor.isRunning
            globalScrollInterceptor.setConsumesScroll(canConsume)
            if wantsConsume, !canConsume {
                AppLogger.shared.log("scroll interception degraded: magnifier active but interceptor unavailable; wheel may pass through")
            }
        } else {
            globalScrollInterceptor.setConsumesScroll(false)
            if globalScrollInterceptor.isRunning {
                globalScrollInterceptor.stop()
                AppLogger.shared.log("global scroll interceptor paused")
            }
        }
        let effectiveConsume = wantsConsume && globalScrollInterceptor.isRunning
        if lastLoggedScrollConsumeState != effectiveConsume {
            AppLogger.shared.log(
                "sync scroll interception: requested=\(wantsConsume), effective=\(effectiveConsume), shortcutHeld=\(isMagnifierShortcutHeld), magnifierEnabled=\(settings.isMagnifierEnabled), trackingEnabled=\(settings.isTrackingEnabled)"
            )
            lastLoggedScrollConsumeState = effectiveConsume
        }
    }

    private func requestAccessibilityPermissionForScrollInterceptionIfNeeded() {
        guard !hasPromptedAccessibilityForScrollInterception else { return }
        guard !AXIsProcessTrusted() else { return }
        hasPromptedAccessibilityForScrollInterception = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trustedAfterPrompt = AXIsProcessTrustedWithOptions(options)
        AppLogger.shared.log("scroll interception requested accessibility permission, trustedAfterPrompt=\(trustedAfterPrompt)")
    }

    private func syncLaunchAtLoginIfNeeded() {
        guard lastAppliedLaunchAtLoginState != settings.isLaunchAtLoginEnabled else { return }
        _ = launchAtLoginManager.setEnabled(settings.isLaunchAtLoginEnabled)
        lastAppliedLaunchAtLoginState = settings.isLaunchAtLoginEnabled
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc
    private func closeMainWindow() {
        if let keyWindow = NSApp.keyWindow {
            keyWindow.performClose(nil)
            return
        }
        settingsWindowController?.window?.performClose(nil)
    }

    private func refreshLocalizedInterface() {
        setupKeyboardShortcutMenu()
        if settings.isStatusItemVisible {
            removeStatusItem()
            setupStatusItem()
        }
        guard let controller = settingsWindowController else { return }
        let wasVisible = controller.window?.isVisible ?? false
        controller.close()
        settingsWindowController = nil
        if wasVisible {
            openSettingsWindow()
        }
    }
}
