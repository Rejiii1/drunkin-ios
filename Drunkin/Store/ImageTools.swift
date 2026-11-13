import Foundation
import ImageIO
import UIKit

enum ImageTools {
    /// Downsamples any image to a small square JPEG without decoding the full
    /// bitmap first, and drops all metadata (EXIF, GPS) on the way. Used for
    /// photos picked on this phone and for every avatar received from another.
    static func avatarJPEG(from data: Data, maxBytes: Int = Limits.fileBytes) -> Data? {
        guard data.count <= maxBytes else { return nil }
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts),
              CGImageSourceGetCount(src) > 0 else { return nil }
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Limits.avatarPixels * 2,
        ] as CFDictionary
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { return nil }

        let side = min(thumb.width, thumb.height)
        guard side > 0 else { return nil }
        let crop = CGRect(x: (thumb.width - side) / 2, y: (thumb.height - side) / 2, width: side, height: side)
        guard let square = thumb.cropping(to: crop) else { return nil }

        let target = CGSize(width: Limits.avatarPixels, height: Limits.avatarPixels)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIImage(cgImage: square).draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.78), jpeg.count <= Limits.avatarBytes else { return nil }
        return jpeg
    }
}
