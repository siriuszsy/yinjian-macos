import Foundation
@testable import tinyTypeless

final class SpyHUDController: StatusHUDControlling {
    private(set) var events: [String] = []
    private(set) var renderedStates: [RuntimeIndicatorState] = []

    func render(_ state: RuntimeIndicatorState) {
        renderedStates.append(state)
        events.append(String(describing: state))
    }
}
