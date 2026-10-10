import Foundation

public enum OutputError: Error, Equatable, LocalizedError {
    case invalidBuffer(String)
    case writeFailed(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBuffer(let m), .writeFailed(let m), .unsupported(let m): return m
        }
    }
}

/// Custom header attribute values supported by `EXRWriter` / `EXRReader`.
public enum EXRAttribute: Equatable, Sendable {
    case float(Float)
    case string(String)
}

public struct EXRImage: Sendable {
    public var width: Int
    public var height: Int
    /// Row-major, top row first; linear RGB.
    public var pixels: [SIMD3<Float>]
    public var attributes: [String: EXRAttribute]
}

/// Minimal OpenEXR (v2, single-part scanline) writer: uncompressed, three 32-bit float channels (B, G, R),
/// Rec. 709 chromaticities, plus optional custom attributes.
///
/// ImageIO can also write EXR but applies colour-space conversions that perturb the values, so physical
/// intensities (FR-007) are written directly to keep them bit-exact.
public enum EXRWriter {
    private static let magic: [UInt8] = [0x76, 0x2F, 0x31, 0x01]
    private static let channelNames = ["B", "G", "R"]  // EXR requires alphabetical channel order

    public static func write(pixels: [SIMD3<Float>], width: Int, height: Int,
                             attributes: [String: EXRAttribute], to url: URL) throws {
        guard width > 0, height > 0, pixels.count == width * height else {
            throw OutputError.invalidBuffer("EXR buffer holds \(pixels.count) pixels but \(width)x\(height) = \(width * height) were expected")
        }
        var out = Data()
        out.append(contentsOf: magic)
        out.append(contentsOf: [2, 0, 0, 0])  // version 2, no flags (single-part scanline)

        func putAttribute(_ name: String, type: String, _ payload: Data) {
            out.append(contentsOf: Array(name.utf8) + [0])
            out.append(contentsOf: Array(type.utf8) + [0])
            out.append(le(Int32(payload.count)))
            out.append(payload)
        }

        var channels = Data()
        for name in channelNames {
            channels.append(contentsOf: Array(name.utf8) + [0])
            channels.append(le(Int32(2)))  // FLOAT
            channels.append(contentsOf: [0, 0, 0, 0])  // pLinear + 3 reserved bytes
            channels.append(le(Int32(1)))
            channels.append(le(Int32(1)))
        }
        channels.append(0)
        putAttribute("channels", type: "chlist", channels)

        var chromaticities = Data()
        for v: Float in [0.6400, 0.3300, 0.3000, 0.6000, 0.1500, 0.0600, 0.3127, 0.3290] { chromaticities.append(le(v)) }
        putAttribute("chromaticities", type: "chromaticities", chromaticities)

        putAttribute("compression", type: "compression", Data([0]))  // NO_COMPRESSION: one scanline per block
        var window = Data()
        for v in [Int32(0), 0, Int32(width - 1), Int32(height - 1)] { window.append(le(v)) }
        putAttribute("dataWindow", type: "box2i", window)
        putAttribute("displayWindow", type: "box2i", window)
        putAttribute("lineOrder", type: "lineOrder", Data([0]))  // INCREASING_Y
        putAttribute("pixelAspectRatio", type: "float", le(Float(1)))
        var center = Data()
        center.append(le(Float(0)))
        center.append(le(Float(0)))
        putAttribute("screenWindowCenter", type: "v2f", center)
        putAttribute("screenWindowWidth", type: "float", le(Float(1)))

        for name in attributes.keys.sorted() {
            switch attributes[name]! {
            case .float(let value): putAttribute(name, type: "float", le(value))
            case .string(let value): putAttribute(name, type: "string", Data(value.utf8))
            }
        }
        out.append(0)  // end of header

        let blockSize = 8 + width * 3 * 4
        let firstBlock = out.count + 8 * height
        for y in 0..<height { out.append(le(UInt64(firstBlock + y * blockSize))) }

        var row = Data(capacity: width * 3 * 4)
        for y in 0..<height {
            out.append(le(Int32(y)))
            out.append(le(Int32(width * 3 * 4)))
            row.removeAll(keepingCapacity: true)
            for component in [2, 1, 0] {  // B, G, R planes (pixels store R, G, B)
                for x in 0..<width { row.append(le(pixels[y * width + x][component])) }
            }
            out.append(row)
        }

        do {
            try out.write(to: url, options: .atomic)
        } catch {
            throw OutputError.writeFailed("could not write \(url.path): \(error.localizedDescription)")
        }
    }

    private static func le<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func le(_ value: Float) -> Data { le(value.bitPattern) }
}

/// Reads the files `EXRWriter` produces (uncompressed scanline, B/G/R float channels). Used by tests and
/// analysis tools; not a general OpenEXR reader.
public enum EXRReader {
    public static func read(_ url: URL) throws -> EXRImage {
        let data = try Data(contentsOf: url)
        var cursor = 0

        func need(_ n: Int) throws {
            if cursor + n > data.count { throw OutputError.invalidBuffer("truncated EXR file") }
        }
        func u8() throws -> UInt8 { try need(1); defer { cursor += 1 }; return data[cursor] }
        func int32() throws -> Int32 {
            try need(4)
            defer { cursor += 4 }
            return Int32(bitPattern: UInt32(data[cursor]) | UInt32(data[cursor + 1]) << 8
                | UInt32(data[cursor + 2]) << 16 | UInt32(data[cursor + 3]) << 24)
        }
        func uint64(at offset: Int) throws -> UInt64 {
            guard offset + 8 <= data.count else { throw OutputError.invalidBuffer("truncated EXR file") }
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(data[offset + i]) << (8 * UInt64(i)) }
            return v
        }
        func float(at offset: Int) -> Float {
            let bits = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
            return Float(bitPattern: bits)
        }
        func cString() throws -> String {
            var bytes: [UInt8] = []
            while true {
                let b = try u8()
                if b == 0 { break }
                bytes.append(b)
            }
            return String(decoding: bytes, as: UTF8.self)
        }

        try need(8)
        guard Array(data[0..<4]) == [0x76, 0x2F, 0x31, 0x01] else { throw OutputError.unsupported("not an OpenEXR file") }
        guard data[4] == 2, data[5] == 0, data[6] == 0, data[7] == 0 else {
            throw OutputError.unsupported("only single-part scanline EXR version 2 is supported")
        }
        cursor = 8

        var width = 0, height = 0
        var attributes: [String: EXRAttribute] = [:]
        while true {
            let name = try cString()
            if name.isEmpty { break }
            let type = try cString()
            let size = Int(try int32())
            try need(size)
            switch (name, type) {
            case ("dataWindow", "box2i"):
                let xMin = Int(Int32(bitPattern: UInt32(data[cursor]) | UInt32(data[cursor + 1]) << 8 | UInt32(data[cursor + 2]) << 16 | UInt32(data[cursor + 3]) << 24))
                let yMin = Int(Int32(bitPattern: UInt32(data[cursor + 4]) | UInt32(data[cursor + 5]) << 8 | UInt32(data[cursor + 6]) << 16 | UInt32(data[cursor + 7]) << 24))
                let xMax = Int(Int32(bitPattern: UInt32(data[cursor + 8]) | UInt32(data[cursor + 9]) << 8 | UInt32(data[cursor + 10]) << 16 | UInt32(data[cursor + 11]) << 24))
                let yMax = Int(Int32(bitPattern: UInt32(data[cursor + 12]) | UInt32(data[cursor + 13]) << 8 | UInt32(data[cursor + 14]) << 16 | UInt32(data[cursor + 15]) << 24))
                guard xMin == 0, yMin == 0 else { throw OutputError.unsupported("data window must start at the origin") }
                width = xMax + 1
                height = yMax + 1
            case ("compression", "compression"):
                guard data[cursor] == 0 else { throw OutputError.unsupported("compressed EXR is not supported") }
            case (_, "float") where size == 4 && !["pixelAspectRatio", "screenWindowWidth"].contains(name):
                attributes[name] = .float(float(at: cursor))
            case (_, "string"):
                attributes[name] = .string(String(decoding: data[cursor..<(cursor + size)], as: UTF8.self))
            default:
                break
            }
            cursor += size
        }
        guard width > 0, height > 0 else { throw OutputError.invalidBuffer("EXR has no data window") }

        let tableStart = cursor
        var pixels = [SIMD3<Float>](repeating: .zero, count: width * height)
        for y in 0..<height {
            let blockOffset = Int(try uint64(at: tableStart + 8 * y))
            guard blockOffset + 8 + width * 12 <= data.count else { throw OutputError.invalidBuffer("truncated EXR file") }
            let base = blockOffset + 8
            for x in 0..<width {
                let b = float(at: base + 4 * x)
                let g = float(at: base + 4 * (width + x))
                let r = float(at: base + 4 * (2 * width + x))
                pixels[y * width + x] = SIMD3(r, g, b)
            }
        }
        return EXRImage(width: width, height: height, pixels: pixels, attributes: attributes)
    }
}
