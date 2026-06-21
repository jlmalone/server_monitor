import SwiftUI

/// Compact "worker (this Mac)" panel for the menu-bar dropdown: shows whether a
/// machine-specific local worker node is running (and its current throughput)
/// with a Turn On / Turn Off button. What the worker *is* lives in untracked
/// local config (`config/worker.example.json`); this open-source app only knows
/// how to start/stop it and read its pid/log. Remote nodes are unaffected.
struct WorkerStatusView: View {
    @ObservedObject var monitor: WorkerStatusMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: monitor.running ? "cpu.fill" : "cpu")
                    .foregroundColor(monitor.headlineColor)
                Text("Worker (this Mac)")
                    .font(.headline)
                Spacer()
                Text(monitor.headline)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(monitor.headlineColor.opacity(0.2))
                    .foregroundColor(monitor.headlineColor)
                    .cornerRadius(4)
            }

            if monitor.configured {
                HStack(spacing: 8) {
                    Text(monitor.running ? "local node · \(monitor.rate ?? "running")" : "local node stopped")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if monitor.running {
                        Button(action: { monitor.stop() }) {
                            Label("Turn Off", systemImage: "stop.fill").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                        .disabled(monitor.busy)
                    } else {
                        Button(action: { monitor.start() }) {
                            Label("Turn On", systemImage: "play.fill").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.green)
                        .disabled(monitor.busy)
                    }
                }
            } else {
                Text("no local worker configured")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

#Preview {
    WorkerStatusView(monitor: WorkerStatusMonitor(pollInterval: 60))
        .frame(width: 320)
}

/// Compact "Transfers" panel: active file transfers (per item: title, %, rate,
/// ETA) plus an aggregate headline. Data + config live in `TransfersMonitor`;
/// this view is pure presentation. Inert when no `transfers.json` is configured.
struct TransfersView: View {
    @ObservedObject var monitor: TransfersMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: monitor.running > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .foregroundColor(monitor.headlineColor)
                Text("Transfers")
                    .font(.headline)
                Spacer()
                Text(monitor.headline)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(monitor.headlineColor.opacity(0.2))
                    .foregroundColor(monitor.headlineColor)
                    .cornerRadius(4)
            }

            if !monitor.configured {
                Text("no transfers source configured")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if monitor.rows.isEmpty {
                Text("no active transfers")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(monitor.rows.prefix(6)) { row in
                    rowView(row)
                }
                if monitor.rows.count > 6 {
                    Text("+\(monitor.rows.count - 6) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func rowView(_ row: TransferRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor(row.status))
                    .frame(width: 6, height: 6)
                Text(row.title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let pct = row.pctText {
                    Text(pct).font(.caption2).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 8) {
                Text(row.machine).font(.caption2).foregroundColor(.secondary)
                if let rate = row.rateText {
                    Text(rate).font(.caption2).foregroundColor(.secondary)
                }
                if let eta = row.etaText {
                    Text(eta).font(.caption2).foregroundColor(.secondary)
                }
                if row.rateText == nil {
                    Text(row.status).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                if row.status == "failed", monitor.canResume(machine: row.machine) {
                    Button("Resume") { monitor.resume(machine: row.machine) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.caption2)
                }
            }
        }
    }

    private func dotColor(_ status: String) -> Color {
        switch status {
        case "running": return .green
        case "failed": return .red
        default: return .secondary
        }
    }
}

#Preview {
    TransfersView(monitor: TransfersMonitor())
        .frame(width: 320)
}

// MARK: - Transfer History window

/// Secondary window opened from the dropdown: browse/inspect the transfer tool's
/// past operations, with stub tabs for Inventory and Reclaim that activate once
/// the tool exposes them as JSON (roadmap "Transfer History + Inventory + Reclaim
/// window"). Reclaim is read-only/dry-run only by design — this window never deletes.
struct TransferHistoryWindow: View {
    @StateObject private var actions = TransferActionsModel()

    var body: some View {
        TabView {
            ManagerView(actions: actions)
                .tabItem { Label("Files", systemImage: "rectangle.split.2x1") }

            TransferHistoryTab()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            TransferLogsView(actions: actions)
                .tabItem { Label("Logs", systemImage: "doc.text.magnifyingglass") }

            TransferToolStubTab(
                title: "Inventory",
                systemImage: "shippingbox",
                message: "For each title: which machines hold it and whether a verified copy exists elsewhere.",
                detail: "Activates once the transfer tool exposes inventory as JSON (roadmap Phase 16)."
            )
            .tabItem { Label("Inventory", systemImage: "shippingbox") }

            TransferToolStubTab(
                title: "Reclaim",
                systemImage: "trash.slash",
                message: "What is safely reclaimable locally and how much space — read-only / dry-run only.",
                detail: "Destructive reclaim stays a deliberate CLI action with live re-verification; this window never deletes. Activates once the tool exposes reclaim as JSON (roadmap Phase 16)."
            )
            .tabItem { Label("Reclaim", systemImage: "trash.slash") }
        }
        .frame(minWidth: 860, minHeight: 520)
    }
}

/// Placeholder for a tab whose data source isn't available yet. Combined into a
/// single accessibility element so VoiceOver reads the whole explanation at once.
private struct TransferToolStubTab: View {
    let title: String
    let systemImage: String
    let message: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Text(detail)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 440)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message) \(detail)")
    }
}

/// The functional History tab: a searchable, status-filtered, newest-first table
/// of past transfers with a click-to-drill detail pane.
struct TransferHistoryTab: View {
    @StateObject private var loader = TransferHistoryLoader()
    @State private var search = ""
    @State private var statusFilter = "FAILED"   // default to failures — the triage view
    @State private var selection: TransferHistoryRecord.ID?
    @State private var confirmClean = false

    private let statuses = ["ALL", "FAILED", "COMPLETED", "CANCELLED"]

    private var filtered: [TransferHistoryRecord] {
        loader.records.filter { rec in
            (statusFilter == "ALL" || rec.status.uppercased() == statusFilter)
                && (search.isEmpty || rec.matches(search))
        }
    }

    private var selectedRecord: TransferHistoryRecord? {
        guard let id = selection else { return nil }
        return loader.records.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            content
            if let rec = selectedRecord {
                Divider()
                TransferHistoryDetail(record: rec)
            }
        }
        .onAppear { if loader.records.isEmpty { loader.reload() } }
        .confirmationDialog("Clean transfer history?", isPresented: $confirmClean, titleVisibility: .visible) {
            Button("Clean", role: .destructive) { loader.clear() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Runs your configured clean command to prune the history log on disk.")
        }
    }

    @ViewBuilder private var controlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary).accessibilityHidden(true)
            TextField("Search title or machine", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .accessibilityLabel("Search transfer history")
            Picker("Status", selection: $statusFilter) {
                ForEach(statuses, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()
            .accessibilityLabel("Filter by status")
            Spacer()
            Text(countLabel).font(.caption).foregroundColor(.secondary)
            Button { loader.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(loader.loading)
            if loader.canClear {
                Button(role: .destructive) { confirmClean = true } label: { Label("Clean", systemImage: "trash") }
                    .disabled(loader.loading)
                    .help("Prune the history log (runs your configured clean command)")
            }
        }
        .padding(10)
    }

    private var countLabel: String {
        loader.loading ? "loading…" : "\(filtered.count) of \(loader.records.count) shown"
    }

    @ViewBuilder private var content: some View {
        if !loader.configured {
            placeholder(
                "Transfer history not configured",
                "Add a \u{201C}history\u{201D} command to ~/.config/server-monitor/transfers.json (see config/transfers.example.json)."
            )
        } else if let err = loader.error, loader.records.isEmpty {
            placeholder("No history to show", err)
        } else {
            Table(filtered, selection: $selection) {
                TableColumn("When") { TransferHistoryWhenCell(record: $0) }
                TableColumn("Repository") { Text($0.titleText).lineLimit(1).truncationMode(.middle) }
                TableColumn("Route") { Text($0.routeText).foregroundColor(.secondary) }
                TableColumn("Status") { TransferStatusBadge(status: $0.status) }
                TableColumn("Files") { Text($0.filesText).foregroundColor(.secondary) }
                TableColumn("Size") { Text($0.sizeText).foregroundColor(.secondary) }
                TableColumn("Errors") { Text($0.errorsText).foregroundColor($0.errorsCount > 0 ? .red : .secondary) }
            }
        }
    }

    @ViewBuilder private func placeholder(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// "When" cell: relative age for scanning, exact timestamp on hover + for VoiceOver.
struct TransferHistoryWhenCell: View {
    let record: TransferHistoryRecord

    private static let rel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
    private static let abs: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        let d = TransferHistoryDates.parse(record.startTime)
        Text(d.map { Self.rel.localizedString(for: $0, relativeTo: Date()) } ?? record.startTime)
            .help(record.startTime)
            .accessibilityLabel(d.map { "Started \(Self.abs.string(from: $0))" } ?? record.startTime)
    }
}

/// Status shown as text + color (never color alone — keeps it legible to
/// color-blind users and VoiceOver).
struct TransferStatusBadge: View {
    let status: String

    private var color: Color {
        switch status.uppercased() {
        case "COMPLETED": return .green
        case "FAILED": return .red
        case "CANCELLED": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        Text(status.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .cornerRadius(4)
            .accessibilityLabel("Status \(status.capitalized)")
    }
}

/// Drill-in detail for the selected row: derived duration + average rate plus the
/// raw fields, all selectable for copy-out.
struct TransferHistoryDetail: View {
    let record: TransferHistoryRecord

    var body: some View {
        let start = TransferHistoryDates.parse(record.startTime)
        let end = TransferHistoryDates.parse(record.endTime)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(record.titleText).font(.headline)
                    TransferStatusBadge(status: record.status)
                    Spacer()
                }
                if let r = record.repositories, r.count > 1 {
                    Text(r.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    detailRow("Route", record.routeText)
                    detailRow("Started", record.startTime)
                    detailRow("Ended", record.endTime ?? "—")
                    detailRow("Duration", TransferHistoryFormat.duration(start, end) ?? "—")
                    detailRow("Avg rate", TransferHistoryFormat.rate(record.bytesTransferred, start, end) ?? "—")
                    detailRow("Files", record.filesText)
                    detailRow("Size", record.sizeText)
                    detailRow("Errors", record.errorsText)
                    detailRow("ID", record.id)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .textSelection(.enabled)
        }
        .frame(maxHeight: 190)
    }

    @ViewBuilder private func detailRow(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key).foregroundColor(.secondary).gridColumnAlignment(.trailing)
            Text(value)
        }
    }
}

private extension TransferHistoryRecord {
    /// First repository with its operation prefix (e.g. "send:") stripped, plus a
    /// "(+N)" when the run touched several.
    var titleText: String {
        guard let r = repositories, !r.isEmpty else { return "—" }
        var first = r[0]
        for prefix in ["send:", "move:", "copy:", "pull:", "push:"] where first.hasPrefix(prefix) {
            first = String(first.dropFirst(prefix.count)); break
        }
        return r.count > 1 ? "\(first)  (+\(r.count - 1))" : first
    }

    var routeText: String { "\(sourceMachine ?? "?") → \(targetMachine ?? "?")" }
    var filesText: String { filesTransferred.map(String.init) ?? "—" }
    var errorsCount: Int { errors ?? 0 }
    var errorsText: String { errors.map(String.init) ?? "—" }
    var sizeText: String { TransferHistoryFormat.bytes(bytesTransferred) }

    func matches(_ query: String) -> Bool {
        let hay = ((repositories ?? []).joined(separator: " ")
                   + " " + (sourceMachine ?? "")
                   + " " + (targetMachine ?? "")).lowercased()
        return hay.contains(query.lowercased())
    }
}

enum TransferHistoryFormat {
    static func bytes(_ b: Int64?) -> String {
        guard let b, b > 0 else { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(b); var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        return i == 0 ? "\(b) B" : String(format: "%.1f %@", v, units[i])
    }

    static func duration(_ start: Date?, _ end: Date?) -> String? {
        guard let start, let end, end > start else { return nil }
        let s = Int(end.timeIntervalSince(start))
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60 { return "\(s / 60)m \(s % 60)s" }
        return "\(s)s"
    }

    static func rate(_ bytes: Int64?, _ start: Date?, _ end: Date?) -> String? {
        guard let bytes, bytes > 0, let start, let end, end > start else { return nil }
        let bps = Double(bytes) / end.timeIntervalSince(start)
        let mb = bps / 1_000_000
        return mb >= 1 ? String(format: "%.1f MB/s", mb) : String(format: "%.0f KB/s", bps / 1000)
    }
}
