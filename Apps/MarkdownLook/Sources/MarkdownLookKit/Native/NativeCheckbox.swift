public import SwiftUI

/// A task's box: the system's checkbox, sized for the text beside it. A click asks the view's owner to rewrite the box in the
/// source (``SwiftUI/View/onTaskToggle(_:)``); with no owner to ask, it is shown and does not act.
@available(macOS 26.0, *)
struct NativeCheckbox: View {
    let done: Bool
    /// Where its `[ ]` starts in the source.
    let offset: Int
    /// The size of the text beside it.
    let size: Double

    @Environment(\.markdownTaskToggle) private var toggle

    var body: some View {
        Toggle("", isOn: Binding(get: { done }, set: { _ in toggle?.action(offset) }))
            .toggleStyle(.checkbox).labelsHidden().controlSize(controlSize)
            .allowsHitTesting(toggle != nil)
    }

    /// The control size whose box is nearest the text: small below 11 points, large from 17.
    private var controlSize: ControlSize {
        if size < 11 { return .small }
        return size < 17 ? .regular : .large
    }
}

/// What a click on a task's box does. Two are always equal: the action is the owner's, set once, and comparing closures is not
/// possible.
struct TaskToggleAction: Equatable {
    let action: @MainActor (Int) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    /// What a click on a task's box does, given where its `[ ]` starts in the source; nil when the boxes do not act.
    @Entry var markdownTaskToggle: TaskToggleAction?
}

extension View {
    /// Makes the boxes of tasks act: a click on one calls `action` with where its `[ ]` starts in the source, for the owner to
    /// rewrite it (``NativeMarker/toggle(in:at:)`` says how).
    /// - Parameter action: Called with the offset of the box's `[` in the source.
    /// - Returns: The view, its tasks' boxes acting.
    @available(macOS 26.0, *)
    public func onTaskToggle(_ action: @escaping @MainActor (Int) -> Void) -> some View {
        environment(\.markdownTaskToggle, TaskToggleAction(action: action))
    }
}
