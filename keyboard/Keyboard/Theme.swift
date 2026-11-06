import UIKit

/// Colours measured from Apple's iOS 27 keyboard screenshots (dark mode).
/// Light mode is not measured yet: it follows Apple's usual light style.
struct Theme {
    let letterKey: UIColor
    /// Apple now draws shift, delete, 123 and return in the same colour as letters.
    let specialKey: UIColor
    let pressedKey: UIColor
    let text: UIColor
    /// Prediction words (Apple shows them slightly dimmed).
    let suggestionText: UIColor
    /// Small marks: symbol hints, the language letter on the space bar.
    let faintText: UIColor
    let shadow: UIColor
    let suggestionDivider: UIColor
    let emojiSelection: UIColor
    /// Thin shadow under each key (light mode only; Apple's dark keys have none).
    let keyShadowOpacity: Float

    static let light = Theme(
        letterKey: .white,
        specialKey: .white,
        pressedKey: UIColor(white: 0.76, alpha: 1),
        text: .black,
        suggestionText: UIColor(white: 0, alpha: 0.7),
        faintText: UIColor(white: 0, alpha: 0.45),
        shadow: UIColor(white: 0, alpha: 1),
        suggestionDivider: UIColor(white: 0, alpha: 0.1),
        emojiSelection: UIColor(white: 0, alpha: 0.1),
        keyShadowOpacity: 0.25
    )

    static let dark = Theme(
        letterKey: UIColor(white: 69.0 / 255.0, alpha: 1),
        specialKey: UIColor(white: 69.0 / 255.0, alpha: 1),
        pressedKey: UIColor(white: 0.42, alpha: 1),
        text: .white,
        suggestionText: UIColor(white: 1, alpha: 0.68),
        faintText: UIColor(white: 1, alpha: 0.48),
        shadow: UIColor(white: 0, alpha: 1),
        suggestionDivider: UIColor(white: 1, alpha: 0.09),
        emojiSelection: UIColor(white: 1, alpha: 0.11),
        keyShadowOpacity: 0
    )
}
