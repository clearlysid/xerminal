import UIKit

struct TabBarItem {
    let id: UUID
    let title: String
}

@MainActor
final class TerminalTabBarView: UIView {

    var onSelect: (UUID) -> Void = { _ in }
    var onClose: (UUID) -> Void = { _ in }
    var onCloseOthers: (UUID) -> Void = { _ in }
    var onNew: () -> Void = {}

    var items: [TabBarItem] = [] { didSet { rebuild() } }
    var activeID: UUID? { didSet { updateActive() } }

    var font: UIFont = .monospacedSystemFont(ofSize: 13, weight: .regular) {
        didSet {
            plusButton.titleLabel?.font = font
            heightConstraint.constant = preferredHeight
            rebuild()
        }
    }

    var bgColor: UIColor = .black {
        didSet {
            backgroundColor = bgColor
            rebuild()
        }
    }
    var fgColor: UIColor = .lightGray {
        didSet {
            plusButton.configuration?.baseForegroundColor = fgColor.withAlphaComponent(0.7)
            rebuild()
        }
    }

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let plusButton = UIButton(type: .system)
    private var heightConstraint: NSLayoutConstraint!

    var preferredHeight: CGFloat {
        ceil(font.lineHeight) + 8
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = bgColor

        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: preferredHeight)
        heightConstraint.isActive = true

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        addSubview(scroll)

        stack.axis = .horizontal
        stack.spacing = 0
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        var cfg = UIButton.Configuration.plain()
        cfg.title = " + "
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)
        cfg.baseForegroundColor = fgColor.withAlphaComponent(0.7)
        plusButton.configuration = cfg
        plusButton.titleLabel?.font = font
        plusButton.isPointerInteractionEnabled = true
        plusButton.addAction(UIAction { [weak self] _ in self?.onNew() }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let cell = TabCellView(font: font, id: item.id)
            cell.bgColor = bgColor
            cell.fgColor = fgColor
            cell.title = item.title
            cell.isActive = (item.id == activeID)
            cell.onSelect = { [weak self] id in self?.onSelect(id) }
            cell.onClose = { [weak self] id in self?.onClose(id) }
            cell.onCloseOthers = { [weak self] id in self?.onCloseOthers(id) }
            stack.addArrangedSubview(cell)
        }
        stack.addArrangedSubview(plusButton)
    }

    private func updateActive() {
        for view in stack.arrangedSubviews {
            if let cell = view as? TabCellView {
                cell.isActive = (cell.id == activeID)
            }
        }
    }
}

@MainActor
private final class TabCellView: UIView, UIPointerInteractionDelegate, UIContextMenuInteractionDelegate {
    let id: UUID
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let font: UIFont
    private let tap = UITapGestureRecognizer()

    var title: String = "" { didSet { titleLabel.text = " \(title) " } }

    var isActive: Bool = false { didSet { updateAppearance() } }

    var bgColor: UIColor = .black
    var fgColor: UIColor = .lightGray

    var onSelect: (UUID) -> Void = { _ in }
    var onClose: (UUID) -> Void = { _ in }
    var onCloseOthers: (UUID) -> Void = { _ in }

    init(font: UIFont, id: UUID) {
        self.font = font
        self.id = id
        super.init(frame: .zero)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        titleLabel.font = font
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        var cfg = UIButton.Configuration.plain()
        cfg.title = "× "
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 4)
        closeButton.configuration = cfg
        closeButton.titleLabel?.font = font
        closeButton.isPointerInteractionEnabled = true
        closeButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onClose(self.id)
        }, for: .touchUpInside)

        let h = UIStackView(arrangedSubviews: [titleLabel, closeButton])
        h.axis = .horizontal
        h.spacing = 0
        h.alignment = .center
        h.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h)
        NSLayoutConstraint.activate([
            h.topAnchor.constraint(equalTo: topAnchor),
            h.bottomAnchor.constraint(equalTo: bottomAnchor),
            h.leadingAnchor.constraint(equalTo: leadingAnchor),
            h.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        tap.addTarget(self, action: #selector(tapped))
        addGestureRecognizer(tap)

        addInteraction(UIPointerInteraction(delegate: self))
        addInteraction(UIContextMenuInteraction(delegate: self))

        updateAppearance()
    }

    // MARK: - Pointer (hover) + context menu

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        let preview = UITargetedPreview(view: self)
        return UIPointerStyle(effect: .highlight(preview))
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let myID = id
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(title: "", children: [
                UIAction(title: "Close", image: UIImage(systemName: "xmark")) { _ in
                    self?.onClose(myID)
                },
                UIAction(title: "Close Others", image: UIImage(systemName: "rectangle.on.rectangle.slash")) { _ in
                    self?.onCloseOthers(myID)
                },
            ])
        }
    }

    @objc private func tapped() { onSelect(id) }

    private func updateAppearance() {
        if isActive {
            backgroundColor = fgColor.withAlphaComponent(0.85)
            titleLabel.textColor = bgColor
            closeButton.configuration?.baseForegroundColor = bgColor
        } else {
            backgroundColor = .clear
            titleLabel.textColor = fgColor.withAlphaComponent(0.6)
            closeButton.configuration?.baseForegroundColor = fgColor.withAlphaComponent(0.6)
        }
    }
}
