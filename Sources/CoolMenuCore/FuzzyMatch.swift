import Foundation

public enum FuzzyMatch {
    /// Subsequence match score, higher is better; nil when `query` is not a subsequence.
    /// Rewards consecutive characters and matches at word starts.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }
        let c = Array(candidate.lowercased())
        var qi = 0
        var score = 0
        var lastMatch = -2
        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            score += 1
            if ci == lastMatch + 1 { score += 3 }
            if ci == 0 || !c[ci - 1].isLetter && !c[ci - 1].isNumber { score += 5 }
            lastMatch = ci
            qi += 1
        }
        return qi == q.count ? score : nil
    }
}
