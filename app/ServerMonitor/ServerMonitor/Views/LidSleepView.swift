import SwiftUI

/// Compact "Lid Close" panel for the menu-bar dropdown: shows whether this Mac
/// keeps running with the lid shut and offers a one-click Keep Awake / Allow
/// Sleep toggle. Backed by `LidSleepMonitor` (which drives `pmset disablesleep`
/// behind the native admin prompt). Rendered only on laptops.
struct LidSleepView: View {
    @ObservedObject var monitor: LidSleepMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: monitor.stayingAwake ? "bolt.fill" : "moon.zzz.fill")
                    .foregroundColor(monitor.headlineColor)
                    .accessibilityHidden(true)
                Text("Lid Close")
                    .font(.headline)
                Spacer()
                Text(monitor.headline)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(monitor.headlineColor.opacity(0.2))
                    .foregroundColor(monitor.headlineColor)
                    .cornerRadius(4)
                    .accessibilityLabel("Lid-close behavior: \(monitor.headline)")
            }

            HStack(spacing: 8) {
                Text(monitor.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if monitor.stayingAwake {
                    Button(action: { monitor.allowSleep() }) {
                        Label("Allow Sleep", systemImage: "moon.zzz.fill").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(monitor.busy)
                    .accessibilityLabel("Allow this Mac to sleep when the lid is closed")
                } else {
                    Button(action: { monitor.keepAwake() }) {
                        Label("Keep Awake", systemImage: "bolt.fill").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.green)
                    .disabled(monitor.busy)
                    .accessibilityLabel("Keep this Mac running when the lid is closed")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .onAppear { monitor.refresh() }
    }
}

#Preview {
    LidSleepView(monitor: LidSleepMonitor())
        .frame(width: 320)
}
