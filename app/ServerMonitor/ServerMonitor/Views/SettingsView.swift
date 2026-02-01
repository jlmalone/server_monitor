import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: ServiceMonitor
    @State private var showingWizard = false
    
    var body: some View {
        VStack {
            List {
                ForEach(monitor.services) { service in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(service.name)
                                .font(.headline)
                            Text(service.identifier)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(service.port)")
                            .font(.system(.body, design: .monospaced))
                        
                        Button(action: {
                            monitor.remove(service: service)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(InsetListStyle())
            
            HStack {
                Button(action: {
                    showingWizard = true
                }) {
                    Label("Add Service", systemImage: "plus")
                }
                Spacer()
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .sheet(isPresented: $showingWizard) {
            ServiceWizardView(monitor: monitor)
        }
    }
}
