import Foundation
import Testing
@testable import BlackHoleKit

/// Input rejection with clear messages (FR-012, spec edge cases, contracts/cli.md).
@Suite struct ConfigValidationTests {
    /// Returns the error message produced by `validate()` for a modified default configuration.
    private func message(_ modify: (inout RenderConfig) -> Void) -> String? {
        var config = RenderConfig()
        modify(&config)
        do {
            try config.validate()
            return nil
        } catch let error as ConfigError {
            return error.errorDescription
        } catch {
            return "unexpected error type: \(error)"
        }
    }

    @Test func defaultConfigurationIsValid() throws {
        try RenderConfig().validate()
    }

    @Test func defaultsMatchTheCliContract() {
        let c = RenderConfig()
        #expect(c.blackHole.spin == 0)
        #expect(c.observer.distance == 100)
        #expect(c.observer.inclinationDegrees == 80)
        #expect(c.observer.fieldOfViewDegrees == 30)
        #expect(c.width == 1920 && c.height == 1080)
        #expect(c.samplesPerPixel == 4)
        #expect(c.disk.outerRadius == 20)
        #expect(c.disk.accretionRateEddington == 0.1)
        #expect(c.blackHole.massSolar == 10)
        #expect(c.sky.kind == .starfield)
        #expect(c.sky.seed == 1)
    }

    @Test func rejectsSpinOutsideZeroToOne() {
        for spin in [-0.1, 1.0, 1.2, Double.nan] {
            let m = message { $0.blackHole.spin = spin }
            #expect(m?.contains("--spin") == true, "spin=\(spin): \(m ?? "accepted")")
            #expect(m?.contains("0 <= a < 1") == true, "spin=\(spin): \(m ?? "accepted")")
        }
    }

    @Test func rejectsNonPositiveMassSizeSamplesAndFieldOfView() {
        #expect(message { $0.blackHole.massSolar = 0 }?.contains("--mass") == true)
        #expect(message { $0.blackHole.massSolar = -3 }?.contains("--mass") == true)
        #expect(message { $0.width = 0 }?.contains("--width") == true)
        #expect(message { $0.height = -5 }?.contains("--height") == true)
        #expect(message { $0.samplesPerPixel = 0 }?.contains("--samples") == true)
        #expect(message { $0.observer.fieldOfViewDegrees = 0 }?.contains("--fov") == true)
        #expect(message { $0.observer.fieldOfViewDegrees = 180 }?.contains("--fov") == true)
        #expect(message { $0.disk.accretionRateEddington = 0 }?.contains("--accretion-rate") == true)
    }

    @Test func rejectsNonSquareSampleCount() {
        for n in [2, 3, 5, 6, 8, 10] {
            let m = message { $0.samplesPerPixel = n }
            #expect(m?.contains("--samples") == true && m?.contains("perfect square") == true, "n=\(n): \(m ?? "accepted")")
        }
        for n in [1, 4, 9, 16] {
            #expect(message { $0.samplesPerPixel = n } == nil, "n=\(n) should be accepted")
        }
    }

    @Test func rejectsInclinationAtThePoles() {
        for inc in [0.0, 180.0, -5.0, 200.0] {
            let m = message { $0.observer.inclinationDegrees = inc }
            #expect(m?.contains("--inclination") == true, "inc=\(inc): \(m ?? "accepted")")
        }
        #expect(message { $0.observer.inclinationDegrees = 0.01 } == nil)
        #expect(message { $0.observer.inclinationDegrees = 179.99 } == nil)
    }

    @Test func rejectsObserverInsideTheErgosphereOrHorizon() {
        // a = 0: ergosphere coincides with the horizon at r = 2.
        let inside = message { $0.observer.distance = 1.5 }
        #expect(inside?.contains("--distance") == true)
        #expect(message { $0.observer.distance = 2.0 }?.contains("--distance") == true)
        // a = 0.9 at 80°: ergosphere radius 1 + √(1 − a²cos²θ) ≈ 1.99, so r = 1.9 has no static observer.
        let spinning = message {
            $0.blackHole.spin = 0.9
            $0.observer.distance = 1.9
            $0.disk.outerRadius = 1.8
        }
        #expect(spinning?.contains("--distance") == true, "\(spinning ?? "accepted")")
        #expect(spinning?.contains("static observer") == true)
        // Outside the ergosphere is fine.
        #expect(message {
            $0.blackHole.spin = 0.9
            $0.observer.distance = 3.0
            $0.disk.outerRadius = 2.8
        } == nil)
    }

    @Test func rejectsDiskOuterRadiusInsideTheIsco() {
        let m = message { $0.disk.outerRadius = 5 }  // a = 0: r_isco = 6
        #expect(m?.contains("--disk-outer") == true)
        #expect(m?.contains("6") == true)
        #expect(message { $0.disk.outerRadius = 6 }?.contains("--disk-outer") == true)
    }

    @Test func rejectsObserverEmbeddedInTheDiskPlane() {
        // Inclination exactly 90° puts the observer in the disk plane; inside the annulus that is inside the disk.
        let m = message {
            $0.observer.inclinationDegrees = 90
            $0.observer.distance = 15
        }
        #expect(m?.contains("--distance") == true, "\(m ?? "accepted")")
        #expect(message {
            $0.observer.inclinationDegrees = 90
            $0.observer.distance = 100
        } == nil)
    }
}
