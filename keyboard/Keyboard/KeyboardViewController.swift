import UIKit

/// Lets the keyboard play Apple's own key click (obeys Settings > Sounds > Keyboard Clicks).
extension UIInputView: UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController, KeysAreaDelegate {
    // Must stay the first property: it stamps the moment the keyboard starts being built.
    private let launchStamp = ProcessInfo.processInfo.systemUptime
    private var reportedLaunch = false

    private let suggestionBar = SuggestionBar()
    private let keysArea = KeysArea()
    // Created the first time they are opened, to keep startup light.
    private var emojiPanel: EmojiPanel?
    private var clipboardPanel: ClipboardPanel?
    private var heightConstraint: NSLayoutConstraint?
    private var barHeightConstraint: NSLayoutConstraint?

    private enum ShiftState { case off, once, locked }

    /// Everything that changes how the keys look. The keys are only redrawn when this changes.
    private struct RenderState: Equatable {
        let mode: KeyboardMode
        let shift: ShiftState
        let dark: Bool
        let returnType: Int
        let globe: Bool
    }

    private var mode: KeyboardMode = .letters
    private var shift: ShiftState = .off
    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast
    private var theme: Theme = .light
    private var rendered: RenderState?

    // Settings of the current text field, read only when the field changes.
    private var appearanceDark = false
    private var returnType: UIReturnKeyType = .default
    private var keyboardTypeCached: UIKeyboardType = .default
    private var autocap: UITextAutocapitalizationType = .sentences

    // Our own copy of the text just before the cursor (nil = unknown, read it when needed).
    private var ctx: String?
    private var lastOwnEdit: TimeInterval = 0
    private var resyncGeneration = 0
    private var needsRefresh = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let predictor = Predictor()
    private let clipboard = ClipboardStore()
    private var clipboardTimer: Timer?

    // MARK: Metrics

    private var isLandscape: Bool { traitCollection.verticalSizeClass == .compact }
    private var barHeight: CGFloat { isLandscape ? 32 : 38 }
    private var rowPitch: CGFloat { isLandscape ? 38 : 52 }
    private var totalHeight: CGFloat { barHeight + rowPitch * 5 + 2 }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        readTraits()

        for sub in [suggestionBar, keysArea] as [UIView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sub)
        }

        let barHeight = suggestionBar.heightAnchor.constraint(equalToConstant: self.barHeight)
        barHeightConstraint = barHeight
        NSLayoutConstraint.activate([
            suggestionBar.topAnchor.constraint(equalTo: view.topAnchor),
            suggestionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHeight,
        ] + panelConstraints(keysArea))

        let height = view.heightAnchor.constraint(equalToConstant: totalHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height

        keysArea.delegate = self
        suggestionBar.onPick = { [weak self] item in self?.applySuggestion(item) }
        suggestionBar.onClipboard = { [weak self] in
            guard let self else { return }
            self.mode = self.mode == .clipboard ? .letters : .clipboard
            self.reload()
        }
        suggestionBar.onSecret = { [weak self] in self?.toggleDebug() }

        reload()
        applyDebugOverlay()
    }

    // MARK: Panels (made on first use)

    private func panelConstraints(_ panel: UIView) -> [NSLayoutConstraint] {
        [
            panel.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
    }

    private func install(_ panel: UIView) {
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(panel, aboveSubview: keysArea)
        NSLayoutConstraint.activate(panelConstraints(panel))
    }

    @discardableResult
    private func loadEmojiPanel() -> EmojiPanel {
        if let emojiPanel { return emojiPanel }
        let panel = EmojiPanel()
        panel.onPick = { [weak self] emoji in
            self?.feedback(.text(emoji))
            self?.insert(emoji)
        }
        panel.onBack = { [weak self] in
            self?.mode = .letters
            self?.reload()
        }
        panel.onDelete = { [weak self] in
            self?.feedback(.delete)
            self?.backspace()
        }
        install(panel)
        emojiPanel = panel
        return panel
    }

    @discardableResult
    private func loadClipboardPanel() -> ClipboardPanel {
        if let clipboardPanel { return clipboardPanel }
        let panel = ClipboardPanel()
        panel.store = clipboard
        panel.onPick = { [weak self] text in
            guard let self else { return }
            self.feedback(.text(text))
            self.insert(text)
            self.mode = .letters
            self.afterEdit()
            self.reload()
        }
        panel.onBack = { [weak self] in
            self?.mode = .letters
            self?.reload()
        }
        install(panel)
        clipboardPanel = panel
        return panel
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        mode = .letters
        readTraits()
        ctx = nil
        haptic.prepare()
        clipboard.refresh(hasFullAccess: hasFullAccess)
        afterEdit()
        reload()
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.clipboard.refresh(hasFullAccess: self.hasFullAccess) {
                self.updateSuggestions()
                if self.mode == .clipboard { self.clipboardPanel?.reloadData() }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !reportedLaunch {
            reportedLaunch = true
            let stamp = launchStamp
            DispatchQueue.main.async { Perf.markLaunch(since: stamp) }
        }
        Perf.startFrames()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Perf.stopFrames()
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        predictor.saveNow()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if heightConstraint?.constant != totalHeight {
            heightConstraint?.constant = totalHeight
            barHeightConstraint?.constant = barHeight
        }
        keysArea.rowPitch = rowPitch
        keysArea.showsPreviews = !isLandscape
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        reload()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Changes caused by our own typing are already handled; a short
        // pause later we double-check them once (see resync).
        if Perf.now() - lastOwnEdit < 0.4 { return }
        readTraits()
        ctx = nil
        needsRefresh = false
        afterEdit()
        reload()
    }

    // MARK: Debug overlay (hidden)

    private func toggleDebug() {
        setSpeedMeter(!Perf.enabled)
    }

    private func setSpeedMeter(_ on: Bool) {
        Perf.enabled = on
        UserDefaults.standard.set(on, forKey: "nk.debug")
        Perf.reset()
        applyDebugOverlay()
    }

    private func applyDebugOverlay() {
        guard Perf.enabled else {
            Perf.stopFrames()
            Perf.label?.isHidden = true
            return
        }
        Perf.startFrames()
        if Perf.label == nil {
            let box = UILabel()
            box.numberOfLines = 3
            box.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
            box.textColor = .white
            box.backgroundColor = UIColor.black.withAlphaComponent(0.8)
            box.isUserInteractionEnabled = false
            box.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(box)
            NSLayoutConstraint.activate([
                box.topAnchor.constraint(equalTo: view.topAnchor),
                box.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 46),
                box.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                box.heightAnchor.constraint(equalToConstant: 38),
            ])
            Perf.label = box
        }
        Perf.label?.isHidden = false
        Perf.refresh(force: true)
    }

    // MARK: Field settings and text cache

    private func readTraits() {
        let proxy = textDocumentProxy
        appearanceDark = proxy.keyboardAppearance == .dark
        returnType = proxy.returnKeyType ?? .default
        keyboardTypeCached = proxy.keyboardType ?? .default
        autocap = proxy.autocapitalizationType ?? .sentences
    }

    /// The text just before the cursor. Uses our copy; asks the text field only if we don't have one.
    private func context() -> String {
        if let ctx { return ctx }
        let real = String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(200))
        ctx = real
        return real
    }

    private func insert(_ text: String) {
        var current = context()
        textDocumentProxy.insertText(text)
        current += text
        ctx = String(current.suffix(200))
        noteOwnEdit()
    }

    private func backspace() {
        var current = context()
        textDocumentProxy.deleteBackward()
        if !current.isEmpty { current.removeLast() }
        // Too short to trust: read the real text next time.
        ctx = current.count < 3 ? nil : current
        noteOwnEdit()
    }

    private func noteOwnEdit() {
        lastOwnEdit = Perf.now()
        resyncGeneration &+= 1
        let generation = resyncGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.resyncGeneration == generation else { return }
            self.resync()
        }
    }

    /// Runs once, shortly after typing stops: compare our copy with the real text.
    private func resync() {
        readTraits()
        let real = String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(200))
        if real != ctx || needsRefresh {
            ctx = real
            needsRefresh = false
            afterEdit()
            reload()
        }
    }

    // MARK: Drawing

    /// Redraws the keys, but only if something visible actually changed.
    private func reload(force: Bool = false) {
        let dark = appearanceDark || traitCollection.userInterfaceStyle == .dark
        let state = RenderState(
            mode: mode, shift: shift, dark: dark,
            returnType: returnType.rawValue, globe: needsInputModeSwitchKey
        )
        guard force || state != rendered else { return }
        rendered = state

        theme = dark ? .dark : .light
        keysArea.theme = theme
        suggestionBar.apply(theme: theme)

        if mode == .emoji { loadEmojiPanel() }
        if mode == .clipboard { loadClipboardPanel() }
        emojiPanel?.apply(theme: theme)
        clipboardPanel?.apply(theme: theme)
        emojiPanel?.isHidden = mode != .emoji
        clipboardPanel?.isHidden = mode != .clipboard
        keysArea.isHidden = mode == .emoji || mode == .clipboard
        if mode == .clipboard, let panel = clipboardPanel {
            panel.hasFullAccess = hasFullAccess
            panel.reloadData()
        }

        let rows = Layouts.rows(mode: mode, shifted: shift != .off, showGlobe: needsInputModeSwitchKey)
        keysArea.setRows(rows)
        for key in keysArea.keyViews {
            configure(key)
        }
    }

    private func configure(_ key: KeyView) {
        switch key.spec.action {
        case .text(let text):
            key.configure(text: text, image: nil, special: false, accent: false, theme: theme, hint: key.spec.hint)
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
            case .letters, .clipboard:
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
        switch returnType {
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

    private static let wordEnders: Set<String> = [".", ",", "!", "?", ";", ":", "،", "؟", "؛"]

    func keysArea(perform action: KeyAction) {
        let started = Perf.enabled ? Perf.now() : 0
        switch action {
        case .text(let text):
            if Self.wordEnders.contains(text) { learnCurrentWord() }
            insert(text)
            Perf.countTyped()
            if shift == .once { shift = .off }
            if mode != .letters && text == "'" { mode = .letters }
        case .space:
            learnCurrentWord()
            insertSpace()
            Perf.countTyped()
            if mode == .symbols || mode == .symbols2 { mode = .letters }
        case .delete:
            backspace()
        case .returnKey:
            learnCurrentWord()
            insert("\n")
            Perf.countTyped()
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
        Perf.recordInsert()
        afterEdit()
        reload()
        Perf.recordWork(since: started)
    }

    func keysAreaDeleteRepeat(wordMode: Bool) {
        if wordMode {
            deleteWord()
        } else {
            backspace()
        }
        // Suggestions catch up once deleting pauses (see resync).
        needsRefresh = true
    }

    func keysAreaDeleteWord() {
        deleteWord()
        needsRefresh = true
    }

    func keysAreaMoveCursor(_ offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: Layouts.isArabic ? -offset : offset)
        ctx = nil
        needsRefresh = true
        noteOwnEdit()
    }

    func keysAreaFeedback(_ action: KeyAction) {
        feedback(action)
    }

    // MARK: Typing helpers

    private func feedback(_ action: KeyAction) {
        guard hasFullAccess else { return }
        haptic.impactOccurred()
        // Keep the vibration motor warmed up so the next tap is instant.
        haptic.prepare()
        UIDevice.current.playInputClick()
    }

    private func deleteWord() {
        var chars = Array(context())
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
            backspace()
        }
    }

    /// Double-tapping space types ". " like the iOS keyboard.
    private func insertSpace() {
        let before = context()
        let now = Date()
        defer { lastSpaceTap = now }
        if now.timeIntervalSince(lastSpaceTap) < 0.6, before.hasSuffix(" "), before.count >= 2 {
            let previous = before[before.index(before.endIndex, offsetBy: -2)]
            if previous.isLetter || previous.isNumber {
                backspace()
                insert(". ")
                lastSpaceTap = .distantPast
                return
            }
        }
        insert(" ")
    }

    private func afterEdit() {
        updateAutoShift()
        updateSuggestions()
    }

    private func updateAutoShift() {
        guard mode == .letters, !Layouts.isArabic, shift != .locked else { return }
        let before = context()
        let want: Bool
        switch autocap {
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

    // MARK: Words

    private static func trailingWord(of text: String) -> String {
        var chars: [Character] = []
        for ch in text.reversed() {
            if ch.isLetter || ch == "'" { chars.append(ch) } else { break }
        }
        return String(chars.reversed())
    }

    /// The word being typed, and the word before it.
    private func wordsBeforeCursor() -> (previous: String?, current: String) {
        let before = context()
        let current = Self.trailingWord(of: before)
        var rest = Substring(before).dropLast(current.count)
        while let last = rest.last, last == " " {
            rest = rest.dropLast()
        }
        let previous = Self.trailingWord(of: String(rest))
        return (previous.isEmpty ? nil : previous, current)
    }

    private var shouldLearn: Bool {
        let type = keyboardTypeCached
        return type != .URL && type != .emailAddress && type != .webSearch
    }

    private func learnCurrentWord() {
        guard shouldLearn else { return }
        let (previous, current) = wordsBeforeCursor()
        guard !current.isEmpty else { return }
        predictor.learn(current, after: previous)
    }

    /// Asks the background predictor; the bar updates when the answer comes back.
    private func updateSuggestions() {
        let (previous, word) = wordsBeforeCursor()
        let before = context()
        let atWordStart = before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n")
        let request = Predictor.Request(
            previous: previous, word: word,
            atWordStart: atWordStart, capitalize: shift == .once
        )
        predictor.suggest(request) { [weak self] words in
            self?.showSuggestions(words, typed: word)
        }
    }

    private func showSuggestions(_ words: [String], typed word: String) {
        typealias Item = SuggestionBar.Item

        if word.isEmpty {
            var items: [Item] = []
            let next = words.map { Item(title: $0, value: $0, kind: .next) }

            if let clip = clipboard.recentChip {
                let short = clip.count > 18 ? String(clip.prefix(18)) + "…" : clip
                items.append(Item(title: "📋 " + short, value: clip, kind: .paste))
                items += next.prefix(2)
            } else if next.count == 3 {
                // Best prediction in the middle, like Gboard.
                items = [next[1], next[0], next[2]]
            } else {
                items = next
            }
            suggestionBar.set(items)
            return
        }

        var items = [Item(title: "\u{201C}\(word)\u{201D}", value: word, kind: .word)]
        items += words.prefix(2).map { Item(title: $0, value: $0, kind: .word) }
        suggestionBar.set(items)
    }

    private func applySuggestion(_ item: SuggestionBar.Item) {
        let (previous, current) = wordsBeforeCursor()
        switch item.kind {
        case .paste:
            insert(item.value)
            clipboard.markChipUsed()
        case .word:
            for _ in 0..<current.count {
                backspace()
            }
            insert(item.value + " ")
            if shouldLearn { predictor.learn(item.value, after: previous) }
        case .next:
            insert(item.value + " ")
            if shouldLearn { predictor.learn(item.value, after: previous) }
        }
        feedback(.text(item.value))
        afterEdit()
        reload()
    }
}
