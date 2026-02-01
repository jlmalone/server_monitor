import SwiftUI

struct ServiceWizardView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var monitor: ServiceMonitor
    
    @State private var name = ""
    @State private var path = ""
    @State private var portStr = ""
    @State private var healthUrl = ""
    @State private var command = ""
    
    var body: some View {
        Form {
            Section(header: Text("Service Details")) {
                TextField("Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Path (Absolute)", text: $path)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Port", text: $portStr)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: portStr) { newValue in
                        let filtered = newValue.filter { "0123456789".contains($0) }
                        if filtered != newValue {
                            portStr = filtered
                        }
                    }
                
                TextField("Command (e.g. npm run dev)", text: $command)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Health Check URL", text: $healthUrl)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            Section {
                Button(action: addService) {
                    Text("Add Service")
                        .frame(maxWidth: .infinity)
                }
                .disabled(name.isEmpty || path.isEmpty || portStr.isEmpty || command.isEmpty)
                
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
    
    private func addService() {
        guard let port = Int(portStr) else { return }
        
        // Generate simple identifier
        let identifier = "com.user." + name.lowercased().replacingOccurrences(of: " ", with: "-")
        
        let newService = Service(
            name: name,
            identifier: identifier,
            port: port,
            healthCheckURL: healthUrl.isEmpty ? "http://localhost:\(port)" : healthUrl
        )
        // Store extra fields for saving
        newService.path = path
        newService.command = command.components(separatedBy: " ")
        newService.enabled = true
        
        monitor.add(service: newService)
        presentationMode.wrappedValue.dismiss()
    }
}
