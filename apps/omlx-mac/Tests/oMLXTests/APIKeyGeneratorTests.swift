// The random-key generator backs the regenerate button in the Security
// screen and the Generate button in the Welcome wizard. The server-side
// validator (`validate_api_key` in `omlx/admin/routes.py`) requires ≥ 4
// printable characters with no whitespace. These tests pin the shape so
// a future tweak to the alphabet, prefix, or length can't silently
// produce keys the server will reject.

import Foundation
import Testing
@testable import oMLX

struct APIKeyGeneratorTests {

    @Test("Has Expected Prefix")
    func hasExpectedPrefix() {
        let key = APIKeyGenerator.random()
        #expect(key.hasPrefix(APIKeyGenerator.prefix), "key should start with prefix; got: \(key)")
    }

    @Test("Total Length Matches Prefix Plus Body")
    func totalLengthMatchesPrefixPlusBody() {
        let key = APIKeyGenerator.random()
        #expect(key.count == APIKeyGenerator.prefix.count + APIKeyGenerator.bodyLength)
    }

    @Test("Body Only Uses Declared Alphabet")
    func bodyOnlyUsesDeclaredAlphabet() {
        let key = APIKeyGenerator.random()
        let body = String(key.dropFirst(APIKeyGenerator.prefix.count))
        let allowed = Set(APIKeyGenerator.bodyAlphabet)
        #expect(body.allSatisfy { allowed.contains($0) }, "body contained non-alphabet chars: \(body)")
    }

    @Test("No Whitespace")
    func noWhitespace() {
        // Server rejects whitespace — the alphabet excludes it but pin
        // the invariant explicitly in case someone extends the alphabet
        // and forgets the constraint.
        for _ in 0..<32 {
            let key = APIKeyGenerator.random()
            #expect(!(key.contains(where: { $0.isWhitespace })), "key contained whitespace: \(key)")
        }
    }

    @Test("Succeeds Server Side Floor")
    func succeedsServerSideFloor() {
        // ≥ 4 printable characters: trivially satisfied by an 8-char
        // prefix + 24-char body, but checked here so a future shorter
        // body still passes the server floor.
        let key = APIKeyGenerator.random()
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        #expect(trimmed.count >= 4)
    }

    @Test("Distinct Outputs Between Calls")
    func distinctOutputsBetweenCalls() {
        // 24 chars of ~62-symbol alphabet → collision probability is
        // vanishing. A literal-equality collision across 16 calls would
        // mean the RNG is broken.
        let samples = (0..<16).map { _ in APIKeyGenerator.random() }
        #expect(Set(samples).count == samples.count, "two random keys collided: \(samples)")
    }
}
