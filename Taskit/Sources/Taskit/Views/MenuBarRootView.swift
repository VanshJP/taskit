import AppKit
import SwiftUI
import TaskitCore

struct MenuBarRootView: View {
    @Bindable var engine: RelayEngine
    @State private var showSettings = false
    @State private var overarchingDraft = ""
    @State private var confirmClear = false
    @FocusState private var overarchingFocused: Bool

    var body: some View {
        ZStack {
            TaskitTheme.atmosphere

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    brandBar
                        .padding(.bottom, 10)
                        .taskitAppear(delay: 0.0)

                    SessionHeroView(engine: engine)
                        .padding(.bottom, 18)
                        .taskitAppear(delay: 0.04)

                    if !engine.readinessIssues.isEmpty {
                        SetupBannerView(issues: engine.readinessIssues) {
                            showSettings = true
                        }
                        .padding(.bottom, 14)
                        .taskitAppear(delay: 0.08)
                    }

                    dayGoalSection
                        .padding(.bottom, 14)
                        .taskitAppear(delay: 0.1)

                    NextUpView(
                        goal: engine.nextGoal,
                        isPaused: engine.isPaused,
                        onCopy: { engine.copyComposedPrompt() }
                    )
                    .padding(.bottom, 14)
                    .taskitAppear(delay: 0.12)

                    GoalQueueView(engine: engine)
                        .padding(.bottom, 16)
                        .taskitAppear(delay: 0.14)

                    actionRow
                        .padding(.bottom, 12)
                        .taskitAppear(delay: 0.16)

                    footer
                        .taskitAppear(delay: 0.18)
                }
                .padding(16)
            }
        }
        .frame(width: 372)
        .frame(maxHeight: 720)
        .sheet(isPresented: $showSettings) {
            SettingsView(engine: engine)
        }
        .confirmationDialog("Clear today’s queue?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear day", role: .destructive) { engine.resetDay() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all prompts and resets the session clock. It can’t be undone.")
        }
        .onAppear {
            if overarchingDraft != engine.settings.overarchingGoal {
                overarchingDraft = engine.settings.overarchingGoal
            }
            Task { await NotificationService.shared.requestAuthorizationIfNeeded() }
        }
    }

    private var brandBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Taskit")
                .font(TaskitTheme.brandFont)
                .foregroundStyle(Color.white.opacity(0.9))

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                GlassIconButton(
                    systemName: engine.isPaused ? "play.fill" : "pause.fill",
                    help: engine.isPaused ? "Resume auto-relay" : "Pause auto-relay",
                    emphasized: engine.isPaused
                ) {
                    engine.setPaused(!engine.isPaused)
                }
                GlassIconButton(systemName: "doc.on.doc", help: "Copy next composed prompt") {
                    engine.copyComposedPrompt()
                }
                GlassIconButton(systemName: "gearshape", help: "Settings") {
                    showSettings = true
                }
                GlassIconButton(systemName: "arrow.up.right.square", help: "Open latest agent") {
                    engine.openActiveAgent()
                }
            }
        }
    }

    private var dayGoalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Day goal")
                TextField("Ship auth end-to-end, keep PRs small…", text: $overarchingDraft, axis: .vertical)
                    .font(.system(size: 13.5, weight: .regular, design: .default))
                    .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(2...3)
                .textFieldStyle(.plain)
                .focused($overarchingFocused)
                .onChange(of: overarchingDraft) { _, value in
                    engine.updateSettingsDebounced { $0.overarchingGoal = value }
                }
        }
        .padding(.horizontal, 2)
    }

    private var actionRow: some View {
        VStack(spacing: 8) {
            coolingAwarePrimaryButton
                .disabled(engine.isBusy)
                .keyboardShortcut("r", modifiers: [.command])

            HStack(spacing: 8) {
                Menu {
                    Button("Use default (\(engine.settings.sessionWindowHours, specifier: "%.1f")h)") {
                        engine.markLimitHit()
                    }
                    Button("1 hour") { engine.markLimitHit(customHours: 1) }
                    Button("2 hours") { engine.markLimitHit(customHours: 2) }
                    Button("5 hours") { engine.markLimitHit(customHours: 5) }
                    Button("8 hours") { engine.markLimitHit(customHours: 8) }
                } label: {
                    Label("Limit hit", systemImage: "hourglass")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(TaskitTheme.mist)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.05))
                                .overlay { Capsule().strokeBorder(TaskitTheme.hairline, lineWidth: 1) }
                        }
                }
                .menuStyle(.borderlessButton)
                .help("Start the cool-down clock. Taskit will re-prompt when it ends.")

                GhostCapsuleButton(title: "Clear day", systemImage: "trash") {
                    confirmClear = true
                }
            }
        }
    }

    @ViewBuilder
    private var coolingAwarePrimaryButton: some View {
        if engine.session.phase == .cooling {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                PrimaryGlassButton(
                    title: "Waiting · \(engine.remainingCoolingLabel(at: context.date))",
                    systemImage: "moon.zzz",
                    isProminent: true
                ) {
                    Task { await engine.startRelay() }
                }
            }
        } else {
            PrimaryGlassButton(
                title: primaryTitle,
                systemImage: primarySymbol,
                isProminent: true
            ) {
                Task { await engine.startRelay() }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(footerDot)
                .frame(width: 6, height: 6)
            Text(engine.statusMessage)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(TaskitTheme.hush)
                .lineLimit(1)
                .help(engine.statusMessage)
            Spacer()
            Button("Quit") {
                engine.persist()
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.28))
        }
        .padding(.top, 2)
    }

    private var primaryTitle: String {
        if engine.isPaused { return "Resume relay" }
        if engine.activeGoal != nil { return "Relay running" }
        if engine.session.phase == .ready { return "Resume queue" }
        return engine.queuedCount == 0 ? "Start when ready" : "Start relay"
    }

    private var primarySymbol: String {
        if engine.isPaused { return "play.fill" }
        if engine.activeGoal != nil { return "waveform.path.ecg" }
        return "play.fill"
    }

    private var footerDot: Color {
        switch engine.session.phase {
        case .active: return Color.white.opacity(0.55)
        case .ready, .cooling: return Color.white.opacity(0.4)
        case .idle: return Color.white.opacity(0.22)
        }
    }
}
