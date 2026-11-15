public import Foundation

/// A paragraph that is one image (ADR-0010): a row of its own, drawn from a local file when there is one, and as the
/// paragraph's text (the image named, as an image among words always is) when there is none.
@available(macOS 26.0, *)
public struct NativeImage: Sendable {
    /// The destination as the document wrote it.
    public var source: String
    public var alt: String
    /// Where the image leads, when it is inside a link.
    public var link: URL?
    /// What shows where the picture cannot.
    public var fallback: AttributedString

    public init(source: String, alt: String, link: URL? = nil, fallback: AttributedString) {
        self.source = source
        self.alt = alt
        self.link = link
        self.fallback = fallback
    }

    /// The file the picture is read from: nothing is ever fetched from a network.
    /// - Parameter base: the folder of the document, which a relative destination is under.
    /// - Returns: a file of this Mac, or nil when the destination is not one.
    public func file(base: URL?) -> URL? { LocalReference.file(source, base: base) }
}

/// A destination written in a document, as a file of this Mac or as nothing.
@available(macOS 26.0, *)
enum LocalReference {
    /// The file `destination` names: a path (relative to `base`, or absolute) or a `file:` address of this Mac, without its
    /// query and fragment. Anything with another scheme, or a host, is nil.
    static func file(_ destination: String, base: URL?) -> URL? {
        var path = Substring(destination.trimmingCharacters(in: .whitespacesAndNewlines))
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = path[..<cut] }
        guard !path.isEmpty, !path.hasPrefix("//") else { return nil }
        if let colon = path.firstIndex(of: ":"), isScheme(path[..<colon]) {
            guard path[..<colon].lowercased() == "file", let url = URL(string: String(path)),
                (url.host ?? "").isEmpty || url.host == "localhost"
            else { return nil }
            return URL(fileURLWithPath: url.path).standardizedFileURL
        }
        let decoded = String(path).removingPercentEncoding ?? String(path)
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded).standardizedFileURL }
        guard let base, base.isFileURL else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
    }

    /// Letters, then letters, digits, `+`, `-` or `.`: what comes before the colon of an address.
    private static func isScheme(_ text: Substring) -> Bool {
        guard let first = text.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII
                && (scalar.properties.isAlphabetic || ("0" ... "9").contains(scalar)
                    || "+-.".unicodeScalars.contains(scalar))
        }
    }
}
