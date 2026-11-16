import Foundation
import Network

/// A completed request measured by Codex's own transport clock; never derived from transcript item timestamps.
struct CodexMeasurement: Codable, Equatable, Sendable {
    var thread: String
    var model: String
    var endMs: Int64
    var output: Int
    var durationMs: Double
    var ttftMs: Double
    var decodeMs: Double? {
        let ms = durationMs - ttftMs
        guard output > 1, ms > 50, Double(output - 1) * 1000 / ms <= 1500 else { return nil }
        return ms
    }
    func matches(_ record: ResponseRecord) -> Bool {
        record.source == .codex && record.host == RemoteHost.localId && record.agentId.contains(thread)
            && record.model == model && record.usage.output == output && abs(record.endMs - endMs) <= 100
    }
}

/// Pairs transport requests and completions independently of any other TPS application.
struct CodexTelemetryTracker {
    private var starts: [String: [String: [Double]]] = [:]
    private var seen: Set<String> = []

    mutating func consume(_ data: Data) -> [CodexMeasurement] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var records: [[String: Any]] = []
        for resource in root["resourceLogs"] as? [[String: Any]] ?? [] {
            for scope in resource["scopeLogs"] as? [[String: Any]] ?? [] {
                for log in scope["logRecords"] as? [[String: Any]] ?? [] {
                    var attributes: [String: Any] = [:]
                    for pair in log["attributes"] as? [[String: Any]] ?? [] {
                        if let key = pair["key"] as? String, let value = pair["value"] as? [String: Any] {
                            attributes[key] = value["stringValue"] ?? value["intValue"] ?? value["doubleValue"]
                        }
                    }
                    records.append(attributes)
                }
            }
        }
        records.sort { ($0["event.timestamp"] as? String ?? "") < ($1["event.timestamp"] as? String ?? "") }
        var result: [CodexMeasurement] = []
        for a in records {
            guard let thread = a["conversation.id"] as? String, let model = a["model"] as? String,
                  let stamp = a["event.timestamp"] as? String,
                  let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(stamp) else { continue }
            let end = date.timeIntervalSince1970 * 1000
            let event = a["event.name"] as? String
            if event == "codex.websocket_request" || (event == "codex.api_request" && a["endpoint"] as? String == "/responses") {
                let sent = end - (Self.number(a["duration_ms"]) ?? 0)
                var pending = starts[thread, default: [:]][model, default: []]
                if !pending.contains(sent) { pending.append(sent) }
                starts[thread, default: [:]][model] = Array(pending.sorted().suffix(16))
            } else if event == "codex.sse_event", a["event.kind"] as? String == "response.completed",
                      let output = Self.number(a["output_token_count"]), output > 0, output <= 1e12,
                      let ttft = Self.number(a["ttft_ms"]), ttft >= 0 {
                let id = "\(thread)|\(stamp)|\(model)"
                guard !seen.contains(id) else { continue }
                let limit = end - ttft + 50
                var candidates = starts[thread] ?? [:]
                var key = model
                if candidates[key]?.contains(where: { $0 <= limit }) != true {
                    let alternatives = candidates.filter { $0.value.contains { $0 <= limit } }
                    guard alternatives.count == 1, let other = alternatives.keys.first else { continue }
                    key = other
                }
                guard var pending = candidates[key], let index = pending.lastIndex(where: { $0 <= limit }) else { continue }
                let sent = pending.remove(at: index)
                let duration = end - sent
                let generation = duration - ttft
                guard duration > 50, duration <= 1_800_000, generation >= -50,
                      generation <= 10_000 + output * 200,
                      output < 64 || (generation > 50 && (output - 1) * 1000 / generation <= 1500) else { continue }
                candidates[key] = pending
                starts[thread] = candidates
                seen.insert(id)
                result.append(CodexMeasurement(thread: thread, model: model, endMs: Int64(end.rounded()), output: Int(output),
                                               durationMs: duration, ttftMs: min(ttft, duration)))
            }
            starts = starts.compactMapValues { models in
                let kept = models.compactMapValues { values in
                    let recent = values.filter { $0 >= end - 1_800_000 }
                    return recent.isEmpty ? nil : recent
                }
                return kept.isEmpty ? nil : kept
            }
        }
        if seen.count > 20_000 { seen.removeAll(keepingCapacity: true) }
        return result
    }
    private static func number(_ value: Any?) -> Double? {
        let n: Double? = if let s = value as? String { Double(s) } else if let n = value as? NSNumber { n.doubleValue } else { nil }
        return n.flatMap { $0.isFinite ? $0 : nil }
    }
}

/// Own loopback OTLP receiver. Persists only numeric measurements and identities, never prompt/response bodies.
public final class CodexTelemetry: @unchecked Sendable {
    public static let shared = CodexTelemetry()
    public static let port: UInt16 = 43181
    private let queue = DispatchQueue(label: "app.agentspeed.codex-telemetry", qos: .utility)
    private var tracker = CodexTelemetryTracker()
    private var measurements: [CodexMeasurement] = []
    private var listener: NWListener?
    private let directory: URL
    private var loaded = false
    private var error: String?

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Agent Speed")) {
        self.directory = directory
    }
    var samples: [CodexMeasurement] { queue.sync { load(); return measurements } }
    public var status: String { queue.sync { error ?? (listener == nil ? "not listening" : "listening on 127.0.0.1:43181") } }

    public func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            load()
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            do {
                let server = try NWListener(using: parameters)
                server.stateUpdateHandler = { [weak self] state in
                    if case .failed = state { self?.error = "Codex telemetry listener unavailable" }
                }
                server.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    connection.start(queue: queue)
                    receive(connection, buffer: Data())
                }
                listener = server
                server.start(queue: queue)
            } catch { self.error = "Codex telemetry listener unavailable" }
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, failure in
            guard let self else { connection.cancel(); return }
            var buffer = buffer + (data ?? Data())
            guard buffer.count <= 4 << 20 else { connection.cancel(); return }
            while let header = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let lines = String(decoding: buffer[..<header.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
                let lengths = lines.dropFirst().compactMap { line -> Int? in
                    let parts = line.split(separator: ":", maxSplits: 1)
                    return parts.count == 2 && parts[0].lowercased() == "content-length" ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
                }
                guard let length = lengths.first, length >= 0, length <= 4 << 20 else { connection.cancel(); return }
                let start = header.upperBound
                guard buffer.count - start >= length else { break }
                let body = Data(buffer[start..<(start + length)])
                let accepted = lines.first?.hasPrefix("POST /v1/logs ") == true
                if accepted { ingest(body); forward(body) }
                let response = "HTTP/1.1 \(accepted ? "200 OK" : "404 Not Found")\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
                buffer = Data(buffer[(start + length)...])
            }
            if done || failure != nil { connection.cancel() } else { receive(connection, buffer: buffer) }
        }
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        if let data = try? Data(contentsOf: directory.appendingPathComponent("codex-measurements.json")),
           let saved = try? JSONDecoder().decode([CodexMeasurement].self, from: data) { measurements = saved }
    }
    private func ingest(_ body: Data) {
        let fresh = tracker.consume(body)
        guard !fresh.isEmpty else { return }
        var keyed = Dictionary(measurements.map { ("\($0.thread)|\($0.endMs)|\($0.model)", $0) }, uniquingKeysWith: { _, new in new })
        for sample in fresh { keyed["\(sample.thread)|\(sample.endMs)|\(sample.model)"] = sample }
        measurements = Array(keyed.values.sorted { $0.endMs < $1.endMs }.suffix(10_000))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(measurements)
            try data.write(to: directory.appendingPathComponent("codex-measurements.json"), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent("codex-measurements.json").path)
        } catch { self.error = "Codex telemetry persistence unavailable" }
    }
    private func forward(_ body: Data) {
        // Optional compatibility relay to the pre-existing loopback exporter, never a data source for this app.
        guard let text = try? String(contentsOf: directory.appendingPathComponent("codex-telemetry-forward.txt"), encoding: .utf8),
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "http",
              url.host == "127.0.0.1", url.port != Int(Self.port) else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = body
        request.timeoutInterval = 2; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request).resume()
    }
}
