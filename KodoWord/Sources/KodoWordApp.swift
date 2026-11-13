
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Combine

// MARK: - App

@main
struct KodoWordApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Document Model

struct KodoDocument: Identifiable, Codable {
    var id: UUID
    var title: String
    var html: String
    var header: String
    var footer: String
    var paper: String
    var orientation: String
    var margin: Double
    var modified: Date

    init(
        title: String = "Untitled Document",
        html: String = "<p></p>"
    ) {
        id = UUID()
        self.title = title
        self.html = html
        header = ""
        footer = ""
        paper = "A4"
        orientation = "Portrait"
        margin = 20
        modified = Date()
    }
}

// MARK: - Storage

final class DocumentStore: ObservableObject {
    @Published var documents: [KodoDocument] = []
    @Published var selectedID: UUID?

    private let key = "KodoWord.Documents"

    init() {
        load()
    }

    var selectedIndex: Int? {
        documents.firstIndex { $0.id == selectedID }
    }

    var selected: KodoDocument {
        if let index = selectedIndex {
            return documents[index]
        }
        return documents[0]
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(
                [KodoDocument].self,
                from: data
           ) {
            documents = saved
        }

        if documents.isEmpty {
            documents = [KodoDocument(title: "My Document")]
        }

        selectedID = documents.first?.id
    }

    func save() {
        if let data = try? JSONEncoder().encode(documents) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func update(_ action: (inout KodoDocument) -> Void) {
        guard let index = selectedIndex else { return }
        action(&documents[index])
        documents[index].modified = Date()
        save()
    }

    func create() {
        let document = KodoDocument()
        documents.insert(document, at: 0)
        selectedID = document.id
        save()
    }

    func duplicate(_ id: UUID) {
        guard let original = documents.first(where: { $0.id == id })
        else { return }

        var copy = original
        copy.id = UUID()
        copy.title += " Copy"
        copy.modified = Date()

        documents.insert(copy, at: 0)
        selectedID = copy.id
        save()
    }

    func delete(_ id: UUID) {
        documents.removeAll { $0.id == id }

        if documents.isEmpty {
            create()
        } else if selectedID == id {
            selectedID = documents.first?.id
        }

        save()
    }
}

// MARK: - Native Editor

struct NativeEditor: UIViewRepresentable {
    @Binding var html: String
    @Binding var editor: UITextView?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .white
        view.textColor = .black
        view.font = .systemFont(ofSize: 12)
        view.allowsEditingTextAttributes = true
        view.isScrollEnabled = true
        view.autocorrectionType = .yes
        view.spellCheckingType = .yes
        view.keyboardDismissMode = .interactive

        view.textContainerInset = UIEdgeInsets(
            top: 60,
            left: 55,
            bottom: 60,
            right: 55
        )

        if let data = html.data(using: .utf8),
           let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
           ) {
            view.attributedText = attributed
        }

        DispatchQueue.main.async {
            editor = view
        }

        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        DispatchQueue.main.async {
            editor = view
        }

        guard context.coordinator.lastHTML != html else { return }

        context.coordinator.lastHTML = html

        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else { return }

        if !view.attributedText.isEqual(to: attributed) {
            let oldSelection = view.selectedRange
            view.attributedText = attributed
            view.selectedRange = NSRange(
                location: min(oldSelection.location, attributed.length),
                length: 0
            )
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeEditor
        var lastHTML: String

        init(_ parent: NativeEditor) {
            self.parent = parent
            lastHTML = parent.html
        }

        func textViewDidChange(_ textView: UITextView) {
            let range = NSRange(
                location: 0,
                length: textView.attributedText.length
            )

            guard let data = try? textView.attributedText.data(
                from: range,
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html
                ]
            ),
            let result = String(data: data, encoding: .utf8)
            else { return }

            lastHTML = result
            parent.html = result
        }
    }
}

// MARK: - Main UI

struct ContentView: View {
    @StateObject private var store = DocumentStore()

    @State private var editor: UITextView?
    @State private var fontSize: Double = 12
    @State private var customFontNames = UIFont.familyNames.sorted()
    @State private var search = ""
    @State private var replacement = ""
    @State private var showSearch = false
    @State private var showDocuments = true
    @State private var showSettings = false
    @State private var showExport = false
    @State private var exportData = Data()
    @State private var exportName = "KodoWord"
    @State private var exportType: UTType = .html

    var body: some View {

        .onReceive(NotificationCenter.default.publisher(for: .customFontsUpdated)) { _ in
            CustomFontManager.shared.refresh()
            customFontNames = UIFont.familyNames.sorted()
        }

        NavigationStack {
            VStack(spacing: 0) {
                ribbon

                if showSearch {
                    searchPanel
                }

                HStack(spacing: 0) {
                    if showDocuments {
                        documentSidebar
                    }

                    editorPanel
                }

                statusBar
            }
            .navigationTitle("KodoWord")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        store.create()
                    } label: {
                        Image(systemName: "plus")
                    }

                    Menu {
                        Button("Export HTML") {
                            exportHTML()
                        }

                        Button("Export TXT") {
                            exportTXT()
                        }

                        Button("Export PDF") {
                            exportPDF()
                        }

                        Button("Print") {
                            printDocument()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                pageSettings
            }
            .fileExporter(
                isPresented: $showExport,
                document: ExportFile(data: exportData),
                contentType: exportType,
                defaultFilename: exportName
            ) { _ in }
        }
    }

    // MARK: Ribbon

    private var ribbon: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 20) {
                    Button("Home") {}
                    Button("Insert") {}
                    Button("Layout") {
                        showSettings = true
                    }
                    Button("Review") {
                        showSearch.toggle()
                    }
                    Button("View") {
                        showDocuments.toggle()
                    }
                }
                .font(.subheadline.bold())

                HStack(spacing: 10) {
                    Button {
                        editor?.undoManager?.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }

                    Button {
                        editor?.undoManager?.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }

                    Divider().frame(height: 25)

                    Menu("Font") {
    Button("Import Custom Font") {
        CustomFontManager.shared.chooseFontFile()
    }

    Divider()

    ForEach(customFontNames, id: \.self) { name in
        Button(name) {
            setFont(name)
        }
    }
}
Stepper(
                        "\(Int(fontSize)) pt",
                        value: $fontSize,
                        in: 6...96
                    )
                    .fixedSize()
                    .onChange(of: fontSize) { newValue in
                        editor?.applyFontSize(newValue)
                    }

                    Divider().frame(height: 25)

                    formatButton("Bold", .traitBold)
                    formatButton("Italic", .traitItalic)

                    Button {
                        if let editor = editor {
                            ImageInsertion.present(editor: editor)
                        }
                    } label: {
                        Image(systemName: "photo")
                    }

                    Menu {
                        ForEach(2...6, id: \.self) { rows in
                            Button("\(rows) × 2 Table") {
                                if let editor = editor {
                                    RichTextEngine.insertTable(
                                        into: editor,
                                        rows: rows,
                                        columns: 2
                                    )
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "tablecells")
                    }

                    Button {
                        toggleAttribute(.underlineStyle, value: 1)
                    } label: {
                        Image(systemName: "underline")
                    }

                    Button {
                        toggleAttribute(.strikethroughStyle, value: 1)
                    } label: {
                        Image(systemName: "strikethrough")
                    }

                    Button {
                        editor?.toggleHighlight()
                    } label: {
                        Image(systemName: "highlighter")
                    }

                    Button {
                        editor?.insertListPrefix("• ")
                    } label: {
                        Image(systemName: "list.bullet")
                    }

                    Button {
                        editor?.insertListPrefix("1. ")
                    } label: {
                        Image(systemName: "list.number")
                    }

                    Button {
                        editor?.clearSelectionFormatting()
                    } label: {
                        Image(systemName: "eraser")
                    }

                    Button {
                        let alert = UIAlertController(title: "Insert Link", message: "Enter URL", preferredStyle: .alert)
                        alert.addTextField { $0.placeholder = "https://example.com" }
                        alert.addAction(UIAlertAction(title: "Insert", style: .default) { _ in
                            guard let value = alert.textFields?.first?.text,
                                  let url = URL(string: value),
                                  let editor = editor else { return }
                            RichTextEngine.insertLink(into: editor, url: url)
                        })
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.windows.first?.rootViewController {
                            root.present(alert, animated: true)
                        }
                    } label: {
                        Image(systemName: "link")
                    }

                    Menu {
                        Button("Black") { setColor(.black) }
                        Button("Red") { setColor(.systemRed) }
                        Button("Blue") { setColor(.systemBlue) }
                        Button("Green") { setColor(.systemGreen) }
                    } label: {
                        Image(systemName: "textformat")
                    }

                    Menu {
                        Button("Left") { setAlignment(.left) }
                        Button("Center") { setAlignment(.center) }
                        Button("Right") { setAlignment(.right) }
                        Button("Justify") { setAlignment(.justified) }
                    } label: {
                        Image(systemName: "text.alignleft")
                    }

                    Button {
                        if let editor = editor {
                            PDFShare.present(editor: editor)
                        }
                    } label: {
                        Image(systemName: "doc.richtext")
                    }

                    Button {
                        if let editor = editor {
                            DOCXShare.present(editor: editor)
                        }
                    } label: {
                        Image(systemName: "doc")
                    }

                    Button {
                        if let editor = editor {
                            DOCXOpen.present(editor: editor)
                        }
                    } label: {
                        Image(systemName: "folder")
                    }

                    Button {
                        if let editor = editor {
                            TXTShare.present(editor: editor)
                        }
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }

                    Button {
                        showSearch.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
        }
        .background(.bar)
    }

    // MARK: Sidebar

    private var documentSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Documents").font(.headline)
                Spacer()

                Button {
                    store.create()
                } label: {
                    Image(systemName: "plus")
                }
            }

            ForEach(store.documents) { document in
                HStack {
                    Button {
                        store.selectedID = document.id
                    } label: {
                        Text(document.title)
                            .lineLimit(1)
                            .foregroundStyle(
                                store.selectedID == document.id
                                ? Color.accentColor : Color.primary
                            )
                    }

                    Spacer(minLength: 0)

                    Menu {
                        Button("Duplicate") {
                            store.duplicate(document.id)
                        }

                        Button("Delete", role: .destructive) {
                            store.delete(document.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .frame(width: 190)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: Editor

    private var editorPanel: some View {
        ScrollView {
            if let index = store.selectedIndex {
                NativeEditor(
                    html: Binding(
                        get: { store.documents[index].html },
                        set: { value in
                            store.update {
                                $0.html = value
                            }
                        }
                    ),
                    editor: $editor
                )
                .id(store.documents[index].id)
                .frame(minWidth: 550, minHeight: 750)
                .background(.white)
                .shadow(radius: 3)
                .padding(20)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: Search

    private var searchPanel: some View {
        HStack {
            TextField("Find", text: $search)
                .textFieldStyle(.roundedBorder)

            TextField("Replace", text: $replacement)
                .textFieldStyle(.roundedBorder)

            Button("Find") {
                findNext()
            }

            Button("Replace") {
                replaceAll()
            }

            Button {
                showSearch = false
            } label: {
                Image(systemName: "xmark")
            }
        }
        .padding(8)
        .background(.bar)
    }

    // MARK: Status

    private var statusBar: some View {
        HStack {
            Text("\(wordCount) words")
            Text("\(editor?.text.count ?? 0) characters")
            Spacer()
            Text("Saved")
            Text("KodoWord")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.bar)
    }

    private var wordCount: Int {
        (editor?.text ?? "").split {
            $0.isWhitespace || $0.isNewline
        }.count
    }

    // MARK: Formatting

    private func formatButton(
        _ name: String,
        _ trait: UIFontDescriptor.SymbolicTraits
    ) -> some View {
        Button {
            guard let editor else { return }

            let old = editor.typingAttributes[.font] as? UIFont
                ?? .systemFont(ofSize: fontSize)

            var traits = old.fontDescriptor.symbolicTraits

            if traits.contains(trait) {
                traits.remove(trait)
            } else {
                traits.insert(trait)
            }

            if let descriptor = old.fontDescriptor.withSymbolicTraits(traits) {
                editor.typingAttributes[.font] =
                    UIFont(descriptor: descriptor, size: old.pointSize)
            }
        } label: {
            Image(systemName: name == "Bold" ? "bold" : "italic")
        }
    }

    private func toggleAttribute(
        _ key: NSAttributedString.Key,
        value: Int
    ) {
        guard let editor else { return }

        let old = editor.typingAttributes[key] as? Int ?? 0
        editor.typingAttributes[key] = old == 0 ? value : nil
    }

    private func setFont(_ name: String) {
    guard let editor,
          let font = UIFont(name: name, size: fontSize) else { return }

    let range = editor.selectedRange

    if range.length > 0 {
        let mutable = NSMutableAttributedString(attributedString: editor.attributedText)
        mutable.addAttribute(.font, value: font, range: range)
        editor.attributedText = mutable
        editor.selectedRange = range
        editor.delegate?.textViewDidChange?(editor)
    } else {
        editor.typingAttributes[.font] = font
    }
}

    private func setColor(_ color: UIColor) {
        editor?.typingAttributes[.foregroundColor] = color
    }

    private func setAlignment(_ alignment: NSTextAlignment) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        editor?.typingAttributes[.paragraphStyle] = style
    }

    // MARK: Find & Replace

    private func findNext() {
        guard let editor, !search.isEmpty else { return }

        let text = editor.text as NSString
        let start = min(
            editor.selectedRange.location + editor.selectedRange.length,
            text.length
        )

        var range = text.range(
            of: search,
            options: [.caseInsensitive],
            range: NSRange(
                location: start,
                length: text.length - start
            )
        )

        if range.location == NSNotFound {
            range = text.range(of: search, options: [.caseInsensitive])
        }

        if range.location != NSNotFound {
            editor.selectedRange = range
            editor.becomeFirstResponder()
        }
    }

    private func replaceAll() {
        guard let editor, !search.isEmpty else { return }

        let result = editor.text.replacingOccurrences(
            of: search,
            with: replacement,
            options: [.caseInsensitive]
        )

        editor.text = result
        editor.delegate?.textViewDidChange?(editor)
    }

    // MARK: Page Settings

    private var pageSettings: some View {
        NavigationStack {
            Form {
                Picker(
                    "Paper",
                    selection: Binding(
                        get: { store.selected.paper },
                        set: { value in
                            store.update { $0.paper = value }
                        }
                    )
                ) {
                    Text("A4").tag("A4")
                    Text("Letter").tag("Letter")
                    Text("Legal").tag("Legal")
                }

                Picker(
                    "Orientation",
                    selection: Binding(
                        get: { store.selected.orientation },
                        set: { value in
                            store.update { $0.orientation = value }
                        }
                    )
                ) {
                    Text("Portrait").tag("Portrait")
                    Text("Landscape").tag("Landscape")
                }

                HStack {
                    Text("Margins")

                    Slider(
                        value: Binding(
                            get: { store.selected.margin },
                            set: { value in
                                store.update { $0.margin = value }
                            }
                        ),
                        in: 5...50
                    )

                    Text("\(Int(store.selected.margin)) mm")
                }

                TextField(
                    "Header",
                    text: Binding(
                        get: { store.selected.header },
                        set: { value in
                            store.update { $0.header = value }
                        }
                    )
                )

                TextField(
                    "Footer",
                    text: Binding(
                        get: { store.selected.footer },
                        set: { value in
                            store.update { $0.footer = value }
                        }
                    )
                )
            }
            .navigationTitle("Page Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Export

    private func prepareExport(
        _ data: Data,
        _ name: String,
        _ type: UTType
    ) {
        exportData = data
        exportName = name
        exportType = type
        showExport = true
    }

    private func exportHTML() {
        let data = Data(store.selected.html.utf8)

        prepareExport(
            data,
            store.selected.title + ".html",
            .html
        )
    }

    private func exportTXT() {
        let text = editor?.text ?? ""
        prepareExport(
            Data(text.utf8),
            store.selected.title + ".txt",
            .plainText
        )
    }

    private func exportPDF() {
        let size: CGSize = store.selected.paper == "Letter"
            ? CGSize(width: 612, height: 792)
            : CGSize(width: 595, height: 842)

        let page = CGRect(origin: .zero, size: size)
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        let data = renderer.pdfData { context in
            context.beginPage()

            let margin = store.selected.margin * 2.834
            let header = store.selected.header
            let footer = store.selected.footer

            header.draw(
                at: CGPoint(x: margin, y: 20),
                withAttributes: [.font: UIFont.systemFont(ofSize: 10)]
            )

            let text = editor?.attributedText
                ?? NSAttributedString(string: "")

            let textRect = page.insetBy(
                dx: margin,
                dy: margin + 20
            )

            text.draw(in: textRect)

            footer.draw(
                at: CGPoint(
                    x: margin,
                    y: page.height - margin
                ),
                withAttributes: [.font: UIFont.systemFont(ofSize: 10)]
            )
        }

        prepareExport(
            data,
            store.selected.title + ".pdf",
            .pdf
        )
    }

    private func printDocument() {
        let controller = UIPrintInteractionController.shared
        controller.printingItem = editor?.attributedText.string ?? ""
        controller.present(animated: true)
    }
}

// MARK: - File Exporter

struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] {
        [.html, .plainText, .pdf, .data]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
