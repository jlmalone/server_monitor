import AppKit
import Combine
import Foundation
import SwiftUI

struct StorageConfiguration: Decodable {
    struct Host: Decodable { let address: String; let ssh: String }
    struct Catalog: Decodable, Identifiable {
        var id: String { name }
        let name: String
        let kind: String
        let path: String
        let ssh: String?
        let sqlite: String?
    }
    let hosts: [Host]?
    let catalogs: [Catalog]?

    static func load() -> Self {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/server-monitor/storage.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.intValue < 262_144,
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(hosts: [], catalogs: [])
        }
        return config
    }
}

struct StorageDrive: Identifiable {
    var id: String { device + mount }
    let device: String
    let mount: String
    let total: Int64
    let free: Int64
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}

struct StorageMachine: Identifiable {
    let id: String
    let name: String
    var state: String
    var drives: [StorageDrive] = []
    var observed: Date?
}

/// Only explicit refreshes contact peers. The menu reads local filesystem metadata only.
@MainActor
final class StorageMonitor: ObservableObject {
    @Published var localFree: Int64?
    @Published var machines: [StorageMachine] = []
    @Published var busy = false
    @Published var message = ""
    private var timer: AnyCancellable?
    private var generation = UUID()

    init() {
        refreshLocal()
        timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refreshLocal() }
    }
    func refreshLocal() {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        localFree = (attrs?[.systemFreeSize] as? NSNumber)?.int64Value
    }
    func stop() { generation = UUID(); message = "Refresh stopped. Readings retain their observation time." }
    func refresh() {
        guard !busy else { return }
        refreshLocal()
        busy = true
        message = "Reading mounted drives…"
        let token = UUID()
        generation = token
        let config = StorageConfiguration.load()
        Task.detached { [weak self] in
            let local = ProcessRunner.run(["/bin/df", "-Pk"], timeout: 5)
            var rows = [StorageMachine(id: "local", name: Host.current().localizedName ?? "This Mac", state: local.succeeded ? "This Mac" : "Unavailable", drives: Self.drives(local.output), observed: local.succeeded ? Date() : nil)]
            let discovery = ProcessRunner.run(["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "status", "--json"], timeout: 8)
            let json = (try? JSONSerialization.jsonObject(with: discovery.data)) as? [String: Any]
            let peers = (json?["Peer"] as? [String: [String: Any]] ?? [:]).sorted { $0.key < $1.key }
            for (index, pair) in peers.enumerated() {
                guard await self?.isCurrent(token) == true else {
                    await MainActor.run { self?.busy = false }
                    return
                }
                let peer = pair.value
                let address = (peer["TailscaleIPs"] as? [String])?.first ?? ""
                let name = peer["HostName"] as? String ?? address
                let online = peer["Online"] as? Bool == true
                let os = peer["OS"] as? String ?? ""
                var row = StorageMachine(id: pair.key, name: name, state: online ? "Storage access unavailable" : "Offline")
                if online && index < 32 && ["macOS", "linux", "freebsd"].contains(os) && !address.isEmpty {
                    let target = config.hosts?.first { $0.address == address }?.ssh ?? address
                    let run = ProcessRunner.run(Self.ssh(target, command: "nice -n 19 df -Pk"), timeout: 10, includeStandardError: false)
                    row.drives = run.succeeded ? Self.drives(run.output) : []
                    row.state = row.drives.isEmpty ? "Storage unavailable (SSH access or drive query failed)" : "Online"
                    row.observed = row.drives.isEmpty ? nil : Date()
                } else if online { row.state = index >= 32 ? "Not probed (32-peer refresh budget)" : "Storage access unsupported" }
                rows.append(row)
                let snapshot = rows
                await MainActor.run { [weak self] in
                    guard self?.generation == token else { return }
                    self?.machines = snapshot
                }
            }
            let snapshot = rows
            await MainActor.run { [weak self] in
                guard self?.generation == token else { self?.busy = false; return }
                self?.machines = snapshot
                self?.message = discovery.succeeded ? "Mounted filesystems only. Shared APFS capacity is not additive. Offline machines have no current reading." : "Network discovery unavailable. Showing this Mac only."
                self?.busy = false
            }
        }
    }
    private func isCurrent(_ token: UUID) -> Bool { generation == token }
    nonisolated static func ssh(_ target: String, command: String) -> [String] {
        ["/usr/bin/ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=3", "-o", "ServerAliveCountMax=1", "--", target, command]
    }
    nonisolated static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    nonisolated static func drives(_ output: String) -> [StorageDrive] {
        output.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(maxSplits: 5, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 6, let total = Int64(fields[1]), let free = Int64(fields[3]), total > 0,
                  total <= Int64.max / 1024, free >= 0, free <= Int64.max / 1024,
                  fields[0] != "devfs", !fields[0].hasPrefix("map ") else { return nil }
            return StorageDrive(device: String(fields[0]), mount: String(fields[5]), total: total * 1024, free: free * 1024)
        }
    }
}

struct CatalogHit: Decodable, Identifiable {
    let id: Int64
    let path: String
    let machine: String
    let drive: String
    let size: Int64
    let cid: String
    let date: String
}

struct CatalogPage {
    var hits: [CatalogHit]
    var cursor: Int64
    var more: Bool
    var note: String
}

/// Read-only adapters: existing FTS index, Sietch location registry, or streamed local TSV.
enum CatalogReader {
    private static let queryLock = NSLock()
    static func read(_ source: StorageConfiguration.Catalog, query: String, mode: String, cursor: Int64) throws -> CatalogPage {
        guard queryLock.try() else { throw failure("A previous query is finishing. Try again shortly.") }
        defer { queryLock.unlock() }
        if source.kind == "flatFile" { return try flat(source, query: query, cursor: cursor) }
        func sql(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
        let statement: String
        if source.kind == "sqliteCatalog" {
            let term = "\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let predicate: String
            switch mode {
            case "CID": predicate = "f.cid = \(sql(query))"
            case "Hash": predicate = "f.hash = \(sql(query))"
            default: predicate = "f.id IN (SELECT rowid FROM files_fts WHERE files_fts MATCH \(sql(term)))"
            }
            statement = "SELECT f.id, substr(f.path,1,4096) AS path, cs.machine, cs.drive_label AS drive, f.size, f.cid, cs.catalog_date AS date FROM files f JOIN catalog_sources cs ON cs.id=f.source_id WHERE f.id > \(cursor) AND \(predicate) ORDER BY f.id LIMIT 51;"
        } else if source.kind == "sqliteRegistry" {
            let predicate = mode == "CID" ? "cid = \(sql(query))" : "instr(lower(file_path),lower(\(sql(query)))) > 0"
            statement = "SELECT rowid AS id, substr(file_path,1,4096) AS path, machine_name AS machine, '' AS drive, coalesce(file_size,0) AS size, cid, coalesce(verified_at,registered_at,'') AS date FROM content_locations WHERE rowid > \(cursor) AND \(predicate) ORDER BY rowid LIMIT 51;"
        } else { throw failure("Unsupported catalog type") }
        let argv = [source.sqlite ?? "/usr/bin/sqlite3", "-readonly", "-json", "-cmd", ".timeout 1000", "-cmd", ".progress 10000 --limit 1000 --quiet", source.path, "PRAGMA cache_size=-2048; PRAGMA temp_store=FILE; " + statement]
        let command = source.ssh.map { StorageMonitor.ssh($0, command: "nice -n 19 " + argv.map(StorageMonitor.quote).joined(separator: " ")) } ?? argv
        let run = ProcessRunner.run(command, timeout: 15, maxOutputBytes: 1_048_576)
        guard run.succeeded else { throw failure(run.failureSummary() ?? "Query failed") }
        let hits = run.data.isEmpty || run.output.isEmpty ? [] : try JSONDecoder().decode([CatalogHit].self, from: run.data)
        let page = Array(hits.prefix(50))
        return CatalogPage(hits: page, cursor: page.last?.id ?? cursor, more: hits.count > 50, note: "Catalog observations, not proof that files are currently present. Scan dates appear on each result.")
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func flat(_ source: StorageConfiguration.Catalog, query: String, cursor: Int64) throws -> CatalogPage {
        guard source.ssh == nil else { throw failure("Flat-file search needs a local catalog. Use the remote FTS database for network catalogs.") }
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: source.path))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(max(0, cursor)))
        var position = cursor
        var buffer = Data()
        var hits: [CatalogHit] = []
        let deadline = Date().addingTimeInterval(3)
        let budget = cursor + 32 * 1024 * 1024
        while Date() < deadline && position < budget {
            let chunk = try handle.read(upToCount: 65_536) ?? Data()
            buffer.append(chunk)
            while let end = buffer.firstIndex(of: 10) {
                let count = buffer.distance(from: buffer.startIndex, to: end) + 1
                let line = String(decoding: buffer.prefix(count - 1), as: UTF8.self)
                buffer.removeFirst(count)
                position += Int64(count)
                if !line.hasPrefix("#"), line.localizedCaseInsensitiveContains(query) {
                    hits.append(CatalogHit(id: position, path: String(line.prefix(4096)), machine: source.name, drive: "", size: 0, cid: "", date: "Flat catalog"))
                    if hits.count == 50 { return CatalogPage(hits: hits, cursor: position, more: true, note: "Streamed TSV rows. Next continues from the last byte read.") }
                }
            }
            guard buffer.count <= 1_048_576 else { throw failure("Catalog line exceeds the 1 MiB safety limit") }
            if chunk.isEmpty {
                if !buffer.isEmpty {
                    let line = String(decoding: buffer, as: UTF8.self)
                    position += Int64(buffer.count)
                    if !line.hasPrefix("#"), line.localizedCaseInsensitiveContains(query) {
                        hits.append(CatalogHit(id: position, path: String(line.prefix(4096)), machine: source.name, drive: "", size: 0, cid: "", date: "Flat catalog"))
                    }
                }
                return CatalogPage(hits: hits, cursor: position, more: false, note: "End of catalog.")
            }
        }
        return CatalogPage(hits: hits, cursor: position, more: true, note: "Scan budget reached. Next continues searching; zero rows here does not mean no matches remain.")
    }
}

@MainActor
final class CatalogSearchModel: ObservableObject {
    @Published var sources = StorageConfiguration.load().catalogs ?? []
    @Published var selected = ""
    @Published var query = ""
    @Published var mode = "Name / path"
    @Published var hits: [CatalogHit] = []
    @Published var busy = false
    @Published var note = "Search the existing index. No catalog rebuild or file scan runs automatically."
    @Published var more = false
    private var cursor: Int64 = 0
    private var generation = UUID()
    private var activeQuery = ""
    private var activeMode = ""
    private var activeSource = ""

    init() { selected = sources.first?.id ?? "" }
    func invalidate() { generation = UUID(); busy = false; hits = []; more = false; cursor = 0 }
    func search(next: Bool = false) {
        guard !busy, let source = sources.first(where: { $0.id == selected }) else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 512, !text.contains("\0") else { note = "Enter 1 to 512 bytes of search text."; return }
        let continuing = next && activeQuery == text && activeSource == selected && activeMode == mode
        let start = continuing ? cursor : 0
        activeQuery = text; activeSource = selected; activeMode = mode
        busy = true; hits = []; more = false
        let token = UUID(); generation = token
        let searchMode = mode
        Task.detached { [weak self] in
            let result = Result { try CatalogReader.read(source, query: text, mode: searchMode, cursor: start) }
            await MainActor.run { [weak self] in
                guard let self, self.generation == token else { return }
                self.busy = false
                switch result {
                case .success(let page): self.hits = page.hits; self.cursor = page.cursor; self.more = page.more; self.note = "\(page.hits.count) results on this page. \(page.note)"
                case .failure(let error): self.note = "Search unavailable: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct StorageStatusWindow: View {
    @ObservedObject var monitor: StorageMonitor
    @StateObject private var search = CatalogSearchModel()
    @State private var showSearch = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Storage Status", systemImage: "externaldrive").font(.title2)
                Spacer()
                Button("Drives") { showSearch = false }
                Button("Search Sietch") { showSearch = true }
                Button("Refresh") { monitor.refresh() }.disabled(monitor.busy)
            }
            if showSearch { catalog } else { drives }
        }
        .padding(20).frame(minWidth: 720, minHeight: 480)
        .onAppear { monitor.refresh() }
        .onDisappear { monitor.stop(); search.invalidate() }
    }
    private var drives: some View {
        VStack(alignment: .leading) {
            if monitor.busy { ProgressView().controlSize(.small) }
            Text(monitor.message).font(.caption).foregroundStyle(.secondary)
            List(monitor.machines) { machine in
                DisclosureGroup {
                    if machine.drives.isEmpty { Text(machine.state).foregroundStyle(.secondary) }
                    ForEach(machine.drives) { drive in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(drive.mount, systemImage: "externaldrive")
                                Spacer()
                                Text("\(StorageDrive.bytes(drive.free)) free / \(StorageDrive.bytes(drive.total))").monospacedDigit()
                            }
                            ProgressView(value: Double(max(0, drive.total - drive.free)), total: Double(drive.total))
                                .tint(Double(drive.free) / Double(drive.total) < 0.1 ? .orange : .accentColor)
                            Text(drive.device).font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                } label: {
                    HStack {
                        Label(machine.name, systemImage: machine.id == "local" ? "laptopcomputer" : "desktopcomputer")
                        Spacer()
                        Text(machine.state).font(.caption).foregroundStyle(.secondary)
                        if let observed = machine.observed { Text(observed, style: .time).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
    private var catalog: some View {
        VStack(alignment: .leading, spacing: 10) {
            if search.sources.isEmpty {
                Text("No Sietch catalog configured. Add a database or local flat catalog in storage.json.")
                Button("Open configuration folder") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/server-monitor")) }
            } else {
                HStack {
                    Picker("Catalog", selection: $search.selected) { ForEach(search.sources) { Text($0.name).tag($0.id) } }
                    if search.sources.first(where: { $0.id == search.selected })?.kind != "flatFile" {
                        Picker("Match", selection: $search.mode) {
                            Text("Name / path").tag("Name / path")
                            Text("CID").tag("CID")
                            if search.sources.first(where: { $0.id == search.selected })?.kind == "sqliteCatalog" { Text("Hash").tag("Hash") }
                        }.frame(width: 180)
                    }
                }.disabled(search.busy)
                HStack {
                    TextField("Search all indexed machines and drives", text: $search.query).onSubmit { search.search() }.disabled(search.busy)
                    Button("Search") { search.search() }.disabled(search.busy)
                    if search.busy { ProgressView().controlSize(.small) }
                    Button("Next 50") { search.search(next: true) }.disabled(search.busy || !search.more)
                }
                Text(search.note).font(.caption).foregroundStyle(.secondary)
                List(search.hits) { hit in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(hit.path).textSelection(.enabled).lineLimit(3)
                        Text("\(hit.machine)  ·  \(hit.drive)  ·  \(StorageDrive.bytes(hit.size))  ·  \(hit.date)")
                            .font(.caption).foregroundStyle(.secondary)
                        if !hit.cid.isEmpty { Text(hit.cid).font(.caption2).textSelection(.enabled) }
                    }.padding(.vertical, 4)
                }
            }
        }
        .onChange(of: search.selected) { _ in search.mode = "Name / path"; search.invalidate() }
        .onChange(of: search.mode) { _ in search.invalidate() }
        .onChange(of: search.query) { _ in search.invalidate() }
    }
}
