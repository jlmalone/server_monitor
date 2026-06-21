import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Manager (dual-pane cross-machine file browser + transfer)
//
// The "Files" tab: two Finder-style panes, each browsing a chosen machine's
// directories. Drag a row from one pane onto a folder (or the path bar) of the
// other to copy or move it into that exact directory. "Chicklets" are pinned
// root shortcuts shown identically above both panes; right-click a folder to
// make one. All behaviour is config-driven via TransferActionsModel — inert when
// no "manager" block is configured.

// MARK: Drag payload

struct TransferDragPayload {
    let machine: String
    let path: String
    let name: String
    let isDir: Bool
    let size: Int64?
}

private let kDelim = "\u{1}"

private func encodePayload(_ p: TransferDragPayload) -> String {
    [p.machine, p.path, p.name, p.isDir ? "1" : "0", p.size.map(String.init) ?? ""]
        .joined(separator: kDelim)
}

private func decodePayload(_ s: String) -> TransferDragPayload? {
    let f = s.components(separatedBy: kDelim)
    guard f.count >= 4, !f[0].isEmpty, !f[1].isEmpty else { return nil }
    return TransferDragPayload(machine: f[0], path: f[1], name: f[2], isDir: f[3] == "1",
                               size: f.count > 4 ? Int64(f[4]) : nil)
}

/// A pending drop awaiting Copy / Move / Cancel.
private struct PendingTransfer: Identifiable {
    let id = UUID()
    let payload: TransferDragPayload
    let destMachine: String
    let destPath: String
}

// MARK: Pane model

@MainActor
final class PaneModel: ObservableObject {
    @Published var machine: ManagerMachine?
    @Published var path: String
    @Published private(set) var entries: [DirEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    let machines: [ManagerMachine]
    private var loadToken = 0

    init(machine: ManagerMachine?, machines: [ManagerMachine]) {
        self.machine = machine
        self.machines = machines
        self.path = machine?.startPath ?? "/"
    }

    func reload() {
        guard let machine else { return }
        loading = true; error = nil
        loadToken += 1
        let token = loadToken
        let m = machine, p = path
        Task {
            do {
                let result = try await DirectoryLister.list(machine: m, path: p)
                guard token == loadToken else { return }
                entries = result; loading = false
            } catch {
                guard token == loadToken else { return }
                self.error = error.localizedDescription; entries = []; loading = false
            }
        }
    }

    func enter(_ entry: DirEntry) {
        guard entry.isDir else { return }
        path = entry.path; reload()
    }

    func up() {
        let parent = (path as NSString).deletingLastPathComponent
        path = parent.isEmpty ? "/" : parent
        reload()
    }

    func switchMachine(_ m: ManagerMachine) {
        machine = m; path = m.startPath; reload()
    }

    func jump(machine m: ManagerMachine, path p: String) {
        machine = m; path = p; reload()
    }
}

// MARK: Manager view (two panes + shared chicklets)

struct ManagerView: View {
    @ObservedObject var actions: TransferActionsModel
    @StateObject private var chicklets: ChickletStore
    @StateObject private var left: PaneModel
    @StateObject private var right: PaneModel
    @State private var pending: PendingTransfer?

    init(actions: TransferActionsModel) {
        _actions = ObservedObject(wrappedValue: actions)
        _chicklets = StateObject(wrappedValue: ChickletStore(path: actions.chickletsPath))
        let ms = actions.machines
        _left = StateObject(wrappedValue: PaneModel(machine: ms.first, machines: ms))
        _right = StateObject(wrappedValue: PaneModel(machine: ms.count > 1 ? ms[1] : ms.first, machines: ms))
    }

    var body: some View {
        Group {
            if actions.configured {
                HSplitView {
                    FilePaneView(pane: left, chicklets: chicklets, actions: actions,
                                 onDropInto: requestTransfer)
                        .frame(minWidth: 320)
                    FilePaneView(pane: right, chicklets: chicklets, actions: actions,
                                 onDropInto: requestTransfer)
                        .frame(minWidth: 320)
                }
            } else {
                placeholder
            }
        }
        .sheet(item: $pending) { p in
            TransferConfirmSheet(actions: actions, payload: p.payload,
                                 destMachine: p.destMachine, destPath: p.destPath) { pending = nil }
        }
    }

    /// Bubble a drop up into a Copy/Move confirmation, unless it would be a no-op.
    private func requestTransfer(_ payload: TransferDragPayload, _ destMachine: String, _ destPath: String) {
        let dst = destPath.hasSuffix("/") ? String(destPath.dropLast()) : destPath
        if payload.machine == destMachine, (payload.path as NSString).deletingLastPathComponent == dst { return }
        if payload.machine == destMachine, payload.path == dst { return }
        pending = PendingTransfer(payload: payload, destMachine: destMachine, destPath: dst)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 40)).foregroundColor(.secondary).accessibilityHidden(true)
            Text("Manager not configured").font(.headline)
            Text("Add a \u{201C}manager\u{201D} block (machines + transferCommand) to ~/.config/server-monitor/transfers.json — see config/transfers.example.json.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}

// MARK: One pane

struct FilePaneView: View {
    @ObservedObject var pane: PaneModel
    @ObservedObject var chicklets: ChickletStore
    @ObservedObject var actions: TransferActionsModel
    let onDropInto: (TransferDragPayload, String, String) -> Void

    @State private var dropTargetPath: String?

    var body: some View {
        VStack(spacing: 0) {
            machineBar
            Divider()
            chickletBar
            Divider()
            pathBar
            Divider()
            content
        }
        .onAppear { if pane.entries.isEmpty && pane.error == nil && !pane.loading { pane.reload() } }
    }

    // MARK: bars

    private var machineBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(pane.machines) { m in
                    Button { pane.switchMachine(m) } label: {
                        Label(m.label, systemImage: m.isLocal ? "laptopcomputer" : "server.rack")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: (pane.machine?.isLocal ?? false) ? "laptopcomputer" : "server.rack")
                    Text(pane.machine?.label ?? "—").fontWeight(.semibold)
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Machine for this pane: \(pane.machine?.label ?? "none"). Click to switch.")
            Spacer()
            Button { pane.reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Reload this directory")
                .accessibilityLabel("Reload")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var chickletBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if chicklets.items.isEmpty {
                    Text("no shortcuts yet — right-click a folder to pin it")
                        .font(.caption2).foregroundColor(.secondary)
                }
                ForEach(chicklets.items) { c in
                    Button { jump(c) } label: {
                        Label(c.label, systemImage: "bookmark.fill").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.14)))
                    .help("\(c.machine):\(c.path)")
                    .contextMenu { Button(role: .destructive) { chicklets.remove(c) } label: { Label("Remove shortcut", systemImage: "trash") } }
                    .accessibilityLabel("Shortcut \(c.label), \(c.machine) \(c.path). Opens this pane there.")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .frame(height: 30)
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Button { pane.up() } label: { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless).help("Up one directory").accessibilityLabel("Up one directory")
            Image(systemName: "folder").foregroundColor(.secondary).accessibilityHidden(true)
            Text(pane.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { pinCurrent() } label: { Image(systemName: "bookmark") }
                .buttonStyle(.borderless).help("Pin this folder as a shortcut")
                .accessibilityLabel("Pin this folder as a shortcut")
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(currentDirHighlighted ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, into: pane.path)
        } isTargeted: { dropTargetPath = $0 ? pane.path : (dropTargetPath == pane.path ? nil : dropTargetPath) }
        .help("Drop here to transfer into this folder")
    }

    private var content: some View {
        ZStack {
            if let error = pane.error {
                paneMessage(icon: "exclamationmark.triangle", title: error,
                            detail: "Check the machine is reachable, then Reload.")
            } else if pane.entries.isEmpty && !pane.loading {
                paneMessage(icon: "tray", title: "Empty folder", detail: nil)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(pane.entries) { entry in
                            FileRowView(entry: entry, machine: pane.machine?.label ?? "",
                                        isDropTarget: dropTargetPath == entry.path,
                                        onOpen: { pane.enter(entry) },
                                        onDrop: { items in handleDrop(items, into: entry.path) },
                                        onHover: { hovering in
                                            dropTargetPath = hovering ? entry.path
                                                : (dropTargetPath == entry.path ? nil : dropTargetPath)
                                        },
                                        onMakeChicklet: { makeChicklet(entry) })
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
            if pane.loading {
                ProgressView().controlSize(.small)
                    .padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paneMessage(icon: String, title: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 30)).foregroundColor(.secondary).accessibilityHidden(true)
            Text(title).font(.callout).multilineTextAlignment(.center)
            if let detail { Text(detail).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center) }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentDirHighlighted: Bool { dropTargetPath == pane.path }

    // MARK: actions

    private func handleDrop(_ items: [String], into destPath: String) -> Bool {
        guard let payload = items.first.flatMap(decodePayload), let m = pane.machine else { return false }
        onDropInto(payload, m.label, destPath)
        return true
    }

    private func jump(_ c: Chicklet) {
        guard let m = pane.machines.first(where: { $0.label == c.machine }) else { return }
        pane.jump(machine: m, path: c.path)
    }

    private func pinCurrent() {
        guard let m = pane.machine else { return }
        let name = (pane.path as NSString).lastPathComponent
        chicklets.add(label: name.isEmpty ? m.label : name, machine: m.label, path: pane.path)
    }

    private func makeChicklet(_ entry: DirEntry) {
        guard let m = pane.machine else { return }
        chicklets.add(label: entry.name, machine: m.label, path: entry.path)
    }
}

// MARK: One row

struct FileRowView: View {
    let entry: DirEntry
    let machine: String
    let isDropTarget: Bool
    let onOpen: () -> Void
    let onDrop: ([String]) -> Bool
    let onHover: (Bool) -> Void
    let onMakeChicklet: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDir ? "folder.fill" : "doc")
                .foregroundColor(entry.isDir ? .accentColor : .secondary)
                .frame(width: 18).accessibilityHidden(true)
            Text(entry.name).font(.callout).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let s = entry.size, !entry.isDir {
                Text(ByteCountFormatter.string(fromByteCount: s, countStyle: .file))
                    .font(.caption2).foregroundColor(.secondary)
            } else if entry.isDir {
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(isDropTarget ? Color.accentColor.opacity(0.22) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if entry.isDir { onOpen() } }
        .draggable(encodePayload(TransferDragPayload(
            machine: machine, path: entry.path, name: entry.name, isDir: entry.isDir, size: entry.size)))
        .modifier(FolderDrop(enabled: entry.isDir, onDrop: onDrop, onHover: onHover))
        .contextMenu {
            if entry.isDir {
                Button { onOpen() } label: { Label("Open", systemImage: "arrow.right.circle") }
                Button { onMakeChicklet() } label: { Label("Make chicklet", systemImage: "bookmark") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowLabel)
    }

    private var rowLabel: String {
        var s = entry.isDir ? "Folder \(entry.name)" : "File \(entry.name)"
        if let sz = entry.size, !entry.isDir { s += ", \(ByteCountFormatter.string(fromByteCount: sz, countStyle: .file))" }
        s += entry.isDir ? ". Double-click to open, drag to transfer, or drop here." : ". Drag to transfer."
        return s
    }
}

/// Apply a drop destination only to folder rows.
private struct FolderDrop: ViewModifier {
    let enabled: Bool
    let onDrop: ([String]) -> Bool
    let onHover: (Bool) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: String.self) { items, _ in onDrop(items) } isTargeted: { onHover($0) }
        } else {
            content
        }
    }
}

// MARK: - Confirm sheet (Copy / Move / Cancel)

struct TransferConfirmSheet: View {
    @ObservedObject var actions: TransferActionsModel
    let payload: TransferDragPayload
    let destMachine: String
    let destPath: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Transfer this \(payload.isDir ? "folder" : "file")?").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Label(payload.name, systemImage: payload.isDir ? "folder.fill" : "doc")
                    .font(.title3.bold()).lineLimit(2).truncationMode(.middle)
                routeRow("From", "\(payload.machine):\((payload.path as NSString).deletingLastPathComponent)")
                routeRow("Into", "\(destMachine):\(destPath)")
                if let s = payload.size, !payload.isDir {
                    Text(ByteCountFormatter.string(fromByteCount: s, countStyle: .file)).font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if actions.supports(.move) {
                    Button { launch(.move) } label: { Label("Move", systemImage: "arrow.right.to.line") }
                        .help("Copy to \(destMachine), then delete the original after it verifies")
                }
                Button { launch(.copy) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .keyboardShortcut(.defaultAction)
                    .help("Copy to \(destMachine), leaving the original in place")
            }
        }
        .padding(18).frame(width: 480)
    }

    private func routeRow(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(k).font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
            Text(v).font(.caption.monospaced()).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.head)
        }
    }

    private func launch(_ mode: TransferMode) {
        let dst = destPath.hasSuffix("/") ? destPath : destPath + "/"
        actions.startTransfer(name: payload.name, srcMachine: payload.machine, srcPath: payload.path,
                              dstMachine: destMachine, dstPath: dst, mode: mode)
        dismiss()
    }
}

// MARK: - Logs tab (live-tail each operation)

struct TransferLogsView: View {
    @ObservedObject var actions: TransferActionsModel
    @State private var selection: String?

    private var selectedOp: TransferOperation? { actions.operations.first { $0.id == selection } }

    private var hasFinished: Bool {
        actions.operations.contains { $0.state == .succeeded || $0.state == .failed || $0.state == .stopped }
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasFinished {
                HStack {
                    Spacer()
                    Button { actions.clearFinished() } label: { Label("Clear finished", systemImage: "trash") }
                        .buttonStyle(.borderless).font(.caption)
                        .help("Remove succeeded/failed/stopped transfers from this list (logs stay on disk)")
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                Divider()
            }
            HSplitView {
                opList.frame(minWidth: 240, idealWidth: 280)
                if let op = selectedOp {
                    LogTailView(op: op, actions: actions)
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36)).foregroundColor(.secondary).accessibilityHidden(true)
                        Text(actions.operations.isEmpty ? "No transfers launched yet" : "Select a transfer to view its log")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var opList: some View {
        Group {
            if actions.operations.isEmpty {
                VStack(spacing: 6) {
                    Text("No transfers launched yet").font(.headline)
                    Text("Drag a file from one pane onto a folder in the other to start one.")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 240)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                List(actions.operations, selection: $selection) { op in
                    HStack(spacing: 8) {
                        TransferStateDot(state: op.state)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(op.title).font(.callout).lineLimit(1).truncationMode(.middle)
                            Text("\(op.mode.rawValue) · \(op.routeText)")
                                .font(.caption2).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                            if op.state == .retrying, let at = op.nextRetryAt {
                                HStack(spacing: 3) {
                                    Text("retry in"); Text(at, style: .timer).monospacedDigit()
                                    Text("· attempt \(op.attempt)/\(op.maxAttempts)")
                                }
                                .font(.caption2).foregroundColor(.orange)
                            }
                        }
                    }
                    .tag(op.id)
                    .accessibilityLabel("\(op.title), \(op.mode.rawValue) \(op.routeText), \(stateLabel(op.state))")
                }
            }
        }
    }

    private func stateLabel(_ s: TransferState) -> String {
        switch s {
        case .running:   return "running"
        case .retrying:  return "retrying after a failure"
        case .succeeded: return "succeeded"
        case .failed:    return "failed"
        case .stopped:   return "stopped"
        }
    }
}

/// Status dot + (for VoiceOver) text — never colour alone.
struct TransferStateDot: View {
    let state: TransferState
    var body: some View {
        Group {
            switch state {
            case .running:   ProgressView().controlSize(.small)
            case .retrying:  Image(systemName: "clock.arrow.circlepath").foregroundColor(.orange)
            case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .failed:    Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
            case .stopped:   Image(systemName: "minus.circle.fill").foregroundColor(.secondary)
            }
        }
        .frame(width: 16)
    }
}

/// Polls the operation's log file so the view follows a running transfer live,
/// and reads it once more when the op finishes.
@MainActor
final class LogTailer: ObservableObject {
    @Published var text = ""
    private var timer: Timer?

    func start(path: String, live: Bool) {
        read(path)
        timer?.invalidate()
        guard live else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.read(path) }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }

    private func read(_ path: String) {
        let t = TransferActionsModel.tail(path)
        if t != text { text = t }
    }
}

struct LogTailView: View {
    let op: TransferOperation
    @ObservedObject var actions: TransferActionsModel
    @StateObject private var tailer = LogTailer()

    private var isLive: Bool { op.state == .running || op.state == .retrying }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TransferStateDot(state: op.state)
                VStack(alignment: .leading, spacing: 1) {
                    Text(op.title).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text(statusLine).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                controls
                Button { NSWorkspace.shared.selectFile(op.logPath, inFileViewerRootedAtPath: "") } label: {
                    Label("Reveal Log", systemImage: "folder")
                }
                .buttonStyle(.borderless).font(.caption).help(op.logPath)
            }
            .padding(8)
            Divider()
            ScrollView {
                Text(tailer.text.isEmpty ? "…" : tailer.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .onAppear { tailer.start(path: op.logPath, live: isLive) }
        .onChange(of: op.state) { _ in tailer.start(path: op.logPath, live: isLive) }
        .onDisappear { tailer.stop() }
        .accessibilityLabel("Log for \(op.title), \(statusLine)")
    }

    private var statusLine: String {
        switch op.state {
        case .running:   return "attempt \(op.attempt)/\(op.maxAttempts) · running"
        case .retrying:  return "attempt \(op.attempt)/\(op.maxAttempts) failed · waiting to retry"
        case .succeeded: return "completed on attempt \(op.attempt)"
        case .failed:    return "failed after \(op.attempt) attempts"
        case .stopped:   return "stopped after \(op.attempt) attempts"
        }
    }

    @ViewBuilder private var controls: some View {
        switch op.state {
        case .retrying:
            if let at = op.nextRetryAt {
                HStack(spacing: 3) { Text("retry in"); Text(at, style: .timer).monospacedDigit() }
                    .font(.caption2).foregroundColor(.orange)
            }
            Button { actions.retryNow(op.id) } label: { Label("Retry Now", systemImage: "bolt.fill") }
                .buttonStyle(.borderless).font(.caption).accessibilityLabel("Retry now, skipping the backoff wait")
            Button { actions.stop(op.id) } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.borderless).font(.caption).foregroundColor(.red).accessibilityLabel("Stop retrying")
        case .failed, .stopped:
            Button { actions.retry(op.id) } label: { Label("Retry", systemImage: "arrow.clockwise") }
                .buttonStyle(.borderless).font(.caption).accessibilityLabel("Retry from the first attempt")
        default:
            EmptyView()
        }
    }
}
