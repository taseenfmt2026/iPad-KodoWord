import UIKit

extension UITextView {

    func toggleHighlight() {
        let range = selectedRange
        guard range.length > 0 else { return }

        let mutable = NSMutableAttributedString(attributedString: attributedText)
        let current = mutable.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? UIColor

        mutable.addAttribute(
            .backgroundColor,
            value: (current == nil || current == .clear) ? UIColor.yellow.withAlphaComponent(0.4) : UIColor.clear,
            range: range
        )

        attributedText = mutable
        selectedRange = range
        delegate?.textViewDidChange?(self)
    }

    func insertListPrefix(_ prefix: String) {
        let range = selectedRange
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: range)
        let line = nsText.substring(with: lineRange)

        let updated = NSMutableString(string: line)
        updated.insert(prefix, at: 0)

        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: lineRange, with: updated as String)

        let newText = mutable as String
        let cursor = lineRange.location + prefix.count + range.location - lineRange.location

        text = newText
        selectedRange = NSRange(location: min(cursor, (newText as NSString).length), length: 0)
        delegate?.textViewDidChange?(self)
    }

    func clearSelectionFormatting() {
        let range = selectedRange
        guard range.length > 0 else { return }

        let mutable = NSMutableAttributedString(attributedString: attributedText)
        let baseFont = UIFont.systemFont(ofSize: 12)

        mutable.addAttributes([
            .font: baseFont,
            .foregroundColor: UIColor.label
        ], range: range)

        mutable.removeAttribute(.underlineStyle, range: range)
        mutable.removeAttribute(.strikethroughStyle, range: range)
        mutable.removeAttribute(.backgroundColor, range: range)

        attributedText = mutable
        selectedRange = range
        delegate?.textViewDidChange?(self)
    }

    func applyFontSize(_ size: CGFloat) {
        let range = selectedRange
        guard range.length > 0 else {
            var attributes = typingAttributes
            let oldFont = attributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: size)
            attributes[.font] = UIFont(descriptor: oldFont.fontDescriptor, size: size)
            typingAttributes = attributes
            return
        }

        let mutable = NSMutableAttributedString(attributedString: attributedText)
        mutable.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let oldFont = value as? UIFont ?? UIFont.systemFont(ofSize: size)
            mutable.addAttribute(
                .font,
                value: UIFont(descriptor: oldFont.fontDescriptor, size: size),
                range: subrange
            )
        }

        attributedText = mutable
        selectedRange = range
        delegate?.textViewDidChange?(self)
    }
}
