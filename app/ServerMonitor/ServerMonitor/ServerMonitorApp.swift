import AppKit
import Combine
import SwiftUI

@main
@MainActor
struct ServerMonitorApp: App {
    @StateObject private var monitor: ServiceMonitor
    @StateObject private var darkmesh: DarkmeshStatusMonitor
    @StateObject private var worker: WorkerStatusMonitor
    @StateObject private var lidSleep: LidSleepMonitor
    @StateObject private var transfers: TransfersMonitor
    @StateObject private var transferActions: TransferActionsModel
    @StateObject private var protection: ProtectionMonitor
    @StateObject private var versions: VersionMonitor
    @StateObject private var backgroundService: BackgroundServiceManager

    // AppKit owns the status item and popover. SwiftUI's MenuBarExtra window can
    // silently stop presenting after macOS privacy or service-state changes.
    private let statusBarController: StatusBarController

    init() {
        let monitor = ServiceMonitor()
        let darkmesh = DarkmeshStatusMonitor()
        let worker = WorkerStatusMonitor()
        let lidSleep = LidSleepMonitor()
        let transfers = TransfersMonitor()
        let transferActions = TransferActionsModel()
        let protection = ProtectionMonitor()
        let versions = VersionMonitor()
        let autoRegisterBackgroundServices =
            ProcessInfo.processInfo.environment["SERVER_MONITOR_DISABLE_AUTO_REGISTER"] != "1"
        let backgroundService = BackgroundServiceManager(autoRegister: autoRegisterBackgroundServices)

        _monitor = StateObject(wrappedValue: monitor)
        _darkmesh = StateObject(wrappedValue: darkmesh)
        _worker = StateObject(wrappedValue: worker)
        _lidSleep = StateObject(wrappedValue: lidSleep)
        _transfers = StateObject(wrappedValue: transfers)
        _transferActions = StateObject(wrappedValue: transferActions)
        _protection = StateObject(wrappedValue: protection)
        _versions = StateObject(wrappedValue: versions)
        _backgroundService = StateObject(wrappedValue: backgroundService)

        statusBarController = StatusBarController(
            monitor: monitor,
            darkmesh: darkmesh,
            worker: worker,
            lidSleep: lidSleep,
            transfers: transfers,
            transferActions: transferActions,
            protection: protection,
            versions: versions,
            backgroundService: backgroundService
        )
        AppResourceGuard.shared.start()
    }

    var body: some Scene {
        // The user-facing windows are owned by StatusBarController so opening
        // them never depends on a MenuBarExtra scene being presentable.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private struct StatusPopoverContent: View {
    @ObservedObject var monitor: ServiceMonitor
    @ObservedObject var darkmesh: DarkmeshStatusMonitor
    @ObservedObject var worker: WorkerStatusMonitor
    @ObservedObject var lidSleep: LidSleepMonitor
    @ObservedObject var transfers: TransfersMonitor
    @ObservedObject var transferActions: TransferActionsModel
    @ObservedObject var protection: ProtectionMonitor
    @ObservedObject var versions: VersionMonitor

    let openManager: () -> Void
    let openSettings: () -> Void
    let openNetwork: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DarkmeshStatusView(monitor: darkmesh, protection: protection)
            Divider()
            WorkerStatusView(monitor: worker)
            if lidSleep.isLaptop {
                Divider()
                LidSleepView(monitor: lidSleep)
            }
            Divider()
            TransfersView(monitor: transfers, actions: transferActions)
            HStack {
                Button(action: openNetwork) { Label("Network Status…", systemImage: "point.3.connected.trianglepath.dotted").font(.caption) }
                    .buttonStyle(.borderless)
                Spacer()
                Button(action: openManager) {
                    Label("Manager…", systemImage: "rectangle.split.2x1")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            Divider()
            MenuBarView(monitor: monitor)

            Divider()
            VersionsView(monitor: versions)

            Divider()

            HStack {
                Button(action: openSettings) {
                    Label("Manage Services", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 320)
    }
}

@MainActor
private final class StatusBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let monitor: ServiceMonitor
    private let darkmesh: DarkmeshStatusMonitor
    private let worker: WorkerStatusMonitor
    private let lidSleep: LidSleepMonitor
    private let transfers: TransfersMonitor
    private let transferActions: TransferActionsModel
    private let protection: ProtectionMonitor
    private let versions: VersionMonitor
    private let backgroundService: BackgroundServiceManager
    private var network: NetworkPostureMonitor?

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var managerWindow: NSWindow?
    private var networkWindow: NSWindow?

    init(
        monitor: ServiceMonitor,
        darkmesh: DarkmeshStatusMonitor,
        worker: WorkerStatusMonitor,
        lidSleep: LidSleepMonitor,
        transfers: TransfersMonitor,
        transferActions: TransferActionsModel,
        protection: ProtectionMonitor,
        versions: VersionMonitor,
        backgroundService: BackgroundServiceManager
    ) {
        self.monitor = monitor
        self.darkmesh = darkmesh
        self.worker = worker
        self.lidSleep = lidSleep
        self.transfers = transfers
        self.transferActions = transferActions
        self.protection = protection
        self.versions = versions
        self.backgroundService = backgroundService
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        observeStatusChanges()

        // SwiftUI constructs its App value before AppKit has completed startup
        // on some macOS releases. Creating an NSStatusItem synchronously from
        // that initializer can trap inside NSStatusBar. The first main-run-loop
        // turn happens after application startup has unwound.
        DispatchQueue.main.async { [weak self] in
            self?.installStatusItem()
        }
    }

    deinit {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Server Monitor")
            button.toolTip = "Server Monitor"
        }

        updateStatusItem()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            loadPopoverContent()
            let fitting = popover.contentViewController?.view.fittingSize ?? NSSize(width: 320, height: 640)
            popover.contentSize = NSSize(width: 320, height: min(max(fitting.height, 420), 760))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        // Keep the always-on status item cheap. Releasing the off-screen SwiftUI
        // tree prevents every monitor tick from laying out a hidden full panel.
        popover.contentViewController = nil
    }

    private func loadPopoverContent() {
        guard popover.contentViewController == nil else { return }
        let content = StatusPopoverContent(
            monitor: monitor,
            darkmesh: darkmesh,
            worker: worker,
            lidSleep: lidSleep,
            transfers: transfers,
            transferActions: transferActions,
            protection: protection,
            versions: versions,
            openManager: { [weak self] in self?.showManager() },
            openSettings: { [weak self] in self?.showSettings() },
            openNetwork: { [weak self] in self?.showNetworkStatus() }
        )
        popover.contentViewController = NSHostingController(rootView: content)
    }

    private func observeStatusChanges() {
        let publishers: [AnyPublisher<Void, Never>] = [
            monitor.objectWillChange.eraseToAnyPublisher(),
            darkmesh.objectWillChange.eraseToAnyPublisher(),
            transfers.objectWillChange.eraseToAnyPublisher(),
            transferActions.objectWillChange.eraseToAnyPublisher(),
            protection.objectWillChange.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(publishers)
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = NSImage(systemSymbolName: monitor.overallStatus.icon, accessibilityDescription: "Server Monitor")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = statusTint
    }

    /// Combined menu-bar tint. ExpressVPN and its public-client gate are useful
    /// protection signals, but do not authorize private LAN/Tailscale transfers.
    private var statusTint: NSColor {
        if darkmesh.status?.verdict == "NO-GO" { return .systemRed }
        if darkmesh.status?.servicesHealthy == false { return .systemRed }
        if monitor.overallStatus == .stopped { return .systemRed }
        if darkmesh.status?.verdict == "DEGRADED" { return .systemYellow }
        if darkmesh.status?.vpnTransferClientBlocked == true { return .systemYellow }
        if protection.atRisk || transfers.needsAttention || transferActions.needsAttention {
            return .systemYellow
        }
        if darkmesh.status?.verdict == "GO" {
            switch monitor.overallStatus {
            case .running: return .systemGreen
            case .stopped: return .systemRed
            case .checking: return .systemOrange
            case .unknown: return .systemGray
            }
        }
        return .systemYellow
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(
                rootView: SettingsView(monitor: monitor, backgroundService: backgroundService)
            )
            let window = NSWindow(contentViewController: controller)
            window.title = "Settings"
            window.setContentSize(NSSize(width: 500, height: 400))
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        present(settingsWindow)
    }

    private func showManager() {
        popover.performClose(nil)
        if managerWindow == nil {
            let controller = NSHostingController(rootView: TransferHistoryWindow(actions: transferActions))
            let window = NSWindow(contentViewController: controller)
            window.title = "Manager"
            window.setContentSize(NSSize(width: 920, height: 600))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            managerWindow = window
        }
        present(managerWindow)
    }

    private func showNetworkStatus() {
        popover.performClose(nil)
        if networkWindow == nil {
            let monitor = NetworkPostureMonitor()
            monitor.start()
            let controller = NSHostingController(rootView: NetworkStatusWindow(monitor: monitor))
            let window = NSWindow(contentViewController: controller)
            window.title = "Network Status"
            window.setContentSize(NSSize(width: 760, height: 600))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            networkWindow = window
            network = monitor
        }
        present(networkWindow)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
        } else if window === managerWindow {
            managerWindow = nil
        } else if window === networkWindow {
            network?.stop()
            network = nil
            networkWindow = nil
        }
    }
}
