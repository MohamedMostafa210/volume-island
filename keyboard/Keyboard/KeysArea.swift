import UIKit

protocol KeysAreaDelegate: AnyObject {
    func keysArea(perform action: KeyAction)
    func keysAreaDeleteRepeat(wordMode: Bool)
    func keysAreaMoveCursor(_ offset: Int)
    func keysAreaFeedback(_ action: KeyAction)
}

/// Lays out the keys and handles all touches (multi-touch, rollover,
/// long-press alternates, delete repeat and space-bar cursor control).
final class KeysArea: UIView {
    weak var delegate: KeysAreaDelegate?

    var rowPitch: CGFloat = 54 { didSet { setNeedsLayout() } }
    var theme: Theme = .light
    var showsPreviews = true

    private(set) var keyViews: [KeyView] = []
    private var rows: [KeyRow] = []
    private var rowViews: [[KeyView]] = []
    private let hGap: CGFloat = 6
    private let sidePad: CGFloat = 3

    private let preview = KeyPreviewView()
    private let alternates = AlternatesView()

    private enum TouchMode { case normal, alternates, trackpad }

    private final class TouchState {
        var key: KeyView
        var mode: TouchMode = .normal
        var committed = false
        var lastX: CGFloat
        var longPress: Timer?
        var repeatTimer: Timer?
        var repeatCount = 0

        init(key: KeyView, x: CGFloat) {
            self.key = key
            self.lastX = x
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
        let keyHeight = rowPitch - 11
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
            let hitFrame = key.frame.insetBy(dx: -hGap / 2, dy: -6)
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

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // Rollover: a new finger commits any letter still held down.
            let pending = states.values.filter { $0.mode == .normal && !$0.committed && $0.key.isCharacter }
            for state in pending {
                state.committed = true
                state.stopTimers()
                state.key.isPressed = false
            }
            if !pending.isEmpty { preview.hide() }
            for state in pending {
                delegate?.keysArea(perform: state.key.spec.action)
            }

            let point = touch.location(in: self)
            guard let key = keyAt(point) else { continue }
            let state = TouchState(key: key, x: point.x)
            states[ObjectIdentifier(touch)] = state
            press(state)
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
                guard let self, let state else { return }
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
                guard let self, let state else { return }
                state.mode = .trackpad
                state.committed = true
                self.keyViews.forEach { $0.alpha = 0.35 }
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

    private func scheduleAlternates(_ state: TouchState) {
        state.longPress?.invalidate()
        guard let text = state.key.characterText, !state.key.spec.alternates.isEmpty else { return }
        state.longPress = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self, weak state] _ in
            guard let self, let state else { return }
            state.mode = .alternates
            self.preview.hide()
            self.alternates.show(options: [text] + state.key.spec.alternates, over: state.key.frame, in: self.bounds, theme: self.theme)
            self.bringSubviewToFront(self.alternates)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let state = states[ObjectIdentifier(touch)] else { continue }
            let point = touch.location(in: self)
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
            case .normal:
                guard state.key.isCharacter, !state.committed,
                      let newKey = keyAt(point), newKey !== state.key, newKey.isCharacter else { continue }
                state.key.isPressed = false
                state.key = newKey
                newKey.isPressed = true
                if showsPreviews, let text = newKey.characterText {
                    preview.show(text: text, over: newKey.frame, in: bounds, theme: theme)
                    bringSubviewToFront(preview)
                }
                scheduleAlternates(state)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let state = states.removeValue(forKey: id) else { continue }
            let action = state.key.spec.action
            let mode = state.mode
            let alreadyCommitted = state.committed
            let chosen = alternates.selected
            finish(state)

            switch mode {
            case .alternates:
                if let chosen { delegate?.keysArea(perform: .text(chosen)) }
            case .trackpad:
                break
            case .normal:
                if !alreadyCommitted { delegate?.keysArea(perform: action) }
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let state = states.removeValue(forKey: ObjectIdentifier(touch)) {
                finish(state)
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
