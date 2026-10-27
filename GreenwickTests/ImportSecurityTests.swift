import XCTest
@testable import Greenwick

/// Malformed, huge and hostile CSV input must never crash, hang or store absurd numbers.
final class ImportSecurityTests: XCTestCase {

    private let tosHeader = "Exec Time,Symbol,Side,Qty,Price,Net Price,P/L,Commission"

    private func writeTemp(_ content: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("greenwick-sec-\(UUID().uuidString).csv")
        try content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    private func importAll(_ path: String) throws -> [Trade] {
        let detection = try GenericCSVParser.detect(fileAt: path)
        guard let mapping = detection.mapping else { return [] }
        return try GenericCSVParser.parse(fileAt: path, mapping: mapping)
    }

    func testNonFiniteAndAbsurdNumbersAreRejected() throws {
        let rows = [
            "03/24/26 09:31:15,AAPL,BUY,inf,171.25,171.30,25.00,0.65",
            "03/24/26 09:32:15,AAPL,BUY,nan,171.25,171.30,25.00,0.65",
            "03/24/26 09:33:15,AAPL,BUY,1e308,171.25,171.30,25.00,0.65",
            "03/24/26 09:34:15,AAPL,BUY,-0,171.25,171.30,25.00,0.65",
            "03/24/26 09:35:15,AAPL,BUY,100,171.25,171.30,1e300,0.65",
            "03/24/26 09:36:15,AAPL,BUY,100,171.25,171.30,25.00,0.65",
        ]
        let trades = try importAll(try writeTemp(([tosHeader] + rows).joined(separator: "\n")))
        for trade in trades {
            XCTAssertTrue(trade.shares.isFinite && trade.shares > 0 && trade.shares <= GenericCSVParser.maxShares)
            XCTAssertFalse(trade.netProfit.isNaN)
            XCTAssertLessThanOrEqual(abs(trade.netProfit), GenericCSVParser.maxAbsAmount)
        }
        // Only the rows with valid share counts survive (the 1e300 P&L row is kept with P&L 0)
        XCTAssertEqual(trades.count, 2)
        _ = MetricsCalculator.calculate(from: trades) // must not trap
    }

    func testFIFONonFiniteQuantitiesDoNotHang() throws {
        let header = "Activity Date,Process Date,Settle Date,Account Type,Instrument,Description,Trans Code,Quantity,Price,Amount,Suppressed"
        let csv = [header,
                   "3/24/2026,3/24/2026,3/26/2026,Brokerage,XYZ,x,Buy,inf,$1.00,$1,",
                   "3/24/2026,3/24/2026,3/26/2026,Brokerage,XYZ,x,Sell,inf,$2.00,$1,",
                   "3/24/2026,3/24/2026,3/26/2026,Brokerage,XYZ,x,Buy,10,$NaN,$1,"].joined(separator: "\n")
        XCTAssertEqual(try importAll(try writeTemp(csv)).count, 0)
    }

    func testMalformedLinesDoNotCrash() throws {
        let rows = [
            "\"unterminated,quote,field",
            ",,,,,,,",
            "03/24/26 09:31:15,=HYPERLINK(\"http://example.invalid\"),BUY,1,1,1,1,1",
            String(repeating: "A", count: 200_000),
            "03/24/26 09:31:15,AAPL,SIDEWAYS,100,171.25,171.30,25.00,0.65",
            "not a date,AAPL,BUY,100,171.25,171.30,25.00,0.65",
            "\u{0000}\u{FFFD}\u{202E}garbage,\u{1F4A9},BUY,1,1,1,1,1",
        ]
        let trades = try importAll(try writeTemp(([tosHeader] + rows).joined(separator: "\n")))
        for trade in trades {
            XCTAssertTrue(trade.symbol.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." })
            XCTAssertLessThanOrEqual(trade.symbol.count, 10)
        }
    }

    func testEmptyAndHeaderOnlyFiles() throws {
        XCTAssertThrowsError(try GenericCSVParser.detect(fileAt: try writeTemp("")))
        XCTAssertEqual(((try? importAll(try writeTemp(tosHeader))) ?? []).count, 0)
    }

    func testBinaryFileDoesNotCrash() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("greenwick-bin-\(UUID().uuidString).csv")
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i &* 7919) }
        try Data(bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        _ = try? importAll(url.path)
    }

    func testOversizedFileIsRefusedWithoutReading() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("greenwick-big-\(UUID().uuidString).csv")
        FileManager.default.createFile(atPath: url.path, contents: Data(tosHeader.utf8))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(GenericCSVParser.maxFileSize + 1)) // sparse, instant
        try handle.close()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try GenericCSVParser.detect(fileAt: url.path)) { error in
            guard case GenericCSVParser.GenericParseError.fileTooLarge = error else {
                return XCTFail("Expected fileTooLarge, got \(error)")
            }
        }
    }

    func testLargeValidFileParsesInReasonableTime() throws {
        var lines = [tosHeader]
        lines.reserveCapacity(20_001)
        for i in 0..<20_000 {
            let minute = i % 60, hour = 9 + (i / 60) % 7
            lines.append(String(format: "03/24/26 %02d:%02d:%02d,SYM%d,BUY,10,100.00,100.00,%d.00,0.10",
                                hour, minute, i % 60, i % 50, (i % 7) - 3))
        }
        let path = try writeTemp(lines.joined(separator: "\n"))
        let start = Date()
        let trades = try importAll(path)
        XCTAssertEqual(trades.count, 20_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 60, "20k rows should parse well within a minute")
    }

    func testFileNotFoundErrorDoesNotLeakFullPath() {
        XCTAssertThrowsError(try GenericCSVParser.detect(fileAt: "/nonexistent/dir/secret-name.csv")) { error in
            XCTAssertFalse(error.localizedDescription.contains("/nonexistent/dir"))
        }
    }
}
