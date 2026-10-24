import XCTest
@testable import MagpieWatch

final class ConsumptionTests: XCTestCase {
    private func decode<T: Decodable>(_ text: String, as: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(text.utf8))
    }

    func testLedgerReplacesTraceCountsWithoutDoublingCachedInput() throws {
        let trace = try decode(#"{"routes":[{"id":1,"done":false,"usage":[{"in":900,"out":10,"cache_read":6000}]}]}"#, as: TraceResponse.self)
        let ledger = try decode(#"{"rows":[{"route_id":1,"in":120,"out":30,"cache_read":1000,"reasoning":20,"status":200}]}"#, as: UsageRequestsResponse.self)
        let records = ConsumptionRecord.merge(trace: trace, ledger: ledger)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].input, 120)
        XCTAssertEqual(records[0].cacheRead, 1000)
        XCTAssertEqual(records[0].output, 30)
        XCTAssertEqual(records[0].reasoning, 20)
        XCTAssertTrue(records[0].done)
    }

    func testUnknownCountsRemainUnknownAndZeroRemainsMeasured() throws {
        let trace = try decode(#"{"routes":[{"id":1,"done":false},{"id":2,"done":true,"usage":[{"in":0,"out":0,"cache_read":0}]}]}"#, as: TraceResponse.self)
        let records = ConsumptionRecord.merge(trace: trace, ledger: nil)
        XCTAssertNil(records.first { $0.id == "1" }?.input)
        XCTAssertEqual(records.first { $0.id == "2" }?.input, 0)
    }

    func testPurposeAndPromptBreakdownDecodeActualMagpieShape() throws {
        let trace = try decode(#"{"routes":[{"id":1,"kind":"memory_consolidation","prompt":{"tokens":150,"counted":true,"parts":[{"kind":"results","tokens":100,"items":[{"name":"exec_command","tag":"result","n":2,"tokens":100}]},{"kind":"tools","tokens":50}]}}]}"#, as: TraceResponse.self)
        let record = try XCTUnwrap(ConsumptionRecord.merge(trace: trace, ledger: nil).first)
        XCTAssertEqual(record.purpose, "记忆整理")
        XCTAssertEqual(record.prompt?.parts?.first?.title, "工具执行返回")
        XCTAssertEqual(record.prompt?.parts?.first?.items?.first?.n, 2)
        let desktop = DesktopConsumptionSummary.make(record)
        XCTAssertNil(desktop.input, "Context counts must not be presented as billed input")
        XCTAssertTrue(desktop.context.contains("工具执行返回 100 令牌"))
        XCTAssertTrue(desktop.context.contains("exec_command"))
        let ledger = try decode(#"{"rows":[{"route_id":1,"compaction":true}]}"#, as: UsageRequestsResponse.self)
        XCTAssertEqual(ConsumptionRecord.merge(trace: trace, ledger: ledger).first?.purpose, "上下文压缩")
    }

    func testLedgerOnlyRequestsAndMultipleAttemptsAreRetained() throws {
        let ledger = try decode(#"{"rows":[{"route_id":1,"in":10,"out":1},{"route_id":1,"in":20,"out":2},{"route_id":2,"kind":"thread_title","in":50}]}"#, as: UsageRequestsResponse.self)
        let records = ConsumptionRecord.merge(trace: nil, ledger: ledger)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first { $0.id == "1" }?.input, 30)
        XCTAssertEqual(records.first { $0.id == "2" }?.purpose, "标题生成")
    }

    func testQuotaPercentAndMissingBalanceAreNotConvertedToMoney() throws {
        let quota = try decode(#"{"provider":"codex","user":"a@example.com","windows":[{"name":"5 hours","used":78,"remaining":22},{"name":"7 days","used":40}]}"#, as: Quota.self)
        let summary = DesktopAccountSummary.make(quota, masked: true)
        XCTAssertEqual(summary.remainingPercent, 22)
        XCTAssertTrue(summary.balance.contains("剩余 22%"))
        XCTAssertTrue(summary.balance.contains("剩余 60%"))
        XCTAssertNotEqual(summary.account, "a@example.com")
        XCTAssertTrue(summary.account.contains("•••"))
        let empty = try decode(#"{"provider":"unknown"}"#, as: Quota.self)
        XCTAssertEqual(DesktopAccountSummary.make(empty, masked: true).balance, "余额 / 额度未提供")
    }
}
