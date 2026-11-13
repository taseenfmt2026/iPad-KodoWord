import UIKit
import UniformTypeIdentifiers
import CoreText

final class CustomFontManager: NSObject, UIDocumentPickerDelegate {
    static let shared = CustomFontManager()
    private(set) var fonts: [String] = []

    private override init() {
        super.init()
        loadSavedFonts()
    }

    func loadSavedFonts() {
        let folder = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("CustomFonts")

        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []

        for file in files where ["ttf", "otf", "ttc"].contains(file.pathExtension.lowercased()) {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(
                file as CFURL,
                .process,
                &error
            )
        }

        refresh()
    }

    func refresh() {
        fonts = UIFont.familyNames.sorted()
    }

    func importFont(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }

        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else {
            throw NSError(domain: "KodoWord.Font", code: 1)
        }

        let folder = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("CustomFonts")

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        let destination = folder.appendingPathComponent(url.lastPathComponent)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: url, to: destination)

        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(
            destination as CFURL,
            .process,
            &error
        ) else {
            throw error?.takeRetainedValue() ?? NSError(
                domain: "KodoWord.Font", code: 2
            )
        }

        loadSavedFonts()
    }

    func chooseFontFile() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.font, .data],
            asCopy: true
        )
        picker.delegate = self

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }

        root.present(picker, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first else { return }

        do {
            try importFont(from: url)
            NotificationCenter.default.post(
                name: .customFontsUpdated,
                object: nil
            )
        } catch {
            print("Font import failed:", error)
        }
    }
}

extension Notification.Name {
    static let customFontsUpdated = Notification.Name("customFontsUpdated")
}
