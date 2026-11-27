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
    private nonisolated static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

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

    private func makeRequest(url: URL, targetSize: CGSize?, cropToFill: Bool = true) -> ImageRequest {
        if let targetSize, targetSize.width > 0, targetSize.height > 0 {
            let resize = ImageProcessors.Resize(
                size: targetSize,
                unit: .points,
                contentMode: cropToFill ? .aspectFill : .aspectFit,
                crop: cropToFill,
                upscale: false
            )
            return ImageRequest(url: url, processors: [resize])
        }
        return ImageRequest(url: url)
    }

    func cachedUIImage(for url: URL, targetSize: CGSize? = nil, cropToFill: Bool = true) -> UIImage? {
        pipeline.cache[makeRequest(url: url, targetSize: targetSize, cropToFill: cropToFill)]?.image
    }

    func loadUIImage(for url: URL, targetSize: CGSize? = nil, cropToFill: Bool = true) async -> UIImage? {
        let req = makeRequest(url: url, targetSize: targetSize, cropToFill: cropToFill)
        if let hit = pipeline.cache[req]?.image {
            return hit
        }
        return try? await pipeline.image(for: req)
    }

    func prefetch(urls: [URL], targetSize: CGSize? = nil, cropToFill: Bool = true) {
        guard !urls.isEmpty else { return }
        let requests = urls.map { makeRequest(url: $0, targetSize: targetSize, cropToFill: cropToFill) }
        prefetcher.startPrefetching(with: requests)
    }

    func stopPrefetching(urls: [URL], targetSize: CGSize? = nil, cropToFill: Bool = true) {
        guard !urls.isEmpty else { return }
        let requests = urls.map { makeRequest(url: $0, targetSize: targetSize, cropToFill: cropToFill) }
        prefetcher.stopPrefetching(with: requests)
    }

    /// Extracts an ambient highlight color off the main thread from a downsampled artwork image.
    func extractGlowColor(for url: URL) async -> Color? {
        let key = url.absoluteString
        if let cached = glowColorCache[key] {
            return cached
        }

        guard let uiImage = await loadUIImage(for: url, targetSize: CGSize(width: 96, height: 144)),
              let cgImage = uiImage.cgImage else {
            return nil
        }

        let rgb = await Task.detached(priority: .utility) { () -> (Double, Double, Double)? in
            let ciInput = CIImage(cgImage: cgImage)
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
            AuraImageCache.sharedCIContext.render(
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

            return (Double(r), Double(g), Double(b))
        }.value

        guard let (r, g, b) = rgb else { return nil }
        let color = Color(red: r, green: g, blue: b)
        glowColorCache[key] = color
        return color
    }
}

// MARK: - Nuke-Backed Cached SwiftUI Image View

struct AuraCachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var targetSize: CGSize? = nil
    var cropToFill: Bool = true
    var onImageLoaded: ((UIImage) -> Void)? = nil
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var loadedKey: String?

    private var requestKey: String? {
        guard let url else { return nil }
        let modeTag = cropToFill ? "fill" : "fit"
        if let targetSize {
            return "\(url.absoluteString)|\(Int(targetSize.width))x\(Int(targetSize.height))|\(modeTag)"
        }
        return "\(url.absoluteString)|\(modeTag)"
    }

    private var activeImage: UIImage? {
        if let loadedImage, loadedKey == requestKey {
            return loadedImage
        }
        if let url, let cached = AuraImageCache.shared.cachedUIImage(for: url, targetSize: targetSize, cropToFill: cropToFill) {
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
        .task(id: requestKey) {
            guard let targetURL = url, let currentKey = requestKey else {
                loadedImage = nil
                loadedKey = nil
                return
            }
            if let hit = AuraImageCache.shared.cachedUIImage(for: targetURL, targetSize: targetSize, cropToFill: cropToFill) {
                loadedImage = hit
                loadedKey = currentKey
                onImageLoaded?(hit)
                return
            }
            if let fetched = await AuraImageCache.shared.loadUIImage(for: targetURL, targetSize: targetSize, cropToFill: cropToFill), !Task.isCancelled {
                loadedImage = fetched
                loadedKey = currentKey
                onImageLoaded?(fetched)
            }
        }
    }
}
