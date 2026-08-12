import Foundation

@main
struct TransferReceiptConsumerTests {
    static func main() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("fixtures/transfer-receipts-v1.json")
        let fixture = try Data(contentsOf: fixtureURL)
        let decoded = try unwrap(TransferReceiptDecoder.decode(fixture))
        precondition(decoded.malformedEntries == 0)
        precondition(decoded.receipts.count == 3)
        precondition(decoded.receipts[0].presentation == .pending)
        precondition(decoded.receipts[1].presentation == .verificationRequired)
        precondition(decoded.receipts[1].presentation.status != "completed")
        precondition(decoded.receipts[2].presentation.needsAttention)

        let activeReceipt = #"{"schema":"choam.transfer-receipt.v1","transferId":"ok-1","attemptId":"try-1","sourceAuthority":{"label":"source-a"},"destinationAuthority":{"label":"destination-a"},"route":{"generation":0,"fingerprint":"route-fingerprint-00"},"expectedBytes":1,"timestamps":{"commandAcceptedAt":"2026-08-12T00:00:00Z","queueAdmittedAt":"2026-08-12T00:00:01Z","startedAt":"2026-08-12T00:00:02Z","lastObservedAt":"2026-08-12T00:00:02Z"},"state":"ACTIVE"}"#
        let malformed = #"{"schema":"choam.transfer-receipts.v1","transferReceipts":["# + activeReceipt + #",{"schema":"unknown"}]}"#
        let partial = try unwrap(TransferReceiptDecoder.decode(Data(malformed.utf8)))
        precondition(partial.receipts.count == 1 && partial.malformedEntries == 1)
        precondition(TransferReceiptDecoder.decode(Data("{}".utf8)) == nil)
        precondition(TransferReceiptDecoder.decode(Data(activeReceipt.replacingOccurrences(of: #""sourceAuthority":{"label":"source-a"},"#, with: "").utf8))?.isMalformed == true)
        precondition(TransferReceiptDecoder.decode(Data(activeReceipt.replacingOccurrences(of: "2026-08-12T00:00:00Z", with: "not-an-instant").utf8))?.isMalformed == true)
        precondition(TransferReceiptDecoder.decode(Data(activeReceipt.replacingOccurrences(of: #","expectedBytes":1"#, with: "").utf8))?.isMalformed == true)
        let incompleteCompletion = activeReceipt
            .replacingOccurrences(of: #""state":"ACTIVE""#, with: #""state":"COMPLETED""#)
            .replacingOccurrences(of: #""lastObservedAt":"2026-08-12T00:00:02Z""#, with: #""destinationCommittedAt":"2026-08-12T00:00:03Z","completedAt":"2026-08-12T00:00:04Z","lastObservedAt":"2026-08-12T00:00:04Z""#)
        precondition(TransferReceiptDecoder.decode(Data(incompleteCompletion.utf8))?.isMalformed == true)
        print("TransferReceiptConsumerTests passed")
    }

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "TransferReceiptConsumerTests", code: 1) }
        return value
    }
}
