import Foundation

@main
struct TransferReceiptConsumerTests {
    static func main() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("fixtures/transfer-receipts-v1.json")
        let fixture = try Data(contentsOf: fixtureURL)
        let decoded = try unwrap(TransferReceiptDecoder.decode(fixture))
        precondition(decoded.malformedEntries == 0)
        precondition(decoded.receipts.count == 5)
        precondition(decoded.receipts[0].state == .deferred)
        precondition(decoded.receipts[0].presentation == .pending)
        precondition(decoded.receipts[1].state == .active)
        precondition(decoded.receipts[1].presentation == .running)
        precondition(decoded.receipts[2].state == .completed)
        precondition(decoded.receipts[2].presentation == .verificationRequired)
        precondition(decoded.receipts[2].presentation.status != "completed")
        precondition(decoded.receipts[3].state == .failed)
        precondition(decoded.receipts[3].presentation.needsAttention)
        precondition(decoded.receipts[4].state == .cancelled)
        precondition(decoded.receipts[4].presentation.needsAttention)

        let activeReceipt = #"{"schema":"choam.transfer-receipt.v1","transferId":"ok-1","attemptId":"try-1","sourceAuthority":{"label":"source-a"},"destinationAuthority":{"label":"destination-a"},"route":{"generation":0,"fingerprint":"route-fingerprint-00"},"expectedBytes":1,"timestamps":{"commandAcceptedAt":"2026-08-12T00:00:00Z"},"state":"ACTIVE"}"#
        let malformed = #"{"schema":"choam.transfer-receipts.v1","transferReceipts":["# + activeReceipt + #",{"schema":"unknown"}]}"#
        let partial = try unwrap(TransferReceiptDecoder.decode(Data(malformed.utf8)))
        precondition(partial.receipts.count == 1 && partial.malformedEntries == 1)
        precondition(TransferReceiptDecoder.decode(Data("{}".utf8)) == nil)
        precondition(TransferReceiptDecoder.decode(Data(activeReceipt.replacingOccurrences(of: #""sourceAuthority":{"label":"source-a"},"#, with: "").utf8))?.isMalformed == true)
        precondition(TransferReceiptDecoder.decode(Data(activeReceipt.replacingOccurrences(of: "2026-08-12T00:00:00Z", with: "not-an-instant").utf8))?.isMalformed == true)
        precondition(TransferReceiptDecoder.decode(Data(activeReceipt.replacingOccurrences(of: #","expectedBytes":1"#, with: "").utf8))?.isMalformed == true)
        let malformedOptionalTimestamp = activeReceipt.replacingOccurrences(of: #""commandAcceptedAt":"2026-08-12T00:00:00Z""#, with: #""commandAcceptedAt":"2026-08-12T00:00:00Z","startedAt":"not-an-instant""#)
        precondition(TransferReceiptDecoder.decode(Data(malformedOptionalTimestamp.utf8))?.isMalformed == true)
        let malformedOptionalFailure = activeReceipt.replacingOccurrences(of: #""state":"ACTIVE""#, with: #""state":"FAILED","failureCode":"not-valid""#)
        precondition(TransferReceiptDecoder.decode(Data(malformedOptionalFailure.utf8))?.isMalformed == true)
        let incompleteCompletion = activeReceipt.replacingOccurrences(of: #""state":"ACTIVE""#, with: #""state":"COMPLETED""#)
        precondition(TransferReceiptDecoder.decode(Data(incompleteCompletion.utf8))?.isMalformed == true)
        print("TransferReceiptConsumerTests passed")
    }

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "TransferReceiptConsumerTests", code: 1) }
        return value
    }
}
