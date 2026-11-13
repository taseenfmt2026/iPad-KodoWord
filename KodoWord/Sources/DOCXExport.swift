
import Foundation
import UIKit
import ZIPFoundation

enum DOCXExport {
    static func xmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func export(_ text: NSAttributedString, to url: URL) throws {
        var body = ""

        text.enumerateAttributes(
            in: NSRange(location: 0, length: text.length)
        ) { attrs, range, _ in
            let value = xmlEscape(
                (text.string as NSString).substring(with: range)
            )

            let font = attrs[.font] as? UIFont
                ?? UIFont.systemFont(ofSize: 12)

            let bold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
            let italic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            let underline = attrs[.underlineStyle] != nil

            var properties = ""
            if bold { properties += "<w:b/>" }
            if italic { properties += "<w:i/>" }
            if underline { properties += "<w:u w:val=\"single\"/>" }

            let size = Int(font.pointSize * 2)

            body += """
            <w:r><w:rPr>\(properties)<w:sz w:val="\(size)"/></w:rPr><w:t xml:space="preserve">\(value)</w:t></w:r>
            """
        }

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body><w:p>\(body)</w:p><w:sectPr/></w:body></w:document>
        """

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let relationships = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        try? FileManager.default.removeItem(at: url)

        let archive = try Archive(url: url, accessMode: .create)

        func add(_ path: String, _ content: String) throws {
            let data = Data(content.utf8)

            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: UInt32(data.count),
                provider: { position, size in
                    let start = Int(position)
                    let length = Int(size)
                    data.subdata(in: start..<(start + length))
                }
            )
        }

        try add("[Content_Types].xml", contentTypes)
        try add("_rels/.rels", relationships)
        try add("word/document.xml", document)
    }
}