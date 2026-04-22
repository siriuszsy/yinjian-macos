import AppKit
import SwiftUI

final class AppKitStatusHUDController: StatusHUDControlling, @unchecked Sendable {
    private let viewModel = FloatingOrbViewModel()
    private var panel: FloatingOrbPanel?

    func render(_ state: RuntimeIndicatorState) {
        Task { @MainActor [weak self] in
            self?.update(state: state)
        }
    }

    func updateInputLevel(_ level: Float) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.viewModel.applyInputLevel(max(0, min(CGFloat(level), 1)))
        }
    }

    func updateVisualization(barLevels: [Float], level: Float) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.viewModel.applyVisualization(
                barLevels: barLevels.map { max(0, min(CGFloat($0), 1)) },
                level: max(0, min(CGFloat(level), 1))
            )
        }
    }

    @MainActor
    private func update(state: HUDState) {
        let wasPresented = self.viewModel.state.presentsOrb
        self.viewModel.state = state
        if !self.isListening(state) {
            self.viewModel.resetInputLevel()
        }

        guard state.presentsOrb else {
            self.hidePanel(animated: wasPresented)
            return
        }

        self.ensurePanel()
        self.positionPanel()
        self.showPanel(animated: !wasPresented)
    }

    @MainActor
    private func ensurePanel() {
        guard panel == nil else {
            return
        }

        let hostingView = NSHostingView(rootView: StatusHUD(viewModel: viewModel))
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 92)

        let panel = FloatingOrbPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        self.panel = panel
    }

    @MainActor
    private func showPanel(animated: Bool) {
        guard let panel else {
            return
        }

        if animated {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    @MainActor
    private func hidePanel(animated: Bool) {
        guard let panel else {
            return
        }

        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak panel] in
            guard let panel else {
                return
            }

            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    @MainActor
    private func positionPanel() {
        guard let panel else {
            return
        }

        let width: CGFloat = 300
        let height: CGFloat = 92
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.midX - (width / 2),
            y: screenFrame.minY + 28
        )

        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    @MainActor
    private func isListening(_ state: HUDState) -> Bool {
        if case .listening = state {
            return true
        }

        return false
    }
}
