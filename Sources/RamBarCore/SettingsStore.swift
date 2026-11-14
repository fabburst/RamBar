import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

public enum MenuBarFormat: String, CaseIterable, Identifiable, Sendable {
    case standard
    case compact
    case percent
    case ultraCompact

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: "18,4 Go"
        case .compact: "18.4G"
        case .percent: "76 %"
        case .ultraCompact: "18,4"
        }
    }
}

public enum ChipsetStyle: String, CaseIterable, Identifiable, Sendable {
    case outline
    case filled

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .outline: L10n.string("settings.chipsetStyle.outline")
        case .filled: L10n.string("settings.chipsetStyle.filled")
        }
    }
}

public enum DisplayMetric: String, CaseIterable, Identifiable, Sendable {
    case available
    case used

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .available: L10n.string("settings.metric.available")
        case .used: L10n.string("settings.metric.used")
        }
    }
}

public enum AvailabilityMode: String, CaseIterable, Identifiable, Sendable {
    case activityMonitor
    case strictlyFree

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .activityMonitor: L10n.string("settings.calc.activity")
        case .strictlyFree: L10n.string("settings.calc.strict")
        }
    }

    public var subtitle: String {
        switch self {
        case .activityMonitor: L10n.string("settings.calc.activity.sub")
        case .strictlyFree: L10n.string("settings.calc.strict.sub")
        }
    }
}

public enum AppCategory: String, CaseIterable, Identifiable, Sendable, Hashable {
    case browsers
    case communication
    case media
    case productivity
    case developer
    case games
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .browsers: L10n.string("cat.browsers")
        case .communication: L10n.string("cat.communication")
        case .media: L10n.string("cat.media")
        case .productivity: L10n.string("cat.productivity")
        case .developer: L10n.string("cat.developer")
        case .games: L10n.string("cat.games")
        case .other: L10n.string("cat.other")
        }
    }

    public static func detect(bundleURL: URL?, bundleID: String?) -> AppCategory {
        if let id = bundleID?.lowercased() {
            let browserHints = ["safari", "chrome", "firefox", "brave", "arc", "edge", "opera", "vivaldi", "orion", "zen-browser"]
            if browserHints.contains(where: { id.contains($0) }) { return .browsers }

            let commHints = ["slack", "discord", "teams", "zoom", "whatsapp", "telegram", "messages", "mail", "spark", "signal", "facetime"]
            if commHints.contains(where: { id.contains($0) }) { return .communication }

            let devHints = ["xcode", "vscode", "cursor", "terminal", "iterm", "warp", "docker", "jetbrains", "zed", "antigravity"]
            if devHints.contains(where: { id.contains($0) }) { return .developer }

            let mediaHints = ["spotify", "music", "vlc", "iina", "quicktime", "tv", "podcasts", "photos", "adobe", "figma"]
            if mediaHints.contains(where: { id.contains($0) }) { return .media }
        }

        if let bundleURL,
           let uti = Bundle(url: bundleURL)?.infoDictionary?["LSApplicationCategoryType"] as? String {
            let lower = uti.lowercased()
            if lower.contains("developer-tools") { return .developer }
            if lower.contains("games") { return .games }
            if lower.contains("social-networking") { return .communication }
            if lower.contains("music") || lower.contains("video") || lower.contains("entertainment") || lower.contains("photography") || lower.contains("graphics-design") {
                return .media
            }
            if lower.contains("productivity") || lower.contains("business") || lower.contains("finance") || lower.contains("education") || lower.contains("utilities") {
                return .productivity
            }
        }

        return .other
    }
}

@MainActor
@Observable
public final class SettingsStore {
    private enum Keys {
        static let menuBarFormat = "menuBarFormat"
        static let chipsetStyle = "chipsetStyle"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let displayMetric = "displayMetric"
        static let availabilityMode = "availabilityMode"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let protectedAppIDs = "protectedAppIDs"
        static let dynamicMenuBarColor = "dynamicMenuBarColor"
        static let warningThresholdPercent = "warningThresholdPercent"
        static let warningColorRGBA = "warningColorRGBA"
        static let criticalThresholdPercent = "criticalThresholdPercent"
        static let criticalColorRGBA = "criticalColorRGBA"
        static let suggestClosingInactiveApps = "suggestClosingInactiveApps"
        static let showAppLastUsedTime = "showAppLastUsedTime"
        static let notifyOnAutoClose = "notifyOnAutoClose"
        static let notifyOnCriticalPressure = "notifyOnCriticalPressure"
        static let hotKeyCombo = "hotKeyCombo"
        static let hotKeyConfigured = "hotKeyConfigured"
        static let autoCloseEnabled = "autoCloseEnabled"
        static let autoCloseRamThresholdPercent = "autoCloseRamThresholdPercent"
        static let autoCloseInactivityMinutes = "autoCloseInactivityMinutes"
        static let autoCloseCategories = "autoCloseCategories"
        static let autoClosePauseInFullscreen = "autoClosePauseInFullscreen"
        static let autoClosePauseDuringCalls = "autoClosePauseDuringCalls"
        static let autoCloseOnlyOnBattery = "autoCloseOnlyOnBattery"
    }

    private let defaults: UserDefaults

    public var menuBarFormat: MenuBarFormat {
        didSet { defaults.set(menuBarFormat.rawValue, forKey: Keys.menuBarFormat) }
    }

    public var chipsetStyle: ChipsetStyle {
        didSet { defaults.set(chipsetStyle.rawValue, forKey: Keys.chipsetStyle) }
    }

    public var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    public var displayMetric: DisplayMetric {
        didSet { defaults.set(displayMetric.rawValue, forKey: Keys.displayMetric) }
    }

    public var availabilityMode: AvailabilityMode {
        didSet { defaults.set(availabilityMode.rawValue, forKey: Keys.availabilityMode) }
    }

    public var refreshIntervalSeconds: Int {
        didSet {
            defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds)
            onRefreshIntervalChanged?(refreshIntervalSeconds)
        }
    }

    public var protectedAppIDs: Set<String> {
        didSet { defaults.set(Array(protectedAppIDs), forKey: Keys.protectedAppIDs) }
    }

    public var dynamicMenuBarColor: Bool {
        didSet { defaults.set(dynamicMenuBarColor, forKey: Keys.dynamicMenuBarColor) }
    }

    public var warningThresholdPercent: Int {
        didSet {
            defaults.set(warningThresholdPercent, forKey: Keys.warningThresholdPercent)
            if criticalThresholdPercent <= warningThresholdPercent {
                criticalThresholdPercent = min(99, warningThresholdPercent + 5)
            }
        }
    }

    public var warningColorRGBA: [Double] {
        didSet { defaults.set(warningColorRGBA, forKey: Keys.warningColorRGBA) }
    }

    public var warningColor: Color {
        get { Self.color(from: warningColorRGBA, fallback: .orange) }
        set { warningColorRGBA = Self.rgba(from: newValue, fallback: .systemOrange) }
    }

    public var criticalThresholdPercent: Int {
        didSet {
            defaults.set(criticalThresholdPercent, forKey: Keys.criticalThresholdPercent)
            if warningThresholdPercent >= criticalThresholdPercent {
                warningThresholdPercent = max(10, criticalThresholdPercent - 5)
            }
        }
    }

    public var criticalColorRGBA: [Double] {
        didSet { defaults.set(criticalColorRGBA, forKey: Keys.criticalColorRGBA) }
    }

    public var criticalColor: Color {
        get { Self.color(from: criticalColorRGBA, fallback: .red) }
        set { criticalColorRGBA = Self.rgba(from: newValue, fallback: .systemRed) }
    }

    private static func color(from rgba: [Double], fallback: Color) -> Color {
        guard rgba.count == 4 else { return fallback }
        return Color(red: rgba[0], green: rgba[1], blue: rgba[2], opacity: rgba[3])
    }

    private static func rgba(from color: Color, fallback: NSColor) -> [Double] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? fallback
        return [
            Double(ns.redComponent),
            Double(ns.greenComponent),
            Double(ns.blueComponent),
            Double(ns.alphaComponent)
        ]
    }

    public var suggestClosingInactiveApps: Bool {
        didSet { defaults.set(suggestClosingInactiveApps, forKey: Keys.suggestClosingInactiveApps) }
    }

    public var showAppLastUsedTime: Bool {
        didSet { defaults.set(showAppLastUsedTime, forKey: Keys.showAppLastUsedTime) }
    }

    public var notifyOnAutoClose: Bool {
        didSet { defaults.set(notifyOnAutoClose, forKey: Keys.notifyOnAutoClose) }
    }

    public var notifyOnCriticalPressure: Bool {
        didSet { defaults.set(notifyOnCriticalPressure, forKey: Keys.notifyOnCriticalPressure) }
    }

    public var hotKeyCombo: HotKeyCombo? {
        didSet {
            defaults.set(true, forKey: Keys.hotKeyConfigured)
            if let hotKeyCombo, let data = try? JSONEncoder().encode(hotKeyCombo) {
                defaults.set(data, forKey: Keys.hotKeyCombo)
            } else {
                defaults.removeObject(forKey: Keys.hotKeyCombo)
            }
            onHotKeyChanged?(hotKeyCombo)
        }
    }

    public var autoCloseEnabled: Bool {
        didSet { defaults.set(autoCloseEnabled, forKey: Keys.autoCloseEnabled) }
    }

    public var autoCloseRamThresholdPercent: Int {
        didSet { defaults.set(autoCloseRamThresholdPercent, forKey: Keys.autoCloseRamThresholdPercent) }
    }

    public var autoCloseInactivityMinutes: Int {
        didSet { defaults.set(autoCloseInactivityMinutes, forKey: Keys.autoCloseInactivityMinutes) }
    }

    public var autoCloseCategories: Set<AppCategory> {
        didSet { defaults.set(autoCloseCategories.map(\.rawValue), forKey: Keys.autoCloseCategories) }
    }

    public var autoClosePauseInFullscreen: Bool {
        didSet { defaults.set(autoClosePauseInFullscreen, forKey: Keys.autoClosePauseInFullscreen) }
    }

    public var autoClosePauseDuringCalls: Bool {
        didSet { defaults.set(autoClosePauseDuringCalls, forKey: Keys.autoClosePauseDuringCalls) }
    }

    public var autoCloseOnlyOnBattery: Bool {
        didSet { defaults.set(autoCloseOnlyOnBattery, forKey: Keys.autoCloseOnlyOnBattery) }
    }

    public var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public private(set) var launchAtLoginError: String?
    public private(set) var previewingColor: Color?
    private var colorPreviewTask: Task<Void, Never>?
    public var onRefreshIntervalChanged: ((Int) -> Void)?
    public var onHotKeyChanged: ((HotKeyCombo?) -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedFormat = defaults.string(forKey: Keys.menuBarFormat)
            .flatMap(MenuBarFormat.init(rawValue:)) ?? .standard
        let savedChipStyle = defaults.string(forKey: Keys.chipsetStyle)
            .flatMap(ChipsetStyle.init(rawValue:)) ?? .outline
        let savedShowIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        let savedMetric = defaults.string(forKey: Keys.displayMetric)
            .flatMap(DisplayMetric.init(rawValue:)) ?? .available
        let savedMode = defaults.string(forKey: Keys.availabilityMode)
            .flatMap(AvailabilityMode.init(rawValue:)) ?? .activityMonitor
        let savedRefresh = defaults.object(forKey: Keys.refreshIntervalSeconds) as? Int ?? 2
        let savedProtected = defaults.stringArray(forKey: Keys.protectedAppIDs) ?? []
        let savedColor = defaults.object(forKey: Keys.dynamicMenuBarColor) as? Bool ?? true
        let savedWarningThreshold = defaults.object(forKey: Keys.warningThresholdPercent) as? Int ?? 78
        let savedWarningRGBA = defaults.array(forKey: Keys.warningColorRGBA) as? [Double]
            ?? [0.96, 0.48, 0.25, 1.0]
        let savedCriticalThreshold = defaults.object(forKey: Keys.criticalThresholdPercent) as? Int ?? 90
        let savedCriticalRGBA = defaults.array(forKey: Keys.criticalColorRGBA) as? [Double]
            ?? [1.0, 0.23, 0.19, 1.0]
        let savedSuggest = defaults.object(forKey: Keys.suggestClosingInactiveApps) as? Bool ?? true
        let savedLastUsed = defaults.object(forKey: Keys.showAppLastUsedTime) as? Bool ?? true
        let savedNotifyAuto = defaults.object(forKey: Keys.notifyOnAutoClose) as? Bool ?? true
        let savedNotifyCritical = defaults.object(forKey: Keys.notifyOnCriticalPressure) as? Bool ?? true

        let hotKeyConfigured = defaults.bool(forKey: Keys.hotKeyConfigured)
        let savedHotKey: HotKeyCombo?
        if hotKeyConfigured {
            if let data = defaults.data(forKey: Keys.hotKeyCombo),
               let decoded = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
                savedHotKey = decoded
            } else {
                savedHotKey = nil
            }
        } else {
            savedHotKey = .defaultCombo
        }

        let savedAutoClose = defaults.object(forKey: Keys.autoCloseEnabled) as? Bool ?? false
        let savedThreshold = defaults.object(forKey: Keys.autoCloseRamThresholdPercent) as? Int ?? 85
        let savedMinutes = defaults.object(forKey: Keys.autoCloseInactivityMinutes) as? Int ?? 30
        let savedCats = defaults.stringArray(forKey: Keys.autoCloseCategories)?
            .compactMap(AppCategory.init(rawValue:))
        let defaultCats: Set<AppCategory> = [.browsers, .communication, .media, .games]

        self.menuBarFormat = savedFormat
        self.chipsetStyle = savedChipStyle
        self.showMenuBarIcon = savedShowIcon
        self.displayMetric = savedMetric
        self.availabilityMode = savedMode
        self.refreshIntervalSeconds = savedRefresh
        self.protectedAppIDs = Set(savedProtected)
        self.dynamicMenuBarColor = savedColor
        self.warningThresholdPercent = savedWarningThreshold
        self.warningColorRGBA = savedWarningRGBA
        self.criticalThresholdPercent = savedCriticalThreshold
        self.criticalColorRGBA = savedCriticalRGBA
        self.suggestClosingInactiveApps = savedSuggest
        self.showAppLastUsedTime = savedLastUsed
        self.notifyOnAutoClose = savedNotifyAuto
        self.notifyOnCriticalPressure = savedNotifyCritical
        self.hotKeyCombo = savedHotKey
        self.autoCloseEnabled = savedAutoClose
        self.autoCloseRamThresholdPercent = savedThreshold
        self.autoCloseInactivityMinutes = savedMinutes
        self.autoCloseCategories = savedCats.map(Set.init) ?? defaultCats
        self.autoClosePauseInFullscreen = defaults.object(forKey: Keys.autoClosePauseInFullscreen) as? Bool ?? true
        self.autoClosePauseDuringCalls = defaults.object(forKey: Keys.autoClosePauseDuringCalls) as? Bool ?? true
        self.autoCloseOnlyOnBattery = defaults.object(forKey: Keys.autoCloseOnlyOnBattery) as? Bool ?? false
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }

    public static let permanentlyProtectedAppIDs: Set<String> = ["com.apple.finder"]

    public func isAlwaysProtected(_ appID: String) -> Bool {
        Self.permanentlyProtectedAppIDs.contains(appID)
    }

    public func isProtected(_ appID: String) -> Bool {
        isAlwaysProtected(appID) || protectedAppIDs.contains(appID)
    }

    public func toggleProtection(for appID: String) {
        guard !isAlwaysProtected(appID) else { return }
        if protectedAppIDs.contains(appID) {
            protectedAppIDs.remove(appID)
        } else {
            protectedAppIDs.insert(appID)
        }
    }

    public func toggleAutoCloseCategory(_ category: AppCategory) {
        if autoCloseCategories.contains(category) {
            autoCloseCategories.remove(category)
        } else {
            autoCloseCategories.insert(category)
        }
    }

    public func triggerColorPreview(_ color: Color) {
        colorPreviewTask?.cancel()
        previewingColor = color
        colorPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.previewingColor = nil
        }
    }
}
