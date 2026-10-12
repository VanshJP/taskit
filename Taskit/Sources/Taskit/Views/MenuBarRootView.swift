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
            VStack(spacing: 12) {
                topBar
                SessionHeroView(engine: engine)
                if !engine.readinessIssues.isEmpty {
                    SetupBannerView(issues: engine.readinessIssues) {
                        showSettings = true
                    }
                }
                overarchingField
                NextUpView(
                    goal: engine.nextGoal,
                    isPaused: engine.isPaused,
                    onCopy: { engine.copyComposedPrompt() }
                )
                GoalQueueView(engine: engine)
                actionRow
                footer
            }
            .padding(14)
        }
        .frame(width: 360)
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

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("Taskit")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(.primary)
            if engine.isPaused {
                StatusPill(text: "Paused", tone: .cooling)
            }
            Spacer()
            GlassIconButton(
                systemName: engine.isPaused ? "play.fill" : "pause.fill",
                help: engine.isPaused ? "Resume auto-relay" : "Pause auto-relay"
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

    private var overarchingField: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Day goal")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("Ship auth end-to-end, keep PRs small…", text: $overarchingDraft, axis: .vertical)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(2...3)
                    .textFieldStyle(.plain)
                    .focused($overarchingFocused)
                    .onChange(of: overarchingDraft) { _, value in
                        engine.updateSettingsDebounced { $0.overarchingGoal = value }
                    }
            }
        }
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
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                }
                .menuStyle(.borderlessButton)
                .help("Start the cool-down clock. Taskit will re-prompt when it ends.")

                Button {
                    confirmClear = true
                } label: {
                    Label("Clear day", systemImage: "trash")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                }
                .buttonStyle(.plain)
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
        HStack {
            Circle()
                .fill(footerDot)
                .frame(width: 7, height: 7)
                .shadow(color: footerDot.opacity(0.55), radius: 3)
            Text(engine.statusMessage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(engine.statusMessage)
            Spacer()
            Button("Quit") {
                engine.persist()
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
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
        if engine.isPaused { return TaskitTheme.warmReady.opacity(0.8) }
        switch engine.session.phase {
        case .active: return TaskitTheme.accent
        case .ready: return TaskitTheme.warmReady
        case .cooling: return TaskitTheme.warmReady.opacity(0.7)
        case .idle: return Color.white.opacity(0.35)
        }
    }
}
