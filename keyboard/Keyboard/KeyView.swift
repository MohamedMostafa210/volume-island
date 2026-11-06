import UIKit

/// One key, drawn like Apple's: flat rounded key, no shadow.
final class KeyView: UIView {
    var spec: KeySpec
    private let label = UILabel()
    private let icon = UIImageView()
    private let hintLabel = UILabel()
    private var hintAtBottom = false
    private var baseColor: UIColor = .white
    private var pressedColor: UIColor = .lightGray

    var isPressed = false {
        didSet {
            if isPressed != oldValue { backgroundColor = isPressed ? pressedColor : baseColor }
        }
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
        layer.cornerCurve = .continuous
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 0
        label.textAlignment = .center
        label.baselineAdjustment = .alignCenters
        icon.contentMode = .center
        hintLabel.textAlignment = .right
        addSubview(label)
        addSubview(icon)
        addSubview(hintLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 3, dy: 0)
        icon.frame = bounds
        if layer.shadowOpacity > 0 {
            // A fixed shadow outline keeps the shadow cheap to draw.
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
        }
        if hintAtBottom {
            hintLabel.frame = CGRect(x: bounds.width - 20, y: bounds.height - 17, width: 14, height: 14)
        } else {
            hintLabel.frame = CGRect(x: bounds.width - 16, y: 2, width: 13, height: 12)
        }
    }

    /// - hint: small symbol in the top-right corner (Gboard style).
    /// - marker: small letter in the bottom-right corner (Apple's space bar language mark).
    func configure(
        text: String?, image: String?, special: Bool, accent: Bool, theme: Theme,
        hint: String? = nil, marker: String? = nil, iconSize: CGFloat = 18
    ) {
        let corner = marker ?? hint
        hintAtBottom = marker != nil
        hintLabel.text = corner
        hintLabel.isHidden = corner == nil
        hintLabel.textColor = theme.faintText
        hintLabel.font = marker != nil
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 10, weight: .medium)

        label.text = text
        label.isHidden = text == nil
        label.adjustsFontSizeToFitWidth = !isCharacter
        label.minimumScaleFactor = 0.6
        if isCharacter {
            label.font = .systemFont(ofSize: Layouts.isArabic ? 21 : 23.5, weight: .regular)
        } else if text == "#+=" {
            label.font = .systemFont(ofSize: 15, weight: .regular)
        } else if (text?.count ?? 0) <= 3 {
            label.font = .systemFont(ofSize: 18, weight: .regular)
        } else {
            label.font = .systemFont(ofSize: 16, weight: .regular)
        }

        if let image {
            let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
            icon.image = UIImage(systemName: image, withConfiguration: config)
            icon.isHidden = false
        } else {
            icon.image = nil
            icon.isHidden = true
        }

        let textColor: UIColor
        if accent {
            baseColor = .systemBlue
            pressedColor = theme.pressedKey
            textColor = .white
        } else if special {
            baseColor = theme.specialKey
            pressedColor = theme.pressedKey
            textColor = theme.text
        } else {
            baseColor = theme.letterKey
            pressedColor = theme.pressedKey
            textColor = theme.text
        }
        label.textColor = textColor
        icon.tintColor = textColor
        layer.shadowColor = theme.shadow.cgColor
        layer.shadowOpacity = theme.keyShadowOpacity
        backgroundColor = isPressed ? pressedColor : baseColor
        setNeedsLayout()
    }
}
