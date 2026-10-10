import Foundation

/// Turns a folder of numbered PNG frames into a movie (User Story 1).
public enum MovieAssembler {
    public struct Options: Sendable {
        public var folder: URL
        public var prefix: String?
        public var allowGaps = false
        public var fps = 24.0
        public var quality = MovieQuality.standard
        public var encoder = EncoderChoice.auto
        public var ffmpegPath: String?
        public var searchPaths: [String]?
        public var output: URL
        public var force = false
        /// Adds to the record before it is written (used by `AnimationMovie`).
        public var customizeRecord: (@Sendable (inout MovieRecord) -> Void)?

        public init(folder: URL, output: URL) {
            self.folder = folder
            self.output = output
        }
    }

    public struct Summary: Sendable {
        public var path: URL
        public var record: URL
        public var frameCount: Int
        public var duration: Double
        public var width: Int
        public var height: Int
        public var fps: Double
        public var encoder: EncoderInfo
    }

    public static let fpsRange = 1.0...240.0

    /// - Parameters:
    ///   - encoder: overrides the encoder chosen by `options.encoder` (tests).
    ///   - progress: called with the completed fraction after each frame.
    ///   - isCancelled: polled before each frame; when true the work stops, nothing is left behind and `cancelled` is thrown.
    @discardableResult
    public static func assemble(_ options: Options, encoder injected: (any MovieEncoder)? = nil,
                                progress: (@Sendable (Double) -> Void)? = nil,
                                isCancelled: (@Sendable () -> Bool)? = nil) throws -> Summary {
        guard fpsRange.contains(options.fps) else {
            throw MovieError.invalidOption("the frame rate must be between 1 and 240 (got \(options.fps))")
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: options.output.path), !options.force { throw MovieError.outputExists(options.output.path) }

        let sequence = try FrameSequence.discover(in: options.folder, prefix: options.prefix, allowGaps: options.allowGaps)
        let encoder = try injected ?? EncoderSelection.select(options.encoder, ffmpegPath: options.ffmpegPath, searchPaths: options.searchPaths)

        let directory = options.output.deletingLastPathComponent()
        do { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) } catch {
            throw MovieError.cannotWrite("could not create \(directory.path): \(error.localizedDescription)")
        }
        let temporary = directory.appendingPathComponent(".\(options.output.lastPathComponent).\(UUID().uuidString).partial")
        defer { try? fileManager.removeItem(at: temporary) }

        try encoder.begin(width: sequence.width, height: sequence.height, fps: options.fps, quality: options.quality, output: temporary)
        for (i, file) in sequence.files.enumerated() {
            if isCancelled?() == true { encoder.cancel(); throw MovieError.cancelled }
            do { try encoder.append(frame: file) } catch { encoder.cancel(); throw error }
            progress?(Double(i + 1) / Double(sequence.files.count))
        }
        do { try encoder.finish() } catch { encoder.cancel(); throw error }

        do {
            if fileManager.fileExists(atPath: options.output.path) { try fileManager.removeItem(at: options.output) }
            try fileManager.moveItem(at: temporary, to: options.output)
        } catch {
            throw MovieError.cannotWrite("could not write \(options.output.path): \(error.localizedDescription)")
        }

        let info = encoder.describe(quality: options.quality)
        var record = MovieRecord(movie: MovieRecord.MovieInfo(file: options.output.lastPathComponent, fps: options.fps,
                                                              frameCount: sequence.files.count, width: sequence.width,
                                                              height: sequence.height, encoder: info),
                                 source: .assembled)
        // Frames made by `animate` have a record each; with all of them present the movie record carries their details.
        var frameRecords: [FrameRecord] = []
        for file in sequence.files {
            guard let data = try? Data(contentsOf: file.deletingPathExtension().appendingPathExtension("json")),
                  let frame = try? JSONDecoder().decode(FrameRecord.self, from: data) else { frameRecords = []; break }
            frameRecords.append(frame)
        }
        if frameRecords.count == sequence.files.count { record.fill(from: frameRecords, omitting: frameRecords.first?.parameter) }
        options.customizeRecord?(&record)
        let recordURL = options.output.appendingPathExtension("json")
        do { try record.jsonData().write(to: recordURL, options: .atomic) } catch {
            throw MovieError.cannotWrite("could not write \(recordURL.path): \(error.localizedDescription)")
        }
        return Summary(path: options.output, record: recordURL, frameCount: sequence.files.count,
                       duration: Double(sequence.files.count) / options.fps, width: sequence.width, height: sequence.height,
                       fps: options.fps, encoder: info)
    }
}
