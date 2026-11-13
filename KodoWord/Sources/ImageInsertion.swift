import SwiftUI
import UIKit

final class ImageInsertion: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    weak var editor: UITextView?
    private var picker: UIImagePickerController?

    static func present(editor: UITextView) {
        let handler = ImageInsertion()
        handler.editor = editor

        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = handler
        handler.picker = picker

        objc_setAssociatedObject(
            picker,
            "KodoWordImageHandler",
            handler,
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

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        if let image = info[.originalImage] as? UIImage,
           let editor = editor {
            RichTextEngine.insertImage(into: editor, image: image)
        }
        picker.dismiss(animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
