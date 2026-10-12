import SwiftUI
import TaskitCore

/// One prompt in the queue. Hover shows its actions; finished prompts expand to show Claude's reply.
@MainActor
struct QueueRowView: View {
    let app: AppModel
    let item: QueueItem
    /// 1-based position among pending prompts.
    let position: Int?
    let isUpNext: Bool
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    @State private var hovering = false

    private var engine: RelayEngine { app.engine }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                glyph
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundStyle(item.isFinished ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let meta {
                        Text(meta)
                            .font(.system(size: 11))
                            .foregroundStyle(metaColor)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actions
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                if item.isFinished { toggleExpanded() }
            }

            if isExpanded {
                details
                    .padding(.leading, 38)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlighted ? Theme.rowHighlight : Color.clear)
        )
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private var highlighted: Bool {
        item.status == .running || item.status == .waiting || hovering || isExpanded
    }

    // MARK: - Pieces

    @ViewBuilder
    private var glyph: some View {
        switch item.status {
        case .queued:
            Text("\(position ?? 0)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5))
        case .running:
            ProgressView().controlSize(.mini)
        case .waiting:
            Image(systemName: "hourglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.waitingText)
        case .done:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.failure)
        }
    }

    private var meta: String? {
        switch item.status {
        case .queued:
            return isUpNext ? "Up next" : nil
        case .running:
            if engine.runState != .running { return "Running · Taskit holds after this one" }
            guard let started = item.startedAt else { return "Running" }
            return "Running · started \(Format.time(started))"
        case .waiting:
            if let limit = engine.limit {
                return "Paused by usage limit · resumes \(Format.time(limit.resetsAt))"
            }
            return "Paused by usage limit"
        case .done:
            guard let ms = item.durationMs else { return "Done" }
            return "Done in \(DurationFormat.short(Double(ms) / 1000))"
        case .failed:
            return item.error.map { "Failed · " + firstLine($0) } ?? "Failed"
        }
    }

    private var metaColor: Color {
        switch item.status {
        case .waiting: return Theme.waitingText
        case .failed: return Theme.failure
        default: return Color.secondary
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 0) {
            switch item.status {
            case .queued, .waiting:
                if position.map({ $0 > 1 }) ?? false {
                    IconButton(systemName: "chevron.up", label: "Move up", size: 11) {
                        engine.moveUp(item.id)
                    }
                }
                IconButton(systemName: "xmark", label: "Remove", size: 10) {
                    engine.remove(item.id)
                }
            case .running:
                IconButton(systemName: "stop.circle", label: "Stop this prompt", size: 14) {
                    engine.stopCurrent()
                }
            case .done, .failed:
                IconButton(
                    systemName: "chevron.down",
                    label: isExpanded ? "Hide reply" : "Show reply",
                    size: 11,
                    action: toggleExpanded
                )
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        // Queued rows only show their buttons on hover; running and finished rows always do.
        .opacity(item.isPending && !hovering ? 0 : 1)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            FittedScrollView(maxHeight: 160) {
                Text(detailText)
                    .font(.system(size: 12))
                    .foregroundStyle(item.status == .failed ? Theme.failure : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )

            HStack(spacing: 6) {
                if item.sessionId != nil {
                    Button {
                        app.openInTerminal(sessionId: item.sessionId)
                    } label: {
                        Label("Open in Terminal", systemImage: "terminal")
                    }
                }
                Button("Copy") { app.copyToClipboard(detailText) }
                Button("Run again") { engine.runAgain(item.id) }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Copy prompt") { app.copyToClipboard(item.prompt) }
        if item.isPending {
            Button("Move to top") { engine.moveToTop(item.id) }
            Button("Remove", role: .destructive) { engine.remove(item.id) }
        }
        if item.isFinished {
            if let result = item.result, !result.isEmpty {
                Button("Copy reply") { app.copyToClipboard(result) }
            }
            if item.sessionId != nil {
                Button("Open in Terminal") { app.openInTerminal(sessionId: item.sessionId) }
            }
            Button("Run again") { engine.runAgain(item.id) }
            Button("Remove", role: .destructive) { engine.remove(item.id) }
        }
        if item.status == .running {
            Button("Stop this prompt") { engine.stopCurrent() }
        }
    }

    private var detailText: String {
        switch item.status {
        case .failed: return item.error ?? "Failed without an error message."
        default:
            let text = item.result ?? ""
            return text.isEmpty ? "Claude finished without a text reply." : text
        }
    }

    private var accessibilityText: String {
        var parts = [item.title, item.status.rawValue]
        if let meta { parts.append(meta) }
        return parts.joined(separator: ", ")
    }

    private func firstLine(_ text: String) -> String {
        text.split(separator: "\n").first.map(String.init) ?? text
    }
}
