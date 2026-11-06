import UIKit

final class EmojiPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onPick: ((String) -> Void)?
    var onBack: (() -> Void)?
    var onDelete: (() -> Void)?

    private let collection: UICollectionView
    private let layout = UICollectionViewFlowLayout()
    private let backButton = UIButton(type: .custom)
    private let deleteButton = UIButton(type: .custom)
    private let barHeight: CGFloat = 40

    static let emojis: [String] = {
        var out = ["❤️", "👍", "😂", "🙏", "😭", "🔥", "😍", "🥹", "✨", "🤣"]
        let ranges: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F,
            0x1F910...0x1F9FF,
            0x1FA70...0x1FAFF,
            0x1F300...0x1F5FF,
            0x1F680...0x1F6FF,
            0x2600...0x27BF,
            0x2B00...0x2BFF,
        ]
        var seen = Set(out)
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation else { continue }
                let emoji = String(Character(scalar))
                if seen.insert(emoji).inserted {
                    out.append(emoji)
                }
            }
        }
        return out
    }()

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
        backButton.titleLabel?.font = .systemFont(ofSize: 16)
        backButton.layer.cornerRadius = 8.5
        backButton.addTarget(self, action: #selector(back), for: .touchUpInside)
        addSubview(backButton)

        let config = UIImage.SymbolConfiguration(pointSize: 18)
        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: config), for: .normal)
        deleteButton.layer.cornerRadius = 8.5
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        addSubview(deleteButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func apply(theme: Theme) {
        backButton.backgroundColor = theme.specialKey
        backButton.setTitleColor(theme.text, for: .normal)
        deleteButton.backgroundColor = theme.specialKey
        deleteButton.tintColor = theme.text
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gridHeight = bounds.height - barHeight
        collection.frame = CGRect(x: 0, y: 0, width: bounds.width, height: gridHeight)
        let rowsCount: CGFloat = 5
        let cell = floor(gridHeight / rowsCount)
        layout.itemSize = CGSize(width: cell, height: cell)
        backButton.frame = CGRect(x: 6, y: gridHeight + 2, width: 60, height: barHeight - 6)
        deleteButton.frame = CGRect(x: bounds.width - 66, y: gridHeight + 2, width: 60, height: barHeight - 6)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        EmojiPanel.emojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        (cell as? EmojiCell)?.label.text = EmojiPanel.emojis[indexPath.item]
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onPick?(EmojiPanel.emojis[indexPath.item])
    }

    @objc private func back() { onBack?() }
    @objc private func deleteTapped() { onDelete?() }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 30)
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
