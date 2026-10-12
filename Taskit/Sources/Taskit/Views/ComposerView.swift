import SwiftUI
import TaskitCore

/// Always-ready input at the bottom of the panel. Enter adds; a pasted list adds several.
@MainActor
struct ComposerView: View {
    @Bindable var app: AppModel
    @FocusState private var focused: Bool

    private var count: Int { PromptBulkImport.prompts(from: app.draft).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                TextField("Add a prompt…", text: $app.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit(add)
                    .padding(.vertical, 3)
                    .accessibilityLabel("Add a prompt")

                Button(action: add) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(count > 0 ? Color.accentColor : Color.secondary.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .disabled(count == 0)
                .help("Add to queue")
                .accessibilityLabel("Add to queue")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.6) : Theme.hairline, lineWidth: focused ? 1.5 : 1)
            )

            Text(count > 1 ? "Enter adds \(count) prompts" : "Enter to add · paste a list to add several at once")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
        .padding(10)
        .onAppear { focused = true }
    }

    private func add() {
        guard app.engine.add(app.draft) > 0 else { return }
        app.draft = ""
    }
}
