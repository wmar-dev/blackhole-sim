import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// Encodes with Apple's AVFoundation (H.264, MP4); needs nothing installed (research D1).
///
/// Every pixel buffer carries BT.709 / sRGB colour attachments and the track carries the matching tags, so the
/// conversion to YUV and the players' decoding use the colour space of the PNG (risk R4: without them an
/// AVFoundation file decoded up to 28 levels off).
///
/// The calls block the calling thread (`finish()` waits for AVFoundation to complete the file), and AVFoundation needs a
/// worker thread of the process's dispatch pool to do so. Callers must therefore not park every pool thread in these
/// calls at once: a test run that did (10 movie tests in parallel on a 10-thread pool) deadlocked. The command-line
/// tool encodes from one thread; tests that encode are serialized per suite.
public final class AVFoundationEncoder: MovieEncoder, @unchecked Sendable {
    public init() {}

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var output: URL?
    private var width = 0, height = 0
    private var timescale: Int32 = 24_000
    private var frameStep: Int64 = 1_000
    private var index: Int64 = 0

    public func describe(quality: MovieQuality) -> EncoderInfo {
        EncoderInfo(name: "avfoundation", version: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", quality: quality.rawValue,
                    setting: "bitsPerPixel=\(quality.bitsPerPixelPerFrame),min=\(quality.minimumBitRate / 1000)kbit/s", reproducibleFile: false)
    }

    /// The sRGB transfer function tag exists from macOS 15; before that the BT.709 tag is the closest available.
    private static var transferTag: String {
        if #available(macOS 15, *) { return AVVideoTransferFunction_IEC_sRGB }
        return AVVideoTransferFunction_ITU_R_709_2
    }

    public func begin(width: Int, height: Int, fps: Double, quality: MovieQuality, output: URL) throws {
        if width % 2 != 0 || height % 2 != 0 { throw MovieError.oddDimensions(width: width, height: height) }
        self.width = width; self.height = height; self.output = output
        timescale = Int32((fps * 1000).rounded()); frameStep = 1000; index = 0
        let bitRate = max(quality.minimumBitRate, Int(quality.bitsPerPixelPerFrame * Double(width * height) * fps))
        do {
            let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                            AVVideoTransferFunctionKey: Self.transferTag,
                                            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitRate,
                                                  AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            ])
            guard writer.canAdd(input) else { throw MovieError.encodingFailed("AVFoundation cannot write \(width)x\(height) H.264") }
            writer.add(input)
            guard writer.startWriting() else {
                throw MovieError.encodingFailed(writer.error?.localizedDescription ?? "AVFoundation could not start writing")
            }
            writer.startSession(atSourceTime: .zero)
            self.writer = writer; self.input = input; self.adaptor = adaptor
        } catch let error as MovieError {
            throw error
        } catch {
            throw MovieError.encodingFailed(error.localizedDescription)
        }
    }

    public func append(frame: URL) throws {
        guard let writer, let input, let adaptor, let pool = adaptor.pixelBufferPool else { throw MovieError.encodingFailed("the encoder was not started") }
        guard let source = CGImageSourceCreateWithURL(frame as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            abort(); throw MovieError.unreadableFrame(frame.lastPathComponent)
        }
        guard image.width == width, image.height == height else {
            abort()
            throw MovieError.sizeMismatch(file: frame.lastPathComponent, found: "\(image.width)x\(image.height)", expected: "\(width)x\(height)")
        }
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { let text = writer.error?.localizedDescription ?? "AVFoundation failed"; abort(); throw MovieError.encodingFailed(text) }
            Thread.sleep(forTimeInterval: 0.001)
        }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pixels = buffer else {
            abort(); throw MovieError.encodingFailed("could not allocate a video frame buffer")
        }
        CVBufferSetAttachment(pixels, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pixels, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        if #available(macOS 15, *) {
            CVBufferSetAttachment(pixels, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
        } else {
            CVBufferSetAttachment(pixels, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        }
        CVPixelBufferLockBaseAddress(pixels, [])
        let drawn = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        drawn?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        guard drawn != nil else { abort(); throw MovieError.encodingFailed("could not convert \(frame.lastPathComponent)") }
        guard adaptor.append(pixels, withPresentationTime: CMTime(value: index * frameStep, timescale: timescale)) else {
            let text = writer.error?.localizedDescription ?? "AVFoundation rejected a frame"
            abort(); throw MovieError.encodingFailed(text)
        }
        index += 1
    }

    public func finish() throws {
        guard let writer, let input else { throw MovieError.encodingFailed("the encoder was not started") }
        input.markAsFinished()
        // Poll the status instead of waiting for the completion handler: the handler needs a free dispatch worker
        // thread, and a caller that blocks all of them (for example many encoders finishing at once in a parallel
        // test run) would deadlock.
        writer.finishWriting {}
        let giveUp = Date().addingTimeInterval(600)
        while writer.status == .writing, Date() < giveUp { Thread.sleep(forTimeInterval: 0.002) }
        let status = writer.status, text = writer.error?.localizedDescription
        reset()
        if status != .completed {
            if let output { try? FileManager.default.removeItem(at: output) }
            throw MovieError.encodingFailed(text ?? "AVFoundation did not complete the movie")
        }
    }

    public func cancel() { abort() }

    private func abort() {
        writer?.cancelWriting()
        if let output { try? FileManager.default.removeItem(at: output) }
        reset()
    }

    private func reset() { writer = nil; input = nil; adaptor = nil }
}
