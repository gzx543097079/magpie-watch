import XCTest
@testable import MagpieWatch

final class WallpaperBoardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_713_600)

    private func board(routes: [[String: Any]], online: Bool = true) throws -> WallpaperFlowBoard {
        let json = try JSONSerialization.data(withJSONObject: ["routes": routes])
        let trace = try JSONDecoder().decode(TraceResponse.self, from: json)
        return WallpaperBoardBuilder.make(usage: nil, trace: trace, service: nil, isOnline: online, now: now)
    }

    private func route(_ id: Int, model: String = "model-a") -> [String: Any] {
        ["id": id, "time": ISO8601DateFormatter().string(from: now.addingTimeInterval(-3)),
         "agent": "codex", "provider": "example", "model": model, "done": false]
    }

    func testConcurrentRequestsFromOneAgentKeepBothDestinations() throws {
        let board = try board(routes: [route(1), route(2, model: "model-b")])
        XCTAssertEqual(board.flows.count, 2)
        XCTAssertEqual(board.agents.count, 1)
        XCTAssertEqual(board.destinations.count, 2)
        XCTAssertEqual(Set(board.flows.map(\.id)), ["route-1", "route-2"])
    }

    func testTokenVolumesComeFromRouteUsageIncludingCache() throws {
        var request = route(3)
        request["usage"] = [["in": 120, "cacheRead": 500, "out": 80]]
        let flow = try XCTUnwrap(board(routes: [request]).flows.first)
        XCTAssertEqual(flow.requestTokens, 620)
        XCTAssertEqual(flow.responseTokens, 80)
    }

    func testRateLimitReturnsAnErrorWithoutInventingTokens() throws {
        var request = route(4)
        request["done"] = true
        request["status"] = 429
        request["ms"] = 300
        let flow = try XCTUnwrap(board(routes: [request]).flows.first)
        XCTAssertEqual(flow.stage, .returning)
        XCTAssertEqual(flow.outcome, .rateLimited)
        XCTAssertEqual(flow.requestTokens, 0)
        XCTAssertEqual(flow.responseTokens, 0)
    }

    func testOldFinishedRequestDoesNotReplay() throws {
        var request = route(5)
        request["time"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        request["done"] = true
        request["ms"] = 200
        XCTAssertTrue(try board(routes: [request]).flows.isEmpty)
    }

    func testActiveOnlyBoardHidesIdleAgentsAndModels() throws {
        let usageJSON = try JSONSerialization.data(withJSONObject: [
            "agents": [["id": "codex", "name": "Codex", "calls": 9], ["id": "curl", "name": "Curl", "calls": 2]],
            "models": [["provider": "example", "model": "model-a", "calls": 9], ["provider": "example", "model": "idle", "calls": 4]]
        ])
        let usage = try JSONDecoder().decode(UsageResponse.self, from: usageJSON)
        let trace = try JSONDecoder().decode(TraceResponse.self, from: JSONSerialization.data(withJSONObject: ["routes": [route(6)]]))
        let board = WallpaperBoardBuilder.make(usage: usage, trace: trace, service: nil, isOnline: true, activeOnly: true, now: now)
        XCTAssertEqual(board.agents.map(\.id), ["codex"])
        XCTAssertEqual(board.agents.first?.calls, 9)
        XCTAssertEqual(board.destinations.count, 1)
        let idle = WallpaperBoardBuilder.make(usage: usage, trace: nil, service: nil, isOnline: true, activeOnly: true, now: now)
        XCTAssertTrue(idle.agents.isEmpty && idle.destinations.isEmpty)
    }

    func testDashboardSumsNaturalWeekAndMonthFromDailySeries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 2026-10-23 is a Friday; the week starts Monday 10-19, the month on 10-01.
        let friday = ISO8601DateFormatter().date(from: "2026-10-23T12:00:00-07:00")!
        func day(_ date: String, _ input: Int) -> [String: Any] {
            ["time": "\(date)T00:00:00-07:00", "input": input, "output": 1, "cache_read": 0, "cache_write": 0, "calls": 1, "cost": 0.5]
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let daily = try decoder.decode(UsageResponse.self, from: JSONSerialization.data(withJSONObject: [
            "series": [day("2026-09-30", 1000), day("2026-10-05", 100), day("2026-10-19", 10), day("2026-10-23", 1)]
        ]))
        let today = try decoder.decode(UsageResponse.self, from: JSONSerialization.data(withJSONObject: [
            "input": 30, "cache_read": 70, "output": 5, "calls": 4, "timed": 2, "ttft_ms": 3000, "decode_ms": 2000, "decode_out": 100,
            "models": [["model": "m", "provider": "codex", "sub": "Codex · someone.private@example.com", "calls": 4]]
        ]))
        let board = WallpaperDashboard.make(today: today, daily: daily, now: friday, calendar: calendar)
        XCTAssertEqual(board.periods[0]?.cacheShare, 70)
        XCTAssertEqual(board.periods[1]?.input, 11)
        XCTAssertEqual(board.periods[2]?.input, 111)
        XCTAssertEqual(board.ttftMs, 1500)
        XCTAssertEqual(board.decodeRate, 50)
        XCTAssertFalse(board.models[0].sub.contains("someone.private@example.com"), "Passive views mask account emails")
        XCTAssertNil(WallpaperDashboard.make(today: today, daily: nil, now: friday, calendar: calendar).periods[1])
    }
}
