import XCTest
@testable import MagpieWatch

final class PetActivityTests: XCTestCase {
    private func flow(_ id: String, stage: WallpaperHopStage, outcome: WallpaperFlowOutcome = .ok) -> WallpaperPacketFlow {
        WallpaperPacketFlow(id: id, agentID: "agent", destinationID: "model", stage: stage,
                            requestTokens: 100, responseTokens: 40, outcome: outcome, statusCode: nil)
    }

    func testCompletedTraceReactsOnlyOnceAcrossPollingAndHideShow() {
        var tracker = PetActivityTracker()
        let finished = [flow("one", stage: .returning)]
        XCTAssertEqual(tracker.next(online: true, flows: finished).state, "success")
        XCTAssertEqual(tracker.next(online: true, flows: finished).state, "idle")
        XCTAssertEqual(tracker.next(online: false, flows: finished).state, "offline")
        XCTAssertEqual(tracker.next(online: true, flows: finished).state, "idle")
    }

    func testConcurrentWorkIsNotInterruptedByCompletion() {
        var tracker = PetActivityTracker()
        let finished = flow("one", stage: .returning, outcome: .failed)
        XCTAssertEqual(tracker.next(online: true, flows: [finished, flow("two", stage: .outbound)]).state, "tool")
        XCTAssertEqual(tracker.next(online: true, flows: [finished]).state, "idle")
    }

    func testRouteStagesAndNewFailureAreDistinguishable() {
        var tracker = PetActivityTracker()
        XCTAssertEqual(tracker.next(online: true, flows: [flow("one", stage: .waiting)]).state, "waiting")
        XCTAssertEqual(tracker.next(online: true, flows: [flow("one", stage: .incoming)]).state, "thinking")
        XCTAssertEqual(tracker.next(online: true, flows: [flow("one", stage: .outbound)]).state, "tool")
        XCTAssertEqual(tracker.next(online: true, flows: [flow("one", stage: .returning, outcome: .rateLimited)]).state, "failure")
        XCTAssertEqual(tracker.next(online: true, flows: [flow("one", stage: .returning, outcome: .rateLimited)]).state, "idle")
    }
}
