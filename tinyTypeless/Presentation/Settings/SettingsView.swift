import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                setupSection
                cloudSection
                defaultsSection
                behaviorSection
                actionSection
            }
            .padding(20)
        }
        .frame(width: 520, height: 560)
        .onAppear {
            viewModel.refreshPermissions()
            viewModel.refreshAPIKeyStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermissions()
            viewModel.refreshAPIKeyStatus()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("tinyTypeless 设置")
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("v1 最小版")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }

            Text("设置页只负责权限、默认行为和回退策略。运行时 orb 只负责 listening 和 thinking。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var setupSection: some View {
        settingsSection(
            title: "首次设置",
            subtitle: viewModel.setupSectionSubtitle
        ) {
            permissionOverviewCard

            if viewModel.showsInputMonitoringSetup {
                permissionRow(
                    title: "键盘监听",
                    subtitle: "让右侧 ⌥ 键的按下和抬起能被捕获。",
                    state: viewModel.inputMonitoringState,
                    primaryButtonTitle: "打开系统设置",
                    primaryAction: viewModel.requestInputMonitoring,
                    secondaryButtonTitle: "刷新状态",
                    secondaryAction: viewModel.refreshPermissions
                )
            }

            permissionRow(
                title: "辅助功能",
                subtitle: "当前阶段先不阻塞开发，但这里仍然显示真实授权状态，后面文本写回会直接用到。",
                state: viewModel.accessibilityState,
                primaryButtonTitle: "请求授权",
                primaryAction: viewModel.requestAccessibility,
                secondaryButtonTitle: "打开系统设置",
                secondaryAction: viewModel.openAccessibilitySettings
            )

            permissionRow(
                title: "麦克风",
                subtitle: "后面接入录音后，允许采集语音。",
                state: viewModel.permissionStatus.microphone,
                primaryButtonTitle: "请求授权",
                primaryAction: viewModel.requestMicrophone,
                secondaryButtonTitle: "打开系统设置",
                secondaryAction: viewModel.openMicrophoneSettings
            )

            HStack {
                Spacer()

                Button("刷新权限状态") {
                    viewModel.refreshPermissions()
                }
            }

            Text(viewModel.permissionHintText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let setupMessage = viewModel.setupMessage {
                Text(setupMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionOverviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.permissionOverviewTitle)
                .font(.body.weight(.medium))

            ForEach(viewModel.permissionOverviewLines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var defaultsSection: some View {
        settingsSection(
            title: "默认配置",
            subtitle: "当前 v1 固定下来的默认配置。"
        ) {
            detailRow(
                title: "触发键",
                subtitle: "当前开发版先用组合热键，绕开键盘监听；后面再切回右侧 ⌥ 或 Fn。",
                value: viewModel.triggerKeyDisplayName
            )

            detailRow(
                title: "麦克风",
                subtitle: "暂时只保留设备来源展示，不做复杂设备管理。",
                value: viewModel.microphoneDisplayName
            )

            detailRow(
                title: "语音转文本",
                subtitle: "负责把短语音转换成文字。",
                value: viewModel.asrModelDisplayName
            )

            detailRow(
                title: "文本整理",
                subtitle: "负责去重复、口头禅和基础标点，不负责扩写。",
                value: viewModel.cleanupModelDisplayName
            )
        }
    }

    private var cloudSection: some View {
        settingsSection(
            title: "云服务",
            subtitle: "先把百炼 API Key 配进去，后面才能真正调用语音转文字。"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("百炼 API Key")
                    .font(.body.weight(.medium))

                SecureField("输入 sk- 开头的 API Key", text: $viewModel.apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("保存 API Key") {
                        viewModel.saveAPIKey()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("刷新状态") {
                        viewModel.refreshAPIKeyStatus()
                    }
                    .buttonStyle(.bordered)
                }

                Text(viewModel.apiKeyStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("开发期直接写入本地用户目录，先保证可用；后面再切回更正式的安全存储。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var behaviorSection: some View {
        settingsSection(
            title: "运行行为",
            subtitle: "这些是 v1 真正可调的运行行为。"
        ) {
            toggleRow(
                title: "启用文本整理",
                subtitle: "默认开启，把逐字稿整理成更像键入的文本。",
                isOn: $viewModel.settings.cleanupEnabled
            )

            toggleRow(
                title: "显示悬浮球",
                subtitle: "按下触发键时显示录音态，松开后进入思考态。",
                isOn: $viewModel.settings.showHUD
            )

            toggleRow(
                title: "启用粘贴回退",
                subtitle: "辅助功能写入失败时，复制到剪贴板作为回退。",
                isOn: $viewModel.settings.fallbackPasteEnabled
            )
        }
    }

    private var actionSection: some View {
        settingsSection(
            title: "操作",
            subtitle: "保存当前设置，或回到 v1 默认值。"
        ) {
            HStack(spacing: 12) {
                Button("恢复默认配置") {
                    viewModel.resetToDefaults()
                }
                .buttonStyle(.bordered)

                Button("保存设置") {
                    viewModel.save()
                }
                .buttonStyle(.borderedProminent)
            }

            if let saveMessage = viewModel.saveMessage {
                Text(saveMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                content()
            }
        }
        .padding(18)
        .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        subtitle: String,
        state: PermissionState,
        primaryButtonTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryButtonTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.medium))

                    Text(state.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(permissionColor(for: state).opacity(0.16), in: Capsule())
                }

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Button(primaryButtonTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)

                Button(secondaryButtonTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func detailRow(
        title: String,
        subtitle: String,
        value: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func permissionColor(for state: PermissionState) -> Color {
        switch state {
        case .granted:
            return .green
        case .needsSetup:
            return .orange
        case .notRequired, .later:
            return .secondary
        }
    }
}
