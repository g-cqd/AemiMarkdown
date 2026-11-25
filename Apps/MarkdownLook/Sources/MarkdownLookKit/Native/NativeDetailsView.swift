internal import SwiftUI

/// A `<details>` disclosure block (matching `ViewerStyle`'s `.disclosure` and `NativeFrontMatterView`):
/// an outlined box with the summary line and rotating chevron, expanding to show its Markdown rows inside.
@available(macOS 26.0, *)
struct NativeDetailsView: View {
    let details: NativeDetails
    let size: CGFloat
    let settings: ViewerSettings
    @State private var open: Bool

    init(details: NativeDetails, size: CGFloat, settings: ViewerSettings) {
        self.details = details
        self.size = size
        self.settings = settings
        _open = State(initialValue: details.isOpen)
    }

    var body: some View {
        let leading = size * 1.6
        let label = details.summary.characters.isEmpty ? AttributedString("Details") : details.summary
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: size * 0.6) {
                PageText(
                    string: label,
                    size: size,
                    weight: .medium,
                    color: NativeTheme.text,
                    lineHeight: leading
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                PageText(
                    string: AttributedString("\u{203A}"),
                    size: size,
                    color: NativeTheme.tertiary,
                    lineHeight: leading,
                    wraps: false
                )
                .frame(width: size)
                .rotationEffect(.degrees(open ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }

            if open, !details.rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(details.rows) { row in
                        NativeRowView(row: row, size: size, settings: settings)
                    }
                }
                .environment(\.documentSelection, nil)
                .padding(.top, size * 0.6)
            }
        }
        .padding(.vertical, size * 0.8 + NativeFrontMatterView.stroke)
        .padding(.horizontal, size * 1.1 + NativeFrontMatterView.stroke)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.6)
                .strokeBorder(NativeTheme.rule, lineWidth: NativeFrontMatterView.stroke)
        )
    }
}
