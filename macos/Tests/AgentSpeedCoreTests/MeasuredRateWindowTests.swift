import Foundation
import Testing
@testable import AgentSpeedCore

@Suite("30-second measured rates")
struct MeasuredRateWindowTests {
    private let now: Int64 = 1_800_000_100_000
    private func response(_ key: String, _ agent: String, _ end: Int64, _ duration: Int64, _ tokens: Int,
                          final: Bool = true) -> ResponseRecord {
        ResponseRecord(key: key, source: .claudeCode, agentId: agent, model: "m", startMs: end - duration - 1000,
                       endMs: end, usage: TokenUsage(output: tokens), isFinal: final, firstMs: end - duration)
    }

    @Test func pooledDurationsAndIndependentAgents() throws {
        let records = [response("a1", "parent", now - 10000, 1000, 100),
                       response("a2", "parent", now, 3000, 600), response("b", "child", now, 2000, 100)]
        let rates = try #require(MeasuredRateWindow.measure(records, nowMs: now))
        #expect(rates.sampleCount == 3)
        #expect(rates.byAgent["parent"]?.output == 175) // 700 / 4 seconds, not (100 + 200) / 2
        #expect(rates.byAgent["child"]?.output == 50)
        #expect(rates.total.output == 225 && rates.average.output == 112.5)
        #expect(rates.total.total == 225)
    }

    @Test func completionBoundaryIncludesThirtySeconds() throws {
        let records = [response("latest", "a", now, 1000, 100), response("29", "b", now - 29000, 1000, 200),
                       response("30", "c", now - 30000, 1000, 300), response("31", "d", now - 31000, 1000, 9999)]
        let rates = try #require(MeasuredRateWindow.measure(records, nowMs: now))
        #expect(rates.sampleCount == 3 && rates.total.output == 600 && rates.average.output == 200)
        #expect(rates.endedAtMs == now && MeasuredRateWindow.durationMs == 30000)
    }

    @Test func invalidAndUnfinishedSamplesCannotAdvanceTheWindow() throws {
        var invalid = response("invalid", "bad", now, 1000, 9999)
        invalid.startMs = nil
        let records = [response("good", "a", now - 10000, 1000, 100), invalid,
                       response("pending", "bad", now, 1000, 9999, final: false),
                       response("future", "bad", now + 1000, 1000, 9999), response("zero", "bad", now, 1000, 0)]
        let rates = try #require(MeasuredRateWindow.measure(records, nowMs: now))
        #expect(rates.sampleCount == 1 && rates.endedAtMs == now - 10000 && rates.total.output == 100)
        #expect(MeasuredRateWindow.measure([], nowMs: now) == nil)
        #expect(MeasuredRateWindow.empty.total == .zero && MeasuredRateWindow.empty.average == .zero)
    }

    @Test func idleHoldsMeasuredResultAndNewCompletionRefreshesWithoutDuplicates() {
        var engine = SpeedEngine()
        let first = response("r", "a", now, 1000, 100)
        engine.upsert(first, project: "p", isCompletion: true, emitsEvents: false)
        func read(_ engine: inout SpeedEngine, _ time: Int64) -> MeasuredRateWindow {
            engine.advance(nowMs: time, todayStartMs: now - 100000, emitsEvents: false).intervalRates
        }
        let initial = read(&engine, now)
        for gap: Int64 in [4000, 60000, 86_400_000] { #expect(read(&engine, now + gap) == initial) }
        let next = response("new", "b", now + 86_401_000, 2000, 600)
        engine.upsert(next, project: "p", isCompletion: true, emitsEvents: false)
        engine.upsert(next, project: "p", isCompletion: true, emitsEvents: false)
        let output = engine.advance(nowMs: next.endMs, todayStartMs: now - 100000, emitsEvents: false)
        #expect(output.intervalRates.sampleCount == 1 && output.intervalRates.total.output == 300)
        let snapshot = SnapshotBuilder.running(output, context: .fixture(todayStartMs: now - 100000))
        #expect(snapshot.intervalRates == output.intervalRates)
    }
    @Test func retentionDoesNotPartiallyRecalculateAnIdleWindowAndCorrectionsRefresh() {
        var engine = SpeedEngine()
        engine.upsert(response("old", "a", now - 10000, 1000, 100), project: "p", isCompletion: true, emitsEvents: false)
        engine.upsert(response("latest", "a", now, 3000, 600), project: "p", isCompletion: true, emitsEvents: false)
        #expect(engine.advance(nowMs: now, todayStartMs: now - 100000, emitsEvents: false).intervalRates.total.output == 175)
        engine.upsert(response("latest", "a", now, 3000, 900), project: "p", isCompletion: true, emitsEvents: false)
        let corrected = engine.advance(nowMs: now, todayStartMs: now - 100000, emitsEvents: false).intervalRates
        #expect(corrected.total.output == 250)
        let idle = engine.advance(nowMs: now + SpeedEngine.retentionMs - 5000, todayStartMs: now - 1000, emitsEvents: false)
        #expect(idle.intervalRates == corrected)
    }

    @Test func measuredWindowDrivesSharedStatusDuringReplayIdleGap() {
        var snapshot = SpeedSnapshot.empty
        snapshot.live = Rate(output: 0, total: 0)
        snapshot.timestamp = Date(timeIntervalSince1970: TimeInterval(now) / 1000)
        snapshot.intervalRates = MeasuredRateWindow(endedAtMs: now, sampleCount: 2,
                                                     byAgent: ["a": Rate(output: 120, total: 120)])
        #expect(snapshot.statusRate == snapshot.intervalRates.total)

        snapshot.timestamp = Date(timeIntervalSince1970: TimeInterval(now + MeasuredRateWindow.durationMs + 1) / 1000)
        #expect(snapshot.statusRate == snapshot.live)

        snapshot.intervalRates = .empty
        snapshot.live = Rate(output: 17, total: 34)
        #expect(snapshot.statusRate == snapshot.live)
    }

}
