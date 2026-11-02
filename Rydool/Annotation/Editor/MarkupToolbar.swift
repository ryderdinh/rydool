import SwiftUI

/// Editing actions shown beside a selection or inside the screenshot editor.
struct MarkupToolbar: View {
    @ObservedObject var state: MarkupSession
    @ObservedObject private var languageSettings = AppSettings.shared
    let primaryAction: AfterCaptureAction
    let onUndo: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    let onPrimary: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            tools
            separator
            palette
            separator
            actions
        }
        .padding(5)
        .modifier(MarkupToolbarSurface())
        .fixedSize()
    }

    private var tools: some View {
        ForEach(AnnotationTool.allCases) { tool in
            ToolbarControl(help: "\(tool.title) (\(tool.key.uppercased()))", selected: state.tool == tool) {
                state.tool = state.tool == tool ? nil : tool
                onInteraction()
            } label: {
                Image(systemName: tool.symbol).font(.system(size: 13, weight: .medium))
            }
        }
    }

    private var palette: some View {
        HStack(spacing: 2) {
            HStack(spacing: 5) {
                ForEach(AnnotationColor.allCases) { color in
                    Button {
                        state.color = color
                        onInteraction()
                    } label: {
                        Circle().fill(Color(nsColor: color.nsColor))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                            .frame(width: 14, height: 14)
                            .padding(2)
                            .overlay(Circle().strokeBorder(state.color == color ? Color.accentColor : .clear, lineWidth: 2))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L(color.rawValue.capitalized))
                }
            }
            .padding(.horizontal, 5)
            ToolbarControl(help: L("Thickness: %@", state.weight.title)) {
                state.weight = state.weight.next
                onInteraction()
            } label: {
                Capsule().fill(Color(nsColor: state.color.nsColor))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 16, height: state.weight.lineWidth + 1)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            ToolbarControl(help: L("Undo (⌘Z)"), enabled: state.canUndo, action: onUndo) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 13, weight: .medium))
            }
            ToolbarControl(help: L("Cancel (Esc)"), action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
            }
            ToolbarControl(help: L("Save As… (⌘S)"), action: onSave) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 13, weight: .medium))
            }
            Button(action: onPrimary) {
                Label(primaryAction.buttonTitle, systemImage: primaryAction.buttonSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(primaryAction.buttonTitle) (↩)")
            .padding(.leading, 4)
        }
    }

    private var separator: some View {
        Rectangle().fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 18).padding(.horizontal, 4)
    }
}

private struct MarkupToolbarSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 11))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}

/// Common hit target and hover behavior for small editor controls.
private struct ToolbarControl<Content: View>: View {
    let help: String
    var selected = false
    var enabled = true
    let action: () -> Void
    @ViewBuilder let label: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.1 : 0),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .help(help)
    }
}
