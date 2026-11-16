import Foundation
import Testing
@testable import AgentSpeedCore

@Suite("Independent Codex telemetry")
struct CodexTelemetryTests {
    private let thread = "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"
    private let base = 1_800_000_000_000.0
    private func event(_ kind: String, _ ms: Double, _ extra: [String: String] = [:], thread: String? = nil) -> [String: Any] {
        let stamp = Date(timeIntervalSince1970: ms / 1000).ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true)) + "Z"
        let attributes = ["event.name": kind, "event.timestamp": stamp, "conversation.id": thread ?? self.thread, "model": "m"].merging(extra) { _, b in b }
        return ["attributes": attributes.sorted { $0.key < $1.key }.map { ["key": $0.key, "value": ["stringValue": $0.value]] }]
    }
    private func batch(_ records: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["resourceLogs": [["scopeLogs": [["logRecords": records]]]]])
    }
    private func response(_ tokens: Int, _ end: Int64, _ logMs: Int64) -> ResponseRecord {
        ResponseRecord(key: "r-\(end)", source: .codex, agentId: "rollout-\(thread).jsonl", model: "m",
                       startMs: end - 20000, endMs: end, usage: TokenUsage(output: tokens), firstMs: end - logMs)
    }

    @Test func reproduces133AndMeasures44UsingItsOwnTransportEvents() throws {
        var tracker = CodexTelemetryTracker()
        let tokens = [170, 205, 218], decode = [5071.0, 5270.0, 3216.0], ttft = [9183.0, 10768.0, 9234.0]
        let ends = [base + 20000, base + 36069, base + 48548]
        var events: [[String: Any]] = []
        for i in 0..<3 {
            events.append(event("codex.websocket_request", ends[i] - decode[i] - ttft[i], ["duration_ms": "0"]))
            events.append(event("codex.sse_event", ends[i], ["event.kind": "response.completed", "output_token_count": "\(tokens[i])", "ttft_ms": "\(ttft[i])"]))
        }
        let data = try batch(events)
        let samples = tracker.consume(data)
        #expect(samples.count == 3 && tracker.consume(data).isEmpty)
        let records = (0..<3).map { response(tokens[$0], Int64(ends[$0]), [990, 2545, 908][$0]) }
        let bad = 593000.0 / 4443
        #expect(abs(bad - 133.47) < 0.01)
        let rates = try #require(MeasuredRateWindow.measure(records, nowMs: Int64(ends[2]), codex: samples))
        #expect(abs(rates.total.output - 43.52) < 0.01 && rates.sampleCount == 3)
        #expect(MeasuredRateWindow.measure(records, nowMs: Int64(ends[2])) == nil)
        var engine = SpeedEngine()
        for r in records { engine.upsert(r, project: "p", isCompletion: true, emitsEvents: false) }
        engine.setCodexMeasurements(samples)
        let output = engine.advance(nowMs: Int64(ends[2]), todayStartMs: Int64(base), emitsEvents: false)
        #expect(output.lastResponse?.ttftMs == 9234)
        #expect(abs(output.intervalRates.total.output - 43.52) < 0.01)
        #expect(output.lastResponse?.speed.map { abs($0 - 217000.0 / 3216) < 0.01 } == true)
    }

    @Test func interruptedRequestsOtherThreadsAndUnmeasurableBursts() throws {
        var tracker = CodexTelemetryTracker()
        let a = event("codex.websocket_request", base)
        let b = event("codex.websocket_request", base + 10000)
        let other = event("codex.websocket_request", base + 11000, thread: "other")
        let end = event("codex.sse_event", base + 14000, ["event.kind": "response.completed", "output_token_count": "101", "ttft_ms": "2000"])
        let short = event("codex.sse_event", base + 15000, ["event.kind": "response.completed", "output_token_count": "4", "ttft_ms": "4000"], thread: "other")
        let samples = tracker.consume(try batch([end, a, other, b, short]))
        #expect(samples.count == 2)
        guard samples.count == 2 else { return }
        #expect(samples[0].decodeMs.map { abs($0 - 2000) < 1 } == true)
        #expect(samples[1].decodeMs == nil)
        let mismatched = response(101, Int64(base + 14000), 1)
        #expect(samples[0].matches(mismatched))
        var different = mismatched; different.agentId = "other-thread"
        #expect(!samples[0].matches(different))
    }

    @Test func excludesWrongEndpointsMissingStartsAndImpossibleTiming() throws {
        var tracker = CodexTelemetryTracker()
        let data = try batch([event("codex.api_request", base, ["endpoint": "/models"]),
            event("codex.sse_event", base + 1000, ["event.kind": "response.completed", "output_token_count": "100", "ttft_ms": "500"]),
            event("codex.websocket_request", base + 2000),
            event("codex.sse_event", base + 3000, ["event.kind": "response.completed", "output_token_count": "1000", "ttft_ms": "999"])])
        #expect(tracker.consume(data).isEmpty)
    }
}
