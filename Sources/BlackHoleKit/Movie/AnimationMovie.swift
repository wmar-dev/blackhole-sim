import Foundation

/// An animation made into a movie in one go: render the frames, assemble them, write the record (User Stories 2 and 3).
public enum AnimationMovie {
    public struct Output: Sendable {
        public var frames: AnimationRunner.Result
        public var summary: MovieAssembler.Summary
    }

    /// - Parameters:
    ///   - assemble: output file, encoder choice and quality for the movie; its `folder`, `prefix`, `fps` and `allowGaps` are set here.
    ///   - onFramesDone: called when all frames are on disk, before encoding starts.
    public static func make(_ animation: Animation, framesFolder: URL, keepEXR: Bool = false, assemble: MovieAssembler.Options,
                            frameProgress: (@Sendable (Int, Int) -> Void)? = nil, onFramesDone: (@Sendable (AnimationRunner.Result) -> Void)? = nil,
                            encodeProgress: (@Sendable (Double) -> Void)? = nil, isCancelled: (@Sendable () -> Bool)? = nil) throws -> Output {
        let frames = try AnimationRunner.run(animation, options: AnimationRunner.Options(framesFolder: framesFolder, keepEXR: keepEXR),
                                             progress: frameProgress, isCancelled: isCancelled)
        onFramesDone?(frames)

        var options = assemble
        options.folder = framesFolder
        options.prefix = "frame_"
        options.fps = animation.fps
        options.allowGaps = false
        let info = MovieRecord.AnimationInfo(parameter: animation.parameter.rawValue, from: animation.from, to: animation.to,
                                             durationSeconds: animation.duration, fps: animation.fps, frameCount: animation.frameCount)
        let summaries = frames.frames
        options.customizeRecord = { record in
            record.source = .animation
            record.animation = info
            // Per-frame figures come from the runner (they include frames kept from an earlier run).
            record.frames = summaries.map { MovieRecord.FrameEntry(index: $0.index, value: $0.value, unresolvedFraction: $0.unresolvedFraction, badRayFraction: $0.badRayFraction) }
            record.diagnostics = MovieRecord.DiagnosticsSummary(frames.diagnostics)
        }
        let summary = try MovieAssembler.assemble(options, progress: encodeProgress, isCancelled: isCancelled)
        return Output(frames: frames, summary: summary)
    }
}
