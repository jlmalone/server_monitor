import Foundation

@main
struct ResourceGuardPolicyTests {
    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        var cpuPolicy = SustainedResourcePolicy(
            cpuFractionLimit: AppResourceLimits.cpuFraction,
            residentByteLimit: AppResourceLimits.residentBytes,
            requiredSamples: AppResourceLimits.requiredSamples
        )
        for _ in 0..<2 {
            require(cpuPolicy.record(cpuFraction: 0.80, residentBytes: 80 * 1_048_576) == nil,
                    "CPU must be sustained before recovery")
        }
        require(cpuPolicy.record(cpuFraction: 0.80, residentBytes: 80 * 1_048_576) == .cpu(fraction: 0.80),
                "three high-CPU samples must trigger recovery")

        var resetPolicy = SustainedResourcePolicy(
            cpuFractionLimit: AppResourceLimits.cpuFraction,
            residentByteLimit: AppResourceLimits.residentBytes,
            requiredSamples: AppResourceLimits.requiredSamples
        )
        for _ in 0..<2 {
            _ = resetPolicy.record(cpuFraction: 0.90, residentBytes: 80 * 1_048_576)
        }
        require(resetPolicy.record(cpuFraction: 0.05, residentBytes: 80 * 1_048_576) == nil,
                "a normal CPU sample must reset the streak")
        for _ in 0..<2 {
            require(resetPolicy.record(cpuFraction: 0.90, residentBytes: 80 * 1_048_576) == nil,
                    "a reset CPU streak must again become sustained")
        }

        var memoryPolicy = SustainedResourcePolicy(
            cpuFractionLimit: AppResourceLimits.cpuFraction,
            residentByteLimit: AppResourceLimits.residentBytes,
            requiredSamples: AppResourceLimits.requiredSamples
        )
        for _ in 0..<2 {
            require(memoryPolicy.record(cpuFraction: 0.01, residentBytes: 900 * 1_048_576) == nil,
                    "memory must be sustained before recovery")
        }
        require(memoryPolicy.record(cpuFraction: 0.01, residentBytes: 900 * 1_048_576)
                    == .memory(bytes: 900 * 1_048_576),
                    "three high-memory samples must trigger recovery")

        require(AppResourceLimits.sampleInterval == 30, "sampling interval is part of the battery contract")
        require(AppResourceLimits.residentBytes == 192 * 1_048_576,
                "resident-memory limit is part of the memory contract")

        print("PASS: sustained CPU and memory guard policy")
    }
}
