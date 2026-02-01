import Foundation
import ServiceManagement

class LaunchAtLogin {
    static let observable = LaunchAtLogin()
    
    var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status == .enabled { return }
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update Launch at Login: \(error)")
            }
        }
    }
}
