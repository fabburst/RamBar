import Carbon.HIToolbox
import Foundation
import Testing
@testable import RamBarCore

@Suite("RamBarCore Tests")
struct RamBarTests {
    @Test("MemorySnapshot metric calculations for available and used")
    func snapshotMetricCalculations() {
        let gb: UInt64 = 1_073_741_824
        let snapshot = MemorySnapshot(
            totalBytes: 16 * gb,
            availableBytes: 4 * gb,
            strictlyFreeBytes: 1 * gb,
            usedBytes: 12 * gb,
            appBytes: 6 * gb,
            wiredBytes: 3 * gb,
            compressedBytes: 3 * gb,
            cachedBytes: 3 * gb,
            swapUsedBytes: 512 * 1_048_576,
            swapTotalBytes: 2 * gb,
            pressure: .normal
        )

        #expect(snapshot.displayedMetricBytes(metric: .available, mode: .activityMonitor) == 4 * gb)
        #expect(snapshot.displayedMetricBytes(metric: .available, mode: .strictlyFree) == 1 * gb)
        #expect(snapshot.displayedMetricBytes(metric: .used, mode: .activityMonitor) == 12 * gb)
        #expect(snapshot.displayedMetricBytes(metric: .used, mode: .strictlyFree) == 15 * gb)
        #expect(snapshot.usedFraction == 0.75)
    }

    @Test("Menu bar text formatting for all formats")
    func menuBarFormatting() {
        let gb: UInt64 = 1_073_741_824
        let snapshot = MemorySnapshot(
            totalBytes: 16 * gb,
            availableBytes: 4 * gb,
            strictlyFreeBytes: 1 * gb,
            usedBytes: 12 * gb,
            appBytes: 6 * gb,
            wiredBytes: 3 * gb,
            compressedBytes: 3 * gb,
            cachedBytes: 3 * gb,
            pressure: .normal
        )

        #expect(snapshot.menuBarText(format: .compact, metric: .available, mode: .activityMonitor) == "4.0G")
        #expect(snapshot.menuBarText(format: .percent, metric: .available, mode: .activityMonitor) == "25 %")
        #expect(snapshot.menuBarText(format: .percent, metric: .used, mode: .activityMonitor) == "75 %")
    }

    @Test("Finder is always protected and cannot be unpinned")
    @MainActor
    func finderProtectionRules() {
        let suiteName = "RamBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.isAlwaysProtected("com.apple.finder"))
        #expect(settings.isProtected("com.apple.finder"))

        settings.toggleProtection(for: "com.apple.finder")
        #expect(settings.isProtected("com.apple.finder"))

        #expect(!settings.isProtected("com.apple.Safari"))
        settings.toggleProtection(for: "com.apple.Safari")
        #expect(settings.isProtected("com.apple.Safari"))
        settings.toggleProtection(for: "com.apple.Safari")
        #expect(!settings.isProtected("com.apple.Safari"))
    }

    @Test("AppCategory detection maps known bundle IDs")
    func appCategoryDetection() {
        #expect(AppCategory.detect(bundleURL: nil, bundleID: "com.apple.Safari") == .browsers)
        #expect(AppCategory.detect(bundleURL: nil, bundleID: "com.tinyspeck.slackmacgap") == .communication)
        #expect(AppCategory.detect(bundleURL: nil, bundleID: "com.apple.dt.Xcode") == .developer)
        #expect(AppCategory.detect(bundleURL: nil, bundleID: "com.spotify.client") == .media)
    }

    @Test("HotKeyCombo formats default shortcut")
    func hotKeyFormatting() {
        let combo = HotKeyCombo.defaultCombo
        #expect(combo.displayString == "⌥⌘R")
    }
}
