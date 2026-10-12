import SwiftUI
import TaskitCore

struct EditGoalSheet: View {
    let goal: Goal
    var onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var prompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Edit prompt")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            TextField("Short title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $prompt)
                .font(.system(size: 13, design: .rounded))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            PrimaryGlassButton(title: "Save", systemImage: "checkmark") {
                onSave(title, prompt)
                dismiss()
            }
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .frame(width: 380, height: 320)
        .background { TaskitTheme.atmosphere }
        .onAppear {
            title = goal.title
            prompt = goal.prompt
        }
    }
}
