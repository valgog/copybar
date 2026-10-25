import AppKit
import CopyBarCore

/// The larger preview that opens next to the menu when an image, formatted
/// text or other content entry stays highlighted for `preview_delay`
/// seconds. It is a non-activating panel that ignores the mouse, so the
/// menu keeps tracking the pointer and keys, and CopyBar never becomes the
/// active app (which would close the menu).
final class PreviewPanel {
    private let store: HistoryStore
    private let panel: NSPanel
    private var timer: Timer?
    /// Rendered text of the entries previewed while the menu is open, so
    /// moving back and forth doesn't parse the same HTML again.
    private var renderedText: [UUID: NSAttributedString] = [:]

    /// Largest image or text area, in points.
    private static let maxContentSize = NSSize(width: 480, height: 360)
    /// Formatted data over these sizes is previewed as plain text: parsing
    /// it would stall the menu.
    private static let maxHTMLSize = 512 * 1024
    private static let maxRTFSize = 8 * 1024 * 1024
    /// Characters of text rendered; the panel can't scroll, so more is wasted.
    private static let maxTextLength = 4000
    private static let padding: CGFloat = 10
    private static let textInset: CGFloat = 8

    private static let formattedTypes: Set<String> = [
        NSPasteboard.PasteboardType.rtfd.rawValue,
        NSPasteboard.PasteboardType.rtf.rawValue,
        NSPasteboard.PasteboardType.html.rawValue,
    ]

    init(store: HistoryStore) {
        self.store = store
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        // Above the menu, which sits at the pop-up menu level.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    /// Whether `item` gets a preview. Plain text keeps its tooltip instead.
    static func hasPreview(_ item: ClipItem) -> Bool {
        switch item.kind {
        case .image: return true
        case .text: return item.types.contains(where: formattedTypes.contains)
        case .rich: return item.text != nil || item.types.contains(NSPasteboard.PasteboardType.html.rawValue)
        }
    }

    /// Hides the current preview and, if `item` has one, shows it after
    /// `delay` seconds unless another entry gets highlighted first.
    func schedule(_ item: ClipItem?, delay: Double?) {
        hide()
        guard let item, let delay, Self.hasPreview(item) else { return }
        let id = item.id
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, let item = self.store.item(id) else { return }
            self.show(item)
        }
        // While a menu is open the run loop is in event tracking mode,
        // which .common includes.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    /// Call when the menu closes.
    func reset() {
        hide()
        renderedText.removeAll()
    }

    // MARK: - Content

    private func show(_ item: ClipItem) {
        guard let body = bodyView(for: item) else { return }
        let caption = NSTextField(labelWithString: captionText(for: item))
        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail

        let padding = Self.padding
        let bodySize = body.frame.size
        let captionHeight = ceil(caption.fittingSize.height)
        let width = max(bodySize.width, min(ceil(caption.fittingSize.width), Self.maxContentSize.width), 120)
        let size = NSSize(width: width + 2 * padding, height: padding + bodySize.height + 6 + captionHeight + padding)

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        body.setFrameOrigin(NSPoint(x: padding, y: padding + captionHeight + 6))
        caption.frame = NSRect(x: padding, y: padding, width: width, height: captionHeight)
        background.addSubview(body)
        background.addSubview(caption)

        panel.contentView = background
        panel.setFrame(frame(for: size), display: true)
        panel.orderFrontRegardless()
    }

    /// The image, or the text drawn on a white page like the document it
    /// will be pasted into (formatted text usually assumes black on white).
    private func bodyView(for item: ClipItem) -> NSView? {
        if item.kind == .image {
            guard let image = store.image(of: item, fitting: Self.maxContentSize) else { return nil }
            let view = NSImageView(frame: NSRect(origin: .zero, size: image.size))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            return view
        }
        guard let text = text(for: item) else { return nil }

        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let inset = Self.textInset
        let maxWidth = Self.maxContentSize.width - 2 * inset
        let container = NSTextContainer(size: NSSize(width: maxWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let textSize = NSSize(width: ceil(min(max(used.width, 1), maxWidth)),
                              height: ceil(min(used.height, Self.maxContentSize.height - 2 * inset)))

        let textView = NSTextView(frame: NSRect(origin: NSPoint(x: inset, y: inset), size: textSize),
                                  textContainer: container)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero

        let page = NSView(frame: NSRect(x: 0, y: 0, width: textSize.width + 2 * inset, height: textSize.height + 2 * inset))
        page.wantsLayer = true
        page.layer?.backgroundColor = NSColor.white.cgColor
        page.layer?.cornerRadius = 4
        page.layer?.masksToBounds = true
        page.addSubview(textView)
        return page
    }

    /// The item's text with its formatting (RTFD, RTF or HTML, in that
    /// order), or its plain text when there is no formatting worth showing.
    private func text(for item: ClipItem) -> NSAttributedString? {
        if let cached = renderedText[item.id] { return cached }
        var text = formattedText(of: item).map(Self.cleaned)
        if let formatted = text, Preview.isBlank(formatted.string) { text = nil }
        if text == nil, let plain = item.kind == .text ? store.fullText(of: item) : item.text,
           !Preview.isBlank(plain) {
            text = NSAttributedString(string: Preview.visiblePrefix(plain, maxLength: Self.maxTextLength), attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.black,
            ])
        }
        guard var result = text else { return nil }
        if result.length > Self.maxTextLength {
            // Cut at a whole character, never inside a surrogate pair or emoji sequence.
            let end = (result.string as NSString).rangeOfComposedCharacterSequence(at: Self.maxTextLength).location
            let cut = NSMutableAttributedString(attributedString: result.attributedSubstring(from: NSRange(location: 0, length: end)))
            cut.append(NSAttributedString(string: "…"))
            result = cut
        }
        renderedText[item.id] = result
        return result
    }

    /// `text` without attachments and invisible characters, starting at its
    /// first visible character. Attachments (pictures in RTFD and RTF) would
    /// be decoded at full size during layout, and no size limit was checked
    /// for them when they were copied. Invisible characters are dropped as
    /// in the menu titles (`Preview.sanitized`), so bidi overrides can't
    /// disguise the text.
    private static func cleaned(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        var attachments: [NSRange] = []
        result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            if value != nil { attachments.append(range) }
        }
        for range in attachments.reversed() {
            result.deleteCharacters(in: range)
        }

        let string = result.string
        if Preview.sanitized(string) != string {
            var replacements: [(NSRange, String)] = []
            let nsString = string as NSString
            nsString.enumerateSubstrings(in: NSRange(location: 0, length: nsString.length),
                                         options: .byComposedCharacterSequences) { substring, range, _, _ in
                guard let substring else { return }
                let visible = Preview.sanitized(substring)
                if visible != substring { replacements.append((range, visible)) }
            }
            for (range, visible) in replacements.reversed() {
                result.replaceCharacters(in: range, with: visible)
            }
        }

        let start = (result.string as NSString).rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted).location
        if start == NSNotFound {
            result.deleteCharacters(in: NSRange(location: 0, length: result.length))
        } else if start > 0 {
            result.deleteCharacters(in: NSRange(location: 0, length: start))
        }
        return result
    }

    private func formattedText(of item: ClipItem) -> NSAttributedString? {
        let representations = Dictionary(store.representations(of: item), uniquingKeysWith: { first, _ in first })
        if let rtfd = representations[NSPasteboard.PasteboardType.rtfd.rawValue], rtfd.count <= Self.maxRTFSize,
           let text = NSAttributedString(rtfd: rtfd, documentAttributes: nil) {
            return text
        }
        if let rtf = representations[NSPasteboard.PasteboardType.rtf.rawValue], rtf.count <= Self.maxRTFSize,
           let text = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return text
        }
        if let data = representations[NSPasteboard.PasteboardType.html.rawValue], data.count <= Self.maxHTMLSize,
           let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            // Rebuilt with bare formatting tags only: WebKit renders it, and
            // copied HTML must not run script or load anything.
            let safe = Data(Preview.safeHTML(html).utf8)
            return try? NSAttributedString(data: safe, options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ], documentAttributes: nil)
        }
        return nil
    }

    private func captionText(for item: ClipItem) -> String {
        var parts: [String] = []
        switch item.kind {
        case .image:
            parts.append("Image")
            if let width = item.pixelWidth, let height = item.pixelHeight {
                parts.append("\(width) × \(height)")
            }
        case .text:
            parts.append("Formatted text")
        case .rich:
            parts.append(item.label ?? "Copied content")
        }
        if Date().timeIntervalSince(item.date) < 60 {
            parts.append("copied just now")
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append("copied " + formatter.localizedString(for: item.date, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Placement

    /// Beside the open menu, on the side with room, lined up with the
    /// pointer when it is over the menu (mouse use) and with the menu's top
    /// otherwise (arrow keys). NSMenu doesn't expose an item's frame.
    private func frame(for size: NSSize) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let menuFrame = openMenuFrame()
        let anchor = menuFrame.map { NSPoint(x: $0.midX, y: $0.midY) } ?? mouse
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)

        var origin: NSPoint
        if let menuFrame {
            origin = NSPoint(x: menuFrame.maxX + 4, y: 0)
            if origin.x + size.width > visible.maxX {
                origin.x = menuFrame.minX - 4 - size.width
            }
            let top = NSMouseInRect(mouse, menuFrame, false) ? mouse.y + 12 : menuFrame.maxY
            origin.y = top - size.height
        } else {
            origin = NSPoint(x: mouse.x + 16, y: mouse.y - size.height - 16)
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }

    /// The frame of the open menu's window, which AppKit creates in this
    /// process at the pop-up menu level.
    private func openMenuFrame() -> NSRect? {
        NSApp.windows
            .filter { $0 !== panel && $0.isVisible && $0.level.rawValue >= NSWindow.Level.popUpMenu.rawValue }
            .map(\.frame)
            .max { $0.width * $0.height < $1.width * $1.height }
    }
}
