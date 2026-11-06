import UIKit

/// Remembers recent copied text (needs Allow Full Access).
final class ClipboardStore {
    private(set) var items: [String] = []
    private var addedAt = Date.distantPast
    private var chipUsed = false
    private var lastChangeCount: Int
    private let defaults = UserDefaults.standard
    private let itemsKey = "nk.clips"
    private let countKey = "nk.clips.changeCount"
    private let maxItems = 20

    init() {
        items = defaults.stringArray(forKey: itemsKey) ?? []
        lastChangeCount = defaults.integer(forKey: countKey)
    }

    /// Checks the system clipboard. Returns true if something new was added.
    @discardableResult
    func refresh(hasFullAccess: Bool) -> Bool {
        guard hasFullAccess else { return false }
        let board = UIPasteboard.general
        guard board.changeCount != lastChangeCount else { return false }
        lastChangeCount = board.changeCount
        defaults.set(lastChangeCount, forKey: countKey)
        guard board.hasStrings, let text = board.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > maxItems { items.removeLast(items.count - maxItems) }
        addedAt = Date()
        chipUsed = false
        save()
        return true
    }

    /// The latest copy, shown in the bar for 2 minutes after copying.
    var recentChip: String? {
        guard !chipUsed, let first = items.first, Date().timeIntervalSince(addedAt) < 120 else { return nil }
        return first
    }

    func markChipUsed() { chipUsed = true }

    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        defaults.set(items, forKey: itemsKey)
    }
}

/// Full clipboard history, shown in place of the keys.
final class ClipboardPanel: UIView, UITableViewDataSource, UITableViewDelegate {
    var onPick: ((String) -> Void)?
    var onBack: (() -> Void)?
    var store: ClipboardStore?
    var hasFullAccess = true

    private let table = UITableView(frame: .zero, style: .plain)
    private let backButton = UIButton(type: .custom)
    private let clearButton = UIButton(type: .custom)
    private let emptyLabel = UILabel()
    private var theme: Theme = .light
    private let barHeight: CGFloat = 40

    override init(frame: CGRect) {
        super.init(frame: frame)
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "clip")
        addSubview(table)

        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 15)
        addSubview(emptyLabel)

        backButton.setTitle(Layouts.isArabic ? "أبج" : "ABC", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 16)
        backButton.layer.cornerRadius = 8.5
        backButton.addTarget(self, action: #selector(back), for: .touchUpInside)
        addSubview(backButton)

        clearButton.setTitle("Clear", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 16)
        clearButton.layer.cornerRadius = 8.5
        clearButton.addTarget(self, action: #selector(clearAll), for: .touchUpInside)
        addSubview(clearButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func apply(theme: Theme) {
        self.theme = theme
        for button in [backButton, clearButton] {
            button.backgroundColor = theme.specialKey
            button.setTitleColor(theme.text, for: .normal)
        }
        emptyLabel.textColor = theme.text.withAlphaComponent(0.6)
        table.separatorColor = theme.suggestionDivider
    }

    func reloadData() {
        table.reloadData()
        let isEmpty = store?.items.isEmpty ?? true
        emptyLabel.isHidden = !isEmpty
        emptyLabel.text = hasFullAccess
            ? "Copied text will show up here"
            : "Turn on Allow Full Access for NumberKeys in Settings to use the clipboard"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let listHeight = bounds.height - barHeight
        table.frame = CGRect(x: 0, y: 0, width: bounds.width, height: listHeight)
        emptyLabel.frame = CGRect(x: 20, y: 0, width: bounds.width - 40, height: listHeight)
        backButton.frame = CGRect(x: 6, y: listHeight + 2, width: 60, height: barHeight - 6)
        clearButton.frame = CGRect(x: bounds.width - 76, y: listHeight + 2, width: 70, height: barHeight - 6)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store?.items.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "clip", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = store?.items[indexPath.row]
        content.textProperties.numberOfLines = 2
        content.textProperties.color = theme.text
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let text = store?.items[indexPath.row] { onPick?(text) }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.store?.remove(at: indexPath.row)
            self?.reloadData()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    @objc private func back() { onBack?() }

    @objc private func clearAll() {
        store?.clear()
        reloadData()
    }
}
