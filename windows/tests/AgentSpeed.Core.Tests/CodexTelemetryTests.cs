using System.Globalization;
using System.Text;
using System.Text.Json;
using AgentSpeed.Core.Engine;
using AgentSpeed.Core.Parsing;
using AgentSpeed.Core.Telemetry;

namespace AgentSpeed.Core.Tests;

public sealed class CodexTelemetryTests
{
    private const string Thread = "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb";
    private const long Base = 1_800_000_000_000;
    private static string Event(string kind, long ms, Dictionary<string, string>? extra = null, string thread = Thread)
    {
        var attributes = new Dictionary<string, string> { ["event.name"] = kind,
            ["event.timestamp"] = DateTimeOffset.FromUnixTimeMilliseconds(ms).ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture),
            ["conversation.id"] = thread, ["model"] = "m" };
        foreach (var pair in extra ?? []) attributes[pair.Key] = pair.Value;
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer))
        {
            writer.WriteStartObject(); writer.WriteStartArray("attributes");
            foreach (var pair in attributes)
            {
                writer.WriteStartObject(); writer.WriteString("key", pair.Key); writer.WriteStartObject("value");
                writer.WriteString("stringValue", pair.Value); writer.WriteEndObject(); writer.WriteEndObject();
            }
            writer.WriteEndArray(); writer.WriteEndObject();
        }
        return Encoding.UTF8.GetString(buffer.ToArray());
    }
    private static byte[] Batch(params string[] events) => Encoding.UTF8.GetBytes("{\"resourceLogs\":[{\"scopeLogs\":[{\"logRecords\":[" + string.Join(',', events) + "]}]}]}");
    private static ParsedResponse Response(long tokens, long end, long logMs) => new($"r-{end}", SourceKind.Codex,
        $"rollout-{Thread}.jsonl", "m", end - 20000, end, new TokenCounts(Output: tokens)) { FirstMs = end - logMs };

    [Fact]
    public void Reproduces133AndMeasures44UsingItsOwnTransportEvents()
    {
        var tracker = new CodexTelemetryTracker();
        long[] tokens = [170, 205, 218], decode = [5071, 5270, 3216], ttft = [9183, 10768, 9234],
            ends = [Base + 20000, Base + 36069, Base + 48548], logs = [990, 2545, 908];
        var events = new List<string>();
        for (var i = 0; i < 3; i++)
        {
            events.Add(Event("codex.websocket_request", ends[i] - decode[i] - ttft[i], new() { ["duration_ms"] = "0" }));
            events.Add(Event("codex.sse_event", ends[i], new() { ["event.kind"] = "response.completed",
                ["output_token_count"] = tokens[i].ToString(CultureInfo.InvariantCulture), ["ttft_ms"] = ttft[i].ToString(CultureInfo.InvariantCulture) }));
        }
        var data = Batch(events.ToArray()); var samples = tracker.Consume(data);
        Assert.Equal(3, samples.Count); Assert.Empty(tracker.Consume(data));
        var records = Enumerable.Range(0, 3).Select(i => Response(tokens[i], ends[i], logs[i])).ToArray();
        Assert.InRange(593000.0 / 4443, 133.46, 133.48);
        var rates = MeasuredRateWindow.Measure(records, ends[2], samples)!;
        Assert.InRange(rates.Total.Output, 43.51, 43.53); Assert.Equal(3, rates.SampleCount);
        Assert.Null(MeasuredRateWindow.Measure(records, ends[2]));
        var engine = new SpeedEngine(Base);
        foreach (var r in records) engine.Upsert(r, true, false);
        engine.SetCodexMeasurements(samples);
        var frame = engine.Compute(ends[2], Base, false);
        Assert.Equal(9234, frame.LastResponse!.TtftMs);
        Assert.InRange(frame.IntervalRates.Total.Output, 43.51, 43.53);
        Assert.InRange(frame.LastResponse.Speed!.Value, 67.47, 67.48);
    }

    [Fact]
    public void InterruptedRequestsOtherThreadsAndUnmeasurableBursts()
    {
        var tracker = new CodexTelemetryTracker();
        var samples = tracker.Consume(Batch(Event("codex.websocket_request", Base), Event("codex.websocket_request", Base + 10000),
            Event("codex.websocket_request", Base + 11000, thread: "other"),
            Event("codex.sse_event", Base + 14000, new() { ["event.kind"] = "response.completed", ["output_token_count"] = "101", ["ttft_ms"] = "2000" }),
            Event("codex.sse_event", Base + 15000, new() { ["event.kind"] = "response.completed", ["output_token_count"] = "4", ["ttft_ms"] = "4000" }, "other")));
        Assert.Equal(2, samples.Count); Assert.Equal(2000, samples[0].DecodeMs); Assert.Null(samples[1].DecodeMs);
        var response = Response(101, Base + 14000, 1);
        Assert.True(samples[0].Matches(response)); Assert.False(samples[0].Matches(response with { AgentId = "other-thread" }));
    }

    [Fact]
    public void ExcludesWrongEndpointsMissingStartsAndImpossibleTiming()
    {
        var tracker = new CodexTelemetryTracker();
        Assert.Empty(tracker.Consume(Batch(Event("codex.api_request", Base, new() { ["endpoint"] = "/models" }),
            Event("codex.sse_event", Base + 1000, new() { ["event.kind"] = "response.completed", ["output_token_count"] = "100", ["ttft_ms"] = "500" }),
            Event("codex.websocket_request", Base + 2000),
            Event("codex.sse_event", Base + 3000, new() { ["event.kind"] = "response.completed", ["output_token_count"] = "1000", ["ttft_ms"] = "999" }))));
    }
}
