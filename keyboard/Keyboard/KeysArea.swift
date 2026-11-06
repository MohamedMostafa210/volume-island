import UIKit

protocol KeysAreaDelegate: AnyObject {
    func keysArea(perform action: KeyAction)
    func keysAreaDeleteRepeat(wordMode: Bool)
    func keysAreaDeleteWord()
    func keysAreaMoveCursor(_ offset: Int)
    func keysAreaFeedback(_ action: KeyAction)
}

/// Lays out the keys and handles all touches: multi-touch, rollover,
/// long-press symbols, delete repeat, swipe-left-to-delete-words and
/// space-bar cursor control (swipe or long-press).
final class KeysArea: UIView {
    weak var delegate: KeysAreaDelegate?

    var rowPitch: CGFloat = 52 {
        didSet { if rowPitch != oldValue { setNeedsLayout() } }
    }
    var theme: Theme = .light
    var showsPreviews = true

    private(set) var keyViews: [KeyView] = []
    private var rows: [KeyRow] = []
    private var rowViews: [[KeyView]] = []
    private let hGap: CGFloat = 6
    private let sidePad: CGFloat = 3
    /// Taps this far above the top row still count as the top row.
    private let topReach: CGFloat = 8
    /// How long to hold a letter before its symbol menu opens.
    private let alternatesDelay: TimeInterval = 0.45

    private let preview = KeyPreviewView()
    private let alternates = AlternatesView()

    private enum TouchMode { case normal, alternates, trackpad, swipeDelete }

    private final class TouchState {
        var key: KeyView
        var mode: TouchMode = .normal
        var committed = false
        let startX: CGFloat
        var lastX: CGFloat
        let startTime: TimeInterval
        /// Where the finger was when it arrived on the current key.
        var keyStart: CGPoint
        /// Where the finger is now.
        var point: CGPoint
        var longPress: Timer?
        var repeatTimer: Timer?
        var repeatCount = 0

        init(key: KeyView, point: CGPoint, time: TimeInterval) {
            self.key = key
            self.startX = point.x
            self.lastX = point.x
            self.startTime = time
            self.keyStart = point
            self.point = point
        }

        func stopTimers() {
            longPress?.invalidate()
            repeatTimer?.invalidate()
            longPress = nil
            repeatTimer = nil
        }
    }

    private var states: [ObjectIdentifier: TouchState] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        clipsToBounds = false
        addSubview(preview)
        addSubview(alternates)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Accept touches slightly above the top row, so near-misses are not lost.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        point.x >= bounds.minX && point.x <= bounds.maxX
            && point.y >= bounds.minY - topReach && point.y <= bounds.maxY
    }

    // MARK: Rows

    func setRows(_ newRows: [KeyRow]) {
        let sameShape = newRows.count == rows.count
            && zip(newRows, rows).allSatisfy { $0.keys.count == $1.keys.count }
        if sameShape {
            for (r, row) in newRows.enumerated() {
                for (i, spec) in row.keys.enumerated() {
                    rowViews[r][i].spec = spec
                }
            }
            rows = newRows
        } else {
            cancelAllTouches()
            keyViews.forEach { $0.removeFromSuperview() }
            rows = newRows
            rowViews = newRows.map { row in row.keys.map { KeyView(spec: $0) } }
            keyViews = rowViews.flatMap { $0 }
            for key in keyViews {
                insertSubview(key, belowSubview: preview)
            }
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let keyHeight = rowPitch - 10
        let width = bounds.width - sidePad * 2
        for (r, row) in rows.enumerated() {
            let used = row.keys.reduce(CGFloat(0)) { $0 + $1.width }
            let total = row.units ?? used
            guard total > 0 else { continue }
            let unit = width / total
            var x = sidePad + (width - used * unit) / 2
            let y = CGFloat(r) * rowPitch + (rowPitch - keyHeight) / 2
            for (i, spec) in row.keys.enumerated() {
                let w = spec.width * unit
                rowViews[r][i].frame = CGRect(x: x + hGap / 2, y: y, width: w - hGap, height: keyHeight)
                x += w
            }
        }
    }

    private func keyAt(_ point: CGPoint) -> KeyView? {
        var best: KeyView?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for key in keyViews {
            let hitFrame = key.frame.insetBy(dx: -hGap / 2, dy: -5)
            if hitFrame.contains(point) { return key }
            let dx = max(key.frame.minX - point.x, 0, point.x - key.frame.maxX)
            let dy = max(key.frame.minY - point.y, 0, point.y - key.frame.maxY)
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = key
            }
        }
        return best
    }

    /// Keys that type something when you let go (letters, space, return).
    private static func typesOnLift(_ action: KeyAction) -> Bool {
        switch action {
        case .text, .space, .returnKey: return true
        default: return false
        }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let began = Perf.enabled ? Perf.now() : 0
        for touch in touches {
            Perf.eventTime = touch.timestamp
            commitHeldKeys()

            let point = touch.location(in: self)
            guard let key = keyAt(point) else { continue }
            let state = TouchState(key: key, point: point, time: touch.timestamp)
            states[ObjectIdentifier(touch)] = state
            if Self.typesOnLift(key.spec.action) { Perf.countTap() }
            press(state)
            Perf.recordDown(eventTime: touch.timestamp, handlerStart: began)
        }
    }

    /// Rollover: a new finger types every key still held down (oldest first),
    /// like Apple's keyboard. Covers letters, space and return.
    private func commitHeldKeys() {
        let held = states.values
            .filter { $0.mode == .normal && !$0.committed && Self.typesOnLift($0.key.spec.action) }
            .sorted { $0.startTime < $1.startTime }
        guard !held.isEmpty else { return }
        // Read the actions first: typing the first one can change shift and relabel the keys.
        let actions = held.map { $0.key.spec.action }
        for state in held {
            state.committed = true
            state.stopTimers()
            state.key.isPressed = false
        }
        preview.hide()
        for action in actions {
            delegate?.keysArea(perform: action)
        }
    }

    private func press(_ state: TouchState) {
        let key = state.key
        key.isPressed = true
        delegate?.keysAreaFeedback(key.spec.action)

        switch key.spec.action {
        case .delete:
            state.committed = true
            delegate?.keysArea(perform: .delete)
            state.longPress = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self, weak state] _ in
                guard let self, let state, state.mode == .normal else { return }
                state.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self, weak state] _ in
                    guard let self, let state else { return }
                    state.repeatCount += 1
                    self.delegate?.keysAreaDeleteRepeat(wordMode: state.repeatCount > 20)
                }
            }
        case .shift:
            state.committed = true
            delegate?.keysArea(perform: .shift)
        case .space:
            state.longPress = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self, weak state] _ in
                guard let self, let state, state.mode == .normal, !state.committed else { return }
                self.startTrackpad(state)
            }
        case .text(let text):
            if showsPreviews {
                preview.show(text: text, over: key.frame, in: bounds, theme: theme)
                bringSubviewToFront(preview)
            }
            scheduleAlternates(state)
        default:
            break
        }
    }

    private func startTrackpad(_ state: TouchState) {
        state.longPress?.invalidate()
        state.longPress = nil
        state.mode = .trackpad
        state.committed = true
        Perf.uncountTap()
        keyViews.forEach { $0.alpha = 0.35 }
    }

    private func scheduleAlternates(_ state: TouchState) {
        state.longPress?.invalidate()
        state.longPress = nil
        state.keyStart = state.point
        guard !state.key.spec.alternates.isEmpty else { return }
        state.longPress = Timer.scheduledTimer(withTimeInterval: alternatesDelay, repeats: false) { [weak self, weak state] _ in
            guard let self, let state, state.mode == .normal, !state.committed else { return }
            // Only open the menu if the finger stayed still (not mid-typing).
            let dx = state.point.x - state.keyStart.x
            let dy = state.point.y - state.keyStart.y
            guard dx * dx + dy * dy <= 144 else { return }
            state.mode = .alternates
            self.preview.hide()
            self.delegate?.keysAreaFeedback(.shift)
            self.alternates.show(options: state.key.spec.alternates, over: state.key.frame, in: self.bounds, theme: self.theme)
            self.bringSubviewToFront(self.alternates)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let state = states[ObjectIdentifier(touch)] else { continue }
            let point = touch.location(in: self)
            state.point = point
            switch state.mode {
            case .alternates:
                alternates.select(atX: point.x)

            case .trackpad:
                let step: CGFloat = 9
                let moved = Int((point.x - state.lastX) / step)
                if moved != 0 {
                    delegate?.keysAreaMoveCursor(moved)
                    state.lastX += CGFloat(moved) * step
                }

            case .swipeDelete:
                let step: CGFloat = 30
                let moved = Int((state.lastX - point.x) / step)
                if moved > 0 {
                    for _ in 0..<moved { delegate?.keysAreaDeleteWord() }
                    state.lastX -= CGFloat(moved) * step
                }

            case .normal:
                switch state.key.spec.action {
                case .space:
                    // Swipe on space moves the cursor straight away.
                    // (Not if the space was already typed by a following key.)
                    if !state.committed, abs(point.x - state.startX) > 12 {
                        startTrackpad(state)
                        state.lastX = point.x
                    }
                case .delete:
                    // Swipe left from delete erases whole words.
                    if state.startX - point.x > 24 {
                        state.stopTimers()
                        state.mode = .swipeDelete
                        state.lastX = point.x
                        delegate?.keysAreaDeleteWord()
                    }
                case .text:
                    guard !state.committed, let newKey = keyAt(point),
                          newKey !== state.key, newKey.isCharacter else { continue }
                    state.key.isPressed = false
                    state.key = newKey
                    newKey.isPressed = true
                    if showsPreviews, let text = newKey.characterText {
                        preview.show(text: text, over: newKey.frame, in: bounds, theme: theme)
                        bringSubviewToFront(preview)
                    }
                    scheduleAlternates(state)
                default:
                    break
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let state = states.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            Perf.eventTime = touch.timestamp
            let action = state.key.spec.action
            let mode = state.mode
            let alreadyCommitted = state.committed
            let chosen = alternates.selected
            finish(state)

            switch mode {
            case .alternates:
                if let chosen { delegate?.keysArea(perform: .text(chosen)) }
            case .trackpad, .swipeDelete:
                break
            case .normal:
                if !alreadyCommitted { delegate?.keysArea(perform: action) }
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let state = states.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            let action = state.key.spec.action
            // iOS sometimes cancels a quick tap (for example when it thinks a
            // screen-edge swipe started). Apple's keyboard still types it, so we do too.
            let shouldType = state.mode == .normal && !state.committed
                && Self.typesOnLift(action) && touch.timestamp - state.startTime < 0.5
            finish(state)
            if shouldType {
                Perf.eventTime = touch.timestamp
                delegate?.keysArea(perform: action)
            }
        }
    }

    private func finish(_ state: TouchState) {
        state.stopTimers()
        state.key.isPressed = false
        if state.mode == .trackpad {
            keyViews.forEach { $0.alpha = 1 }
        }
        if state.mode == .alternates {
            alternates.hide()
        }
        if states.isEmpty {
            preview.hide()
        }
    }

    func cancelAllTouches() {
        for state in states.values {
            state.stopTimers()
            state.key.isPressed = false
        }
        states.removeAll()
        preview.hide()
        alternates.hide()
        keyViews.forEach { $0.alpha = 1 }
    }
}
