using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using AgentSpeed.Core.Parsing;
using AgentSpeed.Core.Remote;

namespace AgentSpeed.Core.Telemetry;

internal sealed record CodexMeasurement(string Thread, string Model, long EndMs, long Output, double DurationMs, double TtftMs)
{
    public double? DecodeMs => Output > 1 && DurationMs - TtftMs > 50 && (Output - 1) * 1000.0 / (DurationMs - TtftMs) <= 1500
        ? DurationMs - TtftMs : null;
    public bool Matches(ParsedResponse r) => r.Source == SourceKind.Codex && r.Host == RemoteHost.LocalId
        && r.AgentId.Contains(Thread, StringComparison.Ordinal) && r.Model == Model && r.Tokens.Output == Output && Math.Abs(r.EndMs - EndMs) <= 100;
}

internal sealed class CodexTelemetryTracker
{
    private readonly Dictionary<string, Dictionary<string, List<double>>> _starts = [];
    private readonly HashSet<string> _seen = [];

    public IReadOnlyList<CodexMeasurement> Consume(ReadOnlyMemory<byte> body)
    {
        using var doc = JsonDocument.Parse(body);
        var records = new List<Dictionary<string, JsonElement>>();
        if (!doc.RootElement.TryGetProperty("resourceLogs", out var resources)) return [];
        foreach (var resource in resources.EnumerateArray())
        {
            if (!resource.TryGetProperty("scopeLogs", out var scopes)) continue;
            foreach (var scope in scopes.EnumerateArray())
            {
                if (!scope.TryGetProperty("logRecords", out var logs)) continue;
                foreach (var log in logs.EnumerateArray())
                {
                    if (!log.TryGetProperty("attributes", out var attributes)) continue;
                    var a = new Dictionary<string, JsonElement>();
                    foreach (var attribute in attributes.EnumerateArray())
                    {
                        if (!attribute.TryGetProperty("key", out var key) || key.GetString() is not { } name
                            || !attribute.TryGetProperty("value", out var value)) continue;
                        foreach (var field in value.EnumerateObject())
                            if (field.Name is "stringValue" or "intValue" or "doubleValue") { a[name] = field.Value; break; }
                    }
                    records.Add(a);
                }
            }
        }
        var result = new List<CodexMeasurement>();
        foreach (var a in records.OrderBy(a => Text(a, "event.timestamp"), StringComparer.Ordinal))
        {
            var thread = Text(a, "conversation.id"); var model = Text(a, "model"); var stamp = Text(a, "event.timestamp");
            if (thread is null || model is null || !DateTimeOffset.TryParse(stamp, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)) continue;
            var end = (date - DateTimeOffset.UnixEpoch).TotalMilliseconds;
            var name = Text(a, "event.name");
            if (name == "codex.websocket_request" || name == "codex.api_request" && Text(a, "endpoint") == "/responses")
            {
                var sent = end - (Number(a, "duration_ms") ?? 0);
                if (!_starts.TryGetValue(thread, out var models)) _starts[thread] = models = [];
                if (!models.TryGetValue(model, out var pending)) models[model] = pending = [];
                if (!pending.Contains(sent)) pending.Add(sent);
                pending.Sort(); if (pending.Count > 16) pending.RemoveRange(0, pending.Count - 16);
            }
            else if (name == "codex.sse_event" && Text(a, "event.kind") == "response.completed"
                && Number(a, "output_token_count") is > 0 and <= 1e12 && Number(a, "ttft_ms") is >= 0)
            {
                var output = Number(a, "output_token_count")!.Value; var ttft = Number(a, "ttft_ms")!.Value;
                var id = $"{thread}|{stamp}|{model}";
                if (_seen.Contains(id) || !_starts.TryGetValue(thread, out var models)) continue;
                var limit = end - ttft + 50;
                var key = model;
                if (!models.TryGetValue(key, out var pending) || !pending.Any(t => t <= limit))
                {
                    var alternatives = models.Where(m => m.Value.Any(t => t <= limit)).ToArray();
                    if (alternatives.Length != 1) continue;
                    key = alternatives[0].Key; pending = alternatives[0].Value;
                }
                var index = pending.FindLastIndex(t => t <= limit); if (index < 0) continue;
                var sent = pending[index]; var duration = end - sent; var generation = duration - ttft;
                if (duration <= 50 || duration > 1_800_000 || generation < -50 || generation > 10_000 + output * 200
                    || output >= 64 && (generation <= 50 || (output - 1) * 1000 / generation > 1500)) continue;
                pending.RemoveAt(index); _seen.Add(id);
                result.Add(new(thread, model, (long)Math.Round(end), (long)output, duration, Math.Min(ttft, duration)));
            }
            foreach (var models in _starts.Values)
                foreach (var pending in models.Values) pending.RemoveAll(t => t < end - 1_800_000);
        }
        if (_seen.Count > 20_000) _seen.Clear();
        return result;
    }
    private static string? Text(Dictionary<string, JsonElement> a, string key) =>
        a.TryGetValue(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    private static double? Number(Dictionary<string, JsonElement> a, string key)
    {
        if (!a.TryGetValue(key, out var v)) return null;
        double n;
        var ok = v.ValueKind == JsonValueKind.String
            ? double.TryParse(v.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out n)
            : v.TryGetDouble(out n);
        return ok && double.IsFinite(n) ? n : null;
    }
}

/// <summary>Own loopback OTLP receiver. Stores measurements only; no prompts or response bodies are saved.</summary>
public sealed class CodexTelemetry
{
    public static CodexTelemetry Shared { get; } = new();
    public const int Port = 43181;
    private readonly object _gate = new();
    private readonly CodexTelemetryTracker _tracker = new();
    private readonly string _directory;
    private List<CodexMeasurement> _samples = [];
    private TcpListener? _listener;
    private bool _loaded;
    private string? _error;
    private static readonly HttpClient Relay = new() { Timeout = TimeSpan.FromSeconds(2) };
    public CodexTelemetry(string? directory = null) => _directory = directory ?? Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AgentSpeed");
    internal IReadOnlyList<CodexMeasurement> Samples { get { lock (_gate) { Load(); return _samples.ToArray(); } } }
    public string Status { get { lock (_gate) return _error ?? (_listener is null ? "not listening" : "listening on 127.0.0.1:43181"); } }
    public void Start()
    {
        lock (_gate)
        {
            if (_listener is not null) return;
            Load();
            try { _listener = new TcpListener(IPAddress.Loopback, Port); _listener.Start(); _ = Accept(_listener); }
            catch (SocketException) { _listener = null; _error = "Codex telemetry listener unavailable"; }
        }
    }
    private async Task Accept(TcpListener listener)
    {
        while (true)
        {
            try { var client = await listener.AcceptTcpClientAsync().ConfigureAwait(false); _ = Serve(client); }
            catch (SocketException) { return; }
        }
    }
    private async Task Serve(TcpClient client)
    {
        using (client)
        {
            try
            {
                var stream = client.GetStream(); var one = new byte[1];
                while (true)
                {
                    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
                    var header = new List<byte>();
                    while (header.Count < 16384)
                    {
                        if (await stream.ReadAsync(one, timeout.Token).ConfigureAwait(false) == 0) return;
                        header.Add(one[0]);
                        if (header.Count >= 4 && header[^4] == 13 && header[^3] == 10 && header[^2] == 13 && header[^1] == 10) break;
                    }
                    var lines = Encoding.ASCII.GetString(header.ToArray()).Split("\r\n");
                    var contentLength = lines.FirstOrDefault(l => l.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase));
                    if (contentLength is null || !int.TryParse(contentLength.Split(':', 2)[1].Trim(), out var length) || length < 0 || length > 4 << 20) return;
                    var body = new byte[length]; await stream.ReadExactlyAsync(body, timeout.Token).ConfigureAwait(false);
                    var accepted = lines[0].StartsWith("POST /v1/logs ", StringComparison.Ordinal);
                    if (accepted)
                    {
                        lock (_gate) Ingest(body);
                        _ = Forward(body);
                    }
                    var response = Encoding.ASCII.GetBytes($"HTTP/1.1 {(accepted ? "200 OK" : "404 Not Found")}\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{{}}");
                    await stream.WriteAsync(response, timeout.Token).ConfigureAwait(false);
                }
            }
            catch (Exception e) when (e is IOException or SocketException or OperationCanceledException or JsonException or InvalidOperationException) { }
        }
    }
    private void Load()
    {
        if (_loaded) return; _loaded = true;
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(_directory, "codex-measurements.json")));
            foreach (var r in doc.RootElement.EnumerateArray())
                _samples.Add(new(r.GetProperty("thread").GetString()!, r.GetProperty("model").GetString()!, r.GetProperty("endMs").GetInt64(),
                    r.GetProperty("output").GetInt64(), r.GetProperty("durationMs").GetDouble(), r.GetProperty("ttftMs").GetDouble()));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or KeyNotFoundException or InvalidOperationException) { _samples.Clear(); }
    }
    private void Ingest(byte[] body)
    {
        var fresh = _tracker.Consume(body); if (fresh.Count == 0) return;
        _samples = _samples.Concat(fresh).DistinctBy(r => (r.Thread, r.EndMs, r.Model)).OrderBy(r => r.EndMs).TakeLast(10000).ToList();
        try
        {
            Directory.CreateDirectory(_directory);
            using var buffer = new MemoryStream();
            using (var writer = new Utf8JsonWriter(buffer))
            {
                writer.WriteStartArray();
                foreach (var r in _samples)
                {
                    writer.WriteStartObject(); writer.WriteString("thread", r.Thread); writer.WriteString("model", r.Model);
                    writer.WriteNumber("endMs", r.EndMs); writer.WriteNumber("output", r.Output);
                    writer.WriteNumber("durationMs", r.DurationMs); writer.WriteNumber("ttftMs", r.TtftMs); writer.WriteEndObject();
                }
                writer.WriteEndArray();
            }
            var path = Path.Combine(_directory, "codex-measurements.json");
            File.WriteAllBytes(path + ".tmp", buffer.ToArray()); File.Move(path + ".tmp", path, true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { _error = "Codex telemetry persistence unavailable"; }
    }
    private async Task Forward(byte[] body)
    {
        try
        {
            var text = File.ReadAllText(Path.Combine(_directory, "codex-telemetry-forward.txt")).Trim();
            if (!Uri.TryCreate(text, UriKind.Absolute, out var url) || url.Scheme != "http" || url.Host != "127.0.0.1" || url.Port == Port) return;
            using var content = new ByteArrayContent(body); content.Headers.ContentType = new("application/json");
            using var response = await Relay.PostAsync(url, content).ConfigureAwait(false);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or HttpRequestException or OperationCanceledException) { }
    }
}
