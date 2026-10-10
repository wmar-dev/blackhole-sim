import Foundation
import Testing
@testable import BlackHoleKit

/// The display transform for the PNG (the EXR is never tone-mapped).
@Suite struct ToneMapTests {
    @Test func filmicCurveIsMonotonicBoundedAndZeroAtZero() {
        #expect(ToneMap.filmic(0) == 0)
        var previous = 0.0
        for x in stride(from: 0.0, through: 50.0, by: 0.01) {
            let y = ToneMap.filmic(x)
            #expect(y >= previous && y <= 1)
            previous = y
        }
        #expect(ToneMap.filmic(-1) == 0)
        #expect(ToneMap.filmic(1e6) > 0.99)
    }

    @Test func srgbEncodingMatchesTheStandardTransfer() {
        #expect(ToneMap.srgbEncode(0) == 0)
        #expect(abs(ToneMap.srgbEncode(1) - 1) < 1e-12)
        #expect(abs(ToneMap.srgbEncode(0.5) - 0.7353569830524495) < 1e-12)  // IEC 61966-2-1
        #expect(abs(ToneMap.srgbEncode(0.002) - 12.92 * 0.002) < 1e-12)  // linear segment
    }

    @Test func exposureOffsetScalesTheInputInStops() {
        let hdr = [SIMD3<Float>(0.2, 0.2, 0.2)]
        let base = ToneMap.rgb8(from: hdr, exposureStops: 0)
        let brighter = ToneMap.rgb8(from: hdr, exposureStops: 1)
        let darker = ToneMap.rgb8(from: hdr, exposureStops: -1)
        #expect(darker[0] < base[0] && base[0] < brighter[0])
        // +1 stop on the offset equals doubling the radiance.
        #expect(ToneMap.rgb8(from: [SIMD3<Float>(0.4, 0.4, 0.4)], exposureStops: 0) == brighter)
    }

    @Test func outputHasThreeBytesPerPixelAndBlackStaysBlack() {
        let out = ToneMap.rgb8(from: [SIMD3<Float>(0, 0, 0), SIMD3(1e6, 1e6, 1e6)], exposureStops: 0)
        #expect(out.count == 6)
        #expect(Array(out[0..<3]) == [0, 0, 0])
        #expect(Array(out[3..<6]) == [255, 255, 255])
    }
}
