import UIKit

/// Top bar: clipboard button + three prediction slots (best one in the middle).
final class SuggestionBar: UIView {
    struct Item {
        enum Kind {
            case word   // replaces the word being typed
            case next   // next-word prediction, inserted after a space
            case paste  // recent clipboard text
        }
        let title: String
        let value: String
        let kind: Kind
    }

    var onPick: ((Item) -> Void)?
    var onClipboard: (() -> Void)?
    var onSecret: (() -> Void)?

    private let clipButton = UIButton(type: .custom)
    private var buttons: [UIButton] = []
    private var dividers: [UIView] = []
    private var items: [Item?] = [nil, nil, nil]
    private var theme: Theme = .light
    private let clipWidth: CGFloat = 40

    override init(frame: CGRect) {
        super.init(frame: frame)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        clipButton.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
        clipButton.addTarget(self, action: #selector(clipTapped), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(secretHold(_:)))
        hold.minimumPressDuration = 1.2
        clipButton.addGestureRecognizer(hold)
        addSubview(clipButton)

        for index in 0..<3 {
            let button = UIButton(type: .custom)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
            button.tag = index
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            addSubview(button)
            buttons.append(button)
        }
        for _ in 0..<3 {
            let divider = UIView()
            addSubview(divider)
            dividers.append(divider)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clipButton.frame = CGRect(x: 2, y: 0, width: clipWidth, height: bounds.height)
        let width = (bounds.width - clipWidth - 4) / 3
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: clipWidth + 2 + CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
        for (index, divider) in dividers.enumerated() {
            divider.frame = CGRect(x: clipWidth + 2 + CGFloat(index) * width, y: bounds.height * 0.28, width: 1, height: bounds.height * 0.44)
        }
    }

    func apply(theme: Theme) {
        self.theme = theme
        clipButton.tintColor = theme.text.withAlphaComponent(0.7)
        dividers.forEach { $0.backgroundColor = theme.suggestionDivider }
        render()
    }

    /// Up to three items. With 2-3 items the best one (index 1) sits in the middle.
    func set(_ newItems: [Item]) {
        items = [nil, nil, nil]
        for (index, item) in newItems.prefix(3).enumerated() {
            items[index] = item
        }
        render()
    }

    private func render() {
        for (index, button) in buttons.enumerated() {
            let item = items[index]
            button.isEnabled = item != nil
            let font: UIFont = index == 1
                ? .systemFont(ofSize: 17, weight: .semibold)
                : .systemFont(ofSize: 17, weight: .regular)
            button.titleLabel?.font = font
            button.setTitleColor(theme.text, for: .normal)
            button.setTitle(item?.title, for: .normal)
        }
        dividers[0].isHidden = false
        dividers[1].isHidden = items[0] == nil || items[1] == nil
        dividers[2].isHidden = items[1] == nil || items[2] == nil
    }

    @objc private func tapped(_ sender: UIButton) {
        guard sender.tag < items.count, let item = items[sender.tag] else { return }
        onPick?(item)
    }

    @objc private func secretHold(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { onSecret?() }
    }

    @objc private func clipTapped() {
        onClipboard?()
    }
}
