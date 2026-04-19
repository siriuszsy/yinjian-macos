import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    private let overviewColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.93, blue: 0.88),
                    Color(red: 0.91, green: 0.95, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    overviewGrid
                    permissionsCard
                    serviceCard
                    behaviorCard
                    actionCard
                }
                .padding(24)
            }
        }
        .frame(width: 640, height: 720)
        .onAppear {
            viewModel.refreshPermissions()
            viewModel.refreshAPIKeyStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermissions()
            viewModel.refreshAPIKeyStatus()
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(BuildInfo.displayName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("按住说话，松开落字。设置页只保留真正影响体验的内容。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("本地调试版")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.62), in: Capsule())
            }

            HStack(spacing: 10) {
                heroPill(
                    title: "API Key",
                    value: apiKeySummary,
                    tint: apiKeyReady ? Color.green : Color.orange
                )
                heroPill(
                    title: "麦克风",
                    value: viewModel.permissionStatus.microphone.title,
                    tint: permissionColor(for: viewModel.permissionStatus.microphone)
                )
                heroPill(
                    title: "识别",
                    value: viewModel.settings.asrMode.displayName,
                    tint: Color(red: 0.09, green: 0.46, blue: 0.53)
                )
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.74),
                    Color(red: 0.99, green: 0.97, blue: 0.93).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: overviewColumns, spacing: 12) {
            overviewTile(
                title: "触发键",
                value: viewModel.triggerKeyDisplayName,
                caption: "当前用于唤起录音的全局快捷键。"
            )
            overviewTile(
                title: "输入设备",
                value: viewModel.microphoneDisplayName,
                caption: "当前仍使用系统默认输入。"
            )
            overviewTile(
                title: "文本整理",
                value: viewModel.settings.cleanupEnabled ? "已开启" : "已关闭",
                caption: "关闭后会直接输出原始转写结果。"
            )
            overviewTile(
                title: "写回回退",
                value: viewModel.settings.fallbackPasteEnabled ? "允许" : "关闭",
                caption: "辅助功能写入失败时，是否回退到粘贴。"
            )
        }
    }

    private var permissionsCard: some View {
        settingsCard(
            title: "必要权限",
            subtitle: "音键最核心的是录音和写回。权限只保留这两条主链，以及未来才会用到的键盘监听。"
        ) {
            permissionRow(
                title: "辅助功能",
                subtitle: "决定文字能不能写回到当前输入框。这是最关键的系统权限。",
                state: viewModel.accessibilityState,
                primaryButtonTitle: "请求授权",
                primaryAction: viewModel.requestAccessibility,
                secondaryButtonTitle: "打开系统设置",
                secondaryAction: viewModel.openAccessibilitySettings
            )

            permissionRow(
                title: "麦克风",
                subtitle: "决定能不能开始录音。没有它，语音识别链路根本不会启动。",
                state: viewModel.permissionStatus.microphone,
                primaryButtonTitle: "请求授权",
                primaryAction: viewModel.requestMicrophone,
                secondaryButtonTitle: "打开系统设置",
                secondaryAction: viewModel.openMicrophoneSettings
            )

            if viewModel.showsInputMonitoringSetup {
                permissionRow(
                    title: "键盘监听",
                    subtitle: "只有切到需要系统键盘监听的触发键时才重要。",
                    state: viewModel.inputMonitoringState,
                    primaryButtonTitle: "打开系统设置",
                    primaryAction: viewModel.requestInputMonitoring,
                    secondaryButtonTitle: "刷新状态",
                    secondaryAction: viewModel.refreshPermissions
                )
            } else {
                inlineNote("当前触发键不依赖键盘监听。后续如果切回右侧 Option 或 Fn，再处理这一项。")
            }

            inlineNote(viewModel.permissionHintText)

            if let setupMessage = viewModel.setupMessage {
                inlineNote(setupMessage)
            }
        }
    }

    private var serviceCard: some View {
        settingsCard(
            title: "识别与整理",
            subtitle: "这里决定语音如何变成文字。默认仍然偏稳，不偏花哨。"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("百炼 API Key")
                    .font(.body.weight(.semibold))

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

                inlineNote(viewModel.apiKeyStatusText)
            }
            .padding(16)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            asrModeRow

            VStack(alignment: .leading, spacing: 12) {
                toggleRow(
                    title: "启用文本整理",
                    subtitle: "开启后，会去掉重复、口头禅和基础噪音，让结果更像你手打出来的。",
                    isOn: $viewModel.settings.cleanupEnabled
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("整理模型")
                        .font(.body.weight(.semibold))

                    TextField("qwen-flash", text: $viewModel.settings.cleanupModel)
                        .textFieldStyle(.roundedBorder)

                    inlineNote("直接填写真实模型名。当前默认值是 qwen-flash。")
                }
            }
            .padding(16)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("翻译设置")
                    .font(.body.weight(.semibold))

                TextField("源语言，默认 auto", text: $viewModel.settings.translationSourceLanguage)
                    .textFieldStyle(.roundedBorder)

                TextField("目标语言，默认 English", text: $viewModel.settings.translationTargetLanguage)
                    .textFieldStyle(.roundedBorder)

                inlineNote("翻译快捷键默认使用 \(TranslationHotKeyCatalog.primary.displayName)。它和听写走同一套全局热键机制，但不共享键位，避免被 `⌘ + ;` 抢走。源语言可填 auto，目标语言建议填写 English、Chinese、Japanese 或对应语言代码。")
            }
            .padding(16)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var behaviorCard: some View {
        settingsCard(
            title: "界面与写回",
            subtitle: "尽量少开关，只保留会明显改变主观体验的行为。"
        ) {
            detailRow(
                title: "触发键",
                subtitle: "当前开发版继续使用组合热键，避免把权限复杂度带回主链。",
                value: viewModel.triggerKeyDisplayName
            )

            detailRow(
                title: "麦克风来源",
                subtitle: "先沿用系统默认输入设备，不在这里扩展复杂的设备管理。",
                value: viewModel.microphoneDisplayName
            )

            toggleRow(
                title: "显示悬浮球",
                subtitle: "按下时显示录音态，松开后显示处理态。关闭后不影响核心能力。",
                isOn: $viewModel.settings.showHUD
            )

            toggleRow(
                title: "启用粘贴回退",
                subtitle: "辅助功能直写失败时，允许复制到剪贴板并尝试粘贴。",
                isOn: $viewModel.settings.fallbackPasteEnabled
            )
        }
    }

    private var actionCard: some View {
        settingsCard(
            title: "保存与恢复",
            subtitle: "设置页不放测试入口。这里只负责保存当前配置，或者恢复到默认值。"
        ) {
            HStack(spacing: 12) {
                Button("恢复默认配置") {
                    viewModel.resetToDefaults()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("保存设置") {
                    viewModel.save()
                }
                .buttonStyle(.borderedProminent)
            }

            if let saveMessage = viewModel.saveMessage {
                inlineNote(saveMessage)
            }
        }
    }

    private var asrModeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("语音识别模式")
                .font(.body.weight(.semibold))

            Picker("语音识别模式", selection: $viewModel.settings.asrMode) {
                ForEach(ASRMode.allCases, id: \.self) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            inlineNote(viewModel.settings.asrMode.settingsSubtitle)
        }
        .padding(16)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                content()
            }
        }
        .padding(20)
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.9),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func heroPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.14), in: Capsule())
    }

    private func overviewTile(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color.white.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
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
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.semibold))

                    Text(state.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(permissionColor(for: state).opacity(0.14), in: Capsule())
                }

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Button(primaryButtonTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)

                Button(secondaryButtonTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    .font(.body.weight(.semibold))

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.72), in: Capsule())
        }
        .padding(16)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    .font(.body.weight(.semibold))

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(16)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func inlineNote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private var apiKeyReady: Bool {
        viewModel.apiKeyStatusText.contains("已保存")
    }

    private var apiKeySummary: String {
        apiKeyReady ? "已配置" : "未配置"
    }

    private var cardFill: Color {
        Color.black.opacity(0.035)
    }
}
