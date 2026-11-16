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

    @Test func balanceClicksUseTheirOwnControlEvenWithoutACurrentMouseEvent() throws {
        _ = NSApplication.shared
        var layout = StatusItemLayout(mode: .glyphValue, showsUnit: false, unit: "", ttft: nil, valueWidth: 20, height: 24)
        layout.tokenRings = true
        layout.balanceWidth = 120
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: layout.length + 10, height: 24))
        let balance = StatusItemBalanceButton(frame: StatusItemController.balanceButtonFrame(layout: layout, bounds: button.bounds))
        balance.isBordered = false
        balance.isTransparent = true
        balance.autoresizingMask = [.minXMargin, .maxXMargin, .height]
        let recorder = MenuBarClickRecorder()
        button.target = recorder
        button.action = #selector(MenuBarClickRecorder.speed)
        balance.target = recorder
        balance.action = #selector(MenuBarClickRecorder.balances)
        button.addSubview(balance)
        balance.itemLayout = layout
        // Exercise native hit testing, including the rightmost padding, and activation without NSApp.currentEvent.
        for x in [balance.frame.minX + 1, balance.frame.midX, button.bounds.maxX - 6] {
            let hit = try #require(button.hitTest(NSPoint(x: x, y: 12)) as? NSButton)
            #expect(hit === balance)
            hit.performClick(nil)
        }
        #expect(recorder.balanceCount == 3 && recorder.speedCount == 0)
        let speed = try #require(button.hitTest(NSPoint(x: 10, y: 12)) as? NSButton)
        #expect(speed === button)
        speed.performClick(nil)
        #expect(recorder.speedCount == 1 && recorder.balanceCount == 3)
        // Native status item width changes may arrive after assigning the new image.
        button.setFrameSize(NSSize(width: button.frame.width + 20, height: 24))
        #expect(balance.frame == StatusItemController.balanceButtonFrame(layout: layout, bounds: button.bounds))
        #expect(StatusItemController.balanceButtonFrame(layout: StatusItemLayout(mode: .glyph, showsUnit: false,
            unit: "", ttft: nil, valueWidth: 0, height: 24), bounds: button.bounds) == .zero)
    }

}

@MainActor
private final class MenuBarClickRecorder: NSObject {
    var speedCount = 0
    var balanceCount = 0
    @objc func speed() { speedCount += 1 }
    @objc func balances() { balanceCount += 1 }
}
