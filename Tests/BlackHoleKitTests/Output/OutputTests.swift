import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import BlackHoleKit

/// PNG, OpenEXR and metadata output (FR-007, contracts/render-metadata.schema.json).
@Suite struct OutputTests {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bhsim-tests-\(UUID().uuidString)-\(name)")
    }

    private static func samplePixels(width: Int, height: Int) -> [SIMD3<Float>] {
        (0..<(width * height)).map { i in
            let f = Float(i)
            // Values spanning many orders of magnitude, including > 1 and tiny ones: HDR data.
            return SIMD3<Float>(f * 0.37 + 1e-7, f * 1234.5678, i == 5 ? 3.0e7 : 1 / (f + 1))
        }
    }

    // MARK: OpenEXR

    @Test func exrRoundTripReturnsExactFloat32Values() throws {
        let width = 7, height = 5
        let pixels = Self.samplePixels(width: width, height: height)
        let url = temporaryURL("roundtrip.exr")
        defer { try? FileManager.default.removeItem(at: url) }
        try EXRWriter.write(pixels: pixels, width: width, height: height,
                            attributes: ["referenceRadiance": .float(2.5e-3), "comments": .string("bhsim test")], to: url)

        let image = try EXRReader.read(url)
        #expect(image.width == width && image.height == height)
        #expect(image.pixels == pixels)  // bit-exact
        #expect(image.attributes["referenceRadiance"] == .float(2.5e-3))
        #expect(image.attributes["comments"] == .string("bhsim test"))
    }

    @Test func exrIsReadableByImageIO() throws {
        let width = 6, height = 4
        let pixels = Self.samplePixels(width: width, height: height)
        let url = temporaryURL("imageio.exr")
        defer { try? FileManager.default.removeItem(at: url) }
        try EXRWriter.write(pixels: pixels, width: width, height: height, attributes: [:], to: url)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == width && image.height == height)
        #expect(image.bitsPerComponent == 32)
        // ImageIO may convert color spaces slightly, but channels must not be permuted or clamped.
        let raw = try #require(image.dataProvider?.data as Data?)
        let components = image.bitsPerPixel / image.bitsPerComponent
        let floats = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        for i in 0..<(width * height) {
            for c in 0..<3 {
                let expected = pixels[i][c]
                let got = floats[i * components + c]
                #expect(abs(got - expected) <= 1e-3 * max(abs(expected), 1) + 1e-5 * 3.0e7 * (i == 5 ? 1 : 0), "pixel \(i) channel \(c): \(got) vs \(expected)")
            }
        }
    }

    @Test func exrRejectsMismatchedBufferSize() {
        let url = temporaryURL("bad.exr")
        #expect(throws: OutputError.self) {
            try EXRWriter.write(pixels: [SIMD3<Float>(0, 0, 0)], width: 2, height: 2, attributes: [:], to: url)
        }
    }

    // MARK: PNG

    @Test func pngHasExpectedSizeProfileAndPixels() throws {
        let width = 5, height = 3
        var rgb = [UInt8]()
        for i in 0..<(width * height) { rgb += [UInt8(i * 16), UInt8(255 - i * 16), UInt8(i * 3)] }
        let url = temporaryURL("test.png")
        defer { try? FileManager.default.removeItem(at: url) }
        try PNGWriter.write(rgb8: rgb, width: width, height: height, to: url)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == width && image.height == height)
        #expect(image.bitsPerComponent == 8)
        #expect(image.colorSpace?.name as String? == CGColorSpace.sRGB as String)
        let raw = try #require(image.dataProvider?.data as Data?)
        let bytesPerPixel = image.bitsPerPixel / 8
        for i in 0..<(width * height) {
            for c in 0..<3 { #expect(raw[image.bytesPerRow * (i / width) + bytesPerPixel * (i % width) + c] == rgb[i * 3 + c]) }
        }
    }

    @Test func pngRejectsMismatchedBufferSize() {
        #expect(throws: OutputError.self) {
            try PNGWriter.write(rgb8: [1, 2, 3], width: 2, height: 2, to: temporaryURL("bad.png"))
        }
    }

    // MARK: Metadata

    @Test func metadataContainsEveryRequiredKeyAndValidatesAgainstTheSchema() throws {
        var config = RenderConfig()
        config.blackHole.spin = 0.9
        var diagnostics = Diagnostics()
        diagnostics.record(.captured, residual: 1e-9)
        diagnostics.record(.sky(direction: SIMD3(0, 0, 1)), residual: 2e-9)
        let metadata = RenderMetadata(config: config, shading: .physical, referenceRadiance: 3.5, diagnostics: diagnostics)
        let data = try metadata.jsonData()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let schemaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("specs/001-black-hole-image/contracts/render-metadata.schema.json")
        let schema = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any])
        let problems = JSONSchemaSubset.validate(json, against: schema, path: "$")
        #expect(problems.isEmpty, "\(problems)")

        // Spot values.
        let blackHole = try #require(json["blackHole"] as? [String: Any])
        #expect(blackHole["spin"] as? Double == 0.9)
        let hdr = try #require(json["hdr"] as? [String: Any])
        #expect(hdr["shading"] as? String == "physical")
        #expect(hdr["referenceRadiance"] as? Double == 3.5)
        let diag = try #require(json["diagnostics"] as? [String: Any])
        #expect(diag["raysTotal"] as? Int == 2)
    }
}

/// Just enough JSON Schema (type, required, properties, const, enum, bounds) to check the metadata contract.
enum JSONSchemaSubset {
    static func validate(_ value: Any, against schema: [String: Any], path: String) -> [String] {
        var problems: [String] = []
        if let c = schema["const"], !equal(value, c) { problems.append("\(path): expected const \(c), got \(value)") }
        if let e = schema["enum"] as? [Any], !e.contains(where: { equal($0, value) }) { problems.append("\(path): \(value) not in enum") }
        if let t = schema["type"] {
            let types = (t as? [String]) ?? [t as? String ?? ""]
            if !types.contains(where: { matches(value, type: $0) }) { problems.append("\(path): type \(types) mismatch for \(value)") }
        }
        if let number = value as? NSNumber, !(value is NSNull), CFGetTypeID(number) != CFBooleanGetTypeID() {
            let x = number.doubleValue
            if let m = schema["minimum"] as? Double, x < m { problems.append("\(path): \(x) < minimum \(m)") }
            if let m = schema["exclusiveMinimum"] as? Double, x <= m { problems.append("\(path): \(x) <= exclusiveMinimum \(m)") }
            if let m = schema["exclusiveMaximum"] as? Double, x >= m { problems.append("\(path): \(x) >= exclusiveMaximum \(m)") }
        }
        if let object = value as? [String: Any] {
            for key in (schema["required"] as? [String]) ?? [] where object[key] == nil { problems.append("\(path): missing required key \(key)") }
            if let properties = schema["properties"] as? [String: [String: Any]] {
                for (key, sub) in properties { if let v = object[key] { problems += validate(v, against: sub, path: "\(path).\(key)") } }
            }
        }
        return problems
    }

    private static func matches(_ v: Any, type: String) -> Bool {
        switch type {
        case "object": return v is [String: Any]
        case "string": return v is String
        case "null": return v is NSNull
        case "integer": return (v as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue == $0.doubleValue.rounded() } ?? false
        case "number": return (v as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() } ?? false
        default: return true
        }
    }

    private static func equal(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? String, let y = b as? String { return x == y }
        if let x = a as? NSNumber, let y = b as? NSNumber { return x == y }
        return false
    }
}
