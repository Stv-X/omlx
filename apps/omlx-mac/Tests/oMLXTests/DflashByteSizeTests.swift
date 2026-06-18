// DFlash's in-memory cache size lives in two units across the stack:
// the server stores raw bytes, the UI lets the user type GiB. These
// tests pin the conversion at the boundaries we care about so the
// editor doesn't silently submit a value that's three orders of
// magnitude off.

import Testing
@testable import oMLX

struct DflashByteSizeTests {

    @Test("Nil Bytes Yields Nil Gib")
    func nilBytesYieldsNilGib() {
        #expect(DflashByteSize.bytesToGib(nil) == nil)
    }

    @Test("Zero Bytes Yields Nil Gib")
    func zeroBytesYieldsNilGib() {
        // 0 is the server's "unset" sentinel — the editor should fall
        // back to the placeholder, not display "0 GiB".
        #expect(DflashByteSize.bytesToGib(0) == nil)
    }

    @Test("One Gib Round Trip")
    func oneGibRoundTrip() throws {
        let bytes = try #require(DflashByteSize.gibToBytes(1))
        #expect(bytes == DflashByteSize.bytesPerGiB)
        #expect(DflashByteSize.bytesToGib(bytes) == 1)
    }

    @Test("Eight Gib Round Trip")
    func eightGibRoundTrip() throws {
        let bytes = try #require(DflashByteSize.gibToBytes(8))
        #expect(bytes == 8 * DflashByteSize.bytesPerGiB)
        #expect(DflashByteSize.bytesToGib(bytes) == 8)
    }

    @Test("Large Value Round Trip")
    func largeValueRoundTrip() throws {
        let bytes = try #require(DflashByteSize.gibToBytes(64))
        #expect(bytes == 64 * DflashByteSize.bytesPerGiB)
        #expect(DflashByteSize.bytesToGib(bytes) == 64)
    }

    @Test("Gib Below One Is Clamped To One")
    func gibBelowOneIsClampedToOne() {
        // The HTML input has min="1"; the helper enforces the floor so
        // a stray 0 from the editor doesn't disable the cache by accident.
        #expect(DflashByteSize.gibToBytes(0) == DflashByteSize.bytesPerGiB)
        #expect(DflashByteSize.gibToBytes(-5) == DflashByteSize.bytesPerGiB)
    }

    @Test("Nil Gib Yields Nil Bytes")
    func nilGibYieldsNilBytes() {
        #expect(DflashByteSize.gibToBytes(nil) == nil)
    }

    @Test("Fractional Bytes Round To Nearest Gib")
    func fractionalBytesRoundToNearestGib() {
        // 1.4 GiB → 1, 1.6 GiB → 2 (typical rounding).
        let lowFraction = Int64(1.4 * Double(DflashByteSize.bytesPerGiB))
        let highFraction = Int64(1.6 * Double(DflashByteSize.bytesPerGiB))
        #expect(DflashByteSize.bytesToGib(lowFraction) == 1)
        #expect(DflashByteSize.bytesToGib(highFraction) == 2)
    }
}
