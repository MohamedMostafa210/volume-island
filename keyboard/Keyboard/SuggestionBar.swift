import UIKit

/// Top bar: small clipboard button + three prediction slots (best one in the middle),
/// styled like Apple's: plain words, thin dividers between the slots.
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

    private let clipButton = UIButton(type: .custom)
    private var buttons: [UIButton] = []
    private var dividers: [UIView] = []
    private var items: [Item?] = [nil, nil, nil]
    private var theme: Theme = .light
    private let clipWidth: CGFloat = 34
    private let font = UIFont.systemFont(ofSize: 18, weight: .regular)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        clipButton.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
        clipButton.addTarget(self, action: #selector(clipTapped), for: .touchUpInside)
        addSubview(clipButton)

        for index in 0..<3 {
            let button = UIButton(type: .custom)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.titleLabel?.font = font
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
            button.tag = index
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            addSubview(button)
            buttons.append(button)
        }
        for _ in 0..<2 {
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
        let start = clipWidth + 2
        let width = (bounds.width - start) / 3
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: start + CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
        // Apple: about 24 pt tall, centred, one hairline wide.
        let hairline = 1 / max(traitCollection.displayScale, 1)
        let lineHeight = min(24, bounds.height * 0.52)
        for (index, divider) in dividers.enumerated() {
            divider.frame = CGRect(
                x: start + CGFloat(index + 1) * width, y: (bounds.height - lineHeight) / 2,
                width: hairline, height: lineHeight
            )
        }
    }

    func apply(theme: Theme) {
        self.theme = theme
        clipButton.tintColor = theme.faintText
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
            button.setTitleColor(theme.suggestionText, for: .normal)
            button.setTitle(item?.title, for: .normal)
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        guard sender.tag < items.count, let item = items[sender.tag] else { return }
        onPick?(item)
    }

    @objc private func clipTapped() {
        onClipboard?()
    }
}
