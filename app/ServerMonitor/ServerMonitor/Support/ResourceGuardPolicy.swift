import Foundation

enum AppResourceLimits {
    static let sampleInterval: TimeInterval = 30
    static let cpuFraction = 0.25
    static let residentBytes: UInt64 = 192 * 1_048_576
    static let requiredSamples = 3
    static let relaunchCooldown: TimeInterval = 30 * 60
}

enum AppResourceViolation: Equatable {
    case cpu(fraction: Double)
    case memory(bytes: UInt64)
}

struct SustainedResourcePolicy {
    let cpuFractionLimit: Double
    let residentByteLimit: UInt64
    let requiredSamples: Int

    private(set) var consecutiveCPUSamples = 0
    private(set) var consecutiveMemorySamples = 0

    mutating func record(cpuFraction: Double, residentBytes: UInt64) -> AppResourceViolation? {
        consecutiveCPUSamples = cpuFraction >= cpuFractionLimit
            ? consecutiveCPUSamples + 1
            : 0
        consecutiveMemorySamples = residentBytes >= residentByteLimit
            ? consecutiveMemorySamples + 1
            : 0

        if consecutiveMemorySamples >= requiredSamples {
            return .memory(bytes: residentBytes)
        }
        if consecutiveCPUSamples >= requiredSamples {
            return .cpu(fraction: cpuFraction)
        }
        return nil
    }
}
