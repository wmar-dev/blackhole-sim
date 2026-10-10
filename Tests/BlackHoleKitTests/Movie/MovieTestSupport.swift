import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
@testable import BlackHoleKit

/// A temporary directory removed when the value is released.
final class TempDirectory: @unchecked Sendable {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("bhsim-movie-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    func file(_ name: String) -> URL { url.appendingPathComponent(name) }
}

enum MovieTestSupport {
    typealias RGB = (r: UInt8, g: UInt8, b: UInt8)

    /// Distinct flat colours, far apart in every channel, for checking the order of decoded frames.
    static func distinctColours(_ count: Int) -> [RGB] {
        (0..<count).map { i in
            let t = Double(i) / Double(max(count - 1, 1))
            return (UInt8(40 + 170 * t), UInt8(210 - 150 * t), UInt8(60 + 120 * abs(sin(6 * t))))
        }
    }

    /// Writes flat-colour PNG frames `<prefix><number>.png`; `padding` 0 means unpadded numbers.
    @discardableResult
    static func writeFlatFrames(_ colours: [RGB], width: Int, height: Int, directory: URL, prefix: String = "frame_",
                                padding: Int = 4, firstNumber: Int = 1) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (i, c) in colours.enumerated() {
            var pixels = [UInt8](); pixels.reserveCapacity(width * height * 3)
            for _ in 0..<(width * height) { pixels += [c.r, c.g, c.b] }
            let number = String(format: "%0\(max(padding, 1))d", firstNumber + i)
            let url = directory.appendingPathComponent("\(prefix)\(padding == 0 ? String(firstNumber + i) : number).png")
            try PNGWriter.write(rgb8: pixels, width: width, height: height, to: url)
            urls.append(url)
        }
        return urls
    }

    /// Small real renders of the default scene with the inclination stepping from 85° down, as display PNGs.
    @discardableResult
    static func writeRenderedFrames(count: Int, width: Int = 160, height: Int = 90, directory: URL, prefix: String = "frame_") throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for i in 0..<count {
            var config = RenderConfig()
            config.width = width; config.height = height; config.samplesPerPixel = 1
            config.observer.inclinationDegrees = 85 - Double(i) * 2
            let image = try Renderer(config: config).render()
            let url = directory.appendingPathComponent(String(format: "\(prefix)%04d.png", i + 1))
            try PNGWriter.write(rgb8: ToneMap.rgb8(from: image.hdr, exposureStops: 0), width: width, height: height, to: url)
            urls.append(url)
        }
        return urls
    }

    /// Decodes a PNG to RGB8 (sRGB), top row first.
    static func decodePNG(_ url: URL) throws -> (rgb: [UInt8], width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (rgb8(of: image), image.width, image.height)
    }

    static func rgb8(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var rgb = [UInt8](); rgb.reserveCapacity(w * h * 3)
        for i in 0..<(w * h) { rgb += [rgba[4 * i], rgba[4 * i + 1], rgba[4 * i + 2]] }
        return rgb
    }

    /// Peak signal-to-noise ratio in dB between two RGB8 buffers of equal size.
    static func psnr(_ a: [UInt8], _ b: [UInt8]) -> Double {
        precondition(a.count == b.count && !a.isEmpty)
        var se = 0.0
        for i in a.indices { let d = Double(a[i]) - Double(b[i]); se += d * d }
        let mse = se / Double(a.count)
        return mse == 0 ? .infinity : 10 * log10(255 * 255 / mse)
    }

    /// Largest per-channel difference between a pixel in the middle of `rgb` and a colour.
    static func centreDifference(_ rgb: [UInt8], width: Int, height: Int, from c: RGB) -> Int {
        let i = ((height / 2) * width + width / 2) * 3
        return max(abs(Int(rgb[i]) - Int(c.r)), abs(Int(rgb[i + 1]) - Int(c.g)), abs(Int(rgb[i + 2]) - Int(c.b)))
    }

    /// An ffmpeg executable with libx264 in one of the usual places (for `.enabled(if:)`).
    static let ffmpegAvailable: Bool = {
        var directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        directories += ["/opt/homebrew/bin", "/usr/local/bin"]
        return directories.contains { FileManager.default.isExecutableFile(atPath: $0 + "/ffmpeg") }
    }()

    /// The sRGB transfer-function tag for AVFoundation writers (macOS 15+; BT.709 before that).
    static var srgbTransfer: String {
        if #available(macOS 15, *) { return AVVideoTransferFunction_IEC_sRGB }
        return AVVideoTransferFunction_ITU_R_709_2
    }

    /// Writes a flat-colour H.264 movie with a plain `AVAssetWriter`, independent of the code under test, so the movie
    /// reader can be tested before the encoders exist.
    static func makeReferenceMovie(colours: [RGB], width: Int, height: Int, fps: Int32, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: srgbTransfer,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for (i, c) in colours.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = buffer!
            CVBufferSetAttachment(pixels, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(pixels, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
            CVBufferSetAttachment(pixels, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixels)
            for y in 0..<height { for x in 0..<width {
                let p = base + y * stride + x * 4
                p[0] = c.b; p[1] = c.g; p[2] = c.r; p[3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(i), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    /// Encodes `files` with `encoder` into `output` (which must not exist).
    static func encode(_ encoder: any MovieEncoder, files: [URL], width: Int, height: Int, fps: Double = 24,
                       quality: MovieQuality = .standard, output: URL) throws {
        try encoder.begin(width: width, height: height, fps: fps, quality: quality, output: output)
        for file in files { try encoder.append(frame: file) }
        try encoder.finish()
    }

    /// Decodes every frame of a movie with ffmpeg (an independent decoder) to RGB8.
    static func decodeWithFFmpeg(_ movie: URL, width: Int, height: Int) throws -> [[UInt8]] {
        let location = try FFmpegEncoder.locate(explicit: nil, searchPaths: EncoderSelection.defaultSearchPaths)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: location.path)
        process.arguments = ["-v", "error", "-i", movie.path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let size = width * height * 3
        return (0..<(data.count / size)).map { Array(data[($0 * size)..<(($0 + 1) * size)]) }
    }

    /// Physical memory footprint of this process in bytes.
    static func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// A stand-in encoder that fails in `finish`, to test cleanup.
    final class FailingEncoder: MovieEncoder, @unchecked Sendable {
        var appended = 0
        private var output: URL?
        func describe(quality: MovieQuality) -> EncoderInfo {
            EncoderInfo(name: "failing", version: "0", quality: quality.rawValue, setting: "none", reproducibleFile: false)
        }
        func begin(width: Int, height: Int, fps: Double, quality: MovieQuality, output: URL) throws {
            self.output = output
            try Data("partial".utf8).write(to: output)
        }
        func append(frame: URL) throws { appended += 1 }
        func finish() throws { throw MovieError.encodingFailed("simulated failure") }
        func cancel() { if let output { try? FileManager.default.removeItem(at: output) } }
    }

    /// A fake `ffmpeg` that passes validation but fails when asked to encode, printing `boom` on standard error.
    static func fakeFailingFFmpeg() throws -> TempDirectory {
        let dir = try TempDirectory()
        let script = """
        #!/bin/sh
        case "$1" in
          -version) echo "ffmpeg version 9.9-fake Copyright"; exit 0 ;;
          -hide_banner) echo " V....D libx264  H.264"; exit 0 ;;
        esac
        cat > /dev/null &
        echo "boom: simulated encoder failure" 1>&2
        exit 3
        """
        let url = dir.file("ffmpeg")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return dir
    }
}
