using AgentSpeed.Core.Engine;
using AgentSpeed.Core.Parsing;

namespace AgentSpeed.Core.Tests;

public sealed class MeasuredLiveTests
{
    [Fact]
    public void ConfirmedAgentSpeedsHaveAnArithmeticMeanWithoutWaitingAgents()
    {
        var snapshot = SpeedSnapshot.Empty with
        {
            Live = new Rate(180),
            Agents = new[] { 60.0, 120.0, 0.0 }.Select((value, index) =>
                new AgentStatus($"a{index}", SourceKind.Codex, "p", "m", AgentPhase.Generating, false,
                    new Rate(value), 999, DateTimeOffset.UnixEpoch)).ToArray(),
        };
        Assert.Equal(90, snapshot.AverageLive.Output);
        Assert.Equal(Rate.Zero, SpeedSnapshot.Empty.AverageLive);
    }

    [Fact]
    public void InFlightAndUnfinalizedUsageDoNotBorrowHistoricalRates()
    {
        const long now = 1_800_000_010_000;
        var engine = new SpeedEngine(now - 10_000);
        engine.UpdateAgent(new AgentInfo("a", SourceKind.Codex, "p", "m", false, AgentPhase.Generating, now - 2000, now));
        engine.Upsert(new ParsedResponse("old", SourceKind.Codex, "a", "m", now - 9000, now - 5000, new TokenCounts(Output: 200)), true, true);
        var pending = new ParsedResponse("new", SourceKind.Codex, "a", "m", now - 2000, now, new TokenCounts(Output: 90), false) { FirstMs = now - 1000 };
        engine.Upsert(pending, false, false);
        Assert.Equal(Rate.Zero, engine.Compute(now, now - 10_000, false).Live);
        pending = pending with { Final = true };
        engine.Upsert(pending, true, false);
        var frame = engine.Compute(now, now - 10_000, false);
        Assert.Equal(30, frame.Live.Output);
        Assert.Equal(0, frame.EstimatedShare);
        Assert.All(frame.History, point => Assert.Equal(Rate.Zero, point.Estimated));
        engine.Upsert(pending, true, false);
        Assert.Equal(frame.Live, engine.Compute(now, now - 10_000, false).Live);
    }
}
