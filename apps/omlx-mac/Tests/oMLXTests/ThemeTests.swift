import AppKit
import SwiftUI
import Testing
@testable import oMLX

@MainActor
struct ThemeTests {

    @Test("Light Window Background Uses Standard Window Color")
    func lightWindowBackgroundUsesStandardWindowColor() throws {
        let actual = try resolvedRGBA(OMLXTheme.light.windowBg, appearance: .aqua)
        let expected = try resolvedRGBA(Color(nsColor: .windowBackgroundColor),
                                        appearance: .aqua)
        let underPage = try resolvedRGBA(Color(nsColor: .underPageBackgroundColor),
                                         appearance: .aqua)

        assertClose(actual, expected)
        #expect(actual.red > 0.95)
        #expect(abs(actual.red - underPage.red) > 0.25)
    }

    @Test("Dark Window Background Keeps Under Page Color")
    func darkWindowBackgroundKeepsUnderPageColor() throws {
        let actual = try resolvedRGBA(OMLXTheme.dark.windowBg, appearance: .darkAqua)
        let expected = try resolvedRGBA(Color(nsColor: .underPageBackgroundColor),
                                        appearance: .darkAqua)

        assertClose(actual, expected)
    }

    @Test("Light Group Background Is Subtle Gray Wash")
    func lightGroupBackgroundIsSubtleGrayWash() throws {
        let actual = try resolvedRGBA(OMLXTheme.light.groupBg, appearance: .aqua)

        #expect(actual.red < 0.01)
        #expect(actual.green < 0.01)
        #expect(actual.blue < 0.01)
        #expect(actual.alpha > 0.025)
        #expect(actual.alpha < 0.05)
    }

    private typealias RGBA = (
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    )

    private func resolvedRGBA(_ color: Color, appearance: NSAppearance.Name) throws -> RGBA {
        let nsColor = NSColor(color)
        var components: RGBA?
        let nsAppearance = try #require(NSAppearance(named: appearance))
        nsAppearance.performAsCurrentDrawingAppearance {
            guard let resolved = nsColor.usingColorSpace(.sRGB) else { return }
            components = (
                red: resolved.redComponent,
                green: resolved.greenComponent,
                blue: resolved.blueComponent,
                alpha: resolved.alphaComponent
            )
        }
        return try #require(components)
    }

    private func assertClose(
        _ actual: RGBA,
        _ expected: RGBA,
        accuracy: CGFloat = 0.001
    ) {
        #expect(abs(actual.red - expected.red) <= accuracy)
        #expect(abs(actual.green - expected.green) <= accuracy)
        #expect(abs(actual.blue - expected.blue) <= accuracy)
        #expect(abs(actual.alpha - expected.alpha) <= accuracy)
    }
}
