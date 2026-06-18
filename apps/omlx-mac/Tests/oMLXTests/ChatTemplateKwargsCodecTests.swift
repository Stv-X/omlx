// The kwargs codec is the only place the editor's flat entry list meets
// the server's (chat_template_kwargs, forced_ct_kwargs) pair. These
// tests pin the round-trip so a future refactor of either side fails
// at compile/test time rather than silently dropping the user's
// settings on save.

import Testing
@testable import oMLX

struct ChatTemplateKwargsCodecTests {

    // MARK: - Encode

    @Test("Empty Entries Encode To Nil Pair")
    func emptyEntriesEncodeToNilPair() {
        let (kwargs, forced) = ChatTemplateKwargsCodec.encode([])
        #expect(kwargs == nil)
        #expect(forced == nil)
    }

    @Test("Enable Thinking Encodes As Bool")
    func enableThinkingEncodesAsBool() {
        let entries = [
            ChatTemplateKwargEntry(kind: .enableThinking, value: "true", force: false),
        ]
        let (kwargs, forced) = ChatTemplateKwargsCodec.encode(entries)
        #expect(kwargs?["enable_thinking"]?.value as? Bool == true)
        #expect(forced == nil)
    }

    @Test("Enable Thinking False Encodes As Bool")
    func enableThinkingFalseEncodesAsBool() {
        let entries = [
            ChatTemplateKwargEntry(kind: .enableThinking, value: "false", force: false),
        ]
        let (kwargs, _) = ChatTemplateKwargsCodec.encode(entries)
        #expect(kwargs?["enable_thinking"]?.value as? Bool == false)
    }

    @Test("Reasoning Effort Encodes As String")
    func reasoningEffortEncodesAsString() {
        let entries = [
            ChatTemplateKwargEntry(kind: .reasoningEffort, value: "medium", force: false),
        ]
        let (kwargs, _) = ChatTemplateKwargsCodec.encode(entries)
        #expect(kwargs?["reasoning_effort"]?.value as? String == "medium")
    }

    @Test("Custom Bool Coercion")
    func customBoolCoercion() {
        let entries = [
            ChatTemplateKwargEntry(kind: .custom, customKey: "do_thing", value: "true"),
            ChatTemplateKwargEntry(kind: .custom, customKey: "skip_thing", value: "false"),
        ]
        let (kwargs, _) = ChatTemplateKwargsCodec.encode(entries)
        #expect(kwargs?["do_thing"]?.value as? Bool == true)
        #expect(kwargs?["skip_thing"]?.value as? Bool == false)
    }

    @Test("Custom Int Coercion")
    func customIntCoercion() {
        let entries = [
            ChatTemplateKwargEntry(kind: .custom, customKey: "n_layers", value: "42"),
        ]
        let (kwargs, _) = ChatTemplateKwargsCodec.encode(entries)
        #expect(kwargs?["n_layers"]?.value as? Int == 42)
    }

    @Test("Custom Double Coercion")
    func customDoubleCoercion() {
        let entries = [
            ChatTemplateKwargEntry(kind: .custom, customKey: "alpha", value: "0.25"),
        ]
        let (kwargs, _) = ChatTemplateKwargsCodec.encode(entries)
        #expect(kwargs?["alpha"]?.value as? Double == 0.25)
    }

    @Test("Custom String Fallback")
    func customStringFallback() {
        // Anything that isn't bool-literal or numeric stays a string.
        let entries = [
            ChatTemplateKwargEntry(kind: .custom, customKey: "role", value: "expert"),
        ]
        let (kwargs, _) = ChatTemplateKwargsCodec.encode(entries)
        #expect(kwargs?["role"]?.value as? String == "expert")
    }

    @Test("Custom Blank Key Is Dropped")
    func customBlankKeyIsDropped() {
        // Mirrors dashboard.js's `e.key && e.key.trim()` guard.
        let entries = [
            ChatTemplateKwargEntry(kind: .custom, customKey: "   ", value: "v"),
            ChatTemplateKwargEntry(kind: .custom, customKey: "real", value: "v"),
        ]
        let (kwargs, _) = ChatTemplateKwargsCodec.encode(entries)
        #expect(kwargs?.count == 1)
        #expect(kwargs?["real"]?.value as? String == "v")
    }

    @Test("Force Routes Into Forced List")
    func forceRoutesIntoForcedList() {
        let entries = [
            ChatTemplateKwargEntry(kind: .enableThinking, value: "true", force: true),
            ChatTemplateKwargEntry(kind: .reasoningEffort, value: "high", force: false),
            ChatTemplateKwargEntry(kind: .custom, customKey: "k", value: "v", force: true),
        ]
        let (kwargs, forced) = ChatTemplateKwargsCodec.encode(entries)
        #expect(kwargs?.count == 3)
        #expect(Set(forced ?? []) == Set(["enable_thinking", "k"]))
    }

    // MARK: - Decode

    @Test("Decode Empty Dict Returns Empty")
    func decodeEmptyDictReturnsEmpty() {
        #expect(ChatTemplateKwargsCodec.decode(kwargs: nil, forced: nil).isEmpty)
        #expect(ChatTemplateKwargsCodec.decode(kwargs: [:], forced: nil).isEmpty)
    }

    @Test("Decode Known Kinds Appear First")
    func decodeKnownKindsAppearFirst() {
        // The HTML editor's UX intuition is that the canonical kinds
        // ride at the top; custom entries below in alphabetical order.
        let kwargs: [String: AnyCodable] = [
            "z_custom": AnyCodable("v"),
            "enable_thinking": AnyCodable(true),
            "a_custom": AnyCodable("v"),
            "reasoning_effort": AnyCodable("low"),
        ]
        let entries = ChatTemplateKwargsCodec.decode(kwargs: kwargs, forced: nil)
        #expect(entries.count == 4)
        #expect(entries[0].kind == .enableThinking)
        #expect(entries[1].kind == .reasoningEffort)
        #expect(entries[2].kind == .custom)
        #expect(entries[2].customKey == "a_custom")
        #expect(entries[3].customKey == "z_custom")
    }

    @Test("Decode Applies Forced Flag")
    func decodeAppliesForcedFlag() {
        let kwargs: [String: AnyCodable] = [
            "enable_thinking": AnyCodable(true),
            "custom_a": AnyCodable("v"),
        ]
        let entries = ChatTemplateKwargsCodec.decode(
            kwargs: kwargs,
            forced: ["enable_thinking"]
        )
        #expect(entries.first(where: { $0.kind == .enableThinking })!.force)
        #expect(!(entries.first(where: { $0.kind == .custom })!.force))
    }

    @Test("Decode Stringifies Values")
    func decodeStringifiesValues() {
        let kwargs: [String: AnyCodable] = [
            "enable_thinking": AnyCodable(true),
            "n":               AnyCodable(7),
            "alpha":           AnyCodable(0.25),
            "role":            AnyCodable("expert"),
        ]
        let entries = ChatTemplateKwargsCodec.decode(kwargs: kwargs, forced: nil)
        let byKey: [String: String] = entries.reduce(into: [:]) {
            $0[$1.resolvedKey ?? ""] = $1.value
        }
        #expect(byKey["enable_thinking"] == "true")
        #expect(byKey["n"] == "7")
        // 0.25 is non-integral → keeps decimal form.
        #expect(byKey["alpha"] == "0.25")
        #expect(byKey["role"] == "expert")
    }

    // MARK: - Round-trip

    @Test("Round Trip Preserves Known And Custom Entries")
    func roundTripPreservesKnownAndCustomEntries() {
        let original = [
            ChatTemplateKwargEntry(kind: .enableThinking, value: "false", force: true),
            ChatTemplateKwargEntry(kind: .reasoningEffort, value: "high", force: false),
            ChatTemplateKwargEntry(kind: .custom, customKey: "max_branches", value: "5", force: true),
        ]
        let (kwargs, forced) = ChatTemplateKwargsCodec.encode(original)
        let roundtripped = ChatTemplateKwargsCodec.decode(kwargs: kwargs, forced: forced)
        #expect(roundtripped.count == 3)

        let byKey: [String: ChatTemplateKwargEntry] = roundtripped.reduce(into: [:]) {
            $0[$1.resolvedKey ?? ""] = $1
        }
        #expect(byKey["enable_thinking"]?.value == "false")
        #expect(byKey["enable_thinking"]?.force == true)
        #expect(byKey["reasoning_effort"]?.value == "high")
        #expect(byKey["reasoning_effort"]?.force == false)
        #expect(byKey["max_branches"]?.value == "5")
        #expect(byKey["max_branches"]?.force == true)
    }
}
