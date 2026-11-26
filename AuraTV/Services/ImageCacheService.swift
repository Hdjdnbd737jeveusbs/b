import Foundation
import SwiftUI
import UIKit
import CoreImage
import Nuke

// MARK: - Nuke Image Cache & Prefetch Service

@MainActor
final class AuraImageCache {
    static let shared = AuraImageCache()

    let pipeline: ImagePipeline
    private let prefetcher: ImagePrefetcher
    private var glowColorCache: [String: Color] = [:]
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {
        ImageCache.shared.costLimit = 256 * 1024 * 1024
        var config = ImagePipeline.Configuration()
        config.imageCache = ImageCache.shared
        config.isUsingPrepareForDisplay = true

        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let diskDir = cachesDir.appendingPathComponent("AuraNukeDiskCache", isDirectory: true)
            if let diskCache = try? DataCache(path: diskDir) {
                diskCache.sizeLimit = 512 * 1024 * 1024
                config.dataCache = diskCache
            }
        }

        let pipe = ImagePipeline(configuration: config)
        self.pipeline = pipe
        self.prefetcher = ImagePrefetcher(pipeline: pipe)
    }

    func cachedUIImage(for url: URL) -> UIImage? {
        pipeline.cache[ImageRequest(url: url)]?.image
    }

    func loadUIImage(for url: URL) async -> UIImage? {
        if let hit = cachedUIImage(for: url) {
            return hit
        }
        return try? await pipeline.image(for: url)
    }

    func prefetch(urls: [URL]) {
        guard !urls.isEmpty else { return }
        prefetcher.startPrefetching(with: urls)
    }

    func stopPrefetching(urls: [URL]) {
        guard !urls.isEmpty else { return }
        prefetcher.stopPrefetching(with: urls)
    }

    /// Extracts an ambient highlight color from a cached poster or backdrop image for Soft Glow theme mode.
    func extractGlowColor(for url: URL) async -> Color? {
        let key = url.absoluteString
        if let cached = glowColorCache[key] {
            return cached
        }

        guard let uiImage = await loadUIImage(for: url),
              let ciInput = CIImage(image: uiImage) else {
            return nil
        }

        let extent = ciInput.extent
        guard extent.width > 0, extent.height > 0,
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: ciInput,
                  kCIInputExtentKey: CIVector(cgRect: extent)
              ]),
              let outputImage = filter.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var r = CGFloat(bitmap[0]) / 255.0
        var g = CGFloat(bitmap[1]) / 255.0
        var b = CGFloat(bitmap[2]) / 255.0

        // Gently boost dark/muted average colors so Soft Glow stays richly tinted on black cinema UI.
        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bri: CGFloat = 0
        var alpha: CGFloat = 1
        let uiColor = UIColor(red: r, green: g, blue: b, alpha: 1)
        if uiColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha) {
            let boosted = UIColor(
                hue: hue,
                saturation: max(sat, 0.36),
                brightness: min(max(bri, 0.42), 0.78),
                alpha: 1.0
            )
            boosted.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        }

        let color = Color(red: Double(r), green: Double(g), blue: Double(b))
        glowColorCache[key] = color
        return color
    }
}

// MARK: - Nuke-Backed Cached SwiftUI Image View

struct AuraCachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var onImageLoaded: ((UIImage) -> Void)? = nil
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var loadedURL: URL?

    private var activeImage: UIImage? {
        if let loadedImage, loadedURL == url {
            return loadedImage
        }
        if let url, let cached = AuraImageCache.shared.cachedUIImage(for: url) {
            return cached
        }
        return nil
    }

    var body: some View {
        Group {
            if let uiImage = activeImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let targetURL = url else {
                loadedImage = nil
                loadedURL = nil
                return
            }
            if let hit = AuraImageCache.shared.cachedUIImage(for: targetURL) {
                loadedImage = hit
                loadedURL = targetURL
                onImageLoaded?(hit)
                return
            }
            if let fetched = await AuraImageCache.shared.loadUIImage(for: targetURL), !Task.isCancelled {
                loadedImage = fetched
                loadedURL = targetURL
                onImageLoaded?(fetched)
            }
        }
    }
}
