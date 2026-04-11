import Foundation

@MainActor
final class FixedTextInsertionProbe {
    private let contextInspector: ContextInspector
    private let textInserter: TextInserter
    private let hudController: StatusHUDControlling
    private let clock: Clock

    private var autoDismissWorkItem: DispatchWorkItem?

    init(
        contextInspector: ContextInspector,
        textInserter: TextInserter,
        hudController: StatusHUDControlling,
        clock: Clock
    ) {
        self.contextInspector = contextInspector
        self.textInserter = textInserter
        self.hudController = hudController
        self.clock = clock
    }

    func run() {
        cancelAutoDismiss()

        let startedAt = clock.now()
        let probeText = "【tinyTypeless 写入测试】"

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let context = try self.contextInspector.currentContext()
                self.hudController.render(.processing(stage: .insertingText))
                let insertionStartedAt = self.clock.now()
                let result = try self.textInserter.insert(probeText, into: context)
                let endedAt = self.clock.now()

                if result.success {
                    let message = result.usedFallback ? "已走回退写入测试" : "已直接写入测试文本"
                    self.hudController.render(.success(message: message))
                } else {
                    self.hudController.render(.error(message: result.failureReason ?? "写入测试失败"))
                }
                self.scheduleAutoDismiss()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.hudController.render(.error(message: message))
                self.scheduleAutoDismiss()
            }
        }
    }

    private func scheduleAutoDismiss() {
        cancelAutoDismiss()

        let workItem = DispatchWorkItem { [weak self] in
            self?.hudController.updateInputLevel(0)
            self?.hudController.render(.idle)
        }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func cancelAutoDismiss() {
        autoDismissWorkItem?.cancel()
        autoDismissWorkItem = nil
    }
}
