import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: ServiceMonitor
    @State private var showingWizard = false
    @State private var editingService: Service?
    @State private var serviceToDelete: Service?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Services")
                    .font(.headline)
                Spacer()
                Text("\(monitor.services.count) services")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            if monitor.services.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Services")
                        .font(.headline)
                    Text("Add a service to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: { showingWizard = true }) {
                        Label("Add Service", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Services list
                List {
                    ForEach(monitor.services) { service in
                        ServiceRow(
                            service: service,
                            onEdit: { editingService = service },
                            onDelete: {
                                serviceToDelete = service
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
                .listStyle(InsetListStyle())
            }
            
            Divider()
            
            // Footer with Add button
            HStack {
                Button(action: { showingWizard = true }) {
                    Label("Add Service", systemImage: "plus")
                }
                Spacer()
                Button(action: { monitor.reloadConfig() }) {
                    Label("Reload Config", systemImage: "arrow.clockwise")
                }
                .help("Reload services.json from disk")
            }
            .padding()
        }
        .frame(width: 550, height: 450)
        .sheet(isPresented: $showingWizard) {
            ServiceWizardView(monitor: monitor)
        }
        .sheet(item: $editingService) { service in
            ServiceWizardView(monitor: monitor, editingService: service)
        }
        .alert("Delete Service?", isPresented: $showDeleteConfirmation, presenting: serviceToDelete) { service in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                monitor.remove(service: service)
            }
        } message: { service in
            Text("Are you sure you want to delete \"\(service.name)\"? This will stop the service and remove its configuration.")
        }
    }
}

// MARK: - Service Row

struct ServiceRow: View {
    let service: Service
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(service.status.color)
                .frame(width: 10, height: 10)
            
            // Service info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(service.name)
                        .font(.headline)
                    
                    if !(service.enabled ?? true) {
                        Text("DISABLED")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                
                Text(service.identifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let path = service.path {
                    Text(path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer()
            
            // Port badge
            if let port = service.port {
                Text(":\(port)")
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Action buttons
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit service")
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Delete service")
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(monitor: ServiceMonitor())
    }
}
