import Foundation
@testable import tinyTypeless

final class SpyHUDController: StatusHUDControlling {
    private(set) var events: [String] = []
    private(set) var renderedStates: [RuntimeIndicatorState] = []
    private(set) var levels: [Float] = []
    private(set) var visualizations: [([Float], Float)] = []

    func render(_ state: RuntimeIndicatorState) {
        renderedStates.append(state)
        events.append(String(describing: state))
    }

    func updateInputLevel(_ level: Float) {
        levels.append(level)
    }

    func updateVisualization(barLevels: [Float], level: Float) {
        visualizations.append((barLevels, level))
    }
}
