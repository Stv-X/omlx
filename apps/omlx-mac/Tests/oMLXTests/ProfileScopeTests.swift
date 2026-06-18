// The Profiles tab splits templates into Preset / Global scopes purely by
// the server's `is_builtin` flag. These tests pin that mapping so a
// rename of the wire field, or a future "default to Preset" decision,
// reaches the build instead of silently flipping every user template
// into the read-only group.

import Testing
@testable import oMLX

struct ProfileScopeTests {

    private func template(isBuiltin: Bool?) -> ProfileDTO {
        ProfileDTO(
            name: "x", displayName: "X",
            description: nil, createdAt: nil, updatedAt: nil,
            sourceTemplate: nil, isBuiltin: isBuiltin,
            exposeAsModel: nil, modelId: nil, hasEngineFields: nil,
            settings: nil
        )
    }

    @Test("Builtin True Resolves To Preset")
    func builtinTrueResolvesToPreset() {
        #expect(template(isBuiltin: true).templateScope == .preset)
    }

    @Test("Builtin False Resolves To Global")
    func builtinFalseResolvesToGlobal() {
        #expect(template(isBuiltin: false).templateScope == .global)
    }

    @Test("Missing Builtin Defaults To Global")
    func missingBuiltinDefaultsToGlobal() {
        // Legacy / partial server responses where the field is absent —
        // the server is the only source of truth for builtin status, so
        // "the server didn't claim built-in" means user-managed.
        #expect(template(isBuiltin: nil).templateScope == .global)
    }
}
