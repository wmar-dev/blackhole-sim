import CoreGraphics
import Foundation
import ImageIO

/// Writes the tone-mapped display image as an 8-bit sRGB PNG.
public enum PNGWriter {
    /// - Parameter rgb8: `width × height × 3` bytes, row-major, top row first, already sRGB-encoded.
    public static func write(rgb8: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard width > 0, height > 0, rgb8.count == width * height * 3 else {
            throw OutputError.invalidBuffer("PNG buffer holds \(rgb8.count) bytes but \(width)x\(height)x3 = \(width * height * 3) were expected")
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(rgb8) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                                  bytesPerRow: width * 3, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else {
            throw OutputError.writeFailed("could not create a PNG encoder for \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw OutputError.writeFailed("could not write \(url.path)")
        }
    }
}
