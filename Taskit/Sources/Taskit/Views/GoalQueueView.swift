import AppKit
import SwiftUI
import TaskitCore

struct GoalQueueView: View {
    @Bindable var engine: RelayEngine
    @State private var draftTitle = ""
    @State private var draftPrompt = ""
    @State private var isComposerExpanded = false
    @State private var editingGoal: Goal?
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Today")
                Spacer()
                Text("\(engine.completedCount) of \(engine.goals.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(TaskitTheme.hush)
                    .monospacedDigit()
            }

            GlassSurface(cornerRadius: 20, padding: 8) {
                VStack(spacing: 0) {
                    if engine.goals.isEmpty && !isComposerExpanded {
                        emptyState
                            .padding(.vertical, 18)
                    } else {
                        List {
                            ForEach(engine.orderedGoals) { goal in
                                GoalRowView(
                                    goal: goal,
                                    onSkip: { engine.skipGoal(goal) },
                                    onDelete: { engine.deleteGoal(goal) },
                                    onOpen: {
                                        if let urlString = goal.agentURL, let url = URL(string: urlString) {
                                            NSWorkspace.shared.open(url)
                                        }
                                    },
                                    onCopy: { engine.copyComposedPrompt(for: goal) },
                                    onEdit: { editingGoal = goal },
                                    onRequeue: { engine.requeueGoal(goal) }
                                )
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                                .listRowSeparator(.hidden)
                            }
                            .onMove(perform: engine.moveGoals)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 72, maxHeight: 200)
                    }

                    composer
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                        .padding(.top, 4)
                }
            }
        }
        .sheet(item: $editingGoal) { goal in
            EditGoalSheet(goal: goal) { title, prompt in
                engine.updateGoal(goal, title: title, prompt: prompt)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.white.opacity(0.45))
            Text("Queue prompts for the day")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(Color.white.opacity(0.85))
            Text("Paste a whole plan — blank lines become separate prompts.")
                .font(.system(size: 11.5, weight: .regular, design: .default))
                .foregroundStyle(TaskitTheme.hush)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
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
                        Text("One prompt, or paste several separated by blank lines…")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.28))
                            .padding(.top, 10)
                            .padding(.leading, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draftPrompt)
                        .font(.system(size: 12, design: .rounded))
                        .frame(minHeight: 72, maxHeight: 110)
                        .scrollContentBackground(.hidden)
                        .focused($promptFocused)
                }
                .padding(4)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Button("Cancel") {
                        withAnimation(TaskitTheme.springSnappy) {
                            isComposerExpanded = false
                            draftTitle = ""
                            draftPrompt = ""
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TaskitTheme.hush)
                    .font(.system(size: 12, weight: .medium, design: .rounded))

                    Spacer()

                    Button {
                        commit()
                    } label: {
                        Label(addButtonTitle, systemImage: "plus")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Color.white.opacity(
                                    draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.2 : 0.9
                                ),
                                in: Capsule()
                            )
                            .foregroundStyle(Color.black.opacity(0.8))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            } else {
                Button {
                    withAnimation(TaskitTheme.springSnappy) {
                        isComposerExpanded = true
                        promptFocused = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add prompt")
                        Spacer()
                        Text("⌘V paste plan")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.28))
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(TaskitTheme.hush)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundStyle(Color.white.opacity(0.16))
                    )
                }
                .buttonStyle(.plain)
                .onPasteCommand(of: [.plainText]) { providers in
                    handlePasteProviders(providers)
                }
            }
        }
    }

    private var addButtonTitle: String {
        let count = PromptBulkImport.prompts(from: draftPrompt).count
        return count > 1 ? "Add \(count) prompts" : "Add prompt"
    }

    private func commit() {
        let raw = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let prompts = PromptBulkImport.prompts(from: raw)
        if prompts.count > 1 || draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = engine.addGoalsFromPaste(raw)
        } else {
            engine.addGoal(title: draftTitle, prompt: prompts[0])
        }
        withAnimation(TaskitTheme.springSnappy) {
            draftTitle = ""
            draftPrompt = ""
            isComposerExpanded = false
        }
    }

    private func handlePasteProviders(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: String.self) { object, _ in
            guard let string = object as? String else { return }
            Task { @MainActor in
                if engine.addGoalsFromPaste(string) > 0 {
                    withAnimation(TaskitTheme.springSnappy) {
                        isComposerExpanded = false
                    }
                }
            }
        }
    }
}
