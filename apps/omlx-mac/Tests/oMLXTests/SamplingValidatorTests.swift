// Validation for sampling-parameter text inputs. The text-field UX accepts
// any string, so the validator is the only thing standing between a slipped
// keystroke and an out-of-band patch hitting the server. These tests pin
// the documented ranges so a future widening/narrowing has to update them.

import Testing
@testable import oMLX

struct SamplingValidatorTests {

    // MARK: - Temperature (≥ 0)

    @Test("Temperature Empty Is Nil")
    func temperatureEmptyIsNil() throws {
        #expect(try SamplingValidator.temperature("").get() == nil)
        #expect(try SamplingValidator.temperature("   ").get() == nil)
    }

    @Test("Temperature Accepts Boundary")
    func temperatureAcceptsBoundary() throws {
        #expect(try SamplingValidator.temperature("0").get() == 0)
        #expect(try SamplingValidator.temperature("0.0").get() == 0)
        #expect(try SamplingValidator.temperature("2.5").get() == 2.5)
    }

    @Test("Temperature Rejects Negative")
    func temperatureRejectsNegative() {
        #expect(throws: (any Error).self) {
            try SamplingValidator.temperature("-0.01").get()
        }
    }

    @Test("Temperature Rejects Non Numeric")
    func temperatureRejectsNonNumeric() {
        #expect(throws: (any Error).self) {
            try SamplingValidator.temperature("hot").get()
        }
    }

    // MARK: - Top P (0 < p ≤ 1)

    @Test("Top P Empty Is Nil")
    func topPEmptyIsNil() throws {
        #expect(try SamplingValidator.topP("").get() == nil)
    }

    @Test("Top P Accepts Upper Boundary")
    func topPAcceptsUpperBoundary() throws {
        #expect(try SamplingValidator.topP("1").get() == 1)
        #expect(try SamplingValidator.topP("0.95").get() == 0.95)
    }

    @Test("Top P Rejects Zero")
    func topPRejectsZero() {
        // 0 would mean "no candidates pass the nucleus filter" — not valid.
        #expect(throws: (any Error).self) {
            try SamplingValidator.topP("0").get()
        }
    }

    @Test("Top P Rejects Above One")
    func topPRejectsAboveOne() {
        #expect(throws: (any Error).self) {
            try SamplingValidator.topP("1.01").get()
        }
    }

    @Test("Top P Rejects Negative")
    func topPRejectsNegative() {
        #expect(throws: (any Error).self) {
            try SamplingValidator.topP("-0.1").get()
        }
    }

    // MARK: - Min P (0 ≤ p ≤ 1)

    @Test("Min P Accepts Zero")
    func minPAcceptsZero() throws {
        // 0 is the documented "disabled" value for min-p.
        #expect(try SamplingValidator.minP("0").get() == 0)
        #expect(try SamplingValidator.minP("0.05").get() == 0.05)
        #expect(try SamplingValidator.minP("1").get() == 1)
    }

    @Test("Min P Rejects Above One")
    func minPRejectsAboveOne() {
        #expect(throws: (any Error).self) {
            try SamplingValidator.minP("1.5").get()
        }
    }

    @Test("Min P Rejects Negative")
    func minPRejectsNegative() {
        #expect(throws: (any Error).self) {
            try SamplingValidator.minP("-0.01").get()
        }
    }

    // MARK: - Top K (Z+)

    @Test("Top K Empty Is Nil")
    func topKEmptyIsNil() throws {
        #expect(try SamplingValidator.topK("").get() == nil)
    }

    @Test("Top K Accepts Positive Integer")
    func topKAcceptsPositiveInteger() throws {
        #expect(try SamplingValidator.topK("1").get() == 1)
        #expect(try SamplingValidator.topK("20").get() == 20)
    }

    @Test("Top K Rejects Zero")
    func topKRejectsZero() {
        #expect(throws: (any Error).self) {
            try SamplingValidator.topK("0").get()
        }
    }

    @Test("Top K Rejects Negative")
    func topKRejectsNegative() {
        #expect(throws: (any Error).self) {
            try SamplingValidator.topK("-3").get()
        }
    }

    @Test("Top K Rejects Float")
    func topKRejectsFloat() {
        // 1.5 is not an integer — must reject so the int-typed patch stays honest.
        #expect(throws: (any Error).self) {
            try SamplingValidator.topK("1.5").get()
        }
    }

    @Test("Top K Rejects Non Numeric")
    func topKRejectsNonNumeric() {
        #expect(throws: (any Error).self) {
            try SamplingValidator.topK("twenty").get()
        }
    }

    // MARK: - Penalty (-2 to 2)

    @Test("Penalty Empty Is Nil")
    func penaltyEmptyIsNil() throws {
        #expect(try SamplingValidator.penalty("", name: "Repetition Penalty").get() == nil)
    }

    @Test("Penalty Accepts Boundaries")
    func penaltyAcceptsBoundaries() throws {
        #expect(try SamplingValidator.penalty("-2", name: "Repetition Penalty").get() == -2)
        #expect(try SamplingValidator.penalty("0", name: "Repetition Penalty").get() == 0)
        #expect(try SamplingValidator.penalty("2", name: "Repetition Penalty").get() == 2)
        #expect(try SamplingValidator.penalty("1.0", name: "Presence Penalty").get() == 1.0)
    }

    @Test("Penalty Rejects Out Of Range")
    func penaltyRejectsOutOfRange() {
        #expect(throws: (any Error).self) {
            try SamplingValidator.penalty("-2.01", name: "Repetition Penalty").get()
        }
        #expect(throws: (any Error).self) {
            try SamplingValidator.penalty("2.01", name: "Presence Penalty").get()
        }
    }

    @Test("Penalty Message Mentions Field Name")
    func penaltyMessageMentionsFieldName() throws {
        // The UI surfaces this string verbatim — keep the field name in the message
        // so the user knows which row to fix.
        let result = SamplingValidator.penalty("9", name: "Repetition Penalty")
        guard case .failure(let err) = result else {
            try #require(Bool(false), "expected failure")
            return
        }
        #expect(err.message.contains("Repetition Penalty"), "message was: \(err.message)")
    }
}
