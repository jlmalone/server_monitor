import Foundation

/// Privacy-preserving V1 transfer-receipt projection. This is deliberately a
/// data-only consumer: it has no destination-evidence verifier, so it cannot
/// turn a producer's `COMPLETED` claim into a delivery-complete UI state.
enum TransferReceiptState: String, Decodable {
    case commandAccepted = "COMMAND_ACCEPTED"
    case queueAdmitted = "QUEUE_ADMITTED"
    case deferred = "DEFERRED"
    case active = "ACTIVE"
    case verifyingBytes = "VERIFYING_BYTES"
    case verifyingFiles = "VERIFYING_FILES"
    case destinationCommitted = "DESTINATION_COMMITTED"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

enum TransferReceiptPresentation: Equatable {
    case pending
    case running
    case failed
    case cancelled
    case verificationRequired

    var status: String {
        switch self {
        case .pending: return "pending"
        case .running: return "running"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        case .verificationRequired: return "verifying"
        }
    }

    var statusText: String {
        switch self {
        case .pending: return "receipt pending"
        case .running: return "receipt in progress"
        case .failed: return "receipt reports failed"
        case .cancelled: return "receipt reports cancelled"
        case .verificationRequired: return "destination evidence required"
        }
    }

    var isRunning: Bool { self == .running || self == .verificationRequired }
    var isPending: Bool { self == .pending }
    var needsAttention: Bool { self == .failed || self == .cancelled }
}

struct TransferReceiptView: Identifiable, Equatable {
    let transferId: String
    let attemptId: String
    let queueEntryId: String?
    let state: TransferReceiptState

    var id: String { "\(transferId):\(attemptId)" }

    /// `COMPLETED` remains provisional because this app intentionally has no
    /// cryptographic verifier for the destination proof.
    var presentation: TransferReceiptPresentation {
        switch state {
        case .commandAccepted, .queueAdmitted, .deferred: return .pending
        case .active, .verifyingBytes, .verifyingFiles, .destinationCommitted: return .running
        case .completed: return .verificationRequired
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }
}

struct TransferReceiptDecodeResult {
    let receipts: [TransferReceiptView]
    let malformedEntries: Int

    var isMalformed: Bool { malformedEntries > 0 }
}

enum TransferReceiptDecoder {
    private static let receiptSchema = "choam.transfer-receipt.v1"
    private static let envelopeSchema = "choam.transfer-receipts.v1"
    private static let opaqueID = try! NSRegularExpression(pattern: "\\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\\z")
    private static let routeFingerprint = try! NSRegularExpression(pattern: "\\A[a-z0-9][a-z0-9_-]{15,127}\\z")
    private static let sha256 = try! NSRegularExpression(pattern: "\\A[0-9a-f]{64}\\z")
    private static let failureCode = try! NSRegularExpression(pattern: "\\A[A-Z][A-Z0-9_]{0,63}\\z")
    private static let instantFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let wholeSecondInstantFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Validates the complete public V1 shape before retaining only the opaque
    /// identifiers and lifecycle state needed by this display. Unknown fields,
    /// including route and evidence details, are never retained or rendered.
    static func decode(_ data: Data) -> TransferReceiptDecodeResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any],
              let schema = object["schema"] as? String else { return nil }

        if schema == receiptSchema {
            guard let receipt = receipt(from: object) else {
                return TransferReceiptDecodeResult(receipts: [], malformedEntries: 1)
            }
            return TransferReceiptDecodeResult(receipts: [receipt], malformedEntries: 0)
        }
        guard schema == envelopeSchema,
              object["queue"] == nil,
              let children = object["transferReceipts"] as? [Any] else { return nil }

        var receipts: [TransferReceiptView] = []
        var malformed = 0
        for child in children {
            guard let receiptObject = child as? [String: Any], let receipt = receipt(from: receiptObject) else {
                malformed += 1
                continue
            }
            receipts.append(receipt)
        }
        return TransferReceiptDecodeResult(receipts: receipts, malformedEntries: malformed)
    }

    private static func receipt(from object: [String: Any]) -> TransferReceiptView? {
        guard object["schema"] as? String == receiptSchema,
              let transferId = validID(object["transferId"] as? String),
              let attemptId = validID(object["attemptId"] as? String),
              let rawState = object["state"] as? String,
              let state = TransferReceiptState(rawValue: rawState),
              let timestamps = object["timestamps"] as? [String: Any],
              validAuthority(object["sourceAuthority"]),
              validAuthority(object["destinationAuthority"]),
              let route = route(from: object["route"]),
              validExpectations(object),
              let timeline = timeline(from: timestamps),
              validStateLineage(state, timeline: timeline),
              validOptionalFields(object) else { return nil }
        let queueEntryId = object["queueEntryId"] as? String
        guard queueEntryId == nil || validID(queueEntryId) != nil else { return nil }
        guard let evidenceObject = object["destinationEvidence"] as? [String: Any] else {
            return state == .completed ? nil : TransferReceiptView(transferId: transferId, attemptId: attemptId,
                                                                    queueEntryId: queueEntryId, state: state)
        }
        guard validEvidence(evidenceObject, transferId: transferId, attemptId: attemptId, route: route,
                            destinationAuthority: object["destinationAuthority"] as! [String: Any],
                            expectations: object),
              state != .completed || completedExpectationsMatch(evidenceObject, expectations: object) else { return nil }
        return TransferReceiptView(transferId: transferId, attemptId: attemptId,
                                   queueEntryId: queueEntryId, state: state)
    }

    private static func validAuthority(_ value: Any?) -> Bool {
        guard let authority = value as? [String: Any] else { return false }
        return validID(authority["label"] as? String) != nil
    }

    private static func route(from value: Any?) -> [String: Any]? {
        guard let route = value as? [String: Any],
              let generation = nonnegativeInteger(route["generation"]),
              generation < Int64.max,
              valid(route["fingerprint"] as? String, expression: routeFingerprint) else { return nil }
        return route
    }

    private static func validExpectations(_ object: [String: Any]) -> Bool {
        let bytes = object["expectedBytes"]
        let files = object["expectedFiles"]
        guard (bytes == nil || nonnegativeInteger(bytes) != nil),
              (files == nil || nonnegativeInteger(files) != nil),
              object["declaredHashes"] == nil || object["declaredHashes"] as? [Any] != nil else { return false }
        let hashes = (object["declaredHashes"] as? [Any]) ?? []
        var algorithms = Set<String>()
        for value in hashes {
            guard let hash = value as? [String: Any],
                  hash["algorithm"] as? String == "SHA-256",
                  valid(hash["expected"] as? String, expression: sha256),
                  algorithms.insert("SHA-256").inserted else { return false }
        }
        return bytes != nil || files != nil || !hashes.isEmpty
    }

    private static func timeline(from timestamps: [String: Any]) -> [String: Date]? {
        let names = ["commandAcceptedAt", "queueAdmittedAt", "startedAt", "verificationStartedAt",
                     "destinationCommittedAt", "completedAt", "failedAt", "cancelledAt", "lastObservedAt"]
        var result: [String: Date] = [:]
        for name in names where timestamps[name] != nil {
            guard let value = timestamps[name] as? String, let date = instant(value) else { return nil }
            result[name] = date
        }
        guard result["commandAcceptedAt"] != nil else { return nil }
        let present = names.compactMap { result[$0] }
        return present.zipWithNext().allSatisfy { $0 <= $1 } ? result : nil
    }

    private static func validStateLineage(_ state: TransferReceiptState, timeline: [String: Date]) -> Bool {
        let required: [String]
        switch state {
        case .commandAccepted: required = ["commandAcceptedAt"]
        case .queueAdmitted, .deferred: required = ["commandAcceptedAt", "queueAdmittedAt", "lastObservedAt"]
        case .active: required = ["commandAcceptedAt", "queueAdmittedAt", "startedAt", "lastObservedAt"]
        case .verifyingBytes, .verifyingFiles: required = ["commandAcceptedAt", "queueAdmittedAt", "startedAt", "verificationStartedAt", "lastObservedAt"]
        case .destinationCommitted: required = ["commandAcceptedAt", "queueAdmittedAt", "startedAt", "verificationStartedAt", "destinationCommittedAt", "lastObservedAt"]
        case .completed: required = ["commandAcceptedAt", "queueAdmittedAt", "startedAt", "verificationStartedAt", "destinationCommittedAt", "completedAt", "lastObservedAt"]
        case .failed: required = ["commandAcceptedAt", "failedAt", "lastObservedAt"]
        case .cancelled: required = ["commandAcceptedAt", "cancelledAt", "lastObservedAt"]
        }
        return required.allSatisfy { timeline[$0] != nil }
    }

    private static func validOptionalFields(_ object: [String: Any]) -> Bool {
        let sequence = nonnegativeInteger(object["lastAppliedObservationSequence"])
        guard object["processExitCode"] == nil || integer(object["processExitCode"]) != nil,
              object["failureCode"] == nil || valid(object["failureCode"] as? String, expression: failureCode),
              validPriorAttempts(object["priorAttempts"]), validObservationIDs(object["appliedObservationIds"]),
              object["lastAppliedObservationSequence"] == nil || (sequence != nil && sequence! < Int64.max) else { return false }
        if object["state"] as? String == TransferReceiptState.failed.rawValue {
            return valid(object["failureCode"] as? String, expression: failureCode)
        }
        return true
    }

    private static func validPriorAttempts(_ value: Any?) -> Bool {
        guard value == nil || value as? [Any] != nil else { return false }
        let attempts = (value as? [Any]) ?? []
        guard attempts.count <= 64 else { return false }
        return attempts.allSatisfy { value in
            guard let attempt = value as? [String: Any],
                  validID(attempt["attemptId"] as? String) != nil,
                  let state = attempt["terminalOrDeferredState"] as? String,
                  state == TransferReceiptState.deferred.rawValue || state == TransferReceiptState.failed.rawValue,
                  instant(attempt["lastObservedAt"] as? String) != nil,
                  route(from: attempt["route"]) != nil,
                  attempt["failureCode"] == nil || valid(attempt["failureCode"] as? String, expression: failureCode) else { return false }
            return true
        }
    }

    private static func validObservationIDs(_ value: Any?) -> Bool {
        guard value == nil || value as? [Any] != nil else { return false }
        let ids = (value as? [Any]) ?? []
        guard ids.count <= 64 else { return false }
        let validated = ids.compactMap { validID($0 as? String) }
        return validated.count == ids.count && Set(validated).count == validated.count
    }

    private static func validEvidence(_ evidence: [String: Any], transferId: String, attemptId: String,
                                      route: [String: Any], destinationAuthority: [String: Any], expectations _: [String: Any]) -> Bool {
        guard let evidenceAuthority = evidence["authority"] as? [String: Any],
              validAuthority(evidenceAuthority),
              evidenceAuthority["label"] as? String == destinationAuthority["label"] as? String,
              instant(evidence["observedAt"] as? String) != nil,
              nonnegativeInteger(evidence["observedBytes"]) != nil,
              nonnegativeInteger(evidence["observedFiles"]) != nil,
              validObservedHashes(evidence["observedHashes"]),
              let proof = evidence["proof"] as? [String: Any], integer(proof["version"]) == 1,
              valid(proof["destinationAuthorityKeyFingerprint"] as? String, expression: routeFingerprint),
              proof["transferId"] as? String == transferId, proof["attemptId"] as? String == attemptId,
              sameRoute(proof["route"], route) else { return false }
        switch proof["scheme"] as? String {
        case "LOCAL_AUTHORITATIVE_PROBE_V1":
            return validToken(proof["localAuthoritativeProbeAttestation"] as? String, maximum: 256)
        case "CANONICAL_RECEIPT_SIGNATURE_V1":
            return valid(proof["canonicalReceiptDigestSha256"] as? String, expression: sha256)
                && validToken(proof["signature"] as? String, maximum: 512)
        default: return false
        }
    }

    private static func validObservedHashes(_ value: Any?) -> Bool {
        guard value == nil || value as? [Any] != nil else { return false }
        let hashes = (value as? [Any]) ?? []
        var algorithms = Set<String>()
        return hashes.allSatisfy { value in
            guard let hash = value as? [String: Any],
                  hash["algorithm"] as? String == "SHA-256",
                  valid(hash["value"] as? String, expression: sha256),
                  algorithms.insert("SHA-256").inserted else { return false }
            return true
        }
    }

    private static func completedExpectationsMatch(_ evidence: [String: Any], expectations: [String: Any]) -> Bool {
        if let bytes = nonnegativeInteger(expectations["expectedBytes"]), nonnegativeInteger(evidence["observedBytes"]) != bytes { return false }
        if let files = nonnegativeInteger(expectations["expectedFiles"]), nonnegativeInteger(evidence["observedFiles"]) != files { return false }
        let observed = (evidence["observedHashes"] as? [[String: Any]] ?? []).compactMap { hash -> String? in
            guard hash["algorithm"] as? String == "SHA-256" else { return nil }
            return hash["value"] as? String
        }
        return (expectations["declaredHashes"] as? [[String: Any]] ?? []).allSatisfy {
            $0["algorithm"] as? String == "SHA-256" && observed.contains($0["expected"] as? String ?? "")
        }
    }

    private static func sameRoute(_ value: Any?, _ expected: [String: Any]) -> Bool {
        guard let route = route(from: value),
              nonnegativeInteger(route["generation"]) == nonnegativeInteger(expected["generation"]),
              route["fingerprint"] as? String == expected["fingerprint"] as? String else { return false }
        return true
    }

    private static func instant(_ value: String?) -> Date? {
        guard let value else { return nil }
        return instantFormatter.date(from: value) ?? wholeSecondInstantFormatter.date(from: value)
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let integer = number.int64Value
        return number.doubleValue == Double(integer) ? integer : nil
    }

    private static func nonnegativeInteger(_ value: Any?) -> Int64? {
        guard let value = integer(value), value >= 0 else { return nil }
        return value
    }

    private static func valid(_ value: String?, expression: NSRegularExpression) -> Bool {
        guard let value else { return false }
        return expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private static func validToken(_ value: String?, maximum: Int) -> Bool {
        guard let value, !value.isEmpty, value.count <= maximum else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 || byte == 45
        }
    }

    private static func validID(_ value: String?) -> String? {
        guard let value else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        return opaqueID.firstMatch(in: value, range: range) != nil ? value : nil
    }
}
