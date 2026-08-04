import Foundation

@main
struct BackgroundRegistrationStampTests {
    static func main() {
        let current = "/Applications/ServerMonitor.app|20"
        precondition(!BackgroundRegistrationStamp.needsRefresh(stored: current, current: current))
        precondition(BackgroundRegistrationStamp.needsRefresh(stored: nil, current: current))
        precondition(
            BackgroundRegistrationStamp.needsRefresh(
                stored: "/private/tmp/ServerMonitor.app|19",
                current: current
            )
        )
        precondition(
            BackgroundRegistrationStamp.needsRefresh(
                stored: "/Applications/ServerMonitor.app|19",
                current: current
            )
        )
        print("PASS: registration refresh follows app path and build changes")
    }
}
