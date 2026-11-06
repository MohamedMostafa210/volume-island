import UIKit

/// Keyboard settings, saved inside this keyboard (English and Arabic each keep their own).
enum KeyboardSettings {
    private static let defaults = UserDefaults.standard

    static var numberRow: Bool {
        get { defaults.object(forKey: "nk.numberRow") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "nk.numberRow") }
    }

    static var hints: Bool {
        get { defaults.object(forKey: "nk.hints") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "nk.hints") }
    }
}

/// Small settings page, opened by holding the emoji key. Shown in place of the keys.
final class SettingsPanel: UIView {
    enum Option: Int, CaseIterable {
        case numberRow, hints, speedMeter

        var title: String {
            switch self {
            case .numberRow: return "Number row"
            case .hints: return "Symbol hints on keys"
            case .speedMeter: return "Speed meter"
            }
        }
    }

    var onToggle: ((Option, Bool) -> Void)?
    var onDone: (() -> Void)?

    private var labels: [UILabel] = []
    private var switches: [UISwitch] = []
    private let doneButton = UIButton(type: .custom)
    private let barHeight: CGFloat = 40

    override init(frame: CGRect) {
        super.init(frame: frame)
        for option in Option.allCases {
            let label = UILabel()
            label.text = option.title
            label.font = .systemFont(ofSize: 16)
            addSubview(label)
            labels.append(label)

            let toggle = UISwitch()
            toggle.tag = option.rawValue
            toggle.addTarget(self, action: #selector(changed(_:)), for: .valueChanged)
            addSubview(toggle)
            switches.append(toggle)
        }
        doneButton.setTitle(Layouts.isArabic ? "أبج" : "ABC", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 16)
        doneButton.layer.cornerRadius = 8.5
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
        addSubview(doneButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func set(_ option: Option, on: Bool) {
        switches[option.rawValue].isOn = on
    }

    func apply(theme: Theme) {
        labels.forEach { $0.textColor = theme.text }
        doneButton.backgroundColor = theme.specialKey
        doneButton.setTitleColor(theme.text, for: .normal)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let listHeight = bounds.height - barHeight
        let rowHeight = min(44, max(listHeight - 8, 0) / CGFloat(Option.allCases.count))
        for (index, label) in labels.enumerated() {
            let y = 4 + CGFloat(index) * rowHeight
            let toggle = switches[index]
            let size = toggle.intrinsicContentSize
            toggle.frame = CGRect(
                x: bounds.width - size.width - 16, y: y + (rowHeight - size.height) / 2,
                width: size.width, height: size.height
            )
            label.frame = CGRect(x: 16, y: y, width: toggle.frame.minX - 24, height: rowHeight)
        }
        doneButton.frame = CGRect(x: 6, y: listHeight + 2, width: 60, height: barHeight - 6)
    }

    @objc private func changed(_ sender: UISwitch) {
        guard let option = Option(rawValue: sender.tag) else { return }
        onToggle?(option, sender.isOn)
    }

    @objc private func done() {
        onDone?()
    }
}
