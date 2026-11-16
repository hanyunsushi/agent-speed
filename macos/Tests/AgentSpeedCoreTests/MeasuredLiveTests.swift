import Foundation
import Testing
@testable import AgentSpeedCore

@Suite("Measured live rates")
struct MeasuredLiveTests {
    @Test func measuredAgentMeanExcludesWaitingAndIdleWithoutOutput() {
        let now: Int64 = 1_800_000_010_000
        var engine = SpeedEngine()
        for (id, tokens) in [("a", 120), ("b", 240), ("waiting", 0)] {
            engine.setAgent(EngineAgent(id: id, source: .codex, project: "p", phase: .generating,
                                        inFlightStartMs: now - 3000, lastLineMs: now))
            if tokens > 0 {
                engine.upsert(ResponseRecord(key: id, source: .codex, agentId: id, model: "m", startMs: now - 4000,
                                             endMs: now, usage: TokenUsage(output: tokens), firstMs: now - 3000),
                              project: "p", isCompletion: true, emitsEvents: false)
            }
        }
        let output = engine.advance(nowMs: now, todayStartMs: now - 10_000, emitsEvents: false)
        let snapshot = SnapshotBuilder.running(output, context: .fixture(todayStartMs: now - 10_000))
        #expect(abs(snapshot.live.output - 120) < 1e-9)
        #expect(abs(snapshot.averageLive.output - 60) < 1e-9)
        #expect(snapshot.liveEstimatedShare == 0)
        #expect(snapshot.history.allSatisfy { $0.estimated == .zero })
        let expired = engine.advance(nowMs: now + 4000, todayStartMs: now - 10_000, emitsEvents: false)
        let idle = SnapshotBuilder.running(expired, context: .fixture(todayStartMs: now - 10_000))
        #expect(idle.live == .zero && idle.averageLive == .zero)
    }

    @Test func waitingDoesNotBorrowItsOwnOrAnotherAgentsHistory() {
        let now: Int64 = 1_800_000_010_000
        var engine = SpeedEngine()
        engine.setAgent(EngineAgent(id: "a", source: .codex, project: "p", model: "m", phase: .generating,
                                    inFlightStartMs: now - 2000, lastLineMs: now))
        engine.upsert(ResponseRecord(key: "old", source: .codex, agentId: "a", model: "m", startMs: now - 9000,
                                     endMs: now - 5000, usage: TokenUsage(output: 200)),
                      project: "p", isCompletion: true, emitsEvents: false)
        var pending = ResponseRecord(key: "new", source: .codex, agentId: "a", model: "m", startMs: now - 2000,
                                     endMs: now, usage: TokenUsage(output: 90), isFinal: false, firstMs: now - 1000)
        engine.upsert(pending, project: "p", isCompletion: false, emitsEvents: false)
        #expect(engine.advance(nowMs: now, todayStartMs: now - 10_000, emitsEvents: false).live == .zero)
        pending.isFinal = true
        engine.upsert(pending, project: "p", isCompletion: true, emitsEvents: false)
        let once = engine.advance(nowMs: now, todayStartMs: now - 10_000, emitsEvents: false)
        #expect(once.live.output == 30) // 90 confirmed tokens in the 3-second window
        engine.upsert(pending, project: "p", isCompletion: true, emitsEvents: false)
        #expect(engine.advance(nowMs: now, todayStartMs: now - 10_000, emitsEvents: false).live == once.live)
        #expect(once.lastResponse?.ttftMs == nil) // Transcript item time is not a measured first token.
        #expect(once.lastResponse?.speed == nil)
    }
}
