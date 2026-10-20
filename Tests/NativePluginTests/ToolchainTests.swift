// SPDX-License-Identifier: GPL-3.0-or-later
import Testing
import EmacsSwiftModule

@Test func libraryCompilesWithSwiftSixLanguageMode() {
    #expect(EmacsSwiftModuleVersion.swiftLanguage == 6)
}
