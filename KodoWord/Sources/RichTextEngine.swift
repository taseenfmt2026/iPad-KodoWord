import UIKit
import UniformTypeIdentifiers

enum RichTextEngine {

    static func applyFont(
        to textView: UITextView,
        family: String,
        size: CGFloat
    ) {
        let range = textView.selectedRange

        if range.length == 0 {
            textView.typingAttributes[.font] =
                UIFont(name: family, size: size)
                ?? UIFont.systemFont(ofSize: size)
            return
        }

        let storage = textView.textStorage
        storage.beginEditing()

        storage.enumerateAttribute(
            .font,
            in: range,
            options: []
        ) { value, subrange, _ in
            let old = value as? UIFont
                ?? UIFont.systemFont(ofSize: size)

            let newFont = UIFont(
                name: family,
                size: old.pointSize
            ) ?? UIFont.systemFont(ofSize: size)

            storage.addAttribute(
                .font,
                value: newFont,
                range: subrange
            )
        }

        storage.endEditing()
    }

    static func applySize(
        to textView: UITextView,
        size: CGFloat
    ) {
        let range = textView.selectedRange

        if range.length == 0 {
            let old = textView.typingAttributes[.font] as? UIFont
                ?? UIFont.systemFont(ofSize: size)

            textView.typingAttributes[.font] =
                old.withSize(size)
            return
        }

        textView.textStorage.enumerateAttribute(
            .font,
            in: range,
            options: []
        ) { value, subrange, _ in
            let old = value as? UIFont
                ?? UIFont.systemFont(ofSize: size)

            textView.textStorage.addAttribute(
                .font,
                value: old.withSize(size),
                range: subrange
            )
        }
    }

    static func applyColor(
        to textView: UITextView,
        color: UIColor
    ) {
        let range = textView.selectedRange

        if range.length == 0 {
            textView.typingAttributes[.foregroundColor] = color
        } else {
            textView.textStorage.addAttribute(
                .foregroundColor,
                value: color,
                range: range
            )
        }
    }

    static func applyHighlight(
        to textView: UITextView,
        color: UIColor
    ) {
        let range = textView.selectedRange

        if range.length == 0 {
            textView.typingAttributes[.backgroundColor] = color
        } else {
            textView.textStorage.addAttribute(
                .backgroundColor,
                value: color,
                range: range
            )
        }
    }

    static func applyAlignment(
        to textView: UITextView,
        alignment: NSTextAlignment
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment

        let range = textView.selectedRange

        if range.length == 0 {
            textView.typingAttributes[.paragraphStyle] = style
        } else {
            textView.textStorage.addAttribute(
                .paragraphStyle,
                value: style,
                range: range
            )
        }
    }

    static func applyLineSpacing(
        to textView: UITextView,
        multiplier: CGFloat
    ) {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = multiplier

        let range = textView.selectedRange

        if range.length == 0 {
            textView.typingAttributes[.paragraphStyle] = style
        } else {
            textView.textStorage.addAttribute(
                .paragraphStyle,
                value: style,
                range: range
            )
        }
    }

    static func insertLink(
        into textView: UITextView,
        url: URL
    ) {
        let range = textView.selectedRange

        guard range.length > 0 else { return }

        textView.textStorage.addAttribute(
            .link,
            value: url,
            range: range
        )

        textView.typingAttributes[.link] = url
    }

    static func insertImage(
        into textView: UITextView,
        image: UIImage,
        maximumWidth: CGFloat = 450
    ) {
        let attachment = NSTextAttachment()
        attachment.image = image

        let ratio = image.size.width > 0
            ? min(1, maximumWidth / image.size.width)
            : 1

        attachment.bounds = CGRect(
            x: 0,
            y: 0,
            width: image.size.width * ratio,
            height: image.size.height * ratio
        )

        let attributed = NSAttributedString(attachment: attachment)

        textView.textStorage.replaceCharacters(
            in: textView.selectedRange,
            with: attributed
        )

        textView.delegate?.textViewDidChange?(textView)
    }

    static func insertTable(
        into textView: UITextView,
        rows: Int,
        columns: Int
    ) {
        let safeRows = min(max(rows, 1), 30)
        let safeColumns = min(max(columns, 1), 15)

        let result = NSMutableAttributedString()

        let border = "│"
        let separator = "─"

        for row in 0..<safeRows {
            var cells: [String] = []

            for column in 0..<safeColumns {
                cells.append(" Cell \(row + 1).\(column + 1) ")
            }

            let line = border + cells.joined(separator: border) + border
            result.append(NSAttributedString(
                string: line + "\n",
                attributes: [
                    .font: UIFont.monospacedSystemFont(
                        ofSize: 12,
                        weight: .regular
                    )
                ]
            ))

            if row == 0 {
                let divider = border +
                    Array(repeating: separator, count: safeColumns)
                    .joined(separator: "┼") +
                    border

                result.append(NSAttributedString(
                    string: divider + "\n",
                    attributes: [
                        .font: UIFont.monospacedSystemFont(
                            ofSize: 12,
                            weight: .regular
                        )
                    ]
                ))
            }
        }

        textView.textStorage.replaceCharacters(
            in: textView.selectedRange,
            with: result
        )

        textView.delegate?.textViewDidChange?(textView)
    }

    static func clearFormatting(
        in textView: UITextView
    ) {
        let range = textView.selectedRange

        guard range.length > 0 else {
            textView.typingAttributes = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.label
            ]
            return
        }

        let text = (textView.textStorage.string as NSString)
            .substring(with: range)

        let normal = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.label
            ]
        )

        textView.textStorage.replaceCharacters(
            in: range,
            with: normal
        )
    }

    static func wordCount(_ text: String) -> Int {
        text.split {
            $0.isWhitespace || $0.isNewline
        }.count
    }

    static func characterCount(_ text: String) -> Int {
        text.count
    }
}

// Native editor integration helpers
extension UITextView {
    func applyBold() {
        RichTextEngine.applyFont(to: self, family: "System-Bold", size: font?.pointSize ?? 16)
    }

    func applyItalic() {
        guard let selectedFont = font else { return }
        font = UIFont.italicSystemFont(ofSize: selectedFont.pointSize)
    }

    func applyUnderline() {
        let range = selectedRange
        guard range.length > 0 else { return }
        let text = attributedText.mutableCopy() as! NSMutableAttributedString
        text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        attributedText = text
        selectedRange = range
    }

    func applyStrikethrough() {
        let range = selectedRange
        guard range.length > 0 else { return }
        let text = attributedText.mutableCopy() as! NSMutableAttributedString
        text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        attributedText = text
        selectedRange = range
    }
}
