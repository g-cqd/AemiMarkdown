internal import SwiftUI

/// An image row (ADR-0010): the picture of a local file at its own size, never wider than the column; what the paragraph
/// would have been where no picture can be read.
@available(macOS 26.0, *)
struct NativeImageView<Fallback: View>: View {
    let image: NativeImage
    let size: CGFloat
    @ViewBuilder let fallback: Fallback
    @Environment(\.documentBase) private var base
    @Environment(\.openURL) private var openURL
    @State private var picture: NativePicture?

    var body: some View {
        let file = image.file(base: base)
        Group {
            if let picture {
                Image(decorative: picture.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(picture.size, contentMode: .fit)
                    .frame(maxWidth: picture.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.3))
                    .accessibilityLabel(image.alt)
                    .onTapGesture { if let link = image.link { openURL(link) } }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                fallback
            }
        }
        .task(id: file) {
            guard let file else {
                picture = nil
                return
            }
            picture = await NativeImageLoader.load(file)
        }
    }
}

@available(macOS 26.0, *)
extension EnvironmentValues {
    /// The folder of the document being drawn: what a relative picture is under.
    @Entry var documentBase: URL?
}
