import SwiftUI

/// Bottom-of-menu section: always shows the app's own version + build, and (when
/// version commands are configured) an expandable list of the tools it monitors.
/// Expanding runs the commands lazily; a Refresh button re-runs them.
struct VersionsView: View {
    @ObservedObject var monitor: VersionMonitor
    @State private var expanded = false

    var body: some View {
        Group {
            if monitor.hasComponents {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(monitor.components) { c in
                            row(c.label,
                                c.version ?? (monitor.loading ? "…" : "unavailable"),
                                failed: c.failed && !monitor.loading)
                        }
                        HStack {
                            Spacer()
                            if monitor.loading {
                                ProgressView().controlSize(.small)
                            } else {
                                Button { monitor.refresh() } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                        .font(.caption2)
                                }
                                .buttonStyle(.borderless)
                                .help("Re-run version checks")
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 4)
                } label: {
                    header
                }
                .onChange(of: expanded) { open in if open { monitor.refreshIfNeeded() } }
                .padding(.horizontal)
                .padding(.vertical, 6)
            } else {
                header
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
        }
    }

    /// Always-visible line naming the app and its version/build.
    private var header: some View {
        HStack(spacing: 6) {
            Text("Server Monitor")
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
            Text(monitor.appVersionText)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }

    private func row(_ label: String, _ value: String, failed: Bool) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(failed ? .red : .secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
