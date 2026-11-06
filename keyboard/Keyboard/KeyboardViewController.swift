import AudioToolbox
import UIKit

final class KeyboardViewController: UIInputViewController, KeysAreaDelegate {
    private let suggestionBar = SuggestionBar()
    private let keysArea = KeysArea()
    private let emojiPanel = EmojiPanel()
    private var heightConstraint: NSLayoutConstraint?

    private enum ShiftState { case off, once, locked }

    private var mode: KeyboardMode = .letters
    private var shift: ShiftState = .off
    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast
    private var theme: Theme = .light

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let checker = UITextChecker()

    // MARK: Metrics

    private var isLandscape: Bool { traitCollection.verticalSizeClass == .compact }
    private var barHeight: CGFloat { isLandscape ? 34 : 44 }
    private var rowPitch: CGFloat { isLandscape ? 40 : 54 }
    private var totalHeight: CGFloat { barHeight + rowPitch * 5 + 4 }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        for sub in [suggestionBar, keysArea, emojiPanel] as [UIView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sub)
        }

        let barHeightConstraint = suggestionBar.heightAnchor.constraint(equalToConstant: barHeight)
        barHeightConstraint.identifier = "bar"
        NSLayoutConstraint.activate([
            suggestionBar.topAnchor.constraint(equalTo: view.topAnchor),
            suggestionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHeightConstraint,

            keysArea.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            keysArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keysArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keysArea.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emojiPanel.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            emojiPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emojiPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emojiPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let height = view.heightAnchor.constraint(equalToConstant: totalHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height

        keysArea.delegate = self
        suggestionBar.onPick = { [weak self] value in self?.applySuggestion(value) }
        emojiPanel.onPick = { [weak self] emoji in
            self?.feedback(.text(emoji))
            self?.textDocumentProxy.insertText(emoji)
        }
        emojiPanel.onBack = { [weak self] in
            self?.mode = .letters
            self?.reload()
        }
        emojiPanel.onDelete = { [weak self] in
            self?.feedback(.delete)
            self?.textDocumentProxy.deleteBackward()
        }

        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        mode = .letters
        afterEdit()
        reload()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if heightConstraint?.constant != totalHeight {
            heightConstraint?.constant = totalHeight
            for constraint in suggestionBar.constraints where constraint.identifier == "bar" {
                constraint.constant = barHeight
            }
        }
        keysArea.rowPitch = rowPitch
        keysArea.showsPreviews = !isLandscape
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        afterEdit()
        reload()
    }

    // MARK: Drawing

    private func reload() {
        let dark = textDocumentProxy.keyboardAppearance == .dark
            || traitCollection.userInterfaceStyle == .dark
        theme = dark ? .dark : .light
        keysArea.theme = theme
        suggestionBar.apply(theme: theme)
        emojiPanel.apply(theme: theme)

        let showEmoji = mode == .emoji
        emojiPanel.isHidden = !showEmoji
        keysArea.isHidden = showEmoji

        let rows = Layouts.rows(mode: mode, shifted: shift != .off, showGlobe: needsInputModeSwitchKey)
        keysArea.setRows(rows)
        for key in keysArea.keyViews {
            configure(key)
        }
    }

    private func configure(_ key: KeyView) {
        switch key.spec.action {
        case .text(let text):
            key.configure(text: text, image: nil, special: false, accent: false, theme: theme)
        case .space:
            key.configure(text: Layouts.isArabic ? "مسافة" : "space", image: nil, special: false, accent: false, theme: theme)
        case .shift:
            let image: String
            switch shift {
            case .off: image = "shift"
            case .once: image = "shift.fill"
            case .locked: image = "capslock.fill"
            }
            key.configure(text: nil, image: image, special: shift == .off, accent: false, theme: theme)
        case .delete:
            key.configure(text: nil, image: "delete.left", special: true, accent: false, theme: theme)
        case .globe:
            key.configure(text: nil, image: "globe", special: true, accent: false, theme: theme)
        case .returnKey:
            let info = returnInfo()
            key.configure(text: info.title, image: nil, special: true, accent: info.blue, theme: theme)
        case .mode(let target):
            switch target {
            case .letters:
                key.configure(text: Layouts.isArabic ? "أبج" : "ABC", image: nil, special: true, accent: false, theme: theme)
            case .symbols:
                key.configure(text: "123", image: nil, special: true, accent: false, theme: theme)
            case .symbols2:
                key.configure(text: "#+=", image: nil, special: true, accent: false, theme: theme)
            case .emoji:
                key.configure(text: nil, image: "face.smiling", special: true, accent: false, theme: theme)
            }
        }
    }

    private func returnInfo() -> (title: String, blue: Bool) {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return ("go", true)
        case .google, .yahoo, .search: return ("search", true)
        case .join: return ("join", true)
        case .next: return ("next", false)
        case .route: return ("route", true)
        case .send: return ("send", true)
        case .done: return ("done", true)
        case .emergencyCall: return ("SOS", true)
        case .continue: return ("continue", true)
        default: return ("return", false)
        }
    }

    // MARK: KeysAreaDelegate

    func keysArea(perform action: KeyAction) {
        let proxy = textDocumentProxy
        switch action {
        case .text(let text):
            proxy.insertText(text)
            if shift == .once { shift = .off }
            if mode != .letters && text == "'" { mode = .letters }
        case .space:
            insertSpace()
            if mode == .symbols || mode == .symbols2 { mode = .letters }
        case .delete:
            proxy.deleteBackward()
        case .returnKey:
            proxy.insertText("\n")
        case .shift:
            let now = Date()
            if shift == .locked {
                shift = .off
            } else if now.timeIntervalSince(lastShiftTap) < 0.35 {
                shift = .locked
            } else {
                shift = shift == .off ? .once : .off
            }
            lastShiftTap = now
            reload()
            return
        case .mode(let target):
            mode = target
            reload()
            return
        case .globe:
            advanceToNextInputMode()
            return
        }
        afterEdit()
        reload()
    }

    func keysAreaDeleteRepeat(wordMode: Bool) {
        let proxy = textDocumentProxy
        if wordMode {
            var chars = Array(proxy.documentContextBeforeInput ?? "")
            var count = 0
            while let last = chars.last, last == " " {
                chars.removeLast()
                count += 1
            }
            while let last = chars.last, last != " ", last != "\n" {
                chars.removeLast()
                count += 1
            }
            for _ in 0..<max(count, 1) {
                proxy.deleteBackward()
            }
        } else {
            proxy.deleteBackward()
        }
        afterEdit()
        reload()
    }

    func keysAreaMoveCursor(_ offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: Layouts.isArabic ? -offset : offset)
    }

    func keysAreaFeedback(_ action: KeyAction) {
        feedback(action)
    }

    // MARK: Typing helpers

    private func feedback(_ action: KeyAction) {
        guard hasFullAccess else { return }
        haptic.impactOccurred()
        let sound: SystemSoundID
        switch action {
        case .text, .space: sound = 1104
        case .delete: sound = 1155
        default: sound = 1156
        }
        AudioServicesPlaySystemSound(sound)
    }

    /// Double-tapping space types ". " like the iOS keyboard.
    private func insertSpace() {
        let proxy = textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""
        let now = Date()
        defer { lastSpaceTap = now }
        if now.timeIntervalSince(lastSpaceTap) < 0.6, before.hasSuffix(" "), before.count >= 2 {
            let previous = before[before.index(before.endIndex, offsetBy: -2)]
            if previous.isLetter || previous.isNumber {
                proxy.deleteBackward()
                proxy.insertText(". ")
                lastSpaceTap = .distantPast
                return
            }
        }
        proxy.insertText(" ")
    }

    private func afterEdit() {
        updateAutoShift()
        updateSuggestions()
    }

    private func updateAutoShift() {
        guard mode == .letters, !Layouts.isArabic, shift != .locked else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let want: Bool
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none:
            want = false
        case .allCharacters:
            want = true
        case .words:
            want = before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n")
        default:
            if before.isEmpty || before.hasSuffix("\n") {
                want = true
            } else if before.hasSuffix(" ") {
                let trimmed = before.trimmingCharacters(in: .whitespaces)
                want = trimmed.isEmpty || [".", "!", "?"].contains(trimmed.last ?? " ")
            } else {
                want = false
            }
        }
        shift = want ? .once : .off
    }

    private func currentWord() -> String {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        var chars: [Character] = []
        for ch in before.reversed() {
            if ch.isLetter || ch == "'" { chars.append(ch) } else { break }
        }
        return String(chars.reversed())
    }

    private func updateSuggestions() {
        let word = currentWord()
        guard !word.isEmpty else {
            suggestionBar.set([])
            return
        }
        let language = Layouts.spellLanguage
        let range = NSRange(location: 0, length: (word as NSString).length)
        var candidates: [String] = []
        let misspelled = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language)
        if misspelled.location != NSNotFound {
            candidates += checker.guesses(forWordRange: range, in: word, language: language) ?? []
        }
        candidates += checker.completions(forPartialWordRange: range, in: word, language: language) ?? []

        let capitalize = word.first?.isUppercase ?? false
        var seen = Set<String>()
        var picks: [String] = []
        for candidate in candidates {
            let fixed = capitalize ? candidate.prefix(1).uppercased() + candidate.dropFirst() : candidate
            guard fixed.lowercased() != word.lowercased(), seen.insert(fixed).inserted else { continue }
            picks.append(fixed)
            if picks.count == 2 { break }
        }

        var items = [SuggestionBar.Item(title: "\u{201C}\(word)\u{201D}", value: word)]
        items += picks.map { SuggestionBar.Item(title: $0, value: $0) }
        suggestionBar.set(items)
    }

    private func applySuggestion(_ value: String) {
        let proxy = textDocumentProxy
        let word = currentWord()
        for _ in 0..<word.count {
            proxy.deleteBackward()
        }
        proxy.insertText(value + " ")
        feedback(.text(value))
        afterEdit()
        reload()
    }
}
