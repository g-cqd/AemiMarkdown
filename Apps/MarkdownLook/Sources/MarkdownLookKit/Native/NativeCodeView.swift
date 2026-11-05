internal import AppKit
import SwiftUI

/// A code block: the code in a rounded tint that scrolls sideways, its language and a copy button in the corner.
struct NativeCodeView: View {
    let code: NativeCode
    let size: CGFloat
    let settings: ViewerSettings
    @State private var hovering = false
    @State private var copied = false

    private var hasHeader: Bool {
        (settings.showsLanguage && !code.isHTML && !code.language.isEmpty) || (settings.copyButton && !code.isHTML)
    }

    /// A header row above the code, with the language on the left and the copy button on the right, so neither is ever over the code.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasHeader { header }
            ScrollView(.horizontal) {
                Text(code.shown)
                    .font(.system(size: size * 0.9, design: .monospaced))
                    .lineSpacing(size * 0.3)
                    .foregroundStyle(code.isHTML ? .secondary : .primary)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(
                        EdgeInsets(
                            top: hasHeader ? size * 0.2 : size * 1.1,
                            leading: size * 1.3,
                            bottom: size * 1.1,
                            trailing: size * 1.3
                        )
                    )
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: size * 0.6))
        .onHover { hovering = $0 }
    }

    private var header: some View {
        HStack(spacing: size * 0.3) {
            if settings.showsLanguage, !code.isHTML, !code.language.isEmpty {
                Text(code.language).font(.system(size: size * 0.75, weight: .medium)).foregroundStyle(.tertiary)
                    .textSelection(.disabled)
            }
            Spacer(minLength: 0)
            if settings.copyButton, !code.isHTML { copyButton }
        }
        .frame(height: size * 1.9)
        .padding(.leading, size * 1.3)
        .padding(.trailing, size * 0.5)
        .padding(.top, size * 0.3)
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code.raw, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "document.on.document")
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: size * 0.95, weight: .medium))
                .frame(width: size * 1.9, height: size * 1.9)
                .contentShape(.rect(cornerRadius: size * 0.3))
        }
        .buttonStyle(.plain)
        .foregroundStyle(copied ? .primary : .secondary)
        .opacity(hovering || copied ? 1 : 0)
        .animation(.smooth(duration: 0.15), value: hovering)
        .help("Copy code")
        .accessibilityLabel("Copy code")
    }
}
