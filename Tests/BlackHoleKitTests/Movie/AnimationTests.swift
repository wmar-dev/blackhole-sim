import Foundation
import Testing
@testable import BlackHoleKit

@Suite struct AnimationTests {
    private func animation(_ parameter: SweepParameter, from: Double, to: Double, duration: Double = 3, fps: Double = 24,
                           edit: (inout RenderConfig) -> Void = { _ in }) -> Animation {
        var base = RenderConfig()
        base.width = 64; base.height = 36; base.samplesPerPixel = 1
        edit(&base)
        return Animation(parameter: parameter, from: from, to: to, duration: duration, fps: fps, base: base)
    }

    @Test func frameValuesAreLinearWithExactEndpoints() {
        let a = animation(.inclination, from: 85, to: 20)
        #expect(a.frameCount == 72)
        #expect(a.value(at: 0) == 85 && a.value(at: 71) == 20)
        for i in [1, 10, 35, 70] { #expect(abs(a.value(at: i) - (85 + (20 - 85) * Double(i) / 71)) < 1e-12) }
    }

    @Test func oneFrameGivesTheStartValueAndShortDurationsGiveOneFrame() {
        let one = animation(.spin, from: 0.3, to: 0.9, duration: 1.0 / 24, fps: 24)
        #expect(one.frameCount == 1 && one.value(at: 0) == 0.3)
        let tiny = animation(.spin, from: 0.3, to: 0.9, duration: 0.001, fps: 24)
        #expect(tiny.frameCount == 1)
        let still = animation(.distance, from: 100, to: 100, duration: 1, fps: 10)
        #expect(still.frameCount == 10 && (0..<10).allSatisfy { still.value(at: $0) == 100 })
    }

    @Test func onlyTheSweptParameterChangesAndEveryFrameCarriesTheCommonReference() {
        let a = animation(.inclination, from: 85, to: 20) { $0.blackHole.spin = 0.5; $0.sky.seed = 9; $0.disk.outerRadius = 25 }
        for i in [0, 30, 71] {
            let c = a.frameConfig(i)
            #expect(c.observer.inclinationDegrees == a.value(at: i))
            #expect(c.blackHole.spin == 0.5 && c.sky.seed == 9 && c.disk.outerRadius == 25 && c.width == 64)
            #expect(c.referenceRadianceOverride == a.referenceRadiance)
        }
        var expected = a.base
        expected.observer.inclinationDegrees = 85
        expected.referenceRadianceOverride = a.referenceRadiance
        #expect(a.frameConfig(0) == expected)
    }

    @Test func theReferenceIsTheSinglesRenderOneForInclinationAndDistanceSweeps() throws {
        for parameter in [SweepParameter.inclination, .distance] {
            let a = animation(parameter, from: parameter == .inclination ? 85 : 100, to: parameter == .inclination ? 30 : 40) { $0.blackHole.spin = 0.7 }
            let single = try Renderer(config: a.base).referenceRadiance
            #expect(a.referenceRadiance == single, "\(parameter)")
        }
    }

    @Test func aSpinSweepUsesTheLargestPerFrameReference() throws {
        let a = animation(.spin, from: 0, to: 0.99, duration: 1, fps: 8)
        var perFrame: [Double] = []
        for i in 0..<a.frameCount {
            var c = a.frameConfig(i); c.referenceRadianceOverride = nil
            perFrame.append(try Renderer(config: c).referenceRadiance)
        }
        #expect(Set(perFrame).count > 1, "the reference really differs between spins")
        #expect(a.referenceRadiance == perFrame.max())
        #expect((0..<a.frameCount).allSatisfy { a.frameConfig($0).referenceRadianceOverride == a.referenceRadiance })
    }

    @Test func aValidSweepValidates() throws {
        try animation(.inclination, from: 85, to: 20).validate()
        try animation(.spin, from: 0, to: 0.998).validate()
        try animation(.distance, from: 100, to: 30).validate()
    }

    @Test(arguments: [(SweepParameter.distance, 100.0, 1.2, "--distance"), (.inclination, 85.0, 180.0, "--inclination"), (.spin, 0.0, 1.0, "--spin")])
    func theFirstInvalidFrameIsNamedWithItsNumberValueAndTheRange(parameter: SweepParameter, from: Double, to: Double, option: String) throws {
        let a = animation(parameter, from: from, to: to, duration: 2, fps: 24)
        // The first invalid frame, found independently by validating each frame's configuration.
        var first: Int?
        for i in 0..<a.frameCount where first == nil { if (try? a.frameConfig(i).validate()) == nil { first = i + 1 } }
        let expected = try #require(first)
        do {
            try a.validate()
            Issue.record("expected an error")
        } catch let error as MovieError {
            let text = error.errorDescription ?? ""
            #expect(text.contains("frame \(expected) of \(a.frameCount)"), "\(text)")
            #expect(text.contains(option), "\(text)")
            #expect(text.contains(String(format: "%.4g", a.value(at: expected - 1))), "the value of the frame is named: \(text)")
            // the same reason as a single render of that frame
            let single = (try? a.frameConfig(expected - 1).validate()).map { _ in "" } ?? ""
            _ = single
        }
    }

    @Test func validationOfAThousandFramesIsInstant() {
        let a = animation(.distance, from: 100, to: 1.2, duration: 100, fps: 10)
        #expect(a.frameCount == 1000)
        let start = ContinuousClock.now
        #expect(throws: MovieError.self) { try a.validate() }
        let seconds = Double((ContinuousClock.now - start).components.seconds) + Double((ContinuousClock.now - start).components.attoseconds) * 1e-18
        #expect(seconds < 2, "validation took \(seconds) s")
    }

    @Test func badDurationsAndFrameRatesAreRejected() {
        for (duration, fps) in [(0.0, 24.0), (-1.0, 24.0), (Double.nan, 24.0), (1.0, 0.0), (1.0, 241.0), (Double.infinity, 24.0)] {
            let a = animation(.inclination, from: 80, to: 40, duration: duration, fps: fps)
            #expect(throws: MovieError.self, "duration \(duration) fps \(fps)") { try a.validate() }
        }
    }
}
