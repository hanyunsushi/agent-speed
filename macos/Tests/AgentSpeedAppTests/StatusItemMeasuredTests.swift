import AgentSpeedCore
import AppKit
import Testing
@testable import AgentSpeed

@Suite("Measured menu bar")
@MainActor
struct StatusItemMeasuredTests {
    @Test func tokensUseTwoRingsAndNeverDrawUnitsOrTTFTOutsideThem() throws {
        _ = NSApplication.shared
        let suite = "MeasuredMenuBar.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(settings: AppSettings(defaults: defaults),
                             updates: UpdateController(configuration: .current(environment: [:]), store: UpdateStore(defaults: defaults)))
        model.subscriptionBalances = SubscriptionBalanceState(defaults: defaults, legacy: nil)
        model.subscriptionBalances.showsMenuBar = false
        model.settings.liveUnit = .tokens
        model.settings.barShowsUnit = true
        model.settings.barSecondary = false
        model.settings.barTraffic = .off
        model.settings.barIntelligence = false
        var snapshot = SpeedSnapshot.empty
        snapshot.live = Rate(output: 999)
        snapshot.intervalRates = MeasuredRateWindow(endedAtMs: 1000, sampleCount: 2, byAgent: ["a": Rate(output: 60), "b": Rate(output: 120)])
        snapshot.agents = [60.0, 120.0, 0.0].enumerated().map { index, speed in
            AgentStatus(id: "\(index)", source: .codex, project: "p", model: "m", phase: .generating,
                        isSubagent: false, live: Rate(output: speed), recentSpeed: 999, lastActivity: Date())
        }
        model.store.publishLive(snapshot)
        model.gauge.snap(to: 999, now: 0) // The readout must use the confirmed snapshot, not animated/predicted UI state.
        model.settings.barMode = .glyphValue
        let state = StatusItemState(model: model, time: 0)
        #expect(state.layout.tokenRings)
        #expect(state.value == "180" && state.averageValue == "90")
        #expect(state.layout.ttft == nil && state.layout.unit == nil)
        #expect(state.layout.length == StatusItemLayout.padding * 2 + StatusItemLayout.tokenRingDiameter * 2 + StatusItemLayout.tokenRingGap)
        #expect(!StatusItemState.needsFrames(model, at: 0))
        let size = NSSize(width: state.layout.length, height: state.layout.height)
        for dark in [false, true] {
            let bitmap = try #require(StatusItemArtist.render(state, dark: dark, size: size))
            let png = try #require(NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/agentspeed-paired-rings-\(dark ? "dark" : "light").png"))
        }
    }
    @Test func balanceSharesTheRingItemAndPrecedesOptionalBlocks() throws {
        _ = NSApplication.shared
        let suite = "BalanceAdjacency.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(settings: AppSettings(defaults: defaults),
            updates: UpdateController(configuration: .current(environment: [:]), store: UpdateStore(defaults: defaults)))
        model.settings.liveUnit = .tokens
        model.settings.barSecondary = false
        model.settings.barTraffic = .off
        model.settings.barIntelligence = false
        model.subscriptionBalances = SubscriptionBalanceState(defaults: defaults, legacy: nil)
        model.subscriptionBalances.showsMenuBar = true
        let state = StatusItemState(model: model, time: 0)
        #expect(state.balance != nil)
        #expect(state.layout.balanceX == StatusItemLayout.padding + StatusItemLayout.tokenRingDiameter * 2 + StatusItemLayout.tokenRingGap)
        #expect(state.layout.secondaryX == state.layout.balanceX + state.layout.balanceWidth)
        model.subscriptionBalances = SubscriptionBalanceState(defaults: defaults, legacy: nil)
        model.subscriptionBalances.showsMenuBar = false
        let hidden = StatusItemState(model: model, time: 0)
        #expect(hidden.balance == nil)
        #expect(state.layout.length - hidden.layout.length == state.layout.balanceWidth)
    }

    @Test func allThreeDisplayChoicesControlBothRingsImmediately() throws {
        _ = NSApplication.shared
        let suite = "MenuBarModes.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(settings: AppSettings(defaults: defaults),
            updates: UpdateController(configuration: .current(environment: [:]), store: UpdateStore(defaults: defaults)))
        model.subscriptionBalances = SubscriptionBalanceState(defaults: defaults, legacy: nil)
        model.subscriptionBalances.showsMenuBar = false
        model.settings.liveUnit = .tokens
        model.settings.barSecondary = false
        model.settings.barTraffic = .off
        model.settings.barIntelligence = false
        var snapshot = SpeedSnapshot.empty
        snapshot.intervalRates = MeasuredRateWindow(endedAtMs: 1000, sampleCount: 2, byAgent: ["a": Rate(output: 60), "b": Rate(output: 120)])
        model.store.publishLive(snapshot)
        var images: [Data] = []
        for mode in BarDisplayMode.allCases {
            model.settings.barMode = mode
            let state = StatusItemState(model: model, time: 0)
            #expect(state.layout.showsGlyph == mode.showsGlyph)
            #expect(state.layout.showsValue == mode.showsValue)
            #expect(state.value == "180" && state.averageValue == "90")
            #expect(state.layout.unit == nil && state.layout.ttft == nil)
            let bitmap = try #require(StatusItemArtist.render(state, dark: false,
                size: NSSize(width: state.layout.length, height: state.layout.height)))
            let png = try #require(NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:]))
            images.append(png)
            try png.write(to: URL(fileURLWithPath: "/tmp/agentspeed-mode-\(mode.rawValue).png"))
        }
        #expect(Set(images).count == 3) // Each stored choice produces a distinct rendered result.
    }

}
