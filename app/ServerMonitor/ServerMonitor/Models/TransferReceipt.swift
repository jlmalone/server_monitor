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

    /// Decodes only the opaque identifiers and lifecycle state needed by this
    /// display. Unknown payload fields, including route and evidence details,
    /// are never retained or rendered.
    static func decode(_ data: Data) -> TransferReceiptDecodeResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any],
              let schema = object["schema"] as? String else { return nil }

        if schema == receiptSchema {
            guard let receipt = receipt(from: object) else { return nil }
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
              timestamps["commandAcceptedAt"] as? String != nil else { return nil }
        let queueEntryId = object["queueEntryId"] as? String
        guard queueEntryId == nil || validID(queueEntryId) != nil else { return nil }
        return TransferReceiptView(transferId: transferId, attemptId: attemptId,
                                   queueEntryId: queueEntryId, state: state)
    }

    private static func validID(_ value: String?) -> String? {
        guard let value else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        return opaqueID.firstMatch(in: value, range: range) != nil ? value : nil
    }
}
