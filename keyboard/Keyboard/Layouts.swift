import UIKit

enum KeyboardMode: Equatable {
    case letters
    case symbols
    case symbols2
    case emoji
}

enum KeyAction: Equatable {
    case text(String)
    case shift
    case delete
    case space
    case returnKey
    case mode(KeyboardMode)
    case globe
}

struct KeySpec {
    var action: KeyAction
    var width: CGFloat = 1
    var alternates: [String] = []
}

struct KeyRow {
    var keys: [KeySpec]
    /// Width of the row in key units. nil = sum of the keys (row fills the width).
    var units: CGFloat? = nil
}

enum Layouts {
    #if ARABIC_KEYBOARD
    static let isArabic = true
    #else
    static let isArabic = false
    #endif

    static let spellLanguage = isArabic ? "ar" : "en_US"

    private static func split(_ s: String) -> [String] {
        s.split(separator: " ").map(String.init)
    }

    // MARK: Number row

    private static let arabicDigits: [String: String] = [
        "1": "١", "2": "٢", "3": "٣", "4": "٤", "5": "٥",
        "6": "٦", "7": "٧", "8": "٨", "9": "٩", "0": "٠",
    ]

    static func numberRow() -> KeyRow {
        let keys = split("1 2 3 4 5 6 7 8 9 0").map { digit -> KeySpec in
            KeySpec(action: .text(digit), alternates: arabicDigits[digit].map { [$0] } ?? [])
        }
        return KeyRow(keys: keys)
    }

    // MARK: English letters

    private static let englishAlternates: [String: [String]] = [
        "a": split("à á â ä æ ã å ā"),
        "c": split("ç ć č"),
        "e": split("è é ê ë ē ė ę"),
        "i": split("î ï í ī į ì"),
        "l": split("ł"),
        "n": split("ñ ń"),
        "o": split("ô ö ò ó œ ø ō õ"),
        "s": split("ß ś š"),
        "u": split("û ü ù ú ū"),
        "y": split("ÿ"),
        "z": split("ž ź ż"),
    ]

    private static func englishRow(_ letters: String, shifted: Bool) -> [KeySpec] {
        split(letters).map { lower -> KeySpec in
            let label = shifted ? lower.uppercased() : lower
            let alts = (englishAlternates[lower] ?? []).map { shifted ? $0.uppercased() : $0 }
            return KeySpec(action: .text(label), alternates: alts)
        }
    }

    // MARK: Arabic letters (standard iOS Arabic order, ض top-left)

    private static let arabicAlternates: [String: [String]] = [
        "ا": split("أ إ آ ء ٱ"),
        "ي": split("ئ"),
        "ى": split("ئ"),
        "و": split("ؤ"),
        "ه": split("ة"),
        "ء": split("ئ ؤ أ إ"),
        "ل": split("لا لأ لإ لآ"),
    ]

    private static func arabicRow(_ letters: String) -> [KeySpec] {
        split(letters).map { KeySpec(action: .text($0), alternates: arabicAlternates[$0] ?? []) }
    }

    // MARK: Pages

    static func rows(mode: KeyboardMode, shifted: Bool, showGlobe: Bool) -> [KeyRow] {
        var rows: [KeyRow] = [numberRow()]
        switch mode {
        case .letters, .emoji:
            if isArabic {
                rows.append(KeyRow(keys: arabicRow("ض ص ث ق ف غ ع ه خ ح ج")))
                rows.append(KeyRow(keys: arabicRow("ش س ي ب ل ا ت ن م ك ط")))
                var last = arabicRow("ذ ء ؤ ر ى ة و ز ظ د")
                last.append(KeySpec(action: .delete, width: 1))
                rows.append(KeyRow(keys: last))
            } else {
                rows.append(KeyRow(keys: englishRow("q w e r t y u i o p", shifted: shifted)))
                rows.append(KeyRow(keys: englishRow("a s d f g h j k l", shifted: shifted), units: 10))
                var last = [KeySpec(action: .shift, width: 1.5)]
                last += englishRow("z x c v b n m", shifted: shifted)
                last.append(KeySpec(action: .delete, width: 1.5))
                rows.append(KeyRow(keys: last))
            }
        case .symbols, .symbols2:
            let page2 = mode == .symbols2
            let rowA: String
            if page2 {
                rowA = "_ \\ | ~ < > € £ ¥ •"
            } else {
                rowA = isArabic ? "- / : ؛ ( ) $ & @ \"" : "- / : ; ( ) $ & @ \""
            }
            let rowB = page2 ? "` ´ ¢ ° © ® ™ § ¶ …" : "[ ] { } # % ^ * + ="
            let punctuation = isArabic ? ". ، ؟ ! '" : ". , ? ! '"
            rows.append(KeyRow(keys: split(rowA).map { KeySpec(action: .text($0)) }))
            rows.append(KeyRow(keys: split(rowB).map { KeySpec(action: .text($0)) }))
            var last = [KeySpec(action: .mode(page2 ? .symbols : .symbols2), width: 1.5)]
            last += split(punctuation).map { KeySpec(action: .text($0), width: 1.4) }
            last.append(KeySpec(action: .delete, width: 1.5))
            rows.append(KeyRow(keys: last))
        }
        rows.append(bottomRow(mode: mode, showGlobe: showGlobe))
        return rows
    }

    private static func bottomRow(mode: KeyboardMode, showGlobe: Bool) -> KeyRow {
        var keys: [KeySpec] = []
        keys.append(KeySpec(action: .mode(mode == .letters ? .symbols : .letters), width: 1.25))
        if showGlobe {
            keys.append(KeySpec(action: .globe, width: 1.25))
        }
        keys.append(KeySpec(action: .mode(.emoji), width: 1.25))
        let used = keys.reduce(CGFloat(0)) { $0 + $1.width }
        keys.append(KeySpec(action: .space, width: 10 - used - 2.5))
        keys.append(KeySpec(action: .returnKey, width: 2.5))
        return KeyRow(keys: keys, units: 10)
    }
}
