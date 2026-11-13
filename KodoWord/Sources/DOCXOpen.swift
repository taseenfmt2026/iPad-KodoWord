import UIKit
import UniformTypeIdentifiers

final class DOCXOpen: NSObject, UIDocumentPickerDelegate {
    weak var editor: UITextView?

    static func present(editor: UITextView) {
        let handler = DOCXOpen()
        handler.editor = editor

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.init(filenameExtension: "docx") ?? .data],
            asCopy: true
        )
        picker.delegate = handler

        objc_setAssociatedObject(
            picker, "KodoWordDOCXHandler", handler,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(picker, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first, let editor = editor else { return }

        do {
            let content = try DOCXEngine.importDocument(from: url)
            editor.attributedText = content
            editor.delegate?.textViewDidChange?(editor)
        } catch {
            print("DOCX import failed:", error)
        }
    }
}
