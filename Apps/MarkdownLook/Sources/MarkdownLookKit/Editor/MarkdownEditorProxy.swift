public import Observation

/// A handle on one editor, for what acts on it from outside (a menu, a key, a toolbar; ADR-0008): its selection, and the
/// formatting commands done there. Made by whoever shows the editor and given to it; an editor that is gone does nothing.
@available(macOS 26.0, *)
@MainActor @Observable
public final class MarkdownEditorProxy {
    /// The selection of the editor, in UTF-16 units of the text; nil while no editor is attached.
    public internal(set) var selection: Range<Int>?
    /// The editor has the keyboard: it was clicked, or given it.
    public internal(set) var isFocused = false
    @ObservationIgnored weak var coordinator: MarkdownSourceEditorCoordinator?

    public init() {}

    /// Does `command` on the editor's selection, as one step of undo, and leaves what it made selected.
    public func perform(_ command: MarkdownCommand) { coordinator?.perform(command) }

    /// Gives the editor the keyboard.
    public func focus() { coordinator?.focus() }
}
