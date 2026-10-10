import Foundation
import Testing
@testable import BlackHoleKit

/// Backend selection, metadata and input validation (FR-002, FR-006, FR-013).
@Suite struct BackendTests {
    @Test func backendNamesAndPrecisions() {
        #expect(Backend.cpu.name == "cpu" && Backend.cpu.precision == "float64")
        #expect(Backend.metal.name == "metal" && Backend.metal.precision == "float32")
        #expect(Set(Backend.allCases) == [.cpu, .metal])
    }

    @Test func cpuIsTheDefaultBackend() {
        #expect(RenderConfig().backend == .cpu)
    }

    @Test func metadataRecordsTheBackendAndValidatesAgainstTheSchema() throws {
        for backend in Backend.allCases {
            var config = RenderConfig()
            config.backend = backend
            let metadata = RenderMetadata(config: config, shading: .physical, referenceRadiance: 2.5, diagnostics: Diagnostics())
            let json = try #require(JSONSerialization.jsonObject(with: metadata.jsonData()) as? [String: Any])
            let info = try #require(json["backend"] as? [String: Any])
            #expect(info["name"] as? String == backend.name)
            #expect(info["precision"] as? String == backend.precision)

            let schemaURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("specs/001-black-hole-image/contracts/render-metadata.schema.json")
            let schema = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any])
            #expect((schema["required"] as? [String])?.contains("backend") == true, "the schema must require the backend record")
            let problems = JSONSchemaSubset.validate(json, against: schema, path: "$")
            #expect(problems.isEmpty, "\(problems)")
        }
    }

    @Test func renderedImagesCarryTheirBackend() throws {
        var config = RenderConfig()
        config.width = 8
        config.height = 4
        config.samplesPerPixel = 1
        config.sky = SkyConfig(kind: .grid, seed: 1, starCount: 0)
        let image = try Renderer(config: config).render()
        #expect(image.backend == .cpu)
    }

    @Test func inputValidationIsIdenticalForBothBackends() {
        let invalid: [(String, (inout RenderConfig) -> Void)] = [
            ("spin", { $0.blackHole.spin = 1.2 }),
            ("mass", { $0.blackHole.massSolar = -1 }),
            ("samples", { $0.samplesPerPixel = 3 }),
            ("distance", { $0.observer.distance = 1.5 }),
            ("inclination", { $0.observer.inclinationDegrees = 0 }),
            ("disk", { $0.disk.outerRadius = 3 }),
            ("width", { $0.width = 0 }),
        ]
        for (name, modify) in invalid {
            var cpu = RenderConfig(), gpu = RenderConfig()
            modify(&cpu)
            modify(&gpu)
            cpu.backend = .cpu
            gpu.backend = .metal
            func message(_ c: RenderConfig) -> String? {
                do { try c.validate(); return nil } catch let e as ConfigError { return e.errorDescription } catch { return "other: \(error)" }
            }
            #expect(message(cpu) != nil, "\(name) should be rejected")
            #expect(message(cpu) == message(gpu), "\(name): messages differ between backends")
        }
        var ok = RenderConfig()
        ok.backend = .metal
        #expect((try? ok.validate()) != nil)
    }

    @Test func unavailableErrorDescribesTheCause() {
        let error = BackendError.unavailable("no Metal-capable GPU was found")
        #expect(error.errorDescription == "no Metal-capable GPU was found")
        #expect(BackendError.unavailable("a") != BackendError.unavailable("b"))
    }
}
