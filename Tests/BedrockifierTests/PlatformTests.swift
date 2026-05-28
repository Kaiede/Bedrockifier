import Testing
@testable import BedrockifierLib

@Suite struct PlatformTimingsafeCompareTests {

    // MARK: - String overload

    @Test func equalStringsReturnsTrue() {
        #expect(Platform.timingsafeCompare("hello", "hello"))
    }

    @Test func differentStringsReturnsFalse() {
        #expect(!Platform.timingsafeCompare("hello", "world"))
    }

    @Test func differentLengthsReturnsFalse() {
        #expect(!Platform.timingsafeCompare("short", "longer string"))
    }

    @Test func emptyStringsReturnTrue() {
        #expect(Platform.timingsafeCompare("", ""))
    }

    @Test func emptyVsNonEmptyReturnsFalse() {
        #expect(!Platform.timingsafeCompare("", "a"))
        #expect(!Platform.timingsafeCompare("a", ""))
    }

    @Test func samePrefixDifferentSuffixReturnsFalse() {
        #expect(!Platform.timingsafeCompare("Bearer abc123x", "Bearer abc123y"))
    }

    @Test func differentByOneByteReturnsFalse() {
        #expect(!Platform.timingsafeCompare("aaaaaaaaa", "aaaaaaaab"))
    }

    // Mirrors the exact call pattern used in TokenCheckingMiddleware.
    @Test func bearerTokenFormat() {
        let token = "dGVzdHRva2VuMTIzNDU2Nzg="
        #expect(Platform.timingsafeCompare("Bearer \(token)", "Bearer \(token)"))
        #expect(!Platform.timingsafeCompare("Bearer wrongtoken====", "Bearer \(token)"))
        #expect(!Platform.timingsafeCompare("Basic \(token)", "Bearer \(token)"))
    }

    // MARK: - [UInt8] overload

    @Test func equalByteArraysReturnsTrue() {
        #expect(Platform.timingsafeCompare([0x01, 0x02, 0x03], [0x01, 0x02, 0x03]))
    }

    @Test func differentByteArraysReturnsFalse() {
        #expect(!Platform.timingsafeCompare([0x01, 0x02, 0x03], [0x01, 0x02, 0x04]))
    }

    @Test func differentLengthByteArraysReturnsFalse() {
        #expect(!Platform.timingsafeCompare([0x01, 0x02], [0x01, 0x02, 0x03]))
    }

    @Test func emptyByteArraysReturnTrue() {
        #expect(Platform.timingsafeCompare([], []))
    }

    @Test func firstByteDiffersReturnsFalse() {
        #expect(!Platform.timingsafeCompare([0xFF, 0x00, 0x00], [0x00, 0x00, 0x00]))
    }

    @Test func lastByteDiffersReturnsFalse() {
        #expect(!Platform.timingsafeCompare([0x00, 0x00, 0xFF], [0x00, 0x00, 0x00]))
    }
}
