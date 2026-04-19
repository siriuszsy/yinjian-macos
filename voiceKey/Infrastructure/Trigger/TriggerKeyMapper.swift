import CoreGraphics
import Foundation

enum TriggerKeyMapper {
    static func keyCode(for key: TriggerKey) -> CGKeyCode {
        switch key {
        case .commandSemicolon:
            return 41
        case .rightOption:
            return 61
        case .fn:
            return 63
        }
    }

    static func matches(
        keyCode: CGKeyCode,
        triggerKey: TriggerKey
    ) -> Bool {
        keyCode == self.keyCode(for: triggerKey)
    }
}
