import Foundation

/// Encodes with the external `ffmpeg` program (libx264). Completed in task T014; this part finds and validates ffmpeg.
public final class FFmpegEncoder: MovieEncoder, @unchecked Sendable {
    public struct Location: Sendable, Equatable {
        public var path: String
        public var version: String
    }

    let location: Location

    init(location: Location) { self.location = location }

    /// Runs a program and returns its exit status and standard output (standard error is discarded).
    static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Checks that `path` is ffmpeg with libx264 and returns its version line.
    static func validate(_ path: String) throws -> Location {
        guard let version = run(path, ["-version"]), version.status == 0,
              let first = version.output.split(separator: "\n").first, first.hasPrefix("ffmpeg version") else {
            throw MovieError.encoderUnavailable("\(path) is not ffmpeg (it did not answer -version like ffmpeg)")
        }
        guard let encoders = run(path, ["-hide_banner", "-encoders"]), encoders.output.contains("libx264") else {
            throw MovieError.encoderUnavailable("the ffmpeg at \(path) was built without libx264, so it cannot make H.264 movies")
        }
        let line = String(first)
        let words = line.split(separator: " ")
        return Location(path: path, version: words.count >= 3 ? String(words[2]) : line)
    }

    /// The first usable ffmpeg: `explicit` if given, otherwise the first `ffmpeg` found in `searchPaths`.
    /// When candidates exist but none is usable, the first candidate's problem is reported.
    static func locate(explicit: String?, searchPaths: [String]) throws -> Location {
        if let explicit {
            guard FileManager.default.isExecutableFile(atPath: explicit) else {
                throw MovieError.encoderUnavailable("the ffmpeg given with --ffmpeg (\(explicit)) does not exist or is not executable")
            }
            return try validate(explicit)
        }
        var firstProblem: MovieError?
        for directory in searchPaths {
            let candidate = (directory as NSString).appendingPathComponent("ffmpeg")
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            do { return try validate(candidate) } catch let error as MovieError { firstProblem = firstProblem ?? error }
        }
        throw firstProblem ?? MovieError.encoderUnavailable(
            "ffmpeg was not found (searched: \(searchPaths.joined(separator: ", "))); install it (for example with Homebrew: brew install ffmpeg) or use --encoder avfoundation")
    }

    public func describe(quality: MovieQuality) -> EncoderInfo {
        EncoderInfo(name: "ffmpeg", version: location.version, quality: quality.rawValue, setting: "crf=\(quality.crf)", reproducibleFile: true)
    }

    // MARK: Encoding (research D1)

    private var process: Process?
    private var input: FileHandle?
    private var output: URL?
    private let lock = NSLock()
    private var errorText = Data()

    private var standardErrorText: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: errorText, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func begin(width: Int, height: Int, fps: Double, quality: MovieQuality, output: URL) throws {
        if width % 2 != 0 || height % 2 != 0 { throw MovieError.oddDimensions(width: width, height: height) }
        signal(SIGPIPE, SIG_IGN)  // a dying ffmpeg must surface as a write error, not kill this process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: location.path)
        // Frames arrive as PNG images on standard input. The BT.709 matrix is stated explicitly (the colour tags already
        // select it); the sRGB transfer function is that of the PNGs; fixed thread count and bit-exact flags make the
        // file reproducible for one ffmpeg version.
        process.arguments = [
            "-v", "error", "-y", "-f", "image2pipe", "-framerate", String(fps), "-c:v", "png", "-i", "-",
            "-vf", "scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p",
            "-c:v", "libx264", "-crf", String(quality.crf), "-threads", "4",
            "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "iec61966-2-1", "-color_range", "tv",
            "-fflags", "+bitexact", "-flags:v", "+bitexact", "-movflags", "+faststart", "-f", "mp4", output.path,
        ]
        let stdin = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.lock.lock(); self.errorText.append(data); self.lock.unlock()
        }
        do { try process.run() } catch {
            throw MovieError.encoderUnavailable("could not start \(location.path): \(error.localizedDescription)")
        }
        self.process = process
        self.input = stdin.fileHandleForWriting
        self.output = output
    }

    public func append(frame: URL) throws {
        guard let input else { throw MovieError.encodingFailed("the encoder was not started") }
        let data: Data
        do { data = try Data(contentsOf: frame) } catch { abort(); throw MovieError.unreadableFrame(frame.lastPathComponent) }
        do { try input.write(contentsOf: data) } catch {
            let text = failureText()
            abort()
            throw MovieError.encodingFailed(text)
        }
    }

    public func finish() throws {
        guard let process, let input else { throw MovieError.encodingFailed("the encoder was not started") }
        try? input.close()
        process.waitUntilExit()
        let status = process.terminationStatus
        let text = standardErrorText
        cleanup()
        if status != 0 {
            if let output { try? FileManager.default.removeItem(at: output) }
            throw MovieError.encodingFailed(text.isEmpty ? "ffmpeg exited with status \(status)" : text)
        }
    }

    public func cancel() { abort() }

    /// The error text ffmpeg has produced so far (it may need a moment to arrive after the pipe breaks).
    private func failureText() -> String {
        process?.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.05)
        let text = standardErrorText
        return text.isEmpty ? "ffmpeg stopped unexpectedly" : text
    }

    private func abort() {
        if let process, process.isRunning { process.terminate() }
        process?.waitUntilExit()
        cleanup()
        if let output { try? FileManager.default.removeItem(at: output) }
    }

    private func cleanup() {
        try? input?.close()
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        input = nil
        process = nil
    }
}
