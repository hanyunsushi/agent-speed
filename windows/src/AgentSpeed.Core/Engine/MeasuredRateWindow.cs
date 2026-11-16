using AgentSpeed.Core.Parsing;
using AgentSpeed.Core.Telemetry;

namespace AgentSpeed.Core.Engine;

/// <summary>Confirmed response averages in the 30 seconds ending at the latest measured completion.</summary>
public sealed record MeasuredRateWindow(long? EndedAtMs, int SampleCount, IReadOnlyDictionary<string, Rate> ByAgent)
{
    public const long DurationMs = 30_000;
    public static MeasuredRateWindow Empty { get; } = new(null, 0, new Dictionary<string, Rate>());
    public Rate Total => new(ByAgent.Values.Sum(r => r.Output), ByAgent.Values.Sum(r => r.Total));
    public Rate Average => ByAgent.Count == 0 ? Rate.Zero : new(Total.Output / ByAgent.Count, Total.Total / ByAgent.Count);

    internal static MeasuredRateWindow? Measure(IEnumerable<ParsedResponse> responses, long nowMs, IReadOnlyList<CodexMeasurement>? codex = null)
    {
        var measured = responses.Where(r => r.Final && r.EndMs <= nowMs && r.Tokens.Output > 0)
            .Select(r =>
            {
                if (r.Source == SourceKind.Codex)
                {
                    var sample = codex?.FirstOrDefault(s => s.Matches(r));
                    return (Response: r, Output: (double)(sample?.Output - 1 ?? 0), Total: (double)r.Tokens.Total - 1,
                        Ms: sample?.DecodeMs ?? 0);
                }
                return (Response: r, Output: (double)r.Tokens.Output, Total: (double)r.Tokens.Total,
                    Ms: SpeedMath.TryGetSpeedInterval(r, out var interval) ? (double)interval.DurationMs : 0);
            }).Where(r => r.Ms > 0).ToArray();
        if (measured.Length == 0) return null;
        var end = measured.Max(r => r.Response.EndMs);
        var pool = measured.Where(r => r.Response.EndMs >= end - DurationMs).ToArray();
        var rates = pool.GroupBy(r => r.Response.AgentId).ToDictionary(g => g.Key, g =>
        {
            var seconds = g.Sum(r => (double)r.Ms) / 1000;
            return new Rate(g.Sum(r => (double)r.Output) / seconds,
                g.Sum(r => (double)r.Total) / seconds);
        });
        return new(end, pool.Length, rates);
    }
}
