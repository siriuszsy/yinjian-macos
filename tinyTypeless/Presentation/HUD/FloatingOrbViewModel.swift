import Combine
import CoreGraphics
import Foundation

final class FloatingOrbViewModel: ObservableObject {
    private enum WaveformConstants {
        static let silenceThreshold: CGFloat = 0.16
        static let restingBars: [CGFloat] = [0.16, 0.2, 0.24, 0.28, 0.32]
    }

    @Published var state: HUDState = .idle
    @Published var inputLevel: CGFloat = 0
    @Published var barLevels: [CGFloat] = WaveformConstants.restingBars

    func applyInputLevel(_ level: CGFloat) {
        let clamped = min(max(level, 0), 1)
        guard clamped >= WaveformConstants.silenceThreshold else {
            inputLevel = 0
            barLevels = WaveformConstants.restingBars
            return
        }

        let gated = (clamped - WaveformConstants.silenceThreshold) / (1 - WaveformConstants.silenceThreshold)
        inputLevel = gated
    }

    func applyVisualization(barLevels newLevels: [CGFloat], level: CGFloat) {
        guard !newLevels.isEmpty else {
            resetInputLevel()
            return
        }

        let clamped = min(max(level, 0), 1)
        guard clamped >= WaveformConstants.silenceThreshold else {
            resetInputLevel()
            return
        }

        let gated = (clamped - WaveformConstants.silenceThreshold) / (1 - WaveformConstants.silenceThreshold)
        inputLevel = gated
        let normalizedBars = newLevels.map { min(max($0, 0.06), 1) }
        barLevels = normalizedBars
    }

    func resetInputLevel() {
        inputLevel = 0
        barLevels = WaveformConstants.restingBars
    }
}
