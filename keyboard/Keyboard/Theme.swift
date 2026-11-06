import UIKit

struct Theme {
    let letterKey: UIColor
    let specialKey: UIColor
    let text: UIColor
    let shadow: UIColor
    let suggestionDivider: UIColor

    static let light = Theme(
        letterKey: .white,
        specialKey: UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1),
        text: .black,
        shadow: UIColor(red: 0.54, green: 0.54, blue: 0.55, alpha: 1),
        suggestionDivider: UIColor(white: 0, alpha: 0.15)
    )

    static let dark = Theme(
        letterKey: UIColor(white: 0.42, alpha: 1),
        specialKey: UIColor(white: 0.27, alpha: 1),
        text: .white,
        shadow: UIColor(white: 0, alpha: 1),
        suggestionDivider: UIColor(white: 1, alpha: 0.2)
    )
}
