import SwiftUI
import AppKit

struct ServiceWizardView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var monitor: ServiceMonitor
    
    // Edit mode support
    var editingService: Service?
    var isEditMode: Bool { editingService != nil }
    
    @State private var name = ""
    @State private var path = ""
    @State private var portStr = ""
    @State private var healthUrl = ""
    @State private var command = ""
    @State private var enabled = true
    @State private var keepAlive = true
    
    init(monitor: ServiceMonitor, editingService: Service? = nil) {
        self.monitor = monitor
        self.editingService = editingService
        
        // Pre-populate fields if editing
        if let service = editingService {
            _name = State(initialValue: service.name)
            _path = State(initialValue: service.path ?? "")
            _portStr = State(initialValue: service.port.map { String($0) } ?? "")
            _healthUrl = State(initialValue: service.healthCheckURL ?? "")
            _command = State(initialValue: service.command?.joined(separator: " ") ?? "")
            _enabled = State(initialValue: service.enabled ?? true)
            _keepAlive = State(initialValue: service.keepAlive ?? true)
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Text(isEditMode ? "Edit Service" : "Add Service")
                .font(.headline)
                .padding(.top)
            
            Divider()
            
            // Form fields with proper labels
            VStack(alignment: .leading, spacing: 12) {
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.caption).foregroundColor(.secondary)
                    TextField("My App", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(isEditMode)
                }
                
                // Working Directory
                VStack(alignment: .leading, spacing: 4) {
                    Text("Working Directory").font(.caption).foregroundColor(.secondary)
                    HStack {
                        TextField("/path/to/project", text: $path)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("Browse...") {
                            browseForFolder()
                        }
                    }
                }
                
                // Command
                VStack(alignment: .leading, spacing: 4) {
                    Text("Command").font(.caption).foregroundColor(.secondary)
                    TextField("npm run dev", text: $command)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // Port and Health Check in HStack
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port").font(.caption).foregroundColor(.secondary)
                        TextField("3000", text: $portStr)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .onChange(of: portStr) { newValue in
                                let filtered = newValue.filter { "0123456789".contains($0) }
                                if filtered != newValue {
                                    portStr = filtered
                                }
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Health Check URL").font(.caption).foregroundColor(.secondary)
                        TextField("auto: http://localhost:PORT", text: $healthUrl)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                Divider()
                
                // Options
                VStack(alignment: .leading, spacing: 8) {
                    Text("Options").font(.caption).foregroundColor(.secondary)
                    Toggle("Enabled", isOn: $enabled)
                    Toggle("Keep Alive (restart on crash)", isOn: $keepAlive)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Buttons
            Divider()
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button(action: saveService) {
                    Text(isEditMode ? "Save Changes" : "Add Service")
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!isFormValid)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 420)
    }
    
    private var isFormValid: Bool {
        !name.isEmpty && !path.isEmpty && !command.isEmpty
    }
    
    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose the working directory for your service"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                path = url.path
            }
        }
    }
    
    private func generateIdentifier(_ name: String) -> String {
        let safeName = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "com.servermonitor.\(safeName)"
    }
    
    private func parseCommand(_ cmd: String) -> [String] {
        // Simple space-based splitting for now
        cmd.components(separatedBy: " ").filter { !$0.isEmpty }
    }
    
    private func saveService() {
        let port = Int(portStr)
        let healthCheck = healthUrl.isEmpty ? (port.map { "http://localhost:\($0)" } ?? nil) : healthUrl
        
        if isEditMode, let existing = editingService {
            // Update existing service
            var updated = existing
            updated.path = path
            updated.command = parseCommand(command)
            updated.port = port
            updated.healthCheckURL = healthCheck
            updated.enabled = enabled
            updated.keepAlive = keepAlive
            
            monitor.update(service: updated)
        } else {
            // Create new service
            let identifier = generateIdentifier(name)
            
            let newService = Service(
                name: name,
                identifier: identifier,
                port: port,
                healthCheckURL: healthCheck,
                critical: true,
                path: path,
                command: parseCommand(command),
                enabled: enabled,
                keepAlive: keepAlive
            )
            
            monitor.add(service: newService)
        }
        
        presentationMode.wrappedValue.dismiss()
    }
}

// Preview
struct ServiceWizardView_Previews: PreviewProvider {
    static var previews: some View {
        ServiceWizardView(monitor: ServiceMonitor())
    }
}
