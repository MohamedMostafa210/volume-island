import UIKit

final class KeyView: UIView {
    var spec: KeySpec
    private let label = UILabel()
    private let icon = UIImageView()
    private var baseColor: UIColor = .white
    private var pressedColor: UIColor = .lightGray

    var isPressed = false {
        didSet { backgroundColor = isPressed ? pressedColor : baseColor }
    }

    var isCharacter: Bool {
        if case .text = spec.action { return true }
        return false
    }

    var characterText: String? {
        if case .text(let s) = spec.action { return s }
        return nil
    }

    init(spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = 8.5
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 0.35
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.baselineAdjustment = .alignCenters
        icon.contentMode = .center
        addSubview(label)
        addSubview(icon)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 3, dy: 0)
        icon.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    func configure(text: String?, image: String?, special: Bool, accent: Bool, theme: Theme) {
        label.text = text
        label.isHidden = text == nil
        if isCharacter {
            label.font = .systemFont(ofSize: Layouts.isArabic ? 21 : 23, weight: .regular)
        } else {
            label.font = .systemFont(ofSize: 16, weight: .regular)
        }

        if let image {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            icon.image = UIImage(systemName: image, withConfiguration: config)
            icon.isHidden = false
        } else {
            icon.image = nil
            icon.isHidden = true
        }

        let textColor: UIColor
        if accent {
            baseColor = .systemBlue
            pressedColor = theme.specialKey
            textColor = .white
        } else if special {
            baseColor = theme.specialKey
            pressedColor = theme.letterKey
            textColor = theme.text
        } else {
            baseColor = theme.letterKey
            pressedColor = theme.specialKey
            textColor = theme.text
        }
        label.textColor = textColor
        icon.tintColor = textColor
        layer.shadowColor = theme.shadow.cgColor
        backgroundColor = isPressed ? pressedColor : baseColor
    }
}
