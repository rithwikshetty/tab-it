import SwiftUI
import ImageIO
import UIKit

/// Drop-in replacement for `AsyncImage(url:)` that decodes a remote image at the
/// pixel size it will actually be shown at, instead of its native resolution.
///
/// A full-resolution receipt photo decodes to a bitmap sized by its pixel
/// dimensions, not the slot it appears in: a 12 MP image is a ~48 MB bitmap
/// whether it fills a 56pt thumbnail or a 180pt card. Downsampling with ImageIO
/// bounds the decoded bitmap to the display size, removing that peak (and the
/// redundant second decode when a card and its full-screen preview are both up).
///
/// The phase-based `content` closure mirrors `AsyncImage` so call sites keep
/// their existing placeholder handling.
struct DownsampledAsyncImage<Content: View>: View {
    let url: URL?
    /// Longest edge of the display slot, in points. The image is decoded to this
    /// many points multiplied by the display scale.
    let maxPointSize: CGFloat
    @ViewBuilder var content: (AsyncImagePhase) -> Content

    @Environment(\.displayScale) private var displayScale
    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(phase)
            .task(id: ReloadKey(url: url, scale: displayScale)) {
                await reload()
            }
    }

    @MainActor
    private func reload() async {
        guard let url else {
            phase = .empty
            return
        }
        phase = .empty
        do {
            let image = try await ReceiptImageLoader.downsampledImage(
                from: url,
                maxPixelSize: maxPointSize * displayScale
            )
            phase = .success(Image(uiImage: image))
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure(error)
        }
    }

    private struct ReloadKey: Equatable {
        let url: URL?
        let scale: CGFloat
    }
}

/// Fetches and downsamples remote images for display. Uses the shared
/// `URLCache`, so the encoded bytes are cached (and system-evicted) the same way
/// `AsyncImage` caches them.
enum ReceiptImageLoader {
    enum Failure: Error { case decodeFailed }

    static func downsampledImage(from url: URL, maxPixelSize: CGFloat) async throws -> sending UIImage {
        let (data, _) = try await URLSession.shared.data(from: url)
        try Task.checkCancellation()
        return try downsample(data: data, maxPixelSize: maxPixelSize)
    }

    static func downsample(data: Data, maxPixelSize: CGFloat) throws -> sending UIImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw Failure.decodeFailed
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded())
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw Failure.decodeFailed
        }
        return UIImage(cgImage: cgImage)
    }
}
