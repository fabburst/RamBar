import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit.ps
import Observation
import SwiftUI

public enum MemoryPressure: Sendable {
    case normal
    case warning
    case critical

    public var label: String {
        switch self {
        case .normal: L10n.string("memory.pressure.normal")
        case .warning: L10n.string("memory.pressure.warning")
        case .critical: L10n.string("memory.pressure.critical")
        }
    }

    public var symbolName: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }
}

public struct MemorySnapshot: Sendable, Equatable {
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let strictlyFreeBytes: UInt64
    public let usedBytes: UInt64
    public let appBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let cachedBytes: UInt64
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let pressure: MemoryPressure

    public init(
        totalBytes: UInt64,
        availableBytes: UInt64,
        strictlyFreeBytes: UInt64,
        usedBytes: UInt64,
        appBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        cachedBytes: UInt64,
        swapUsedBytes: UInt64 = 0,
        swapTotalBytes: UInt64 = 0,
        pressure: MemoryPressure
    ) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.strictlyFreeBytes = strictlyFreeBytes
        self.usedBytes = usedBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressure = pressure
    }

    public func displayedAvailableBytes(for mode: AvailabilityMode) -> UInt64 {
        switch mode {
        case .activityMonitor: availableBytes
        case .strictlyFree: strictlyFreeBytes
        }
    }

    public func displayedAvailableFraction(for mode: AvailabilityMode) -> Double {
        guard totalBytes > 0 else { return 0 }
        return Double(displayedAvailableBytes(for: mode)) / Double(totalBytes)
    }

    public func displayedMetricBytes(metric: DisplayMetric, mode: AvailabilityMode) -> UInt64 {
        switch metric {
        case .available:
            return displayedAvailableBytes(for: mode)
        case .used:
            switch mode {
            case .activityMonitor:
                return usedBytes
            case .strictlyFree:
                return totalBytes > strictlyFreeBytes ? totalBytes - strictlyFreeBytes : 0
            }
        }
    }

    public func displayedMetricFraction(metric: DisplayMetric, mode: AvailabilityMode) -> Double {
        guard totalBytes > 0 else { return 0 }
        return Double(displayedMetricBytes(metric: metric, mode: mode)) / Double(totalBytes)
    }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    public func menuBarColor(
        enabled: Bool,
        warningThreshold: Int = 78,
        warningColor: Color = .orange,
        criticalThreshold: Int = 90,
        criticalColor: Color = .red
    ) -> Color {
        guard enabled else { return .primary }
        let pct = usedFraction * 100
        if pct >= Double(criticalThreshold) {
            return criticalColor
        }
        if pct >= Double(warningThreshold) {
            return warningColor
        }
        return .primary
    }

    public func menuBarText(format: MenuBarFormat, metric: DisplayMetric, mode: AvailabilityMode) -> String {
        let bytes = displayedMetricBytes(metric: metric, mode: mode)
        let gb = Double(bytes) / 1_073_741_824.0
        switch format {
        case .standard:
            return "\(gb.formatted(.number.precision(.fractionLength(1)))) Go"
        case .compact:
            return String(format: "%.1fG", gb)
        case .percent:
            let pct = Int((displayedMetricFraction(metric: metric, mode: mode) * 100).rounded())
            return "\(pct) %"
        case .ultraCompact:
            return "\(gb.formatted(.number.precision(.fractionLength(1))))"
        }
    }

    public static let empty = MemorySnapshot(
        totalBytes: 0,
        availableBytes: 0,
        strictlyFreeBytes: 0,
        usedBytes: 0,
        appBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        cachedBytes: 0,
        swapUsedBytes: 0,
        swapTotalBytes: 0,
        pressure: .normal
    )
}

public struct AppMemoryInfo: Identifiable {
    public let id: String
    public let appID: String
    public let pid: pid_t
    public let name: String
    public let icon: NSImage?
    public let memoryBytes: UInt64
    public let isActive: Bool
    public let lastActiveDate: Date
    public let category: AppCategory
    public let application: NSRunningApplication
}

public struct AutoCloseEvent: Identifiable, Sendable {
    public let id = UUID()
    public let appName: String
    public let appID: String
    public let bundleURL: URL?
    public let freedBytes: UInt64
    public let closedAt: Date
}

@MainActor
@Observable
public final class MemoryMonitor {
    public private(set) var snapshot: MemorySnapshot = .empty
    public private(set) var history: [Double] = []
    public private(set) var runningApps: [AppMemoryInfo] = []
    public private(set) var autoCloseHistory: [AutoCloseEvent] = []
    public private(set) var lastAutoClosedMessage: String?

    public weak var settings: SettingsStore? {
        didSet {
            if let interval = settings?.refreshIntervalSeconds {
                refreshIntervalSeconds = interval
            }
        }
    }

    private var refreshIntervalSeconds: Int = 2
    private var lastActiveDates: [String: Date] = [:]
    private var lastAutoCloseAttempt: Date = .distantPast
    private var lastCriticalNotification: Date = .distantPast
    private var previousPressure: MemoryPressure = .normal
    private var monitorTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?
    private let maxHistoryCount = 30

    public init(startAutomatically: Bool = true) {
        let now = Date()
        for app in NSWorkspace.shared.runningApplications {
            let key = app.bundleIdentifier ?? app.localizedName ?? "pid-\(app.processIdentifier)"
            lastActiveDates[key] = now
        }
        refresh()
        if startAutomatically {
            refreshRunningApps()
            startMonitoring()
            observeAppActivations()
        }
    }

    public func updateRefreshInterval(_ seconds: Int) {
        let clamped = max(1, seconds)
        guard clamped != refreshIntervalSeconds else { return }
        refreshIntervalSeconds = clamped
        monitorTask?.cancel()
        monitorTask = nil
        startMonitoring()
    }

    public func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.refreshIntervalSeconds ?? 2
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                self?.refresh()
                self?.evaluateAutoCloseIfNeeded()
            }
        }
    }

    private func observeAppActivations() {
        guard activationTask == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        activationTask = Task { [weak self] in
            for await notification in center.notifications(named: NSWorkspace.didActivateApplicationNotification) {
                guard !Task.isCancelled else { break }
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    let key = app.bundleIdentifier ?? app.localizedName ?? "pid-\(app.processIdentifier)"
                    self?.lastActiveDates[key] = Date()
                }
            }
        }
    }

    public func refresh() {
        let newSnapshot = Self.readMemorySnapshot()
        snapshot = newSnapshot
        history.append(newSnapshot.usedFraction)
        if history.count > maxHistoryCount {
            history.removeFirst(history.count - maxHistoryCount)
        }

        if newSnapshot.pressure == .critical && previousPressure != .critical {
            let now = Date()
            if settings?.notifyOnCriticalPressure == true,
               now.timeIntervalSince(lastCriticalNotification) >= 300 {
                lastCriticalNotification = now
                NotificationManager.shared.notifyCriticalPressure()
            }
        }
        previousPressure = newSnapshot.pressure
    }

    public func refreshRunningApps() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
        let now = Date()

        var regularApps: [NSRunningApplication] = []
        var pidToAppID: [pid_t: String] = [:]
        var bundlePaths: [(path: String, appID: String)] = []

        for app in apps {
            guard app.processIdentifier != selfPID,
                  !app.isTerminated,
                  app.activationPolicy == .regular
            else {
                continue
            }
            let pid = app.processIdentifier
            let name = app.localizedName ?? app.bundleIdentifier ?? "PID \(pid)"
            let appID = app.bundleIdentifier ?? name
            regularApps.append(app)
            pidToAppID[pid] = appID
            if let bundlePath = app.bundleURL?.path {
                bundlePaths.append((bundlePath + "/", appID))
            }
        }

        let totalByAppID = Self.readProcessGroupFootprints(
            pidToAppID: pidToAppID,
            bundlePaths: bundlePaths
        )

        var byKey: [String: AppMemoryInfo] = [:]

        for app in regularApps {
            let pid = app.processIdentifier
            let name = app.localizedName ?? app.bundleIdentifier ?? "PID \(pid)"
            let appID = app.bundleIdentifier ?? name
            let bytes = totalByAppID[appID] ?? Self.readProcessFootprint(pid: pid)
            guard bytes > 0 else { continue }

            if app.isActive {
                lastActiveDates[appID] = now
            }
            let lastActive = lastActiveDates[appID] ?? now
            let category = AppCategory.detect(bundleURL: app.bundleURL, bundleID: app.bundleIdentifier)

            if let existing = byKey[appID] {
                let merged = AppMemoryInfo(
                    id: existing.id,
                    appID: appID,
                    pid: pid,
                    name: existing.name,
                    icon: existing.icon ?? app.icon,
                    memoryBytes: max(existing.memoryBytes, bytes),
                    isActive: existing.isActive || app.isActive,
                    lastActiveDate: max(existing.lastActiveDate, lastActive),
                    category: existing.category,
                    application: app.isActive ? app : existing.application
                )
                byKey[appID] = merged
            } else {
                byKey[appID] = AppMemoryInfo(
                    id: appID,
                    appID: appID,
                    pid: pid,
                    name: name,
                    icon: app.icon,
                    memoryBytes: bytes,
                    isActive: app.isActive,
                    lastActiveDate: lastActive,
                    category: category,
                    application: app
                )
            }
        }

        runningApps = byKey.values
            .sorted { $0.memoryBytes > $1.memoryBytes }
    }

    public func inactiveSuggestions(protectedIDs: Set<String>) -> [AppMemoryInfo] {
        let minimumBytes: UInt64 = 150 * 1_048_576
        return runningApps
            .filter { app in
                !app.isActive &&
                !SettingsStore.permanentlyProtectedAppIDs.contains(app.appID) &&
                !protectedIDs.contains(app.appID) &&
                app.application.activationPolicy == .regular &&
                app.memoryBytes >= minimumBytes
            }
            .sorted { lhs, rhs in
                if lhs.memoryBytes != rhs.memoryBytes {
                    return lhs.memoryBytes > rhs.memoryBytes
                }
                return lhs.lastActiveDate < rhs.lastActiveDate
            }
            .prefix(3)
            .map { $0 }
    }

    public func forceQuit(_ app: AppMemoryInfo) {
        if !app.application.forceTerminate() {
            Darwin.kill(app.pid, SIGKILL)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.refreshRunningApps()
            self?.refresh()
        }
    }

    public func closeGracefully(_ app: AppMemoryInfo) {
        if !app.application.terminate() {
            app.application.forceTerminate()
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.refreshRunningApps()
            self?.refresh()
        }
    }

    public func relaunch(_ event: AutoCloseEvent) {
        if let url = event.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: event.appID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.refreshRunningApps()
        }
    }

    public func openActivityMonitor() {
        let url = URL(filePath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func evaluateAutoCloseIfNeeded() {
        guard let settings, settings.autoCloseEnabled else { return }

        if settings.autoCloseOnlyOnBattery && !Self.isOnBatteryPower() { return }
        if settings.autoClosePauseInFullscreen && Self.isFrontmostAppInFullscreen() { return }
        if settings.autoClosePauseDuringCalls && isCallAppActive() { return }

        let now = Date()
        guard now.timeIntervalSince(lastAutoCloseAttempt) >= 15 else { return }

        let usedPercent = snapshot.usedFraction * 100
        guard usedPercent >= Double(settings.autoCloseRamThresholdPercent) else { return }

        refreshRunningApps()
        let requiredInactivity = TimeInterval(settings.autoCloseInactivityMinutes * 60)

        let candidate = runningApps.first { app in
            !app.isActive &&
            !settings.isProtected(app.appID) &&
            app.application.activationPolicy == .regular &&
            settings.autoCloseCategories.contains(app.category) &&
            now.timeIntervalSince(app.lastActiveDate) >= requiredInactivity
        }

        guard let target = candidate else { return }
        lastAutoCloseAttempt = now
        let freedText = target.memoryBytes.formattedMemoryCompact
        lastAutoClosedMessage = "\(target.name) (\(freedText))"

        let event = AutoCloseEvent(
            appName: target.name,
            appID: target.appID,
            bundleURL: target.application.bundleURL,
            freedBytes: target.memoryBytes,
            closedAt: now
        )
        autoCloseHistory.insert(event, at: 0)
        if autoCloseHistory.count > 10 {
            autoCloseHistory.removeLast(autoCloseHistory.count - 10)
        }

        if settings.notifyOnAutoClose {
            NotificationManager.shared.notifyAutoClose(appName: target.name, freedText: freedText)
        }

        closeGracefully(target)
    }

    private func isCallAppActive() -> Bool {
        let callBundleIDs: Set<String> = [
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.apple.FaceTime"
        ]
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return callBundleIDs.contains(id) && app.isActive
        }
    }

    private static func isFrontmostAppInFullscreen() -> Bool {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let screenFrame = NSScreen.main?.frame,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return false
        }

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == frontPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else {
                continue
            }
            if bounds.width >= screenFrame.width - 2 && bounds.height >= screenFrame.height - 2 {
                return true
            }
        }
        return false
    }

    private nonisolated static func isOnBatteryPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String?
        else {
            return false
        }
        return type == kIOPSBatteryPowerValue
    }

    private nonisolated static func readProcessGroupFootprints(
        pidToAppID: [pid_t: String],
        bundlePaths: [(path: String, appID: String)]
    ) -> [String: UInt64] {
        typealias ResponsibilityFn = @convention(c) (pid_t) -> pid_t
        let respFn: ResponsibilityFn? = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2),
            "responsibility_get_pid_responsible_for_pid"
        ).map { unsafeBitCast($0, to: ResponsibilityFn.self) }

        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [:] }

        var pids = [pid_t](repeating: 0, count: Int(estimated) * 2)
        let bytesWritten = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        let count = Int(bytesWritten) / MemoryLayout<pid_t>.stride
        guard count > 0 else { return [:] }

        var parentOf: [pid_t: pid_t] = [:]
        var footprintOf: [pid_t: UInt64] = [:]

        for index in 0..<count {
            let pid = pids[index]
            guard pid > 0 else { continue }

            let footprint = readProcessFootprint(pid: pid)
            guard footprint > 0 else { continue }
            footprintOf[pid] = footprint

            var bsdInfo = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize {
                parentOf[pid] = pid_t(bsdInfo.pbi_ppid)
            }
        }

        var totals: [String: UInt64] = [:]
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)

        for (pid, footprint) in footprintOf {
            var resolvedAppID: String?

            if let direct = pidToAppID[pid] {
                resolvedAppID = direct
            } else if let respPID = respFn?(pid), respPID > 0, let respApp = pidToAppID[respPID] {
                resolvedAppID = respApp
            }

            if resolvedAppID == nil {
                var current = parentOf[pid] ?? 0
                var depth = 0
                while current > 1 && depth < 12 {
                    if let parentApp = pidToAppID[current] {
                        resolvedAppID = parentApp
                        break
                    }
                    if let respPID = respFn?(current), respPID > 0, let respApp = pidToAppID[respPID] {
                        resolvedAppID = respApp
                        break
                    }
                    current = parentOf[current] ?? 0
                    depth += 1
                }
            }

            if resolvedAppID == nil && !bundlePaths.isEmpty {
                let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
                if pathLen > 0,
                   let execPath = pathBuffer.withUnsafeBufferPointer({ buf -> String? in
                       guard let base = buf.baseAddress else { return nil }
                       return String(cString: base)
                   }) {
                    for entry in bundlePaths where execPath.hasPrefix(entry.path) {
                        resolvedAppID = entry.appID
                        break
                    }
                }
            }

            if let appID = resolvedAppID {
                totals[appID, default: 0] += footprint
            }
        }

        return totals
    }

    private nonisolated static func readProcessFootprint(pid: pid_t) -> UInt64 {
        var rusage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &rusage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
            }
        }
        guard result == 0 else { return 0 }
        return rusage.ri_phys_footprint
    }

    private nonisolated static func readMemorySnapshot() -> MemorySnapshot {
        let total = ProcessInfo.processInfo.physicalMemory
        let host = mach_host_self()

        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else {
            return .empty
        }

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return .empty
        }

        let page = UInt64(pageSize)
        let strictlyFreeBytes = UInt64(vmStats.free_count) * page
        let internalBytes = UInt64(vmStats.internal_page_count) * page
        let purgeableBytes = UInt64(vmStats.purgeable_count) * page
        let wiredBytes = UInt64(vmStats.wire_count) * page
        let compressedBytes = UInt64(vmStats.compressor_page_count) * page
        let cachedBytes = UInt64(vmStats.external_page_count) * page + purgeableBytes

        let appBytes = internalBytes > purgeableBytes ? internalBytes - purgeableBytes : 0
        let usedBytes = min(total, appBytes + wiredBytes + compressedBytes)
        let availableBytes = total > usedBytes ? total - usedBytes : 0
        let swap = readSwapUsage()

        return MemorySnapshot(
            totalBytes: total,
            availableBytes: availableBytes,
            strictlyFreeBytes: strictlyFreeBytes,
            usedBytes: usedBytes,
            appBytes: appBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedBytes: cachedBytes,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            pressure: readPressure()
        )
    }

    private nonisolated static func readSwapUsage() -> (used: UInt64, total: UInt64) {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let status = sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        guard status == 0 else { return (0, 0) }
        return (swap.xsu_used, swap.xsu_total)
    }

    private nonisolated static func readPressure() -> MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        guard status == 0 else { return .normal }
        switch level {
        case 2: return .warning
        case 4: return .critical
        default: return .normal
        }
    }
}

public extension UInt64 {
    func formattedGigabytes(decimals: Int = 1) -> String {
        let gb = Double(self) / 1_073_741_824.0
        return "\(gb.formatted(.number.precision(.fractionLength(decimals)))) Go"
    }

    var formattedShortGigabytes: String {
        formattedGigabytes(decimals: 1)
    }

    var formattedMemoryCompact: String {
        if self >= 1_073_741_824 {
            return formattedGigabytes(decimals: 1)
        }
        let mb = Double(self) / 1_048_576.0
        return "\(Int(mb.rounded())) Mo"
    }
}

public extension Date {
    func formattedLastUsed(isActive: Bool) -> String {
        let targetDate = isActive ? Date() : self
        let calendar = Calendar.current
        if calendar.isDateInToday(targetDate) {
            return targetDate.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(targetDate) {
            return "Hier \(targetDate.formatted(date: .omitted, time: .shortened))"
        }

        let startOfSelf = calendar.startOfDay(for: targetDate)
        let startOfToday = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: startOfSelf, to: startOfToday).day ?? 0
        if days > 1 && days < 7 {
            return "\(days) j"
        }
        return targetDate.formatted(.dateTime.day().month(.abbreviated))
    }
}
