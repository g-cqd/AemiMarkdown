public import SwiftUI

/// What the host shows in a link's menu (Sunset: open in a new tab, beside, in a window; copy the address). Two are always
/// equal: the content is the host's, set once, and closures cannot be compared.
@available(macOS 26.0, *)
struct LinkMenuAction: Equatable {
    let content: @MainActor (URL) -> AnyView

    static func == (lhs: Self, rhs: Self) -> Bool { true }

    /// Where a link's menu is about, as a click would give it to the host: a web address as written, a file of this Mac;
    /// nil for a note's link, which has no menu.
    /// - Parameters:
    ///   - url: the link as the page holds it.
    ///   - base: the folder of the document.
    /// - Returns: the target, or nil.
    static func target(of url: URL, base: URL?) -> URL? {
        if case .host(let target) = NativeLinkRoute(url, base: base, hostTakesLinks: true) { return target }
        return nil
    }
}

extension EnvironmentValues {
    /// The menu of a link of the page, given where it leads; nil when links have no menu.
    @available(macOS 26.0, *)
    @Entry var markdownLinkMenu: LinkMenuAction?
}

extension View {
    /// Gives each link of a native page a menu, opened by a secondary click on its words.
    /// - Parameter menu: Its items, given where the link leads (a web address as written, or a file of this Mac).
    /// - Returns: The view, its links with a menu.
    @available(macOS 26.0, *)
    public func linkMenu<Items: View>(@ViewBuilder _ menu: @escaping @MainActor (URL) -> Items) -> some View {
        environment(\.markdownLinkMenu, LinkMenuAction { AnyView(menu($0)) })
    }
}
