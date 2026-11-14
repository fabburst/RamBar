import SwiftUI

public enum PopoverTab: Hashable, Sendable {
    case memory
    case apps
    case settings
}

public struct MemoryPopoverView: View {
    public let monitor: MemoryMonitor
    public let settings: SettingsStore

    @State private var selectedTab: PopoverTab
    @State private var isHoveringQuit = false
    @State private var isHoveringPressure = false

    public init(monitor: MemoryMonitor, settings: SettingsStore, initialTab: PopoverTab = .memory) {
        self.monitor = monitor
        self.settings = settings
        self._selectedTab = State(initialValue: initialTab)
    }

    private var snapshot: MemorySnapshot {
        monitor.snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Picker(
                    "",
                    selection: Binding(
                        get: { selectedTab == .settings ? .memory : selectedTab },
                        set: { selectedTab = $0 }
                    )
                ) {
                    Text(L10n.string("tab.memory")).tag(PopoverTab.memory)
                    Text(L10n.string("tab.apps")).tag(PopoverTab.apps)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
                .opacity(selectedTab == .settings ? 0.55 : 1)

                HStack {
                    Spacer()
                    Button {
                        selectedTab = selectedTab == .settings ? .memory : .settings
                    } label: {
                        Image(systemName: selectedTab == .settings ? "gearshape.fill" : "gearshape")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selectedTab == .settings ? Color.primary : Color.secondary)
                            .frame(width: 26, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(.primary.opacity(selectedTab == .settings ? 0.14 : 0))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.string("tab.settings"))
                }
            }

            switch selectedTab {
            case .memory:
                memoryTab
            case .apps:
                appsTab
            case .settings:
                settingsTab
            }

            Divider()
                .opacity(0.35)

            quitButton
        }
        .padding(16)
        .frame(width: 320)
        .preferredColorScheme(settings.appTheme.colorScheme)
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .apps {
                monitor.refreshRunningApps()
            }
        }
    }

    // MARK: - Mémoire

    private var memoryTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            SparklineView(values: monitor.history, tint: sparklineTint)
                .frame(height: 28)

            Divider()
                .opacity(0.35)

            breakdownSection

            Divider()
                .opacity(0.35)

            VStack(spacing: 4) {
                pressureRow
                if snapshot.swapUsedBytes > 0 {
                    swapRow
                }
            }

            if settings.suggestClosingInactiveApps,
               snapshot.usedFraction >= 0.78,
               let topSuggestion = monitor.inactiveSuggestions(protectedIDs: settings.protectedAppIDs).first {
                inactiveBanner(for: topSuggestion)
            }
        }
    }

    private func inactiveBanner(for app: AppMemoryInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.orange)

            Text("\(app.name) (\(app.memoryBytes.formattedMemoryCompact))")
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Button(L10n.string("apps.close")) {
                monitor.closeGracefully(app)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.08))
        )
    }

    private var headerTitle: String {
        switch settings.displayMetric {
        case .available:
            settings.availabilityMode == .activityMonitor
                ? L10n.string("memory.available")
                : L10n.string("memory.free")
        case .used:
            L10n.string("memory.used")
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(headerTitle)
                        .font(.headline)
                    Image(systemName: "memorychip")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                let metricBytes = snapshot.displayedMetricBytes(
                    metric: settings.displayMetric,
                    mode: settings.availabilityMode
                )
                Text(metricBytes.formattedShortGigabytes)
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.35), value: metricBytes)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "cpu")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("Apple Silicon")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 6) {
                    Text("↑ \(snapshot.totalBytes.formattedGigabytes(decimals: 0))")
                    Text("↓ \(snapshot.usedBytes.formattedShortGigabytes)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    private var breakdownSection: some View {
        HStack(spacing: 0) {
            BreakdownItem(
                title: L10n.string("memory.apps"),
                symbol: "square.stack.3d.up",
                value: snapshot.appBytes.formattedShortGigabytes
            )
            BreakdownItem(
                title: L10n.string("memory.wired"),
                symbol: "lock",
                value: snapshot.wiredBytes.formattedShortGigabytes
            )
            BreakdownItem(
                title: L10n.string("memory.compressed"),
                symbol: "arrow.down.right.and.arrow.up.left",
                value: snapshot.compressedBytes.formattedShortGigabytes
            )
            BreakdownItem(
                title: L10n.string("memory.cache"),
                symbol: "internaldrive",
                value: snapshot.cachedBytes.formattedShortGigabytes
            )
        }
    }

    private var pressureRow: some View {
        Button {
            monitor.openActivityMonitor()
        } label: {
            HStack {
                Text(L10n.string("memory.pressure"))
                    .font(.subheadline)

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: snapshot.pressure.symbolName)
                        .foregroundStyle(pressureColor)
                    Text(snapshot.pressure.label)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(isHoveringPressure ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringPressure = $0 }
        .help(L10n.string("settings.openActivityMonitor"))
    }

    private var swapRow: some View {
        HStack {
            Text(L10n.string("memory.swap"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(snapshot.swapUsedBytes.formattedMemoryCompact) / \(snapshot.swapTotalBytes.formattedMemoryCompact)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Apps

    private var appsTab: some View {
        let suggestions = settings.suggestClosingInactiveApps
            ? monitor.inactiveSuggestions(protectedIDs: settings.protectedAppIDs)
            : []

        return VStack(alignment: .leading, spacing: 10) {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(L10n.string("apps.suggestions"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(suggestions) { app in
                        HStack(spacing: 8) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 16, height: 16)
                            }
                            Text(app.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(app.memoryBytes.formattedMemoryCompact)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Button(L10n.string("apps.close")) {
                                monitor.closeGracefully(app)
                            }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(.primary.opacity(0.07))
                        )
                    }
                }

                Divider()
                    .opacity(0.35)
            }

            HStack {
                Text(L10n.string("apps.active"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    monitor.refreshRunningApps()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if monitor.runningApps.isEmpty {
                Text(L10n.string("apps.none"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(monitor.runningApps) { app in
                            AppMemoryRow(
                                app: app,
                                isProtected: settings.isProtected(app.appID),
                                isAlwaysProtected: settings.isAlwaysProtected(app.appID),
                                showLastUsed: settings.showAppLastUsedTime,
                                onToggleProtect: {
                                    settings.toggleProtection(for: app.appID)
                                },
                                onForceQuit: {
                                    monitor.forceQuit(app)
                                }
                            )
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(height: suggestions.isEmpty ? 220 : 150)
            }
        }
    }

    // MARK: - Réglages

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        L10n.string("settings.showIcon"),
                        isOn: Binding(
                            get: { settings.showMenuBarIcon },
                            set: { settings.showMenuBarIcon = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .font(.subheadline)

                    Text(L10n.string("settings.format"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker(
                        "Format",
                        selection: Binding(
                            get: { settings.menuBarFormat },
                            set: { settings.menuBarFormat = $0 }
                        )
                    ) {
                        ForEach(MenuBarFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    if settings.menuBarFormat == .percent {
                        HStack {
                            Text(L10n.string("settings.chipsetStyle"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker(
                                "ChipsetStyle",
                                selection: Binding(
                                    get: { settings.chipsetStyle },
                                    set: { settings.chipsetStyle = $0 }
                                )
                            ) {
                                ForEach(ChipsetStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("settings.metric"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker(
                        "Metric",
                        selection: Binding(
                            get: { settings.displayMetric },
                            set: { settings.displayMetric = $0 }
                        )
                    ) {
                        ForEach(DisplayMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("settings.calculation"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker(
                        "Calcul",
                        selection: Binding(
                            get: { settings.availabilityMode },
                            set: { settings.availabilityMode = $0 }
                        )
                    ) {
                        ForEach(AvailabilityMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Text(settings.availabilityMode.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("settings.theme"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker(
                        "Theme",
                        selection: Binding(
                            get: { settings.appTheme },
                            set: { settings.appTheme = $0 }
                        )
                    ) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                HStack {
                    Text(L10n.string("settings.refreshInterval"))
                        .font(.subheadline)
                    Spacer()
                    Picker(
                        "Refresh",
                        selection: Binding(
                            get: { settings.refreshIntervalSeconds },
                            set: { settings.refreshIntervalSeconds = $0 }
                        )
                    ) {
                        Text("1 s").tag(1)
                        Text("2 s").tag(2)
                        Text("5 s").tag(5)
                        Text("10 s").tag(10)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }

                HStack {
                    Text(L10n.string("settings.hotkey"))
                        .font(.subheadline)
                    Spacer()
                    ShortcutRecorderView(
                        combo: Binding(
                            get: { settings.hotKeyCombo },
                            set: { settings.hotKeyCombo = $0 }
                        )
                    )
                }

                Divider()
                    .opacity(0.35)

                Toggle(
                    L10n.string("settings.launchAtLogin"),
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    )
                )
                .toggleStyle(.switch)
                .font(.subheadline)

                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Toggle(
                    L10n.string("settings.dynamicColor"),
                    isOn: Binding(
                        get: { settings.dynamicMenuBarColor },
                        set: { settings.dynamicMenuBarColor = $0 }
                    )
                )
                .toggleStyle(.switch)
                .font(.subheadline)

                if settings.dynamicMenuBarColor {
                    criticalColorSelector
                }

                Toggle(
                    L10n.string("settings.suggestInactive"),
                    isOn: Binding(
                        get: { settings.suggestClosingInactiveApps },
                        set: { settings.suggestClosingInactiveApps = $0 }
                    )
                )
                .toggleStyle(.switch)
                .font(.subheadline)

                Toggle(
                    L10n.string("settings.showLastUsed"),
                    isOn: Binding(
                        get: { settings.showAppLastUsedTime },
                        set: { settings.showAppLastUsedTime = $0 }
                    )
                )
                .toggleStyle(.switch)
                .font(.subheadline)

                Divider()
                    .opacity(0.35)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("settings.notifications"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Toggle(
                        L10n.string("settings.notifyAutoClose"),
                        isOn: Binding(
                            get: { settings.notifyOnAutoClose },
                            set: { settings.notifyOnAutoClose = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .font(.subheadline)

                    Toggle(
                        L10n.string("settings.notifyCritical"),
                        isOn: Binding(
                            get: { settings.notifyOnCriticalPressure },
                            set: { settings.notifyOnCriticalPressure = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .font(.subheadline)
                }

                Divider()
                    .opacity(0.35)

                autoCloseSection

                Divider()
                    .opacity(0.35)

                Button {
                    monitor.openActivityMonitor()
                } label: {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                        Text(L10n.string("settings.openActivityMonitor"))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 4)
        }
        .frame(height: 360)
    }

    private var criticalColorSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            thresholdRow(
                title: "Seuil 1",
                threshold: Binding(
                    get: { settings.warningThresholdPercent },
                    set: { settings.warningThresholdPercent = $0 }
                ),
                choices: [60, 65, 70, 75, 78, 80, 85],
                color: Binding(
                    get: { settings.warningColor },
                    set: { settings.warningColor = $0 }
                )
            )

            thresholdRow(
                title: "Seuil 2",
                threshold: Binding(
                    get: { settings.criticalThresholdPercent },
                    set: { settings.criticalThresholdPercent = $0 }
                ),
                choices: [80, 85, 88, 90, 92, 95],
                color: Binding(
                    get: { settings.criticalColor },
                    set: { settings.criticalColor = $0 }
                )
            )
        }
        .padding(.leading, 4)
    }

    private func thresholdRow(
        title: String,
        threshold: Binding<Int>,
        choices: [Int],
        color: Binding<Color>
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Picker(title, selection: threshold) {
                ForEach(choices, id: \.self) { pct in
                    Text("≥ \(pct) %").tag(pct)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 82)

            Spacer()

            Button {
                ColorPanelCoordinator.shared.open(initialColor: color.wrappedValue) { newColor in
                    color.wrappedValue = newColor
                    settings.triggerColorPreview(newColor)
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color.wrappedValue)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .strokeBorder(.primary.opacity(0.25), lineWidth: 1)
                        )
                    Image(systemName: "eyedropper")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.primary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .help("Choisir n'importe quelle couleur")
        }
    }

    private var autoCloseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                L10n.string("settings.autoclose"),
                isOn: Binding(
                    get: { settings.autoCloseEnabled },
                    set: { settings.autoCloseEnabled = $0 }
                )
            )
            .toggleStyle(.switch)
            .font(.subheadline.weight(.medium))

            if settings.autoCloseEnabled {
                HStack {
                    Text(L10n.string("settings.autoclose.threshold"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker(
                        "Threshold",
                        selection: Binding(
                            get: { settings.autoCloseRamThresholdPercent },
                            set: { settings.autoCloseRamThresholdPercent = $0 }
                        )
                    ) {
                        ForEach([75, 80, 85, 90, 95], id: \.self) { pct in
                            Text("\(pct) %").tag(pct)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 85)
                }

                HStack {
                    Text(L10n.string("settings.autoclose.inactivity"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker(
                        "Inactivity",
                        selection: Binding(
                            get: { settings.autoCloseInactivityMinutes },
                            set: { settings.autoCloseInactivityMinutes = $0 }
                        )
                    ) {
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 h").tag(60)
                        Text("2 h").tag(120)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 85)
                }

                Text(L10n.string("settings.autoclose.categories"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(AppCategory.allCases) { category in
                        let isSelected = settings.autoCloseCategories.contains(category)
                        Button {
                            settings.toggleAutoCloseCategory(category)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.caption2)
                                Text(category.title)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? Color.primary.opacity(0.15) : Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Toggle(
                    L10n.string("settings.autoclose.dnd.fullscreen"),
                    isOn: Binding(
                        get: { settings.autoClosePauseInFullscreen },
                        set: { settings.autoClosePauseInFullscreen = $0 }
                    )
                )
                .toggleStyle(.switch)
                .font(.caption)

                Toggle(
                    L10n.string("settings.autoclose.dnd.calls"),
                    isOn: Binding(
                        get: { settings.autoClosePauseDuringCalls },
                        set: { settings.autoClosePauseDuringCalls = $0 }
                    )
                )
                .toggleStyle(.switch)
                .font(.caption)

                Toggle(
                    L10n.string("settings.autoclose.dnd.battery"),
                    isOn: Binding(
                        get: { settings.autoCloseOnlyOnBattery },
                        set: { settings.autoCloseOnlyOnBattery = $0 }
                    )
                )
                .toggleStyle(.switch)
                .font(.caption)

                if !monitor.autoCloseHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("settings.autoclose.history"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(monitor.autoCloseHistory.prefix(5)) { event in
                            HStack(spacing: 6) {
                                Text(event.closedAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                                Text(event.appName)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(event.freedBytes.formattedMemoryCompact)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Button(L10n.string("apps.relaunch")) {
                                    monitor.relaunch(event)
                                }
                                .font(.caption2)
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                Text(L10n.string("settings.autoclose.note"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Footer

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack {
                Text(L10n.string("apps.quit"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("⌘Q")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(isHoveringQuit ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringQuit = $0 }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var pressureColor: Color {
        switch snapshot.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private var sparklineTint: Color {
        switch snapshot.pressure {
        case .normal: .primary
        case .warning: .orange
        case .critical: .red
        }
    }
}

private struct AppMemoryRow: View {
    let app: AppMemoryInfo
    let isProtected: Bool
    let isAlwaysProtected: Bool
    let showLastUsed: Bool
    let onToggleProtect: () -> Void
    let onForceQuit: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }

            Text(app.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Spacer()

            if showLastUsed {
                Text(app.lastActiveDate.formattedLastUsed(isActive: app.isActive))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Text(app.memoryBytes.formattedMemoryCompact)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: onToggleProtect) {
                Image(systemName: isAlwaysProtected ? "lock.shield.fill" : (isProtected ? "pin.fill" : "pin"))
                    .font(.caption)
                    .foregroundStyle(isProtected ? Color.primary : Color.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(isAlwaysProtected)

            Button(action: onForceQuit) {
                Image(systemName: isProtected ? "lock.fill" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(isProtected ? Color.secondary.opacity(0.4) : Color.red.opacity(0.85))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(isProtected)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(isHovering ? 0.10 : (isProtected ? 0.06 : 0)))
        )
        .onHover { isHovering = $0 }
    }
}

private struct BreakdownItem: View {
    let title: String
    let symbol: String
    let value: String

    var body: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(height: 18)

            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
