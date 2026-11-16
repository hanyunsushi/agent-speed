import Foundation

/// Confirmed response averages over 30 seconds ending at the latest measured completion, not the ticking wall clock.
public struct MeasuredRateWindow: Equatable, Sendable {
    public static let durationMs: Int64 = 30_000
    public static let empty = MeasuredRateWindow()
    public var endedAtMs: Int64?
    public var sampleCount: Int = 0
    public var byAgent: [String: Rate] = [:]

    public init(endedAtMs: Int64? = nil, sampleCount: Int = 0, byAgent: [String: Rate] = [:]) {
        self.endedAtMs = endedAtMs
        self.sampleCount = sampleCount
        self.byAgent = byAgent
    }

    public var total: Rate {
        byAgent.values.reduce(.zero) { Rate(output: $0.output + $1.output, total: $0.total + $1.total) }
    }

    public var average: Rate {
        guard !byAgent.isEmpty else { return .zero }
        return Rate(output: total.output / Double(byAgent.count), total: total.total / Double(byAgent.count))
    }

    /// No sample means unknown; callers retain the last observed window during an idle gap.
    static func measure(_ records: [ResponseRecord], nowMs: Int64, codex: [CodexMeasurement] = []) -> MeasuredRateWindow? {
        let measured = records.filter { $0.isFinal && $0.endMs <= nowMs && $0.usage.output > 0 }.compactMap { record -> (record: ResponseRecord, output: Double, total: Double, ms: Double)? in
            if record.source == .codex {
                guard let sample = codex.first(where: { $0.matches(record) }), let ms = sample.decodeMs else { return nil }
                return (record, Double(sample.output - 1), Double(record.usage.total - 1), ms)
            }
            guard let timed = TimedResponse(record) else { return nil }
            return (record, timed.output, timed.total, Double(timed.durationMs))
        }
        guard let end = measured.map({ $0.record.endMs }).max() else { return nil }
        var sums: [String: (output: Double, total: Double, ms: Double)] = [:]
        var count = 0
        for response in measured where response.record.endMs >= end - durationMs {
            let id = response.record.agentId
            var sum = sums[id] ?? (0, 0, 0)
            sum.output += response.output
            sum.total += response.total
            sum.ms += response.ms
            sums[id] = sum
            count += 1
        }
        let rates = sums.mapValues { Rate(output: $0.output * 1000 / $0.ms, total: $0.total * 1000 / $0.ms) }
        return MeasuredRateWindow(endedAtMs: end, sampleCount: count, byAgent: rates)
    }
}
