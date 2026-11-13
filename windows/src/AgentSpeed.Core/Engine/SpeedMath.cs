using AgentSpeed.Core.Parsing;

namespace AgentSpeed.Core.Engine;

internal readonly record struct Interval(long StartMs, long EndMs)
{
    public long DurationMs => EndMs - StartMs;
}

/// <summary>Response timing rules (METRICS 3.3).</summary>
internal static class SpeedMath
{
    public const long MaxIntervalMs = 15 * 60_000;
    /// <summary>The decode interval <c>[first token, end]</c>, falling back to request start when first content is unknown.</summary>
    public static bool TryGetSpeedInterval(ParsedResponse response, out Interval interval)
    {
        if (response.StartMs is not { } start || response.EndMs < start || response.EndMs - start > MaxIntervalMs)
        {
            interval = default;
            return false;
        }

        var effectiveStart = response.FirstMs is { } first && first >= start && first < response.EndMs ? first : start;
        if (response.EndMs <= effectiveStart)
        {
            interval = default;
            return false;
        }
        interval = new Interval(effectiveStart, response.EndMs);
        return true;
    }

    public static long Overlap(long a0, long a1, long b0, long b1) => Math.Max(0, Math.Min(a1, b1) - Math.Max(a0, b0));

    public static long FloorDiv(long value, long divisor)
    {
        var quotient = value / divisor;
        return value % divisor != 0 && (value < 0) != (divisor < 0) ? quotient - 1 : quotient;
    }
}
