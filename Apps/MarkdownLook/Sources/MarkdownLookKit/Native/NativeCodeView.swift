internal import AppKit
internal import SwiftUI

/// A code block: the code in a rounded tint that scrolls sideways, its language and a copy button in the corner.
struct NativeCodeView: View {
    let code: NativeCode
    let size: CGFloat
    let settings: ViewerSettings
    @State private var hovering = false
    @State private var copied = false

    private var showsLanguage: Bool { settings.showsLanguage && !code.isHTML && !code.language.isEmpty }
    private var showsCopy: Bool { settings.copyButton && !code.isHTML }

    /// The block as the page draws it: padding of 1.1 em by 1.3 em in a rounded tint, lines of 1.55 of the block's own size (the code is 0.9 em inside it, the line's strut keeps the lines at the block's
    /// pitch), the language small in the top right corner over the padding, and, on hover, the copy button in its place.
    var body: some View {
        let lineHeight = size * 1.55
        ScrollView(.horizontal) {
            BalancedLayout(lineHeight: lineHeight) {
                Text(code.shown)
                    .font(.system(size: size * 0.9, design: .monospaced))
                    .lineHeight(.exact(points: lineHeight))
                    .foregroundColor(code.isHTML ? NativeTheme.secondary : NativeTheme.text)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .offset(y: NativeMetrics.shift(size: size * 0.9, design: .monospaced, strut: size, lineHeight: lineHeight))
            .padding(EdgeInsets(top: size * 1.1, leading: size * 1.3, bottom: size * 1.1, trailing: size * 1.3))
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(NativeTheme.tint, in: .rect(cornerRadius: size * 0.6))
        .overlay(alignment: .topTrailing) { corner }
        .onHover { hovering = $0 }
    }

    private var corner: some View {
        ZStack(alignment: .topTrailing) {
            if showsLanguage {
                let label = size * 0.75
                let font = NSFont.systemFont(ofSize: label, weight: .medium)
                // A line of 1: the box is the font's size, not its natural height, so the text rises by half the difference.
                let rise = (font.ascender - font.descender + font.leading - label) / 2
                Text(code.language).font(.system(size: label, weight: .medium)).tracking(label * 0.04)
                    .foregroundColor(NativeTheme.tertiary).textSelection(.disabled).lineLimit(1)
                    .padding(.top, label * 0.55 - rise).padding(.trailing, label * 0.9)
                    .opacity(hovering && showsCopy || copied ? 0 : 1)
            }
            if showsCopy { copyButton }
        }
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
