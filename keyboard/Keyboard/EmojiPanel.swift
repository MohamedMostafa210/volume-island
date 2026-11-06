import UIKit

/// Emoji keyboard laid out like Apple's: a sideways-scrolling grid, and a bottom bar
/// with ABC, category icons (tap to jump) and delete.
final class EmojiPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onPick: ((String) -> Void)?
    var onBack: (() -> Void)?
    var onDelete: (() -> Void)?

    private let collection: UICollectionView
    private let layout = UICollectionViewFlowLayout()
    private let backButton = UIButton(type: .custom)
    private let deleteButton = UIButton(type: .custom)
    private let selection = UIView()
    private var categoryButtons: [UIButton] = []
    private var selectedCategory = 0
    private var theme: Theme = .light
    private let barHeight: CGFloat = 44
    private let defaults = UserDefaults.standard
    private let recentsKey = "nk.emoji.recent"
    private let maxRecents = 32

    /// Section 0 is "recently used"; the rest come from `EmojiCatalog`.
    private var sections: [[String]] = []

    override init(frame: CGRect) {
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)

        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "cell")
        addSubview(collection)

        backButton.setTitle(Layouts.isArabic ? "أبج" : "ABC", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 18)
        backButton.addTarget(self, action: #selector(back), for: .touchUpInside)
        addSubview(backButton)

        selection.isUserInteractionEnabled = false
        addSubview(selection)

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        for (index, category) in EmojiCatalog.categories.enumerated() {
            let button = UIButton(type: .custom)
            button.setImage(UIImage(systemName: category.icon, withConfiguration: iconConfig), for: .normal)
            button.tag = index
            button.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            addSubview(button)
            categoryButtons.append(button)
        }

        let deleteConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: deleteConfig), for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        addSubview(deleteButton)

        sections = [loadRecents()] + EmojiCatalog.categories.dropFirst().map { $0.emojis }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func apply(theme: Theme) {
        self.theme = theme
        backButton.setTitleColor(theme.text, for: .normal)
        deleteButton.tintColor = theme.text
        categoryButtons.forEach { $0.tintColor = theme.text }
        selection.backgroundColor = theme.emojiSelection
    }

    /// Called each time the panel opens: refresh the "recent" list.
    func prepareToShow() {
        let recents = loadRecents()
        if sections.first != recents {
            sections[0] = recents
            collection.reloadData()
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let gridHeight = max(bounds.height - barHeight, 0)
        collection.frame = CGRect(x: 0, y: 0, width: bounds.width, height: gridHeight)
        // Apple shows 4 rows of about 54 pt; use more rows if the keyboard is taller.
        let rows = max(3, Int((gridHeight / 54).rounded(.down)))
        let cell = floor(gridHeight / CGFloat(rows))
        if layout.itemSize.height != cell {
            layout.itemSize = CGSize(width: cell, height: cell)
            layout.invalidateLayout()
        }

        let barY = gridHeight
        backButton.frame = CGRect(x: 4, y: barY, width: 54, height: barHeight)
        deleteButton.frame = CGRect(x: bounds.width - 54, y: barY, width: 50, height: barHeight)
        let iconsStart = backButton.frame.maxX
        let iconsWidth = max(deleteButton.frame.minX - iconsStart, 0)
        let step = iconsWidth / CGFloat(max(categoryButtons.count, 1))
        for (index, button) in categoryButtons.enumerated() {
            button.frame = CGRect(x: iconsStart + CGFloat(index) * step, y: barY, width: step, height: barHeight)
        }
        placeSelection()
    }

    private func placeSelection() {
        guard categoryButtons.indices.contains(selectedCategory) else { return }
        let button = categoryButtons[selectedCategory]
        let size = min(button.bounds.width, 30)
        selection.frame = CGRect(x: button.frame.midX - size / 2, y: button.frame.midY - size / 2, width: size, height: size)
        selection.layer.cornerRadius = size / 2
    }

    // MARK: Recents

    private func loadRecents() -> [String] {
        let saved = defaults.stringArray(forKey: recentsKey) ?? []
        return saved.isEmpty ? EmojiCatalog.starter : saved
    }

    private func remember(_ emoji: String) {
        var saved = defaults.stringArray(forKey: recentsKey) ?? []
        saved.removeAll { $0 == emoji }
        saved.insert(emoji, at: 0)
        if saved.count > maxRecents { saved.removeLast(saved.count - maxRecents) }
        // Saved now, shown next time the panel opens (so the grid doesn't jump).
        defaults.set(saved, forKey: recentsKey)
    }

    // MARK: Grid

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        if let emojiCell = cell as? EmojiCell {
            emojiCell.label.text = sections[indexPath.section][indexPath.item]
            emojiCell.label.font = .systemFont(ofSize: min(35, layout.itemSize.height * 0.64))
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let emoji = sections[indexPath.section][indexPath.item]
        remember(emoji)
        onPick?(emoji)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Highlight the category currently on screen.
        let probe = CGPoint(x: scrollView.contentOffset.x + layout.itemSize.width / 2, y: layout.itemSize.height / 2)
        guard let path = collection.indexPathForItem(at: probe), path.section != selectedCategory else { return }
        selectedCategory = path.section
        placeSelection()
    }

    // MARK: Buttons

    @objc private func categoryTapped(_ sender: UIButton) {
        let section = sender.tag
        guard sections.indices.contains(section), !sections[section].isEmpty else { return }
        collection.scrollToItem(at: IndexPath(item: 0, section: section), at: .left, animated: false)
        selectedCategory = section
        placeSelection()
    }

    @objc private func back() { onBack?() }
    @objc private func deleteTapped() { onDelete?() }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 34)
        contentView.addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }
}

/// All emoji, grouped roughly like Apple's categories (built once, on first use).
enum EmojiCatalog {
    struct Category {
        let icon: String
        let emojis: [String]
    }

    /// Shown under "recent" until you have used some emoji.
    static let starter = ["❤️", "👍", "😂", "🙏", "😭", "🔥", "😍", "🥹", "✨", "🤣"]

    static let categories: [Category] = build()

    private static func build() -> [Category] {
        var seen = Set<String>()
        func collect(_ ranges: [ClosedRange<UInt32>]) -> [String] {
            var out: [String] = []
            for range in ranges {
                for value in range {
                    guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation else { continue }
                    let emoji = String(Character(scalar))
                    if seen.insert(emoji).inserted { out.append(emoji) }
                }
            }
            return out
        }

        let smileys = collect([
            0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97A, 0x1FAE0...0x1FAFF,
            0x1F930...0x1F939, 0x1F9D0...0x1F9DF, 0x1F440...0x1F487, 0x1F48B...0x1F4AF,
            0x1F9B0...0x1F9BF, 0x1F918...0x1F91F,
        ])
        let nature = collect([
            0x1F400...0x1F43F, 0x1F980...0x1F9AE, 0x1F330...0x1F344, 0x1F300...0x1F320,
            0x1FAB0...0x1FABF, 0x1F490...0x1F490,
        ])
        let food = collect([0x1F345...0x1F37F, 0x1F950...0x1F96F, 0x1F9C0...0x1F9CB, 0x1FAD0...0x1FADF])
        let activities = collect([0x1F380...0x1F3FF, 0x1F93A...0x1F94F, 0x1FA80...0x1FA8F])
        let travel = collect([0x1F680...0x1F6FF, 0x1F5FA...0x1F5FF])
        let objects = collect([
            0x1F4B0...0x1F4FF, 0x1F500...0x1F5F9, 0x1FA70...0x1FA7F, 0x1FA90...0x1FAAF,
            0x1F9E0...0x1F9FF, 0x1F97B...0x1F97F, 0x1F488...0x1F48A,
        ])
        // Everything the old emoji panel had and is not placed yet ends up in symbols.
        let symbols = collect([
            0x2600...0x27BF, 0x2B00...0x2BFF,
            0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF,
            0x1F910...0x1F9FF, 0x1FA70...0x1FAFF,
        ])

        return [
            Category(icon: "clock", emojis: []),
            Category(icon: "face.smiling", emojis: smileys),
            Category(icon: "pawprint", emojis: nature),
            Category(icon: "fork.knife", emojis: food),
            Category(icon: "soccerball", emojis: activities),
            Category(icon: "car", emojis: travel),
            Category(icon: "lightbulb", emojis: objects),
            Category(icon: "heart", emojis: symbols),
            Category(icon: "flag", emojis: flags()),
        ]
    }

    private static let countryCodes = """
    AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV \
    BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES \
    ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE \
    IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY \
    MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU \
    NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM \
    SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE \
    VG VI VN VU WF WS XK YE YT ZA ZM ZW
    """

    private static func flags() -> [String] {
        var out = ["🏁", "🚩", "🎌", "🏴", "🏳️", "🏳️‍🌈", "🏳️‍⚧️", "🏴‍☠️"]
        for code in countryCodes.split(separator: " ") where code.count == 2 {
            var flag = ""
            for letter in code.unicodeScalars {
                guard let indicator = Unicode.Scalar(0x1F1E6 + letter.value - 65) else { continue }
                flag.unicodeScalars.append(indicator)
            }
            out.append(flag)
        }
        return out
    }
}
