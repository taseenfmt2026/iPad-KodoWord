import UIKit

enum TXTShare {
    static func present(editor: UITextView) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KodoWord-Document.txt")

        do {
            try editor.text.write(to: url, atomically: true, encoding: .utf8)

            let sheet = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )

            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }

            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }

            if let popover = sheet.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(
                    x: top.view.bounds.midX,
                    y: top.view.bounds.midY,
                    width: 0,
                    height: 0
                )
            }

            top.present(sheet, animated: true)
        } catch {
            print("TXT export failed:", error)
        }
    }
}
