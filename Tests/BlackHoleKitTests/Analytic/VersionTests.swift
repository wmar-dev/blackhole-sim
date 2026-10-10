import Testing
@testable import BlackHoleKit

@Test func packageBuilds() {
    #expect(!BlackHoleKit.version.isEmpty)
}
