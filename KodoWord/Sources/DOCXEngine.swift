
import Foundation
import ZIPFoundation
import UIKit

final class DOCXEngine: NSObject, XMLParserDelegate {
    private var result = NSMutableAttributedString(string: "")
    private var paragraph = NSMutableAttributedString(string: "")
    private var currentText = ""
    private var bold = false
    private var italic = false
    private var underline = false
    private var fontSize: CGFloat = 12
    private var insideText = false

    static func importDocument(from url: URL) throws -> NSAttributedString {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let archive = try Archive(url: url, accessMode: .read)

        guard let entry = archive["word/document.xml"] else {
            throw NSError(domain: "KodoWord", code: 1)
        }

        let xmlURL = folder.appendingPathComponent("document.xml")
        _ = try archive.extract(entry, to: xmlURL)

        let parser = XMLParser(data: try Data(contentsOf: xmlURL))
        let engine = DOCXEngine()
        parser.delegate = engine

        guard parser.parse() else {
            throw parser.parserError ?? NSError(domain: "KodoWord", code: 2)
        }

        return engine.result
    }

    func parser(
        _ parser: XMLParser,
        didStartElement name: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        switch name {
        case "p":
            paragraph = NSMutableAttributedString(string: "")

        case "b":
            bold = true

        case "i":
            italic = true

        case "u":
            underline = true

        case "sz":
            if let value = attributes["val"],
               let size = Double(value) {
                fontSize = CGFloat(size) / 2
            }

        case "t":
            insideText = true

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if insideText {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement name: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch name {
        case "t":
            var traits = UIFontDescriptor.SymbolicTraits()

            if bold {
                traits.insert(.traitBold)
            }

            if italic {
                traits.insert(.traitItalic)
            }

            let baseFont = UIFont.systemFont(ofSize: fontSize)

            let descriptor = baseFont.fontDescriptor
                .withSymbolicTraits(traits)
                ?? baseFont.fontDescriptor

            let font = UIFont(
                descriptor: descriptor,
                size: fontSize
            )

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font
            ]

            if underline {
                attributes[.underlineStyle] =
                    NSUnderlineStyle.single.rawValue
            }

            paragraph.append(
                NSAttributedString(
                    string: currentText,
                    attributes: attributes
                )
            )

            currentText = ""
            insideText = false

        case "p":
            result.append(paragraph)
            result.append(NSAttributedString(string: "\n"))

            bold = false
            italic = false
            underline = false
            fontSize = 12

        default:
            break
        }
    }
}
