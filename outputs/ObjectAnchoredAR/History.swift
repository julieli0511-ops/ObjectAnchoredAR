import UIKit

/// One past question and the assistant's answer, kept on the device only. Evaluation mode is never recorded.
struct HistoryEntry: Codable {
    let id: UUID, date: Date
    let question: String, display: String, source: String
    let object: String, location: String, explanation: String, confidence: String, icon: String
    let reason: String?
    /// "Confirmed" or "Corrected to …", once the user has responded.
    var response: String?
}

final class HistoryStore {
    static let shared = HistoryStore()
    private(set) var entries: [HistoryEntry] = []  // newest first
    /// Application Support, not Documents: Documents is shared with the Files app (for exporting Evaluation records),
    /// and the history must stay private to the app.
    private static let fileURL: URL = {
        let fm = FileManager.default, folder = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("history.json")
        // Move history saved by earlier versions out of Documents.
        let old = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("history.json")
        if fm.fileExists(atPath: old.path) {
            if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: old) } else { try? fm.moveItem(at: old, to: url) }
        }
        return url
    }()
    private static let limit = 100
    private init() {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        entries = (try? d.decode([HistoryEntry].self, from: Data(contentsOf: Self.fileURL))) ?? []
    }
    @discardableResult func add(_ item: AIInterpretation, display: String, source: String) -> UUID {
        let entry = HistoryEntry(id: UUID(), date: Date(), question: item.question, display: display, source: source, object: item.interpretedTarget,
                                 location: item.interpretedLocation, explanation: item.explanation, confidence: item.confidence, icon: item.icon, reason: item.reason, response: nil)
        entries.insert(entry, at: 0); entries = Array(entries.prefix(Self.limit)); save(); return entry.id
    }
    func setResponse(_ response: String, for id: UUID) { guard let i = entries.firstIndex(where: { $0.id == id }) else { return }; entries[i].response = response; save() }
    func remove(at index: Int) { entries.remove(at: index); save() }
    func clear() { entries.removeAll(); save() }
    private func save() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        do { try e.encode(entries).write(to: Self.fileURL, options: [.atomic, .completeFileProtection]) } catch { print("Failed to save history: \(error)") }
    }
}

/// Past conversations in a drawer that slides in from the left, as in chat apps.
final class HistoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onSelect: ((HistoryEntry) -> Void)?
    private let dim = UIView(), panel = UIView(), table = UITableView(frame: .zero, style: .plain)
    private let empty = UILabel(), clearButton = UIButton(type: .system)
    private let relative: RelativeDateTimeFormatter = { let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f }()
    private var panelWidth: CGFloat { min(view.bounds.width * 0.82, 360) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.35); dim.alpha = 0
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissDrawer)))
        panel.backgroundColor = InterfaceStyle.panel
        let title = UILabel(); title.text = "History"; title.font = .systemFont(ofSize: 22, weight: .bold); title.textColor = InterfaceStyle.ink
        clearButton.setTitle("Clear all", for: .normal); clearButton.tintColor = InterfaceStyle.accent; clearButton.addTarget(self, action: #selector(clearAll), for: .touchUpInside)
        let note = UILabel(); note.text = "Saved on this iPhone only."; note.font = .preferredFont(forTextStyle: .footnote); note.textColor = .secondaryLabel
        let header = UIStackView(arrangedSubviews: [title, UIView(), clearButton]); header.alignment = .center
        table.dataSource = self; table.delegate = self; table.backgroundColor = .clear; table.rowHeight = UITableView.automaticDimension
        empty.text = "No conversations yet.\nAsk about something you see."; empty.numberOfLines = 0; empty.textAlignment = .center; empty.textColor = .secondaryLabel
        [dim, panel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        [header, note, table, empty].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview($0) }
        NSLayoutConstraint.activate([
            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor), dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dim.topAnchor.constraint(equalTo: view.topAnchor), dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor), panel.topAnchor.constraint(equalTo: view.topAnchor), panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.widthAnchor.constraint(equalToConstant: panelWidth),
            header.topAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20), header.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            note.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2), note.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            table.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 10), table.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: panel.trailingAnchor), table.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            empty.centerYAnchor.constraint(equalTo: panel.centerYAnchor), empty.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 24),
            empty.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -24),
        ])
        panel.transform = CGAffineTransform(translationX: -panelWidth, y: 0)
        refreshEmptyState()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseOut) { self.panel.transform = .identity; self.dim.alpha = 1 }
    }
    @objc private func dismissDrawer() { close(then: nil) }
    private func close(then action: (() -> Void)?) {
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseIn, animations: {
            self.panel.transform = CGAffineTransform(translationX: -self.panelWidth, y: 0); self.dim.alpha = 0
        }) { _ in self.dismiss(animated: false, completion: action) }
    }
    @objc private func clearAll() { HistoryStore.shared.clear(); table.reloadData(); refreshEmptyState() }
    private func refreshEmptyState() { let none = HistoryStore.shared.entries.isEmpty; empty.isHidden = !none; clearButton.isHidden = none }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { HistoryStore.shared.entries.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let entry = HistoryStore.shared.entries[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil); cell.backgroundColor = .clear
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: entry.icon) ?? UIImage(systemName: "cube.fill"); content.imageProperties.tintColor = InterfaceStyle.accent
        content.text = entry.question; content.textProperties.font = .systemFont(ofSize: 15, weight: .semibold); content.textProperties.numberOfLines = 2
        let when = Date().timeIntervalSince(entry.date) < 60 ? "Just now" : relative.localizedString(for: entry.date, relativeTo: Date())
        content.secondaryText = "\(entry.object) · \(entry.response ?? "No response") · \(when)"
        content.secondaryTextProperties.color = .secondaryLabel; content.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = content
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = HistoryStore.shared.entries[indexPath.row]
        close { [onSelect] in onSelect?(entry) }
    }
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            HistoryStore.shared.remove(at: indexPath.row); tableView.deleteRows(at: [indexPath], with: .automatic); self?.refreshEmptyState(); done(true)
        }])
    }
}
