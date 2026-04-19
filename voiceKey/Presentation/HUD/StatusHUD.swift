import SwiftUI

struct StatusHUD: View {
    @ObservedObject var viewModel: FloatingOrbViewModel

    var body: some View {
        VStack {
            Spacer()

            runtimeCard
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 300, height: 92, alignment: .bottom)
        .animation(.spring(duration: 0.24), value: viewModel.state)
        .animation(.linear(duration: 0.045), value: viewModel.barLevels)
    }

    private var runtimeCard: some View {
        HStack(spacing: 12) {
            leadingVisual

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let trailingLabel {
                Text(trailingLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 8)
        .scaleEffect(containerScale)
    }

    @ViewBuilder
    private var leadingVisual: some View {
        switch viewModel.state {
        case .listening:
            listeningWaveform
        case .processing:
            thinkingIndicator
        case .success:
            stateGlyph(symbol: "checkmark")
        case .fallback:
            stateGlyph(symbol: "doc.on.doc")
        case .blocked:
            stateGlyph(symbol: "hand.raised")
        case .error:
            stateGlyph(symbol: "exclamationmark")
        case .idle:
            EmptyView()
        }
    }

    private var listeningWaveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(viewModel.barLevels.enumerated()), id: \.offset) { _, level in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.94))
                    .frame(width: 4, height: waveformHeight(level: level))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 52, height: 34)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.9 - (Double(index) * 0.18)))
                    .frame(width: 5, height: 5)
                    .scaleEffect(index == activeThinkingDot ? 1.2 : 0.86)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 44, height: 30)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func stateGlyph(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 44, height: 30)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var isListening: Bool {
        if case .listening = viewModel.state {
            return true
        }

        return false
    }

    private var containerScale: CGFloat {
        isListening ? 1.018 : 1
    }

    private var activeThinkingDot: Int {
        switch viewModel.state {
        case .processing(let stage):
            switch stage {
            case .finalizingCapture:
                return 0
            case .transcribingAudio:
                return 1
            case .translatingText:
                return 2
            case .cleaningTranscript:
                return 1
            case .insertingText:
                return 2
            }
        default:
            return 1
        }
    }

    private func waveformHeight(level: CGFloat) -> CGFloat {
        let base: CGFloat = 8
        let gain: CGFloat = 24
        return base + (level * gain)
    }

    private var title: String {
        switch viewModel.state {
        case .idle:
            return "待命"
        case .listening(let intent, _):
            switch intent {
            case .dictation:
                return "正在录音"
            case .translation:
                return "翻译录音中"
            }
        case .processing(let stage):
            return stage.title
        case .success:
            return "已完成"
        case .fallback:
            return "已复制到剪贴板"
        case .blocked(let reason):
            return reason.title
        case .error:
            return "出错了"
        }
    }

    private var subtitle: String {
        switch viewModel.state {
        case .idle:
            return "后台待命"
        case .listening(let intent, let triggerLabel):
            switch intent {
            case .dictation:
                return "按住\(triggerLabel)说话，松开结束"
            case .translation:
                return "按住\(triggerLabel)说话，松开后自动翻译"
            }
        case .processing(let stage):
            return stage.subtitle
        case .success(let message):
            return message
        case .fallback(let message):
            return message
        case .blocked(let reason):
            return reason.subtitle
        case .error(let message):
            return message
        }
    }

    private var trailingLabel: String? {
        switch viewModel.state {
        case .idle:
            return nil
        case .listening(let intent, _):
            switch intent {
            case .dictation:
                return nil
            case .translation:
                return "翻译"
            }
        case .processing(let stage):
            return stage.pill
        case .success:
            return nil
        case .fallback:
            return "回退"
        case .blocked:
            return "权限"
        case .error:
            return "错误"
        }
    }
}
