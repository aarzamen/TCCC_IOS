import PDFKit
import UIKit
import TCCCReports

enum DD1380FillError: Error, Equatable {
    case templateMissing
    case templateUnreadable
    case emptyOutput
}

/// Fills the official DD Form 1380 (JUN 2014) template bundled with the app
/// and flattens it. Every value comes from `DD1380OfficialForm.values(for:)`
/// (TCCCKit, deterministic); this type only writes them into PDFKit widgets.
/// Notes that do not fit the box are printed on an extra page after the back.
enum DD1380OfficialFormFiller {

    /// Continuation page capacity at 10 pt in a 528 × 660 pt text area.
    static let continuationCharsPerLine = 95
    static let continuationMaxLines = 50

    static func render(_ card: DD1380CardData, bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: DD1380OfficialForm.templateResource, withExtension: "pdf") else {
            throw DD1380FillError.templateMissing
        }
        guard let doc = PDFDocument(url: url), doc.pageCount == 2 else {
            throw DD1380FillError.templateUnreadable
        }
        let values = DD1380OfficialForm.values(for: card)
        for index in 0..<doc.pageCount {
            for annotation in doc.page(at: index)?.annotations ?? [] {
                guard annotation.type == "Widget", let name = annotation.fieldName else { continue }
                switch annotation.widgetFieldType {
                case .text:
                    let value = values.text[name] ?? ""
                    if name == "notes" {
                        annotation.isMultiline = true
                    } else {
                        shrinkToFit(annotation, value)
                    }
                    annotation.widgetStringValue = value
                case .button:
                    annotation.buttonWidgetState = values.checked.contains(name) ? .onState : .offState
                default:
                    continue
                }
            }
        }
        // As many continuation pages as the overflow needs, each ending in the marker but the last.
        var remaining = values.continuationNotes
        while let text = remaining {
            let split = DD1380OfficialForm.splitNotes(text, charsPerLine: continuationCharsPerLine,
                                                      maxLines: continuationMaxLines)
            guard let page = continuationPage(card: card, notes: split.onForm) else { break }
            doc.insert(page, at: doc.pageCount)
            remaining = split.overflow
        }
        guard let data = doc.dataRepresentation(options: [PDFDocumentWriteOption.burnInAnnotationsOption: true]),
              !data.isEmpty else {
            throw DD1380FillError.emptyOutput
        }
        return data
    }

    /// Several boxes are narrow (systolic BP is 20 pt wide). Shrink the font,
    /// down to 5 pt, rather than let the flattened value run past the box.
    private static func shrinkToFit(_ annotation: PDFAnnotation, _ value: String) {
        guard !value.isEmpty, var font = annotation.font else { return }
        // PDFKit insets widget text about 3 pt on each side (measured on a render).
        let available = annotation.bounds.width - 7
        while font.pointSize > 5,
              (value as NSString).size(withAttributes: [.font: font]).width > available {
            font = font.withSize(font.pointSize - 0.5)
        }
        annotation.font = font
    }

    /// One US-Letter page carrying the rest of Notes, identified by BR#, name and date.
    private static func continuationPage(card: DD1380CardData, notes: String) -> PDFPage? {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 42
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            ctx.beginPage()
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13)]
            let label: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10),
                                                        .foregroundColor: UIColor.darkGray]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10)]
            "\(DD1380OfficialForm.edition) — NOTES (continued)".draw(at: CGPoint(x: margin, y: margin), withAttributes: title)
            let identity = [("BATTLE ROSTER #", card.battleRosterNumber), ("NAME", card.nameLastFirst),
                            ("DATE", card.dateDDMMMYY)]
                .map { "\($0.0): \($0.1.isEmpty ? "—" : $0.1)" }
                .joined(separator: "     ")
            identity.draw(at: CGPoint(x: margin, y: margin + 22), withAttributes: label)
            notes.draw(in: CGRect(x: margin, y: margin + 48, width: bounds.width - margin * 2,
                                  height: bounds.height - margin * 2 - 48), withAttributes: body)
        }
        return PDFDocument(data: data)?.page(at: 0)
    }
}
