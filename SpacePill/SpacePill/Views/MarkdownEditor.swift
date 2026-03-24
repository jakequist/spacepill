import SwiftUI
import AppKit

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var scrollPosition: Double
    let spaceUUID: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        
        let textView = MarkdownTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        
        // Setup syntax highlighting
        textView.textStorage?.delegate = context.coordinator
        textView.delegate = context.coordinator
        
        scrollView.documentView = textView
        
        // Observe scroll changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollWheelDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! MarkdownTextView
        
        // Update text if changed from external source
        if textView.string != text {
            textView.string = text
            context.coordinator.highlight(textView.textStorage!)
            context.coordinator.updateHeight(textView)
        }
        
        // Restore scroll position ONLY when switching spaces to avoid race conditions while typing
        if context.coordinator.lastSpaceUUID != spaceUUID {
            context.coordinator.lastSpaceUUID = spaceUUID
            DispatchQueue.main.async {
                nsView.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(scrollPosition)))
                nsView.reflectScrolledClipView(nsView.contentView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownEditor
        var isHighlighting = false
        var lastSpaceUUID: String = ""
        
        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }
        
        @objc func scrollWheelDidChange(_ notification: Notification) {
            guard let contentView = notification.object as? NSClipView else { return }
            let newPos = Double(contentView.bounds.origin.y)
            // Only update if it's a significant change to avoid jitter
            if abs(parent.scrollPosition - newPos) > 1.0 {
                DispatchQueue.main.async {
                    self.parent.scrollPosition = newPos
                }
            }
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
            updateHeight(textView)
            
            // Force auto-scroll to cursor after a tiny delay to allow window/layout to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textView.scrollRangeToVisible(textView.selectedRange())
        }
        
        func updateHeight(_ textView: NSTextView) {
            if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                layoutManager.ensureLayout(for: container)
                let usedRect = layoutManager.usedRect(for: container)
                let newHeight = usedRect.height + 20 // padding
                if abs(parent.height - newHeight) > 1.0 {
                    DispatchQueue.main.async {
                        self.parent.height = newHeight
                    }
                }
            }
        }
        
        // MARK: - NSTextStorageDelegate
        
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            if editedMask.contains(.editedCharacters) && !isHighlighting {
                highlight(textStorage)
            }
        }
        
        func highlight(_ textStorage: NSTextStorage) {
            isHighlighting = true
            let string = textStorage.string
            let fullRange = NSRange(location: 0, length: string.utf16.count)
            
            textStorage.beginEditing()
            
            // Reset to default
            textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            textStorage.removeAttribute(.backgroundColor, range: fullRange)
            
            // 1. Headers
            applyRegex(pattern: "^#+ .*", options: .anchorsMatchLines, to: textStorage) { range in
                textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold), range: range)
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
            }
            
            // 2. Bold
            applyRegex(pattern: "\\*\\*.*?\\*\\*|__.*?__", to: textStorage) { range in
                textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), range: range)
            }
            
            // 3. Italics
            applyRegex(pattern: "(?<!\\*)\\*[^\\*].*?\\*(?!\\*)|(?<!_)_[^_].*?_(?!_)", to: textStorage) { range in
                let font = NSFontManager.shared.convert(.monospacedSystemFont(ofSize: 13, weight: .regular), toHaveTrait: .italicFontMask)
                textStorage.addAttribute(.font, value: font, range: range)
            }
            
            // 4. Code
            applyRegex(pattern: "`.*?`", to: textStorage) { range in
                textStorage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: range)
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: range)
            }
            
            // 5. Code blocks
            applyRegex(pattern: "```[\\s\\S]*?```", to: textStorage) { range in
                textStorage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: range)
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: range)
            }
            
            // 6. Lists
            applyRegex(pattern: "^(\\s*[*\\-+]|\\s*\\d+\\.) ", options: .anchorsMatchLines, to: textStorage) { range in
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
            }
            
            textStorage.endEditing()
            isHighlighting = false
        }
        
        private func applyRegex(pattern: String, options: NSRegularExpression.Options = [], to textStorage: NSTextStorage, action: (NSRange) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let matches = regex.matches(in: textStorage.string, range: NSRange(location: 0, length: textStorage.length))
            for match in matches {
                action(match.range)
            }
        }
    }
}

/**
 * Custom NSTextView to handle auto-indentation and markdown-friendly behaviors.
 */
class MarkdownTextView: NSTextView {
    override func insertNewline(_ sender: Any?) {
        let string = self.string as NSString
        let selectedRange = self.selectedRange()
        let lineRange = string.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        let currentLine = string.substring(with: lineRange)
        
        // Match list patterns: "* ", "- ", "1. ", "  * " etc.
        let listRegex = try? NSRegularExpression(pattern: "^(\\s*([*\\-+]|\\d+\\.)) ", options: [])
        let range = NSRange(location: 0, length: currentLine.utf16.count)
        
        if let match = listRegex?.firstMatch(in: currentLine, options: [], range: range) {
            let listMarker = (currentLine as NSString).substring(with: match.range)
            
            let trimmedLine = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedMarker = listMarker.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine == trimmedMarker {
                self.setSelectedRange(lineRange)
                self.insertText("\n", replacementRange: lineRange)
                return
            }
            
            super.insertNewline(sender)
            self.insertText(listMarker, replacementRange: self.selectedRange())
            return
        }
        
        super.insertNewline(sender)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window != nil {
            self.window?.makeFirstResponder(self)
        }
    }
}
