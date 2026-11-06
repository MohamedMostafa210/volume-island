import UIKit

/// Magnified letter shown above a key while it is pressed.
final class KeyPreviewView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 2
        layer.shadowOpacity = 0.3
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 32, weight: .regular)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(text: String, over key: CGRect, in bounds: CGRect, theme: Theme) {
        let width = key.width + 16
        let height = key.height * 2 + 6
        var x = key.midX - width / 2
        x = min(max(x, 0), bounds.width - width)
        frame = CGRect(x: x, y: key.maxY - height, width: width, height: height)
        label.frame = CGRect(x: 2, y: 0, width: width - 4, height: key.height + 6)
        label.text = text
        label.textColor = theme.text
        backgroundColor = theme.letterKey
        layer.shadowColor = theme.shadow.cgColor
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}

/// Row of accented / alternate characters shown on long-press.
final class AlternatesView: UIView {
    private var labels: [UILabel] = []
    private var options: [String] = []
    private var cellWidth: CGFloat = 34
    private var theme: Theme = .light
    private(set) var selectedIndex = 0

    var selected: String? {
        options.indices.contains(selectedIndex) ? options[selectedIndex] : nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 3
        layer.shadowOpacity = 0.35
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(options: [String], over key: CGRect, in bounds: CGRect, theme: Theme) {
        self.options = options
        self.theme = theme
        labels.forEach { $0.removeFromSuperview() }
        cellWidth = max(key.width, 34)
        let width = cellWidth * CGFloat(options.count) + 8
        let height = key.height + 8
        var x = key.minX - 4
        x = min(max(x, 0), max(bounds.width - width, 0))
        frame = CGRect(x: x, y: key.minY - height + 4 - key.height * 0.15, width: width, height: height)
        backgroundColor = theme.letterKey
        layer.shadowColor = theme.shadow.cgColor

        labels = options.enumerated().map { index, option in
            let label = UILabel(frame: CGRect(x: 4 + CGFloat(index) * cellWidth, y: 4, width: cellWidth, height: key.height))
            label.text = option
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 24)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
            label.layer.cornerRadius = 7
            label.clipsToBounds = true
            addSubview(label)
            return label
        }
        selectedIndex = 0
        refresh()
        isHidden = false
    }

    func select(atX x: CGFloat) {
        guard !options.isEmpty else { return }
        let index = Int((x - frame.minX - 4) / cellWidth)
        let clamped = min(max(index, 0), options.count - 1)
        if clamped != selectedIndex {
            selectedIndex = clamped
            refresh()
        }
    }

    private func refresh() {
        for (index, label) in labels.enumerated() {
            let isSelected = index == selectedIndex
            label.backgroundColor = isSelected ? .systemBlue : .clear
            label.textColor = isSelected ? .white : theme.text
        }
    }

    func hide() {
        isHidden = true
        options = []
    }
}
