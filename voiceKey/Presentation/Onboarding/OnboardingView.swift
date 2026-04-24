import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    @State private var testInput = ""
    @FocusState private var testFieldFocused: Bool

    private let steps = OnboardingStep.allCases

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.93, blue: 0.88),
                    Color(red: 0.9, green: 0.95, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    topBar
                    stepper
                    summaryStrip
                    contentCard
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            viewModel.refreshPermissions()
            viewModel.refreshAPIKeyStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermissions()
            viewModel.refreshAPIKeyStatus()
        }
        .onChange(of: viewModel.currentStep) { _, newValue in
            if newValue == .directWrite {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    testFieldFocused = true
                }
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(BuildInfo.displayName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("首次使用向导")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("4 步完成第一次输入")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.62), in: Capsule())
        }
    }

    private var stepper: some View {
        HStack(spacing: 10) {
            ForEach(steps, id: \.rawValue) { step in
                stepPill(step)
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            summaryChip(title: "API Key", value: viewModel.apiKeyStatusText)
            summaryChip(title: "麦克风", value: viewModel.permissionStatus.microphone.title)
            summaryChip(title: "写回模式", value: viewModel.writeModeLabel)
        }
    }

    private var contentCard: some View {
        card {
            VStack(alignment: .leading, spacing: 20) {
                header
                currentStepContent
            }
        }
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            welcomeStep
        case .apiKey:
            apiKeyStep
        case .permissions:
            permissionsStep
        case .directWrite:
            directWriteStep
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.currentStep.progressLabel)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.7), in: Capsule())

            Text(viewModel.currentStep.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text(viewModel.currentStep.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let guideMessage = viewModel.guideMessage {
                infoCallout(
                    title: "当前反馈",
                    copy: guideMessage,
                    tint: Color(red: 0.1, green: 0.46, blue: 0.53)
                )
            }
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            infoCallout(
                title: "这次只讲 3 件事",
                copy: "需要百炼 API Key、需要麦克风、辅助功能只影响是否直接写回当前光标。",
                tint: Color(red: 0.8, green: 0.36, blue: 0.14)
            )

            overviewCard(
                title: "这条路径会发生什么",
                body: "欢迎 -> API Key -> 权限准备 -> 直接写入测试。首次引导的目标是让你在 2 分钟内成功写出第一句话。"
            )

            HStack(spacing: 12) {
                Button("开始设置") {
                    viewModel.continueFromWelcome()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())

                Button("稍后配置") {
                    viewModel.finishOnboarding()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                modeButton(title: "我已经有 Key", selected: viewModel.apiKeyMode == .haveKey) {
                    viewModel.chooseHaveKey()
                }
                modeButton(title: "我还没有 Key", selected: viewModel.apiKeyMode == .needKey) {
                    viewModel.chooseNeedKey()
                }
            }

            if viewModel.apiKeyMode == .haveKey {
                inputCard
            } else {
                applyKeyCard
            }

            VStack(alignment: .leading, spacing: 12) {
                overviewCard(
                    title: "为什么放在同一步",
                    body: "没有 Key 的用户不该先面对一个空输入框；先给申请路径，再回到同一页输入，更顺。"
                )

                overviewCard(
                    title: "当前原则",
                    body: "默认主路径是“本次使用”。不要自动读取钥匙串，也不要一开始逼用户理解长期保存策略。"
                )
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            infoCallout(
                title: "这里把两类权限一起准备好",
                copy: "麦克风决定能不能录音，辅助功能决定第一次测试能不能直接落到光标。但它们的动作和提示必须分清。",
                tint: Color(red: 0.71, green: 0.49, blue: 0.11)
            )

            VStack(alignment: .leading, spacing: 14) {
                microphonePermissionRow
                accessibilityPermissionRow
            }

            HStack(spacing: 12) {
                Button("开始直接写入测试") {
                    viewModel.continueToDirectWriteTest()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())

                Button("返回 API Key") {
                    viewModel.move(to: .apiKey)
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }

    private var inputCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("连接百炼 API Key")
                    .font(.headline)
                Text(viewModel.apiKeyStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SecureField("输入 sk- 开头的 API Key", text: $viewModel.apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("本次使用") {
                        viewModel.useAPIKeyForCurrentSession()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                    Button("读取已保存 Key") {
                        viewModel.loadSavedAPIKeyIntoCurrentSession()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }

                Button("顺手存入安全存储") {
                    viewModel.saveAPIKeyToPersistentStore()
                }
                .buttonStyle(OnboardingGhostButtonStyle())

                Text("默认不会自动读取你的钥匙串。只有你手动点“读取已保存 Key”时，系统才可能要求 Touch ID 或密码。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var applyKeyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                Text("先申请你的百炼 API Key")
                    .font(.headline)

                applyStep(title: "1. 登录百炼控制台", body: "先完成账号登录和实名认证。")
                applyStep(title: "2. 切到华北 2（北京）", body: "当前 app 默认对接北京节点，这一步必须明显。")
                applyStep(title: "3. 创建 API Key", body: "建议先用默认业务空间 + 全部权限。")
                applyStep(title: "4. 开启免费额度保护", body: "把“会不会误扣费”的担心提前化解掉。")

                HStack(spacing: 10) {
                    Button("打开百炼控制台") {
                        viewModel.openBailianConsole()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                    Button("查看 API Key 文档") {
                        viewModel.openGetAPIKeyDocs()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }

                HStack(spacing: 10) {
                    Button("免费额度说明") {
                        viewModel.openFreeQuotaDocs()
                    }
                    .buttonStyle(OnboardingGhostButtonStyle())

                    Button("我已经拿到 Key 了") {
                        viewModel.markKeyObtained()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            }
        }
    }

    private var directWriteStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            infoCallout(
                title: "第一次测试就验证完整链路",
                copy: "先把光标点进下面这个测试框。然后按住 Fn 说一句话，目标是让结果直接落到这个输入框里；如果权限没开，也必须明确知道当前会回退到剪贴板。",
                tint: viewModel.accessibilityReady ? Color.green : Color.orange
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("当前写回模式")
                        .font(.headline)
                    Spacer()
                    Text(viewModel.writeModeLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(viewModel.accessibilityReady ? Color.green : Color.orange)
                }

                TextEditor(text: $testInput)
                    .focused($testFieldFocused)
                    .font(.system(size: 15))
                    .frame(minHeight: 220)
                    .padding(10)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    Button("点这里聚焦测试框") {
                        testFieldFocused = true
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())

                    Button("写入测试文本") {
                        testFieldFocused = true
                        viewModel.runWriteTest()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                    Button("清空测试框") {
                        testInput = ""
                        testFieldFocused = true
                    }
                    .buttonStyle(OnboardingGhostButtonStyle())
                }

                Text("推荐测试句：今天先测试第一句听写。也可以先点“写入测试文本”验证当前光标写回链路。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("完成首次引导") {
                    viewModel.finishOnboarding()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())

                Button("返回权限准备") {
                    viewModel.move(to: .permissions)
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }

    private func stepPill(_ step: OnboardingStep) -> some View {
        Button {
            viewModel.move(to: step)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Text("\(step.rawValue + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(viewModel.currentStep == step ? Color.white : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        (viewModel.currentStep == step ? Color(red: 0.8, green: 0.36, blue: 0.14) : Color.white.opacity(0.62)),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(step.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(viewModel.currentStep == step ? Color.white.opacity(0.76) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func summaryChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }

    private func overviewCard(title: String, body: String) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func infoCallout(title: String, copy: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(copy)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func applyStep(title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(title.prefix(1)))
                .font(.caption.weight(.bold))
                .frame(width: 32, height: 32)
                .background(Color(red: 0.8, green: 0.36, blue: 0.14).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(Color(red: 0.8, green: 0.36, blue: 0.14))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        state: String,
        primaryTitle: String,
        primaryAction: (() -> Void)?,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(state)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.7), in: Capsule())
            }

            HStack(spacing: 10) {
                if let primaryAction {
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                } else {
                    Text(primaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func modeButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Group {
            if selected {
                Button(title, action: action)
                    .buttonStyle(OnboardingPrimaryButtonStyle())
            } else {
                Button(title, action: action)
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }

    private var microphonePermissionRow: some View {
        Group {
            if viewModel.microphoneReady {
                permissionRow(
                    title: "麦克风",
                    subtitle: "必须。不开就无法开始语音识别。",
                    state: viewModel.permissionStatus.microphone.title,
                    primaryTitle: "麦克风已就绪",
                    primaryAction: nil,
                    secondaryTitle: "打开系统设置",
                    secondaryAction: viewModel.openMicrophoneSettings
                )
            } else {
                permissionRow(
                    title: "麦克风",
                    subtitle: "必须。不开就无法开始语音识别。",
                    state: viewModel.permissionStatus.microphone.title,
                    primaryTitle: "请求麦克风权限",
                    primaryAction: viewModel.requestMicrophone,
                    secondaryTitle: "打开系统设置",
                    secondaryAction: viewModel.openMicrophoneSettings
                )
            }
        }
    }

    private var accessibilityPermissionRow: some View {
        Group {
            if viewModel.accessibilityReady {
                permissionRow(
                    title: "辅助功能",
                    subtitle: "建议。开了之后，第一次测试直接验证写回光标。",
                    state: viewModel.permissionStatus.accessibility.title,
                    primaryTitle: "辅助功能已就绪",
                    primaryAction: nil,
                    secondaryTitle: "打开系统设置",
                    secondaryAction: viewModel.openAccessibilitySettings
                )
            } else {
                permissionRow(
                    title: "辅助功能",
                    subtitle: "建议。开了之后，第一次测试直接验证写回光标。",
                    state: viewModel.permissionStatus.accessibility.title,
                    primaryTitle: "请求辅助功能",
                    primaryAction: viewModel.requestAccessibility,
                    secondaryTitle: "打开系统设置",
                    secondaryAction: viewModel.openAccessibilitySettings
                )
            }
        }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.84, green: 0.4, blue: 0.18), Color(red: 0.75, green: 0.3, blue: 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.45 : 0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct OnboardingGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white.opacity(configuration.isPressed ? 0.38 : 0.46), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}
