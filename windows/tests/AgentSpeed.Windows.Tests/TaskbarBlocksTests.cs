using AgentSpeed.Core.Intelligence;
using AgentSpeed.Core.Traffic;
using AgentSpeed.Presentation.Formatting;
using AgentSpeed.Presentation.Localization;
using AgentSpeed.Core.Perf;
using AgentSpeed.Presentation.Perf;
using AgentSpeed.Taskbar;
using AgentSpeed.Presentation.Settings;
using AgentSpeed.Presentation.Orb;
using System.Runtime.InteropServices;

namespace AgentSpeed.Windows.Tests;

/// <summary>
/// The taskbar widget with its readout blocks (DESIGN 10, Menu bar and taskbar): the network block and the intelligence
/// block each add their fixed width, alone or together, and the widget never changes width with their values.
/// </summary>
public class TaskbarBlocksTests
{
    private static readonly Localizer ZhHant = new(Localizer.LoadEmbeddedTable(), LanguageCodes.ZhHant);

    private static TaskbarState Widget(BarTrafficBlock? traffic, BarIntelligenceBlock? intelligence) =>
        TaskbarState.Initial with { Enabled = true, Value = 532, Traffic = traffic, Intelligence = intelligence };

    private static BarTrafficBlock Network(string rx, string tx) =>
        new(new TrafficFormat.Parts(rx, "MB/s"), new TrafficFormat.Parts(tx, "KB/s"), false, null);

    private static BarIntelligenceBlock Score(int? shown, double thinking) => BarIntelligenceBlock.Of(
        shown is null ? PerfSetReading.None : new PerfSetReading(PerfForm.Live, shown, false, 1, null, null),
        new IntelligenceSums(thinking > 0 ? 3 * thinking : 0, 3 * thinking, 3 * thinking), ZhHant);

    [Theory]
    [InlineData(1.0)]
    [InlineData(1.25)]
    [InlineData(1.5)]
    [InlineData(2.0)]
    public void BothBlocksAddTheirFixedWidthsAndNeverMoveWithTheValues(double scale)
    {
        var (plain, network, intelligence, both, others) = OnStaThread(() =>
        {
            var renderer = new TaskbarRenderer();
            int Length(TaskbarState state) => renderer.MeasureLength(state, scale, vertical: false);
            var traffic = Network("1.28", "64.0");
            var score = Score(1286, 128);
            var variants = new[]
            {
                Length(Widget(Network("0", "0"), Score(null, 0))),
                Length(Widget(Network("8.88", "888"), Score(8_888, 8_880))),
                Length(Widget(Network("8.88", "888"), Score(99_960, 8_880))),
                Length(Widget(new BarTrafficBlock(null, null, false, null), Score(940, 0.4))),
            };
            return (Length(Widget(null, null)), Length(Widget(traffic, null)), Length(Widget(null, score)), Length(Widget(traffic, score)), variants);
        });

        // Whole pixels per measure: the sum may round by one pixel.
        Assert.True(network > plain && intelligence > plain);
        Assert.InRange(both - plain, network - plain + intelligence - plain - 1, network - plain + intelligence - plain + 1);
        Assert.All(others, length => Assert.Equal(both, length));
    }

    [Fact]
    public void PairedTokenModesRenderDistinctlyAndBalancesReserveTheirOwnSpace()
    {
        OnStaThread(() =>
        {
            var renderer = new TaskbarRenderer();
            var baseline = TaskbarState.Initial with { Enabled = true, Value = 180, AverageValue = 90, TokensMeasured = true };
            var pictures = new List<byte[]>();
            foreach (var mode in new[] { BarDisplayMode.GlyphAndValue, BarDisplayMode.GlyphOnly, BarDisplayMode.ValueOnly })
            {
                var state = baseline with { Mode = mode };
                var width = renderer.MeasureLength(state, 1, false);
                var buffer = Marshal.AllocHGlobal(width * 40 * 4);
                try {
                    renderer.Render(state, new BarScene(), width, 40, 1, false, false, false, buffer, width * 40 * 4);
                    var bytes = new byte[width * 40 * 4]; Marshal.Copy(buffer, bytes, 0, bytes.Length); pictures.Add(bytes);
                } finally { Marshal.FreeHGlobal(buffer); }
            }
            Assert.False(pictures[0].SequenceEqual(pictures[1]));
            Assert.False(pictures[0].SequenceEqual(pictures[2]));
            Assert.False(pictures[1].SequenceEqual(pictures[2]));
            Assert.True(renderer.MeasureLength(baseline with { BalanceText = "Provider $20" }, 1, false) > renderer.MeasureLength(baseline, 1, false));
            Assert.True(renderer.MeasureLength(baseline with { BalanceText = "Provider $20" }, 1, true) > renderer.MeasureLength(baseline, 1, true));
            return true;
        });
    }

    [Theory]
    [InlineData(1.0, false)]
    [InlineData(1.5, false)]
    [InlineData(2.0, false)]
    [InlineData(1.0, true)]
    [InlineData(1.5, true)]
    [InlineData(2.0, true)]
    public void BalanceClicksFollowTheDrawnRegionAndClearWhenHidden(double scale, bool vertical)
    {
        OnStaThread(() =>
        {
            var renderer = new TaskbarRenderer();
            var state = TaskbarState.Initial with {
                Enabled = true, Value = 180, AverageValue = 90, TokensMeasured = true, BalanceText = "Provider $20"
            };
            // Include retained extra space while the widget waits to shrink.
            var length = renderer.MeasureLength(state, scale, vertical) + 40;
            var width = vertical ? (int)(84 * scale) : length;
            var height = vertical ? length : (int)(40 * scale);
            var bytes = width * height * 4;
            var buffer = Marshal.AllocHGlobal(bytes);
            try {
                renderer.Render(state, new BarScene(), width, height, scale, vertical, false, false, buffer, bytes);
                var hit = renderer.BalanceHitRect;
                Assert.False(hit.IsEmpty);
                Assert.True(hit.Contains(new System.Windows.Point(hit.X + hit.Width / 2, hit.Y + hit.Height / 2)));
                Assert.False(hit.Contains(new System.Windows.Point(0, 0)));
                if (vertical) Assert.True(hit.Y >= 8 + 28 * 2 + 6);
                else Assert.True(hit.X >= 8 + 28 * 2 + 6);
                renderer.Render(state with { BalanceText = null }, new BarScene(), width, height, scale,
                    vertical, false, false, buffer, bytes);
                Assert.True(renderer.BalanceHitRect.IsEmpty);
            } finally { Marshal.FreeHGlobal(buffer); }
            return true;
        });
    }

    private static T OnStaThread<T>(Func<T> work)
    {
        T result = default!;
        Exception? error = null;
        var thread = new Thread(() =>
        {
            try
            {
                result = work();
            }
            catch (Exception ex)
            {
                error = ex;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        return error is null ? result : throw new InvalidOperationException("Measuring failed.", error);
    }
}
