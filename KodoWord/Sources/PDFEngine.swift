import UIKit
import CoreText

enum PDFEngine {
    static func export(
        attributedText: NSAttributedString,
        to url: URL,
        pageSize: CGSize = CGSize(width: 595, height: 842),
        margin: CGFloat = 50
    ) throws {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize)
        )

        let data = renderer.pdfData { context in
            let framesetter = CTFramesetterCreateWithAttributedString(
                attributedText as CFAttributedString
            )

            var location = 0
            let totalLength = attributedText.length

            repeat {
                context.beginPage()

                let cg = context.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: pageSize.height)
                cg.scaleBy(x: 1, y: -1)

                let rect = CGRect(
                    x: margin,
                    y: margin,
                    width: pageSize.width - margin * 2,
                    height: pageSize.height - margin * 2
                )

                let path = CGPath(
                    rect: rect,
                    transform: nil
                )

                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: location, length: 0),
                    path,
                    nil
                )

                CTFrameDraw(frame, cg)

                let visible = CTFrameGetVisibleStringRange(frame)
                location += visible.length

                cg.restoreGState()

                if visible.length == 0 { break }
            } while location < totalLength
        }

        try data.write(to: url, options: .atomic)
    }
}
