import UIKit

/// The three-slot prediction bar above the keys.
final class SuggestionBar: UIView {
    struct Item {
        let title: String
        let value: String
    }

    var onPick: ((String) -> Void)?

    private var buttons: [UIButton] = []
    private var dividers: [UIView] = []
    private var items: [Item] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        for index in 0..<3 {
            let button = UIButton(type: .custom)
            button.titleLabel?.font = .systemFont(ofSize: 17)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
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
        let width = bounds.width / 3
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
        for (index, divider) in dividers.enumerated() {
            divider.frame = CGRect(x: CGFloat(index + 1) * width, y: bounds.height * 0.25, width: 1, height: bounds.height * 0.5)
        }
    }

    func apply(theme: Theme) {
        buttons.forEach { $0.setTitleColor(theme.text, for: .normal) }
        dividers.forEach { $0.backgroundColor = theme.suggestionDivider }
    }

    func set(_ newItems: [Item]) {
        items = newItems
        for (index, button) in buttons.enumerated() {
            button.setTitle(index < items.count ? items[index].title : nil, for: .normal)
            button.isEnabled = index < items.count
        }
        for (index, divider) in dividers.enumerated() {
            divider.isHidden = items.count < index + 2
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        guard sender.tag < items.count else { return }
        onPick?(items[sender.tag].value)
    }
}
