using AgentSpeed.Core.Engine;
using AgentSpeed.Core.Parsing;

namespace AgentSpeed.Core.Tests;

public sealed class MeasuredRateWindowTests
{
    private const long Now = 1_800_000_100_000;
    private static ParsedResponse Response(string key, string agent, long end, long duration, long tokens, bool final = true) =>
        new(key, SourceKind.ClaudeCode, agent, "m", end - duration - 1000, end, new TokenCounts(Output: tokens), final)
        { FirstMs = end - duration };

    [Fact]
    public void PooledDurationsAndIndependentAgents()
    {
        var rates = MeasuredRateWindow.Measure([Response("a1", "parent", Now - 10000, 1000, 100),
            Response("a2", "parent", Now, 3000, 600), Response("b", "child", Now, 2000, 100)], Now)!;
        Assert.Equal(3, rates.SampleCount);
        Assert.Equal(175, rates.ByAgent["parent"].Output);
        Assert.Equal(50, rates.ByAgent["child"].Output);
        Assert.Equal(225, rates.Total.Output);
        Assert.Equal(112.5, rates.Average.Output);
    }

    [Fact]
    public void CompletionBoundaryIncludesThirtySeconds()
    {
        var rates = MeasuredRateWindow.Measure([Response("latest", "a", Now, 1000, 100),
            Response("29", "b", Now - 29000, 1000, 200), Response("30", "c", Now - 30000, 1000, 300),
            Response("31", "d", Now - 31000, 1000, 9999)], Now)!;
        Assert.Equal(3, rates.SampleCount);
        Assert.Equal(600, rates.Total.Output);
        Assert.Equal(200, rates.Average.Output);
        Assert.Equal(Now, rates.EndedAtMs);
        Assert.Equal(30000, MeasuredRateWindow.DurationMs);
    }

    [Fact]
    public void InvalidAndUnfinishedSamplesCannotAdvanceTheWindow()
    {
        var rates = MeasuredRateWindow.Measure([Response("good", "a", Now - 10000, 1000, 100),
            Response("invalid", "bad", Now, 1000, 9999) with { StartMs = null },
            Response("pending", "bad", Now, 1000, 9999, false), Response("future", "bad", Now + 1000, 1000, 9999),
            Response("zero", "bad", Now, 1000, 0)], Now)!;
        Assert.Equal(1, rates.SampleCount);
        Assert.Equal(Now - 10000, rates.EndedAtMs);
        Assert.Equal(100, rates.Total.Output);
        Assert.Null(MeasuredRateWindow.Measure([], Now));
        Assert.Equal(Rate.Zero, MeasuredRateWindow.Empty.Average);
    }

    [Fact]
    public void IdleHoldsMeasuredResultAndNewCompletionRefreshesWithoutDuplicates()
    {
        var engine = new SpeedEngine(Now - 100000);
        engine.Upsert(Response("r", "a", Now, 1000, 100), true, false);
        var first = engine.Compute(Now, Now - 100000, false).IntervalRates;
        foreach (var gap in new long[] { 4000, 60000, 86_400_000 })
        {
            var idle = engine.Compute(Now + gap, Now - 100000, false).IntervalRates;
            Assert.Equal(first.Total, idle.Total);
            Assert.Equal(first.EndedAtMs, idle.EndedAtMs);
        }
        var next = Response("new", "b", Now + 86_401_000, 2000, 600);
        engine.Upsert(next, true, false);
        engine.Upsert(next, true, false);
        var updated = engine.Compute(next.EndMs, Now - 100000, false).IntervalRates;
        Assert.Equal(1, updated.SampleCount);
        Assert.Equal(300, updated.Total.Output);
    }
    [Fact]
    public void RetentionDoesNotPartiallyRecalculateAnIdleWindowAndCorrectionsRefresh()
    {
        var engine = new SpeedEngine(Now - 100000);
        engine.Upsert(Response("old", "a", Now - 10000, 1000, 100), true, false);
        engine.Upsert(Response("latest", "a", Now, 3000, 600), true, false);
        Assert.Equal(175, engine.Compute(Now, Now - 100000, false).IntervalRates.Total.Output);
        engine.Upsert(Response("latest", "a", Now, 3000, 900), true, false);
        var corrected = engine.Compute(Now, Now - 100000, false).IntervalRates;
        Assert.Equal(250, corrected.Total.Output);
        var idle = engine.Compute(Now + SpeedEngine.RetentionMs - 5000, Now - 1000, false).IntervalRates;
        Assert.Equal(corrected.Total, idle.Total);
        Assert.Equal(corrected.SampleCount, idle.SampleCount);
    }

}
