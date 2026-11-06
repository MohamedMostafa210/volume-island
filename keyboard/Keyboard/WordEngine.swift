import Foundation

/// Thread-safe counter used to throw away out-of-date prediction requests.
final class Generation {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func isCurrent(_ ticket: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ticket == value
    }
}

/// Runs all word work (loading, predicting, learning, saving) on one
/// background queue, so a typed letter never waits for it.
final class Predictor {
    struct Request {
        let previous: String?
        let word: String
        let atWordStart: Bool
        let capitalize: Bool
    }

    private let queue = DispatchQueue(label: "numberkeys.words", qos: .userInitiated)
    private let generation = Generation()
    // Only touched on `queue`.
    private var engine: WordEngine?
    private var saveTicket = 0

    init() {
        // Loading the word list is the first job on the queue, so every
        // later request automatically waits for it, without blocking typing.
        queue.async { [weak self] in
            self?.engine = WordEngine()
        }
    }

    /// Works out suggestions in the background. `done` runs on the main thread,
    /// and only if no newer request was made in the meantime.
    func suggest(_ request: Request, done: @escaping ([String]) -> Void) {
        let ticket = generation.next()
        queue.async { [weak self] in
            guard let self, self.generation.isCurrent(ticket), let engine = self.engine else { return }
            let result = engine.suggestions(for: request)
            DispatchQueue.main.async {
                guard self.generation.isCurrent(ticket) else { return }
                done(result)
            }
        }
    }

    func learn(_ word: String, after previous: String?) {
        queue.async { [weak self] in
            guard let self, let engine = self.engine else { return }
            engine.learn(word, after: previous)
            self.scheduleSave()
        }
    }

    /// Saves now (when the keyboard is closing).
    func saveNow() {
        queue.async { [weak self] in
            self?.engine?.save()
        }
    }

    /// Saves 3 seconds after the last learned word, in the background.
    private func scheduleSave() {
        saveTicket += 1
        let ticket = saveTicket
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.saveTicket == ticket else { return }
            self.engine?.save()
        }
    }
}

/// Predictions that learn from what you type. Used only from Predictor's queue.
/// Base vocabulary: a bundled word-frequency list (most common first).
/// Learned data: how often you use each word, and which word you type after which.
final class WordEngine {
    private struct Entry {
        let lower: String
        let word: String
    }

    private var words: [String] = []
    /// The same words sorted alphabetically, so a prefix is found by binary search.
    private var sorted: [Entry] = []
    private var baseRank: [String: Int] = [:]
    private var userCounts: [String: Int] = [:]
    private var bigrams: [String: [String: Int]] = [:]
    private var unsaved = false

    private let defaults = UserDefaults.standard
    private let userKey = "nk.words.\(Layouts.isArabic ? "ar" : "en")"
    private let bigramKey = "nk.bigrams.\(Layouts.isArabic ? "ar" : "en")"

    private static let maxWords = 5000
    private static let maxPairs = 3000
    private static let maxFollowers = 12
    private static let alphabet: [Character] = Array(
        Layouts.isArabic ? "ابتثجحخدذرزسشصضطظعغفقكلمنهويءآأإؤئىة" : "abcdefghijklmnopqrstuvwxyz'"
    )

    init() {
        let file = Layouts.isArabic ? "words_ar" : "words_en"
        if let url = Bundle.main.url(forResource: file, withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            words = text.split(whereSeparator: { $0.isNewline }).map(String.init)
            var entries: [Entry] = []
            entries.reserveCapacity(words.count)
            for (index, word) in words.enumerated() {
                let lower = word.lowercased()
                if baseRank[lower] == nil { baseRank[lower] = index }
                entries.append(Entry(lower: lower, word: word))
            }
            entries.sort { $0.lower.utf8.lexicographicallyPrecedes($1.lower.utf8) }
            sorted = entries
        }
        userCounts = defaults.dictionary(forKey: userKey) as? [String: Int] ?? [:]
        var pairs = defaults.dictionary(forKey: bigramKey) as? [String: [String: Int]] ?? [:]
        for (key, followers) in pairs where followers.count > Self.maxFollowers {
            pairs[key] = Self.strongest(followers, keep: Self.maxFollowers)
        }
        bigrams = pairs
        trimIfNeeded()
    }

    private static func strongest(_ counts: [String: Int], keep: Int) -> [String: Int] {
        let top = counts.sorted { $0.value > $1.value }.prefix(keep)
        return Dictionary(uniqueKeysWithValues: top.map { ($0.key, $0.value) })
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

    private func isKnownLower(_ lower: String) -> Bool {
        baseRank[lower] != nil || userCounts[lower] != nil
    }

    func isKnown(_ word: String) -> Bool {
        isKnownLower(word.lowercased())
    }

    // MARK: Suggestions

    func suggestions(for request: Predictor.Request) -> [String] {
        if request.word.isEmpty {
            guard request.atWordStart else { return [] }
            var next = nextWords(after: request.previous, limit: 3)
            if request.capitalize {
                next = next.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            }
            return next
        }

        let word = request.word
        var picks: [String] = []
        var seen = Set<String>([word.lowercased()])
        func add(_ candidate: String) {
            let fixed = Self.matchCase(candidate, like: word)
            if seen.insert(fixed.lowercased()).inserted { picks.append(fixed) }
        }
        if !isKnown(word) {
            guesses(for: word, limit: 2).forEach(add)
        }
        completions(for: word, limit: 4).forEach(add)
        return Array(picks.prefix(2))
    }

    private static func matchCase(_ word: String, like typed: String) -> String {
        guard typed.first?.isUppercase ?? false else { return word }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    /// Index of the first word that is not alphabetically before `prefix`.
    private func firstIndex(atLeast prefix: String) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid].lower.utf8.lexicographicallyPrecedes(prefix.utf8) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// Words that start with what you've typed so far.
    func completions(for prefix: String, limit: Int) -> [String] {
        let p = prefix.lowercased()
        guard !p.isEmpty else { return [] }
        let length = p.utf8.count
        var scored: [(String, Double)] = []
        var index = firstIndex(atLeast: p)
        while index < sorted.count, sorted[index].lower.utf8.starts(with: p.utf8) {
            let entry = sorted[index]
            if entry.lower.utf8.count > length {
                scored.append((entry.word, score(entry.lower)))
            }
            index += 1
        }
        for word in userCounts.keys where baseRank[word] == nil && word.utf8.count > length && word.utf8.starts(with: p.utf8) {
            scored.append((word, score(word)))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    /// Known words one typo away (a letter missing, extra, swapped or wrong).
    func guesses(for word: String, limit: Int) -> [String] {
        let lower = word.lowercased()
        let chars = Array(lower)
        guard chars.count >= 2, chars.count <= 20 else { return [] }
        var found: [String: Double] = [:]
        func check(_ candidate: [Character]) {
            let text = String(candidate)
            if found[text] == nil, isKnownLower(text) {
                found[text] = score(text)
            }
        }
        for i in 0..<chars.count {
            var c = chars
            c.remove(at: i)
            check(c)
        }
        for i in 0..<(chars.count - 1) {
            var c = chars
            c.swapAt(i, i + 1)
            check(c)
        }
        for i in 0..<chars.count {
            for letter in Self.alphabet where letter != chars[i] {
                var c = chars
                c[i] = letter
                check(c)
            }
        }
        for i in 0...chars.count {
            for letter in Self.alphabet {
                var c = chars
                c.insert(letter, at: i)
                check(c)
            }
        }
        found.removeValue(forKey: lower)
        return found.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    /// Words you're likely to type next.
    func nextWords(after previous: String?, limit: Int) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        if let previous, let followers = bigrams[previous.lowercased()] {
            let top = followers.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
            for word in top where seen.insert(word.lowercased()).inserted {
                out.append(word)
            }
        }
        for word in words {
            if out.count >= limit { break }
            if seen.insert(word.lowercased()).inserted {
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
            if followers.count > Self.maxFollowers, let weakest = followers.min(by: { $0.value < $1.value })?.key {
                followers.removeValue(forKey: weakest)
            }
            bigrams[prev] = followers
        }
        trimIfNeeded()
        unsaved = true
    }

    private func trimIfNeeded() {
        if userCounts.count > Self.maxWords + 1000 {
            userCounts = Self.strongest(userCounts, keep: Self.maxWords)
        }
        if bigrams.count > Self.maxPairs + 1000 {
            let keep = bigrams.sorted { $0.value.count > $1.value.count }.prefix(Self.maxPairs)
            bigrams = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    func save() {
        guard unsaved else { return }
        defaults.set(userCounts, forKey: userKey)
        defaults.set(bigrams, forKey: bigramKey)
        unsaved = false
    }
}
