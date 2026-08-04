import Darwin
import Foundation

@main
struct AppResourcePriorityTests {
    static func main() {
        AppResourceGuard.shared.start()
        precondition(getpriority(PRIO_PROCESS, 0) == 19)
        print("PASS: app lowers itself to idle-friendly priority")
    }
}
