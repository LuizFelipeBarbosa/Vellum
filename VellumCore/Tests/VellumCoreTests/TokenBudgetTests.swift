import Testing
@testable import VellumCore

@Test("Token estimates follow the documented formula and are monotonic")
func tokenEstimateFormulaAndMonotonicity() {
    #expect(TokenBudget.estimatedTokens(forCharacterCount: 0) == 0)
    #expect(TokenBudget.estimatedTokens(forCharacterCount: 1) == 1)
    #expect(TokenBudget.estimatedTokens(forCharacterCount: 35) == 12)
    #expect(TokenBudget.estimatedTokens(forCharacterCount: 350) == 120)

    let estimates = (0...100).map(TokenBudget.estimatedTokens(forCharacterCount:))
    #expect(zip(estimates, estimates.dropFirst()).allSatisfy { $0 <= $1 })
}

@Test("Text within the character budget is unchanged")
func tokenTruncationIsNoOpWithinBudget() {
    let text = "Short text"

    #expect(TokenBudget.truncateHeadAndTail(text, charBudget: text.count) == text)
    #expect(TokenBudget.truncateHeadAndTail(text, charBudget: text.count + 5) == text)
}

@Test("Head-tail truncation preserves both ends within the exact budget")
func tokenTruncationPreservesEndsAtBoundary() {
    let text = "abcdefghijklmnopqrstuvwxyz"
    let result = TokenBudget.truncateHeadAndTail(text, charBudget: 13)

    #expect(result.count == 13)
    #expect(result.count <= 13)
    #expect(result.hasPrefix("abcdefgh"))
    #expect(result.hasSuffix("yz"))
    #expect(result.contains("\n…\n"))

    for budget in 0..<text.count {
        #expect(TokenBudget.truncateHeadAndTail(text, charBudget: budget).count <= budget)
    }
}
