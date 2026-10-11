import Foundation
import Testing
@testable import BlackHoleKit

/// A small JSON-Schema checker for the subset used by `contracts/movie-record.schema.json`:
/// type, const, enum, minimum, exclusiveMinimum, maximum, required, properties, items and allOf with if/then.
enum MiniSchema {
    static func load() throws -> [String: Any] {
        // .../Tests/BlackHoleKitTests/Movie/<this file> → repository root
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("specs/003-movie-from-frames/contracts/movie-record.schema.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func errors(_ value: Any, _ schema: [String: Any], path: String = "$") -> [String] {
        var found: [String] = []
        if let type = schema["type"] as? String {
            let ok: Bool
            switch type {
            case "object": ok = value is [String: Any]
            case "array": ok = value is [Any]
            case "string": ok = value is String
            case "boolean": ok = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            case "integer": ok = (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && floor($0.doubleValue) == $0.doubleValue } ?? false
            case "number": ok = (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() } ?? false
            default: ok = true
            }
            if !ok { return ["\(path): expected \(type), got \(value)"] }
        }
        if let const = schema["const"], "\(const)" != "\(value)" { found.append("\(path): expected \(const), got \(value)") }
        if let options = schema["enum"] as? [Any], !options.contains(where: { "\($0)" == "\(value)" }) { found.append("\(path): \(value) is not one of \(options)") }
        if let number = (value as? NSNumber)?.doubleValue {
            if let minimum = (schema["minimum"] as? NSNumber)?.doubleValue, number < minimum { found.append("\(path): \(number) < \(minimum)") }
            if let minimum = (schema["exclusiveMinimum"] as? NSNumber)?.doubleValue, number <= minimum { found.append("\(path): \(number) <= \(minimum)") }
            if let maximum = (schema["maximum"] as? NSNumber)?.doubleValue, number > maximum { found.append("\(path): \(number) > \(maximum)") }
        }
        if let object = value as? [String: Any] {
            for key in (schema["required"] as? [String]) ?? [] where object[key] == nil { found.append("\(path): missing required '\(key)'") }
            for (key, sub) in (schema["properties"] as? [String: Any]) ?? [:] {
                if let child = object[key], let subSchema = sub as? [String: Any] { found += errors(child, subSchema, path: "\(path).\(key)") }
            }
        }
        if let array = value as? [Any], let items = schema["items"] as? [String: Any] {
            for (i, element) in array.enumerated() { found += errors(element, items, path: "\(path)[\(i)]") }
        }
        for clause in (schema["allOf"] as? [[String: Any]]) ?? [] {
            if let condition = clause["if"] as? [String: Any], let then = clause["then"] as? [String: Any], errors(value, condition, path: path).isEmpty {
                found += errors(value, then, path: path)
            }
        }
        return found
    }
}

@Suite(.serialized, .enabled(if: MovieTestSupport.avfoundationCanEncode)) struct MovieRecordTests {
    private func animation(parameter: SweepParameter = .inclination, from: Double = 85, to: Double = 60) -> Animation {
        var base = RenderConfig()
        base.width = 64; base.height = 36; base.samplesPerPixel = 1; base.sky.seed = 5
        return Animation(parameter: parameter, from: from, to: to, duration: 1, fps: 8, base: base)  // 8 frames
    }

    private func make(_ a: Animation, in dir: TempDirectory) throws -> (record: MovieRecord, json: Data, output: AnimationMovie.Output) {
        var options = MovieAssembler.Options(folder: dir.file("frames"), output: dir.file("m.mp4"))
        options.encoder = .avfoundation
        let output = try AnimationMovie.make(a, framesFolder: dir.file("m_frames"), assemble: options)
        let json = try Data(contentsOf: dir.file("m.mp4.json"))
        return (try JSONDecoder().decode(MovieRecord.self, from: json), json, output)
    }

    @Test func anAnimationRecordHoldsEverythingTheDataModelListsAndMatchesTheSchema() throws {
        let dir = try TempDirectory()
        let a = animation()
        let (record, json, output) = try make(a, in: dir)
        #expect(record.source == .animation && record.version == BlackHoleKit.version)
        #expect(record.movie.fps == 8 && record.movie.frameCount == 8 && record.movie.width == 64 && record.movie.height == 36)
        #expect(abs(record.movie.durationSeconds - 1) < 1e-9 && record.movie.file == "m.mp4")
        #expect(record.movie.encoder.name == "avfoundation" && record.movie.encoder.quality == "standard" && !record.movie.encoder.reproducibleFile)
        #expect(record.movie.colour == MovieRecord.Colour())
        let info = try #require(record.animation)
        #expect(info.parameter == "inclination" && info.from == 85 && info.to == 60 && info.fps == 8 && info.frameCount == 8 && info.durationSeconds == 1)
        #expect(record.backend == BackendInfo(backend: .cpu))
        #expect(record.referenceRadiance == a.referenceRadiance)
        #expect(record.seed == 5)
        let common = try #require(record.common)
        #expect(common.observer.inclinationDeg == nil, "the swept parameter is left out of the common settings")
        #expect(common.observer.distance == 100 && common.observer.fovDeg == 30 && common.blackHole.spin == 0 && common.image.width == 64)
        #expect(common.sky.seed == 5 && common.disk.enabled)
        let frames = try #require(record.frames)
        #expect(frames.count == 8 && frames.map(\.index) == Array(1...8))
        #expect(frames.first?.value == 85 && frames.last?.value == 60)
        let diagnostics = try #require(record.diagnostics)
        #expect(diagnostics.raysTotal == 8 * 64 * 36 && diagnostics.raysTotal == output.frames.diagnostics.raysTotal)

        let object = try JSONSerialization.jsonObject(with: json)
        let problems = MiniSchema.errors(object, try MiniSchema.load())
        #expect(problems.isEmpty, "schema violations: \(problems)")
        #expect(try JSONDecoder().decode(MovieRecord.self, from: record.jsonData()) == record, "the record survives a round trip")
    }

    @Test func aSpinSweepLeavesOutSpinAndTheQuantitiesDerivedFromIt() throws {
        let dir = try TempDirectory()
        let (record, _, _) = try make(animation(parameter: .spin, from: 0, to: 0.9), in: dir)
        let common = try #require(record.common)
        #expect(common.blackHole.spin == nil && common.blackHole.horizonRadius == nil && common.blackHole.iscoRadius == nil)
        #expect(common.observer.inclinationDeg == 80 && common.observer.distance == 100)
    }

    @Test func theSummedDiagnosticsEqualTheSumOfTheFrameRecords() throws {
        let dir = try TempDirectory()
        let (record, _, _) = try make(animation(), in: dir)
        var total = MovieDiagnostics()
        for i in 1...8 {
            let frame = try JSONDecoder().decode(FrameRecord.self, from: Data(contentsOf: dir.file(String(format: "m_frames/frame_%04d.json", i))))
            total.add(frame.metadata.diagnostics)
        }
        let d = try #require(record.diagnostics)
        #expect(d.raysTotal == total.raysTotal && d.captured == total.captured && d.disk == total.disk && d.sky == total.sky)
        #expect(d.unresolved == total.unresolved && d.raysOverResidualTolerance == total.raysOverTolerance && d.maxResidual == total.maxResidual)
    }

    @Test func anAssembledMovieHasTheSubsetAndFillsInFromFrameRecordsWhenTheyExist() throws {
        // plain frames: no render information
        let plain = try TempDirectory()
        try MovieTestSupport.writeFlatFrames(MovieTestSupport.distinctColours(6), width: 64, height: 48, directory: plain.file("frames"))
        var options = MovieAssembler.Options(folder: plain.file("frames"), output: plain.file("p.mp4"))
        options.encoder = .avfoundation
        _ = try MovieAssembler.assemble(options)
        let bare = try JSONDecoder().decode(MovieRecord.self, from: Data(contentsOf: plain.file("p.mp4.json")))
        #expect(bare.source == .assembled && bare.animation == nil && bare.backend == nil && bare.diagnostics == nil)
        let bareObject = try JSONSerialization.jsonObject(with: Data(contentsOf: plain.file("p.mp4.json")))
        #expect(MiniSchema.errors(bareObject, try MiniSchema.load()).isEmpty)

        // the frames folder of an animation: assembling it again recovers the render information
        let dir = try TempDirectory()
        _ = try make(animation(), in: dir)
        var again = MovieAssembler.Options(folder: dir.file("m_frames"), output: dir.file("again.mp4"))
        again.encoder = .avfoundation
        _ = try MovieAssembler.assemble(again)
        let filled = try JSONDecoder().decode(MovieRecord.self, from: Data(contentsOf: dir.file("again.mp4.json")))
        #expect(filled.source == .assembled && filled.animation == nil)
        #expect(filled.backend != nil && filled.referenceRadiance != nil && filled.diagnostics?.raysTotal == 8 * 64 * 36 && filled.frames?.count == 8)
    }
}
