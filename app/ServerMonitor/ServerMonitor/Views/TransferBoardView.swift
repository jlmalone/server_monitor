import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Transfer board (drag a title onto a machine to copy/move it)
//
// Lives as two extra tabs in the Transfer History window. The "Transfer" tab
// lists distinct titles seen in history; drag one onto a machine chip to copy or
// move it there. The "Logs" tab live-tails the output of each launched
// operation. All behaviour is config-driven via TransferActionsModel — inert
// when no "transfer" block is configured.

/// SOH-delimited drag payload (title + current machine + counts). SOH (\u{1})
/// can't appear in a filename/title, so it's a safe field separator.
private let kDragDelim = "\u{1}"

private func encodeDrag(_ item: TransferItem) -> String {
    [item.title, item.src, item.files.map(String.init) ?? "", item.bytes.map(String.init) ?? ""]
        .joined(separator: kDragDelim)
}

private func decodeDrag(_ s: String) -> TransferItem? {
    let f = s.components(separatedBy: kDragDelim)
    guard f.count >= 2, !f[0].isEmpty else { return nil }
    return TransferItem(title: f[0], src: f[1],
                        files: f.count > 2 ? Int(f[2]) : nil,
                        bytes: f.count > 3 ? Int64(f[3]) : nil)
}

/// Strip the operation prefix the transfer tool records on each item (e.g. "send:Foo" → "Foo").
private func stripOp(_ s: String) -> String {
    for p in ["send:", "move:", "copy:", "pull:", "push:", "sync:"] where s.hasPrefix(p) {
        return String(s.dropFirst(p.count))
    }
    return s
}

struct TransferItem: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let src: String          // machine the title currently lives on (drag source)
    let files: Int?
    let bytes: Int64?
}

/// A pending drop awaiting Copy/Move/Cancel.
private struct PendingDrop: Identifiable {
    let id = UUID()
    let item: TransferItem
    let dst: String
}

struct TransferBoardView: View {
    @ObservedObject var actions: TransferActionsModel
    @StateObject private var loader = TransferHistoryLoader()
    @State private var search = ""
    @State private var pending: PendingDrop?
    @State private var dropTarget: String?

    private var items: [TransferItem] {
        var seen = Set<String>(); var out: [TransferItem] = []
        for r in loader.records {
            let title = stripOp((r.repositories?.first).map { $0 } ?? "")
            guard !title.isEmpty, !seen.contains(title) else { continue }
            seen.insert(title)
            out.append(TransferItem(title: title,
                                    src: r.targetMachine ?? r.sourceMachine ?? "",
                                    files: r.filesTransferred, bytes: r.bytesTransferred))
            if out.count >= 400 { break }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? out : out.filter { $0.title.lowercased().contains(q) }
    }

    private var machines: [String] {
        var s = Set(actions.configuredMachines)
        for r in loader.records {
            if let m = r.sourceMachine { s.insert(m) }
            if let m = r.targetMachine { s.insert(m) }
        }
        return s.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            if !actions.configured {
                placeholder
            } else {
                machineStrip
                Divider()
                itemList
            }
        }
        .onAppear { if loader.records.isEmpty { loader.reload() } }
        .sheet(item: $pending) { drop in
            TransferConfirmSheet(actions: actions, item: drop.item, dst: drop.dst) { pending = nil }
        }
    }

    // MARK: pieces

    private var machineStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Drag a title onto a machine to transfer it there")
                .font(.caption).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(machines, id: \.self) { machine in
                        machineChip(machine)
                    }
                    if machines.isEmpty {
                        Text("no machines found in history").font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
    }

    private func machineChip(_ machine: String) -> some View {
        let active = dropTarget == machine
        return Label(machine, systemImage: "desktopcomputer")
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill((active ? Color.accentColor : Color.secondary).opacity(active ? 0.30 : 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(active ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { payloads, _ in
                guard let item = payloads.first.flatMap(decodeDrag), item.src != machine else { return false }
                pending = PendingDrop(item: item, dst: machine)
                return true
            } isTargeted: { dropTarget = $0 ? machine : (dropTarget == machine ? nil : dropTarget) }
            .accessibilityLabel("Transfer destination \(machine). Drop a title here to copy or move it to \(machine).")
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).accessibilityHidden(true)
                TextField("Search titles", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search titles to transfer")
                Text("\(items.count)").font(.caption).foregroundColor(.secondary)
            }
            .padding(10)
            Divider()
            if items.isEmpty {
                Spacer()
                Text(loader.loading ? "loading…" : "no titles in history yet")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(items) { item in
                    TransferItemRow(item: item)
                        .draggable(encodeDrag(item))
                }
                .listStyle(.inset)
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 40)).foregroundColor(.secondary).accessibilityHidden(true)
            Text("Drag-and-drop transfers not configured").font(.headline)
            Text("Add a \u{201C}transfer\u{201D} block (machines + copyCommand) to ~/.config/server-monitor/transfers.json — see config/transfers.example.json.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}

/// One draggable title row.
struct TransferItemRow: View {
    let item: TransferItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc").foregroundColor(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.callout).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "line.3.horizontal").foregroundColor(.secondary.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .help("Drag onto a machine to transfer")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(subtitle). Drag onto a machine to transfer.")
    }

    private var subtitle: String {
        var parts: [String] = []
        if !item.src.isEmpty { parts.append("on \(item.src)") }
        if let s = TransferFormat.summary(files: item.files, bytes: item.bytes) { parts.append(s) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Confirm sheet (Copy / Move / Cancel)

struct TransferConfirmSheet: View {
    @ObservedObject var actions: TransferActionsModel
    let item: TransferItem
    let dst: String
    let dismiss: () -> Void

    @State private var exact: TransferDescription?

    private var sameMachine: Bool { item.src == dst }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Transfer this title?").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.title3.bold()).lineLimit(2).truncationMode(.middle)
                Label("\(item.src.isEmpty ? "?" : item.src)  →  \(dst)", systemImage: "arrow.right")
                    .font(.callout).foregroundColor(.secondary)
                Text(countLine).font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))

            if sameMachine {
                Label("This title is already on \(dst).", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.orange)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if actions.supports(.move) {
                    Button {
                        actions.start(title: item.title, src: item.src, dst: dst, mode: .move); dismiss()
                    } label: { Label("Move", systemImage: "arrow.right.to.line") }
                        .disabled(sameMachine)
                        .help("Copy to \(dst), then delete the original on \(item.src)")
                }
                Button {
                    actions.start(title: item.title, src: item.src, dst: dst, mode: .copy); dismiss()
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sameMachine)
                    .help("Copy to \(dst), leaving the original in place")
            }
        }
        .padding(18)
        .frame(width: 420)
        .task {
            exact = await actions.describe(title: item.title, src: item.src)
        }
    }

    /// Prefer an exact files/folders breakdown when a describeCommand supplied
    /// one; otherwise the counts the dragged history row already carried.
    private var countLine: String {
        if let e = exact, let detail = TransferFormat.exact(files: e.files, folders: e.folders) {
            return detail
        }
        return TransferFormat.summary(files: item.files, bytes: item.bytes) ?? "size unknown"
    }
}

// MARK: - Logs tab (live-tail each operation)

struct TransferLogsView: View {
    @ObservedObject var actions: TransferActionsModel
    @State private var selection: String?

    private var selectedOp: TransferOperation? {
        actions.operations.first { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            opList
                .frame(minWidth: 240, idealWidth: 280)
            if let op = selectedOp {
                LogTailView(op: op)
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

    private var opList: some View {
        Group {
            if actions.operations.isEmpty {
                VStack(spacing: 6) {
                    Text("No transfers launched yet").font(.headline)
                    Text("Drag a title onto a machine in the Transfer tab to start one.")
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
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .tag(op.id)
                    .accessibilityLabel("\(op.title), \(op.mode.rawValue) \(op.routeText), \(stateLabel(op.state))")
                }
            }
        }
    }

    private func stateLabel(_ s: TransferState) -> String {
        switch s { case .running: return "running"; case .succeeded: return "succeeded"; case .failed: return "failed" }
    }
}

/// Status dot + (for VoiceOver) text — never colour alone.
struct TransferStateDot: View {
    let state: TransferState
    var body: some View {
        Group {
            switch state {
            case .running:   ProgressView().controlSize(.small)
            case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .failed:    Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
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
    @StateObject private var tailer = LogTailer()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TransferStateDot(state: op.state)
                Text(op.title).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button {
                    NSWorkspace.shared.selectFile(op.logPath, inFileViewerRootedAtPath: "")
                } label: { Label("Reveal Log", systemImage: "folder") }
                    .buttonStyle(.borderless).font(.caption)
                    .help(op.logPath)
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
        .onAppear { tailer.start(path: op.logPath, live: op.state == .running) }
        .onChange(of: op.state) { newState in
            tailer.start(path: op.logPath, live: newState == .running)
        }
        .onDisappear { tailer.stop() }
        .accessibilityLabel("Log for \(op.title)")
    }
}

// MARK: - formatting

enum TransferFormat {
    private static let count: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    static func summary(files: Int?, bytes: Int64?) -> String? {
        var parts: [String] = []
        if let f = files, f > 0 { parts.append("\(count.string(from: NSNumber(value: f)) ?? "\(f)") files") }
        if let b = bytes, b > 0 { parts.append(ByteCountFormatter.string(fromByteCount: b, countStyle: .file)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func exact(files: Int?, folders: Int?) -> String? {
        let f = files ?? 0, d = folders ?? 0
        if files == nil && folders == nil { return nil }
        switch (f, d) {
        case (0, 0): return "empty"
        case (_, 0): return "\(f) file\(f == 1 ? "" : "s")"
        case (0, _): return "\(d) folder\(d == 1 ? "" : "s")"
        default:     return "\(f) file\(f == 1 ? "" : "s") and \(d) folder\(d == 1 ? "" : "s")"
        }
    }
}
