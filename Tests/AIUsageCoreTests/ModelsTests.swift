import Testing
@testable import AIUsageCore

@Test func providerNames() {
    #expect(Provider.allCases.map(\.name) == ["Claude Code", "Codex"])
}
