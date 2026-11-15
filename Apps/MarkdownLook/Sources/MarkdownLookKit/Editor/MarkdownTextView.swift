internal import AppKit

/// The editor's text view: a plain `NSTextView` that says when it takes and gives up the keyboard, which nothing else tells
/// whoever shows it (ADR-0010).
@available(macOS 26.0, *)
final class MarkdownTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }
}
