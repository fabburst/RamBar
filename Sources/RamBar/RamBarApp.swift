import RamBarCore
import SwiftUI

@main
struct RamBarApp: App {
    @State private var monitor: MemoryMonitor
    @State private var settings: SettingsStore

    init() {
        let settingsStore = SettingsStore()
        let memoryMonitor = MemoryMonitor()
        memoryMonitor.settings = settingsStore

        settingsStore.onRefreshIntervalChanged = { seconds in
            memoryMonitor.updateRefreshInterval(seconds)
        }
        settingsStore.onHotKeyChanged = { combo in
            GlobalHotKeyManager.shared.register(combo: combo) {
                memoryMonitor.refresh()
                GlobalHotKeyManager.toggleMenuBarPopover()
            }
        }

        GlobalHotKeyManager.shared.register(combo: settingsStore.hotKeyCombo) {
            memoryMonitor.refresh()
            GlobalHotKeyManager.toggleMenuBarPopover()
        }
        NotificationManager.shared.requestAuthorizationIfNeeded()

        _settings = State(initialValue: settingsStore)
        _monitor = State(initialValue: memoryMonitor)
    }

    var body: some Scene {
        MenuBarExtra {
            MemoryPopoverView(monitor: monitor, settings: settings)
        } label: {
            let previewColor = settings.previewingColor
            let usedPercent = monitor.snapshot.usedFraction * 100
            let isColored = previewColor != nil || (settings.dynamicMenuBarColor && usedPercent >= Double(settings.warningThresholdPercent))
            let tint = previewColor ?? monitor.snapshot.menuBarColor(
                enabled: settings.dynamicMenuBarColor,
                warningThreshold: settings.warningThresholdPercent,
                warningColor: settings.warningColor,
                criticalThreshold: settings.criticalThresholdPercent,
                criticalColor: settings.criticalColor
            )

            if settings.menuBarFormat == .percent {
                let pct = Int(
                    (monitor.snapshot.displayedMetricFraction(
                        metric: settings.displayMetric,
                        mode: settings.availabilityMode
                    ) * 100).rounded()
                )
                Image(
                    nsImage: ChipsetPercentImage.make(
                        percent: pct,
                        tint: tint,
                        isTemplate: !isColored,
                        style: settings.chipsetStyle
                    )
                )
            } else {
                HStack(spacing: 4) {
                    if settings.showMenuBarIcon {
                        Image(systemName: "memorychip")
                    }
                    Text(
                        monitor.snapshot.menuBarText(
                            format: settings.menuBarFormat,
                            metric: settings.displayMetric,
                            mode: settings.availabilityMode
                        )
                    )
                    .monospacedDigit()
                }
                .foregroundStyle(tint)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
