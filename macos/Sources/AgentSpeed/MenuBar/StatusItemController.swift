import AppKit

/// Owns the menu bar item: a status item that hugs its content, showing the image drawn by `StatusItemArtist`.
///
/// The speed area toggles the dashboard; the balance control opens balances. Secondary clicks open the quick menu.
/// Clicks act on mouse down like native extras.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let autosaveName = "AgentSpeedStatusItem"

    private let model: AppModel
    private let item: NSStatusItem
    private var accessibility: StatusItemAccessibility?
    private var renderer: StatusItemRenderer?
    private let balanceButton = StatusItemBalanceButton(frame: .zero)
    private var isHighlighted = false
    private var isMenuScheduled = false

    init(model: AppModel) {
        self.model = model
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.autosaveName = Self.autosaveName
        item.isVisible = true
        guard let button = item.button else { return }
        configure(button)
        accessibility = StatusItemAccessibility(model: model, button: button)
    }

    var anchorView: NSView? { item.button }

    /// Shows the item pressed while the dashboard is open.
    func setHighlighted(_ highlighted: Bool) {
        isHighlighted = highlighted
        applyHighlight()
        reapplyHighlightAfterTracking()
    }

    // MARK: Setup

    private func configure(_ button: NSStatusBarButton) {
        button.title = ""
        button.image = nil
        button.imagePosition = .noImage
        button.focusRingType = .none
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.setAccessibilityLabel(model.l10n("app.name"))

        button.imageScaling = .scaleNone
        button.imagePosition = .imageOnly
        balanceButton.isBordered = false
        balanceButton.isTransparent = true
        balanceButton.title = ""
        balanceButton.focusRingType = .none
        balanceButton.autoresizingMask = [.minXMargin, .maxXMargin, .height]
        balanceButton.target = self
        balanceButton.action = #selector(showBalances)
        balanceButton.sendAction(on: [.leftMouseDown])
        balanceButton.setAccessibilityLabel("Sub 4 Tokens — 订阅余额")
        balanceButton.onSecondaryClick = { [weak self] in self?.scheduleQuickMenu() }
        button.addSubview(balanceButton)
        renderer = StatusItemRenderer(model: model, item: item) { [weak self] state in
            self?.updateBalanceButton(state)
        }
    }

    private func updateBalanceButton(_ state: StatusItemState) {
        balanceButton.isHidden = state.balance == nil
        balanceButton.itemLayout = state.layout
        balanceButton.setAccessibilityValue(state.balance)
        balanceButton.toolTip = state.balance
    }

    static func balanceButtonFrame(layout: StatusItemLayout, bounds: NSRect) -> NSRect {
        guard layout.balanceWidth > 0 else { return .zero }
        // NSStatusBarButton centers its unscaled image inside its bounds.
        let imageX = bounds.midX - layout.length / 2
        let trailingPadding = layout.secondaryWidth + layout.readoutWidth == 0 ? StatusItemLayout.padding : 0
        return NSRect(x: imageX + layout.balanceX, y: bounds.minY,
                      width: layout.balanceWidth + trailingPadding, height: bounds.height)
    }

    @objc private func showBalances() {
        model.commands?.closeDashboard()
        model.showSubscriptionBalances?()
    }

    // MARK: Clicks

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard item.menu == nil else { return }
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseDown || event?.type == .rightMouseUp
            || !(event?.modifierFlags.intersection([.option, .control]).isEmpty ?? true)
        if isSecondary {
            scheduleQuickMenu()
        } else if !balanceButton.isHidden, let window = sender.window,
                  balanceButton.frame.contains(sender.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)) {
            // Some menu-bar activation paths target the parent button directly. Use its actual child frame,
            // with the pointer converted from screen coordinates, rather than the event's possibly different window.
            showBalances()
        } else {
            model.commands?.toggleDashboard()
            reapplyHighlightAfterTracking()
        }
    }

    /// Opens the menu once the button has finished tracking the click, so the menu's own tracking loop never nests
    /// inside the button's.
    private func scheduleQuickMenu() {
        guard !isMenuScheduled else { return }
        isMenuScheduled = true
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.showQuickMenu() }
        }
    }

    private func showQuickMenu() {
        isMenuScheduled = false
        guard let button = item.button, item.menu == nil else { return }
        let menu = MenuFactory.quickMenu(model: model)
        menu.delegate = self
        item.menu = menu
        button.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard item.menu === menu else { return }
        item.menu = nil
        reapplyHighlightAfterTracking()
    }

    // MARK: Highlight

    private func applyHighlight() {
        guard let button = item.button, item.menu == nil, button.isHighlighted != isHighlighted else { return }
        button.highlight(isHighlighted)
    }

    /// The button clears its highlight when mouse tracking ends; restore the wanted state right after.
    private func reapplyHighlightAfterTracking() {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.applyHighlight() }
        }
    }
}

/// A real child control routes balance clicks without relying on NSApp.currentEvent's window coordinates.
final class StatusItemBalanceButton: NSButton {
    var onSecondaryClick: (() -> Void)?
    var itemLayout: StatusItemLayout? { didSet { updateFrame() } }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        updateFrame()
    }

    private func updateFrame() {
        guard let itemLayout, let superview else { return }
        frame = StatusItemController.balanceButtonFrame(layout: itemLayout, bounds: superview.bounds)
    }

    override func mouseDown(with event: NSEvent) {
        if !event.modifierFlags.intersection([.option, .control]).isEmpty {
            onSecondaryClick?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick?()
    }
}
