import Foundation

/// Predictions that learn from what you type.
/// Base vocabulary: a bundled word-frequency list (most common first).
/// Learned data: how often you use each word, and which word you type after which.
final class WordEngine {
    private var words: [String] = []
    private var lowerWords: [String] = []
    private var baseRank: [String: Int] = [:]
    private var userCounts: [String: Int] = [:]
    private var bigrams: [String: [String: Int]] = [:]
    private var unsaved = 0

    private let defaults = UserDefaults.standard
    private let userKey = "nk.words.\(Layouts.isArabic ? "ar" : "en")"
    private let bigramKey = "nk.bigrams.\(Layouts.isArabic ? "ar" : "en")"

    init() {
        let file = Layouts.isArabic ? "words_ar" : "words_en"
        if let url = Bundle.main.url(forResource: file, withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            words = text.split(separator: "\n").map(String.init)
            lowerWords = words.map { $0.lowercased() }
            for (index, word) in lowerWords.enumerated() where baseRank[word] == nil {
                baseRank[word] = index
            }
        }
        userCounts = defaults.dictionary(forKey: userKey) as? [String: Int] ?? [:]
        bigrams = defaults.dictionary(forKey: bigramKey) as? [String: [String: Int]] ?? [:]
    }

    // MARK: Scoring

    private func score(_ lower: String) -> Double {
        var value = 0.0
        if let rank = baseRank[lower] {
            value += 1_000_000 / Double(rank + 100)
        }
        if let count = userCounts[lower] {
            value += Double(count) * 4000
        }
        return value
    }

    func isKnown(_ word: String) -> Bool {
        let lower = word.lowercased()
        return baseRank[lower] != nil || userCounts[lower] != nil
    }

    // MARK: Predictions

    /// Words that start with what you've typed so far.
    func completions(for prefix: String, limit: Int) -> [String] {
        let p = prefix.lowercased()
        guard !p.isEmpty else { return [] }
        var scored: [(String, Double)] = []
        for (index, lower) in lowerWords.enumerated() where lower.count > p.count && lower.hasPrefix(p) {
            scored.append((words[index], score(lower)))
        }
        for word in userCounts.keys where baseRank[word] == nil && word.count > p.count && word.hasPrefix(p) {
            scored.append((word, score(word)))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    /// Words you're likely to type next.
    func nextWords(after previous: String?, limit: Int) -> [String] {
        var out: [String] = []
        if let previous, let followers = bigrams[previous.lowercased()] {
            out = followers.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
        }
        for word in words where out.count < limit {
            if !out.contains(where: { $0.lowercased() == word.lowercased() }) {
                out.append(word)
            }
        }
        return out
    }

    // MARK: Learning

    func learn(_ word: String, after previous: String?) {
        let lower = word.lowercased()
        guard lower.count >= 2 || lower == "a" || lower == "i" else { return }
        userCounts[lower, default: 0] += 1
        if let previous {
            let prev = previous.lowercased()
            var followers = bigrams[prev] ?? [:]
            followers[lower, default: 0] += 1
            if followers.count > 30, let weakest = followers.min(by: { $0.value < $1.value })?.key {
                followers.removeValue(forKey: weakest)
            }
            bigrams[prev] = followers
        }
        trimIfNeeded()
        unsaved += 1
        if unsaved >= 8 { save() }
    }

    private func trimIfNeeded() {
        if userCounts.count > 6000 {
            let keep = userCounts.sorted { $0.value > $1.value }.prefix(5000)
            userCounts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if bigrams.count > 6000 {
            let keep = bigrams.sorted { $0.value.count > $1.value.count }.prefix(5000)
            bigrams = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    func save() {
        defaults.set(userCounts, forKey: userKey)
        defaults.set(bigrams, forKey: bigramKey)
        unsaved = 0
    }
}
