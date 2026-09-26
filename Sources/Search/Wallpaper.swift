import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class Wallpaper: ObservableObject {
    static let shared = Wallpaper()

    @Published var enabled: Bool {
        didSet {
            settings.set(enabled, forKey: "wallpaper")
            if !enabled { image = nil; loaded = false }
        }
    }
    @Published var fit: Bool {
        didSet { settings.set(fit, forKey: "wallpaper.fit") }
    }
    @Published private(set) var image: CGImage?
    @Published private(set) var hasImage: Bool
    @Published private(set) var busy = false
    @Published private(set) var error: String?

    private let file: URL
    private let settings: UserDefaults
    private var loaded = false

    init(file: URL = Store.file("wallpaper.png"), settings: UserDefaults = Store.settings) {
        self.file = file
        self.settings = settings
        enabled = settings.bool(forKey: "wallpaper")
        fit = settings.bool(forKey: "wallpaper.fit")
        hasImage = FileManager.default.fileExists(atPath: file.path)
    }

    func load() async {
        guard enabled, hasImage, !loaded, !busy else { return }
        loaded = true
        busy = true
        defer { busy = false }
        let file = file
        let result = await Task.detached(priority: .utility) {
            try? Self.read(file)
        }.value
        if enabled { image = result }
        if result == nil { error = "Couldn't open the saved image. Choose another." }
    }

    func use(_ source: URL) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        let file = file
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                let image = try Self.read(source)
                let data = NSMutableData()
                guard let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
                else { throw Failure.unreadable }
                CGImageDestinationAddImage(output, image, nil)
                guard CGImageDestinationFinalize(output) else { throw Failure.unreadable }
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Commit only a decoded copy; a failed replacement leaves the old image intact.
                try (data as Data).write(to: file, options: .atomic)
                return image
            }.value
            image = result
            hasImage = true
            loaded = true
            enabled = true
        } catch {
            self.error = "Couldn't use that image. \(error.localizedDescription)"
        }
    }

    func remove() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        let file = file
        do {
            try await Task.detached(priority: .utility) {
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
            }.value
            enabled = false
            hasImage = false
            fit = false
        } catch {
            self.error = "Couldn't remove the saved image. Try again."
        }
    }

    nonisolated private static func read(_ url: URL) throws -> CGImage {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true else { throw Failure.unreadable }
        guard let bytes = size.fileSize, bytes <= 50 * 1024 * 1024 else { throw Failure.large }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.jpeg, .png, .heic, .heif].contains(where: { $0.identifier == type }),
              CGImageSourceGetCount(source) == 1
        else { throw Failure.format }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0, width * height <= 100_000_000
        else { throw Failure.large }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2560,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let color = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: color,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.unreadable }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard let image = context.makeImage() else { throw Failure.unreadable }
        return image
    }

    private enum Failure: LocalizedError {
        case format, large, unreadable

        var errorDescription: String? {
            switch self {
            case .format: return "Choose a still JPEG, PNG or HEIC image."
            case .large: return "Choose an image under 50 MB and 100 megapixels."
            case .unreadable: return "The file couldn't be read as an image."
            }
        }
    }
}
