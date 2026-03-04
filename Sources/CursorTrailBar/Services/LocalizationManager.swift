//
// LocalizationManager.swift
// MVC: 国际化服务（目录驱动语言包 + 中文兜底）
//
import Foundation

extension Notification.Name {
    static let cursorTrailBarLanguageDidChange = Notification.Name("cursorTrailBar.language.didChange")
}

struct LanguageOption {
    let code: String
    let displayName: String
    let isBuiltIn: Bool
}

private struct LanguagePack {
    let code: String
    let displayName: String
    let strings: [String: String]
}

private struct LanguagePackFilePayload: Decodable {
    let code: String?
    let name: String?
    let strings: [String: String]?
}

private struct LanguagePackExportPayload: Encodable {
    let code: String
    let name: String
    let strings: [String: String]
}

/// 全局语言管理器。
/// 说明：
/// 1) 具体支持哪些语言，以 `LanguagePacks` 目录中的 JSON 配置文件为准；
/// 2) 若目录中无任何语言包文件，则回退为“仅内置简体中文”。
final class LocalizationManager: @unchecked Sendable {
    static let shared = LocalizationManager()

    private static let defaultLanguagePackSeededKey = "language.packs.seeded.defaults.v1"

    private let fallbackChinesePack = LanguagePack(code: "zh-Hans", displayName: "简体中文", strings: [:])
    private var directoryPacks: [String: LanguagePack] = [:]
    private(set) var currentLanguageCode: String

    private init() {
        currentLanguageCode = "zh-Hans"
        seedDefaultLanguagePacksIfNeeded()
        reloadCustomLanguagePacks()
        currentLanguageCode = defaultLanguageCode
    }

    var defaultLanguageCode: String {
        Self.detectPreferredLanguageCode(from: availableLanguageCodes())
    }

    func availableLanguages() -> [LanguageOption] {
        let packs = activePacks().values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        let isFallbackOnly = directoryPacks.isEmpty
        return packs.map { pack in
            LanguageOption(code: pack.code, displayName: pack.displayName, isBuiltIn: isFallbackOnly)
        }
    }

    func setLanguage(code: String) {
        let supported = availableLanguageCodes()
        let newCode = supported.contains(code) ? code : defaultLanguageCode
        guard currentLanguageCode != newCode else { return }
        currentLanguageCode = newCode
        NotificationCenter.default.post(name: .cursorTrailBarLanguageDidChange, object: nil)
    }

    func reloadCustomLanguagePacks() {
        directoryPacks.removeAll()

        let directoryURL = languagePacksDirectoryURL()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in urls where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let payload = try? JSONDecoder().decode(LanguagePackFilePayload.self, from: data),
               let strings = payload.strings ?? Self.decodeFlatStringMap(from: data)
            {
                let code = payload.code?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? url.deletingPathExtension().lastPathComponent
                guard !code.isEmpty else { continue }
                let name = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? code
                directoryPacks[code] = LanguagePack(code: code, displayName: name, strings: strings)
                continue
            }
            if let flat = Self.decodeFlatStringMap(from: data) {
                let code = url.deletingPathExtension().lastPathComponent
                directoryPacks[code] = LanguagePack(code: code, displayName: code, strings: flat)
            }
        }

        if !availableLanguageCodes().contains(currentLanguageCode) {
            currentLanguageCode = defaultLanguageCode
        }
    }

    func localized(_ key: String, fallback: String, args: [CVarArg] = []) -> String {
        let template =
            activePacks()[currentLanguageCode]?.strings[key]
            ?? fallbackChinesePack.strings[key]
            ?? fallback
        guard !args.isEmpty else { return template }
        return withVaList(args) { pointer in
            NSString(format: template, locale: Locale.current, arguments: pointer) as String
        }
    }

    func languagePacksDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let appFolder = base.appendingPathComponent("CursorTrailBar", isDirectory: true)
        let packsFolder = appFolder.appendingPathComponent("LanguagePacks", isDirectory: true)
        try? FileManager.default.createDirectory(at: packsFolder, withIntermediateDirectories: true)
        return packsFolder
    }

    private func activePacks() -> [String: LanguagePack] {
        if directoryPacks.isEmpty {
            return [fallbackChinesePack.code: fallbackChinesePack]
        }
        return directoryPacks
    }

    private func availableLanguageCodes() -> Set<String> {
        Set(activePacks().keys)
    }

    private func seedDefaultLanguagePacksIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.defaultLanguagePackSeededKey) == false else { return }

        let directoryURL = languagePacksDirectoryURL()
        let payloads = Self.defaultLanguagePackPayloads()
        for payload in payloads {
            let fileURL = directoryURL.appendingPathComponent("\(payload.code).json")
            guard !FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(payload) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        defaults.set(true, forKey: Self.defaultLanguagePackSeededKey)
    }

    private static func decodeFlatStringMap(from data: Data) -> [String: String]? {
        try? JSONDecoder().decode([String: String].self, from: data)
    }

    private static func detectPreferredLanguageCode(from codes: some Sequence<String>) -> String {
        let available = Set(codes)
        for preferred in Locale.preferredLanguages {
            if available.contains(preferred) { return preferred }
            if preferred.hasPrefix("zh"), available.contains("zh-Hans") {
                return "zh-Hans"
            }
            if preferred.hasPrefix("en"), available.contains("en") {
                return "en"
            }
            if let base = preferred.split(separator: "-").first.map(String.init),
               available.contains(base)
            {
                return base
            }
        }
        return available.contains("zh-Hans") ? "zh-Hans" : (available.first ?? "zh-Hans")
    }

    private static func defaultLanguagePackPayloads() -> [LanguagePackExportPayload] {
        let zhHans = LanguagePackExportPayload(code: "zh-Hans", name: "简体中文", strings: [:])
        let en = LanguagePackExportPayload(
            code: "en",
            name: "English",
            strings: [
                "sidebar.trailEffects": "Trail Effects",
                "sidebar.clickEffects": "Click Effects",
                "sidebar.magnifier": "Magnifier",
                "sidebar.general": "Settings",
                "window.settings.title": "CursorTrailBar Settings",
                "preset.custom": "Custom",
                "preset.thunderFirstForm": "Thunder Breathing",
                "preset.waterFirstForm": "Water Breathing",
                "menu.toggleTrail.on": "Disable Trail",
                "menu.toggleTrail.off": "Enable Trail",
                "menu.openSettings": "Open Settings…",
                "menu.clearTrail": "Clear Trail",
                "menu.hotkeyToggle": "Toggle Shortcut: %@",
                "menu.quit": "Quit",
                "menu.quitApp": "Quit CursorTrailBar",
                "menu.window": "Window",
                "menu.close": "Close",
                "section.general.title": "General",
                "section.general.subtitle": "Startup, tray, and app-wide options",
                "section.about.title": "About Mouse cursor Trail",
                "section.about.subtitle": "Author and build information",
                "row.launchAtLogin.title": "Launch at Login",
                "row.logging.title": "Enable Logging",
                "row.logging.subtitle": "Write runtime logs for troubleshooting",
                "row.logFolder.title": "Log Folder",
                "row.statusItem.title": "Show Menu Bar Icon",
                "row.statusItem.subtitle": "Keep core features available even if hidden",
                "row.language.title": "Language",
                "row.languagePackFolder.title": "Language Pack Folder",
                "row.about.appName": "App Name",
                "row.about.author": "Author",
                "row.about.email": "Author Email",
                "row.about.version": "Version",
                "button.openLogFolder": "Open Log Folder",
                "button.openLanguagePackFolder": "Open Folder",
                "button.confirm": "Confirm",
                "button.cancel": "Cancel",
                "button.preset.add": "Add",
                "button.preset.save": "Save",
                "button.preset.rename": "Rename",
                "button.preset.delete": "Delete",
                "button.preset.manage": "Manage",
                "button.preset.import": "Import",
                "button.preset.export": "Export",
                "button.close": "Close",
                "section.trail.title": "Trail",
                "section.trail.subtitle": "Mouse trail and base effect parameters",
                "section.trailEffect.title": "Effects",
                "section.trailEffect.subtitle": "Trail extra effect type and parameters",
                "row.tracking.title": "Enable Trail",
                "row.tracking.subtitle": "Hide trail rendering when disabled",
                "row.trail.type": "Trail Type",
                "row.trail.color": "Trail Color",
                "row.trail.waterColors": "Water Blade Colors",
                "row.trail.waterHighlight": "Highlight",
                "row.trail.waterPrimary": "Primary",
                "row.trail.waterShadow": "Shadow",
                "row.trail.waterHighlightRatio": "Highlight Ratio",
                "row.trail.waterPrimaryRatio": "Primary Ratio",
                "row.trail.waterShadowRatio": "Shadow Ratio",
                "row.trail.waterMixRandomness": "Random Mix Strength",
                "row.trail.waterSeedLock": "Lock Random Seed",
                "row.trail.waterSeedLock.subtitle": "Keep style stable between runs",
                "row.trail.waterSplashSize": "Splash Size",
                "row.trail.waterSplashSpeed": "Splash Speed",
                "row.trail.waterSplashLifetime": "Splash Time (ms)",
                "row.trail.waterSplashDensity": "Splash Density",
                "row.trail.waterSplashColor": "Splash Color",
                "row.trail.effectColor": "Effect Color",
                "row.trail.effectType": "Effect Type",
                "row.trail.effects.enabled": "Enable Effects",
                "row.trail.effects.enabled.subtitle": "Disable all additional trail effects",
                "row.trail.effectIntensity": "Effect Intensity",
                "row.trail.width": "Trail Width",
                "row.trail.lengthMs": "Trail Length (ms)",
                "row.trail.intensity": "Effect Intensity",
                "row.trail.rainbowColors": "Rainbow Colors",
                "row.trail.neonColors": "Neon Colors",
                "row.trail.neonPrimary": "Primary",
                "row.trail.neonSecondary": "Secondary",
                "label.trailPreset": "Preset",
                "section.speedBurst.title": "Speed Burst",
                "section.speedBurst.subtitle": "Extra burst effect triggered by fast movement",
                "row.speedBurst.enabled": "Enable Speed Burst",
                "row.speedBurst.enabled.subtitle": "Disable to turn off speed-triggered burst effects",
                "row.speedBurst.type": "Burst Type",
                "row.speedBurst.velocity": "Trigger Velocity",
                "row.speedBurst.cooldown": "Cooldown (ms)",
                "row.speedBurst.surgeScaleMode": "Scale Logic",
                "row.speedBurst.accentColor": "Endpoint Burst Color",
                "row.speedBurst.accentDuration": "Endpoint Burst Duration (ms)",
                "row.speedBurst.accentSize": "Endpoint Burst Size",
                "row.speedBurst.lineColor": "Burst Line Color",
                "row.speedBurst.duration": "Burst Line Duration (ms)",
                "row.speedBurst.durationMin": "Burst Min Duration (ms)",
                "row.speedBurst.durationMax": "Burst Max Duration (ms)",
                "row.speedBurst.minLength": "Burst Line Min Length",
                "row.speedBurst.maxLength": "Burst Line Max Length",
                "row.speedBurst.widthMultiplier": "Burst Line Width Factor",
                "row.speedBurst.trailScaleMin": "Min Trail Scale",
                "row.speedBurst.trailScaleMax": "Max Trail Scale",
                "row.speedBurst.effectScaleMin": "Min Effect Scale",
                "row.speedBurst.effectScaleMax": "Max Effect Scale",
                "row.speedBurst.jitter": "Burst Line Jitter",
                "section.click.title": "Click",
                "section.click.subtitle": "Click effects, radius, duration, and per-button colors",
                "row.click.enabled": "Enable Click Effects",
                "row.click.enabled.subtitle": "Disable all click visuals",
                "row.click.style": "Click Style",
                "row.click.radius": "Click Radius",
                "row.click.duration": "Click Effect Duration (ms)",
                "row.click.waterImpact.density": "Droplet Density",
                "row.click.waterImpact.spreadSpeed": "Droplet Spread Speed",
                "row.click.waterImpact.lifetime": "Droplet Lifetime (ms)",
                "row.click.waterImpact.size": "Droplet Size",
                "row.click.perButtonTitle": "%@ Click Effect",
                "dialog.preset.add.title": "Add Preset",
                "dialog.preset.add.message": "Enter a name for the new preset",
                "dialog.preset.rename.title": "Rename Preset",
                "dialog.preset.rename.message": "Enter a new preset name",
                "dialog.preset.delete.title": "Delete Preset",
                "dialog.preset.delete.message": "Delete this custom preset?",
                "dialog.preset.manager.title": "Preset Manager",
                "dialog.preset.inUse.title": "Cannot Delete",
                "dialog.preset.inUse.message": "The active preset cannot be deleted. Switch to another preset first.",
                "dialog.preset.export.empty.title": "Export Failed",
                "dialog.preset.export.empty.message": "No snapshot found. Please update this preset before export.",
                "dialog.preset.import.failed.title": "Import Failed",
                "dialog.preset.import.failed.message": "Invalid preset JSON file.",
                "column.preset.active": "Use",
                "column.preset.name": "Name",
                "column.preset.updatedAt": "Updated At",
                "column.preset.actions": "Actions",
                "placeholder.preset.name": "Preset name",
                "section.magnifier.title": "Magnifier",
                "section.magnifier.subtitle": "Hold shortcut to zoom, style, and permissions",
                "row.magnifier.enabled": "Enable Magnifier",
                "row.magnifier.enabled.subtitle": "Shortcut no longer triggers when disabled",
                "row.magnifier.showEffects": "Show Trail/Effects While Magnifying",
                "row.magnifier.showEffects.subtitle": "Only zoomed content when disabled",
                "row.magnifier.radius": "Magnifier Radius",
                "row.magnifier.zoom": "Zoom Ratio",
                "row.magnifier.borderWidth": "Border Width",
                "row.magnifier.borderColor": "Border Color",
                "row.magnifier.shadow": "Shadow Strength",
                "row.magnifier.shortcut": "Magnifier Shortcut",
                "hint.magnifier.shortcut": "Click record, then press keyboard/mouse shortcut. Hold to trigger.",
                "button.permission.inputMonitoring": "Open Input Monitoring Settings",
                "button.permission.accessibility": "Open Accessibility Settings",
                "button.permission.screenCapture": "Open Screen Recording Settings",
                "status.inputMonitoring.granted": "Input Monitoring: Granted ✅",
                "status.inputMonitoring.denied": "Input Monitoring: Not Granted ❌ (global shortcut may fail)",
                "status.accessibility.granted": "Accessibility: Granted ✅",
                "status.accessibility.denied": "Accessibility: Not Granted ❌ (scroll interception unavailable)",
                "status.screenCapture.granted": "Screen Recording: Granted ✅",
                "status.screenCapture.denied": "Screen Recording: Not Granted ❌ (magnifier capture may fail)",
                "status.launchAtLogin.unsupported": "Current macOS version does not support in-app launch-at-login.",
                "status.launchAtLogin.enabled": "Launch at login requested. Put app into Applications if needed.",
                "status.launchAtLogin.disabled": "Launch at login is disabled.",
                "status.about.version.dev": "Development Build",
                "shortcut.recordingPrompt": "Press keyboard/mouse shortcut… (Esc to cancel)",
                "unit.px": "px",
                "unit.ms": "ms",
                "unit.pxps": "px/s",
                "unit.multiplier": "x",
                "unit.percent": "%",
                "mouse.left": "Left",
                "mouse.right": "Right",
                "mouse.middle": "Middle",
                "mouse.button": "Mouse",
                "effectIntensity.off": "Off",
                "effectIntensity.low": "Low (Eco)",
                "effectIntensity.normal": "Normal (Default)",
                "effectIntensity.high": "High (Vivid)",
                "trailStyle.neon": "Dual Neon",
                "trailStyle.ribbon": "Fading Ribbon",
                "trailStyle.rainbow": "Rainbow Trail",
                "trailStyle.lightning": "Lightning Trail",
                "trailStyle.waterBlade": "Water Blade Stream",
                "trailEffect.particles": "Spark Particles",
                "trailEffect.ink": "Ink Diffusion",
                "trailEffect.electric": "Electric Arc",
                "trailEffect.waterSplash": "Water Splash",
                "speedBurstType.firstFlash": "First Flash",
                "speedBurstType.waterSurge": "Water Surge",
                "speedSurgeMode.randomRange": "Random Range",
                "speedSurgeMode.velocityBased": "Velocity Based",
                "clickStyle.solidPulse": "Solid Pulse",
                "clickStyle.crossFlare": "Cross Flare",
                "clickStyle.waterImpact": "Water Impact",
            ]
        )
        return [zhHans, en]
    }
}

func i18n(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
    LocalizationManager.shared.localized(key, fallback: fallback, args: args)
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
