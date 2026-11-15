public import Foundation

/// Where a link of the page leads (ADR-0010): to a note of the page or back from one, to the host that shows the page
/// (which opens it where it likes: Sunset, in a split), to the system as before when no host takes links, or nowhere.
@available(macOS 26.0, *)
public enum NativeLinkRoute: Sendable, Equatable {
    case note(String)
    case reference(String)
    /// The host's: a web address as written, or a file of this Mac (a relative link resolved against the document's folder).
    case host(URL)
    case system
    case nothing

    /// - Parameters:
    ///   - url: the link, as the page holds it (only what `HTMLText.isSafeDestination` let through is a link at all).
    ///   - base: the folder of the document.
    ///   - hostTakesLinks: whoever shows the page asked for its links.
    public init(_ url: URL, base: URL?, hostTakesLinks: Bool) {
        if let link = NativeLink.parse(url) {
            self = link.scheme == NativeLink.note ? .note(link.label) : .reference(link.label)
            return
        }
        if let scheme = url.scheme?.lowercased() {
            let known = ["http", "https", "mailto"].contains(scheme)
            self = known ? (hostTakesLinks ? .host(url) : .system) : .nothing
            return
        }
        // A place in this page (`#part`): the page has no named places yet.
        guard hostTakesLinks, !url.path.isEmpty, let file = LocalReference.file(url.relativeString, base: base) else {
            self = .nothing
            return
        }
        self = .host(file)
    }
}
