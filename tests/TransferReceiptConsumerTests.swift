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

        let malformed = #"{"schema":"choam.transfer-receipts.v1","transferReceipts":[{"schema":"choam.transfer-receipt.v1","transferId":"ok-1","attemptId":"try-1","timestamps":{"commandAcceptedAt":"2026-08-12T00:00:00Z"},"state":"ACTIVE"},{"schema":"unknown"}]}"#
        let partial = try unwrap(TransferReceiptDecoder.decode(Data(malformed.utf8)))
        precondition(partial.receipts.count == 1 && partial.malformedEntries == 1)
        precondition(TransferReceiptDecoder.decode(Data("{}".utf8)) == nil)
        precondition(TransferReceiptDecoder.decode(Data(#"{"schema":"choam.transfer-receipt.v1","transferId":"bad id","attemptId":"try-1","timestamps":{"commandAcceptedAt":"x"},"state":"ACTIVE"}"#.utf8)) == nil)
        print("TransferReceiptConsumerTests passed")
    }

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "TransferReceiptConsumerTests", code: 1) }
        return value
    }
}
