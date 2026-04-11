import Foundation

protocol StatusHUDControlling: AnyObject {
    func render(_ state: RuntimeIndicatorState)
    func updateInputLevel(_ level: Float)
    func updateVisualization(barLevels: [Float], level: Float)
}
