import AppKit
import SwiftUI
import TaskitCore

struct GoalQueueView: View {
    @Bindable var engine: RelayEngine
    @State private var draftTitle = ""
    @State private var draftPrompt = ""
    @State private var isComposerExpanded = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Today")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(engine.completedCount) of \(engine.goals.count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                if engine.goals.isEmpty && !isComposerExpanded {
                    emptyState
                } else {
                    List {
                        ForEach(engine.goals.sorted(by: { $0.sortIndex < $1.sortIndex })) { goal in
                            GoalRowView(
                                goal: goal,
                                onSkip: { engine.skipGoal(goal) },
                                onDelete: { engine.deleteGoal(goal) },
                                onOpen: {
                                    if let urlString = goal.agentURL, let url = URL(string: urlString) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                        }
                        .onMove(perform: engine.moveGoals)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 220)
                }

                composer
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(TaskitTheme.accent.opacity(0.9))
            Text("Queue prompts for the day")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("When a five-hour window clears, Taskit sends the next one — even if you’re away.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isComposerExpanded {
                TextField("Short title (optional)", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                ZStack(alignment: .topLeading) {
                    if draftPrompt.isEmpty {
                        Text("What should the agent do next?")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 10)
                            .padding(.leading, 10)
                    }
                    TextEditor(text: $draftPrompt)
                        .font(.system(size: 12, design: .rounded))
                        .frame(minHeight: 64, maxHeight: 96)
                        .scrollContentBackground(.hidden)
                        .focused($promptFocused)
                }
                .padding(4)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Button("Cancel") {
                        withAnimation(.snappy) {
                            isComposerExpanded = false
                            draftTitle = ""
                            draftPrompt = ""
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))

                    Spacer()

                    Button {
                        commit()
                    } label: {
                        Label("Add prompt", systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(TaskitTheme.accent.opacity(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1), in: Capsule())
                            .foregroundStyle(Color.black.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button {
                    withAnimation(.snappy) {
                        isComposerExpanded = true
                        promptFocused = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add prompt")
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundStyle(Color.white.opacity(0.18))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commit() {
        let prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        engine.addGoal(title: draftTitle, prompt: prompt)
        withAnimation(.snappy) {
            draftTitle = ""
            draftPrompt = ""
            isComposerExpanded = false
        }
    }
}
