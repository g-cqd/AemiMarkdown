public import CoreGraphics
public import Foundation
internal import ImageIO

/// A picture read from a file: its pixels, and its size on the page.
@available(macOS 26.0, *)
public struct NativePicture: Sendable {
    public var image: CGImage
    /// In points: the picture's pixels at the density its file names (a screenshot of a Retina screen is half its pixels).
    public var size: CGSize
}

/// Reads the picture of an image row (ADR-0010): off the caller's actor, decoded no larger than it is drawn, and never from
/// a file larger than a bound, so a document cannot make the app decode what it likes.
@available(macOS 26.0, *)
public enum NativeImageLoader {
    /// 64 MiB: a file larger than this is not opened.
    public static let largestFile = 64 << 20
    /// The longest side decoded when none is asked for.
    public static let longestSide = 2560

    /// The picture at `url`, or nil when it is not there, too large, or not a picture ImageIO reads.
    /// - Complexity: O(the file) to decode, once; nothing is kept here.
    @concurrent
    public static func load(
        _ url: URL,
        longestSide: Int = Self.longestSide,
        largestFile: Int = Self.largestFile
    ) async -> NativePicture? {
        guard url.isFileURL,
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true, let bytes = values.fileSize, bytes <= largestFile
        else { return nil }
        let quiet = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, quiet),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, quiet) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        let turned = (properties[kCGImagePropertyOrientation] as? Int ?? 1) >= 5
        let density = Swift.max((properties[kCGImagePropertyDPIWidth] as? Double ?? 72) / 72, 1)
        let pixels = turned ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Swift.min(Swift.max(width, height), Swift.max(longestSide, 1))
            ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NativePicture(
            image: image,
            size: CGSize(width: (pixels.width / density).rounded(), height: (pixels.height / density).rounded())
        )
    }
}
