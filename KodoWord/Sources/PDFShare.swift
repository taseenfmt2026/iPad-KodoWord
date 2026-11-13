import UIKit

enum PDFShare {
    static func present(editor: UITextView) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KodoWord-Document.pdf")

        do {
            try PDFEngine.export(
                attributedText: editor.attributedText,
                to: url
            )

            let activity = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )

            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                var top = root
                while let presented = top.presentedViewController {
                    top = presented
                }

                if let popover = activity.popoverPresentationController {
                    popover.sourceView = top.view
                    popover.sourceRect = CGRect(
                        x: top.view.bounds.midX,
                        y: top.view.bounds.midY,
                        width: 0,
                        height: 0
                    )
                }

                top.present(activity, animated: true)
            }
        } catch {
            print("PDF export failed:", error)
        }
    }
}
