import PDFKit
import UIKit
import TCCCReports

enum DD1380FillError: Error, Equatable {
    case templateMissing
    case templateUnreadable
    case emptyOutput
}

/// Fills the official DD Form 1380 (JUN 2014) template bundled with the app
/// and flattens it. Every value comes from `DD1380OfficialForm.cardSet(for:)`
/// (TCCCKit, deterministic); this type only writes them into PDFKit widgets.
/// When Notes overflow, each further card is another copy of the official
/// form, labelled "DD 1380 #2", "#3"… above the card on both sides.
enum DD1380OfficialFormFiller {

    static func render(_ card: DD1380CardData, bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: DD1380OfficialForm.templateResource, withExtension: "pdf") else {
            throw DD1380FillError.templateMissing
        }
        let output = PDFDocument()
        for values in DD1380OfficialForm.cardSet(for: card) {
            // Each card is filled and flattened on its own copy: copies share
            // field names, and live fields with one name in one document can
            // share a value.
            guard let flat = PDFDocument(data: try fillCard(templateURL: url, values: values)) else {
                throw DD1380FillError.emptyOutput
            }
            for index in 0..<flat.pageCount {
                if let page = flat.page(at: index) { output.insert(page, at: output.pageCount) }
            }
        }
        guard output.pageCount >= 2, let data = output.dataRepresentation(), !data.isEmpty else {
            throw DD1380FillError.emptyOutput
        }
        return data
    }

    /// One card, front and back, filled and flattened.
    private static func fillCard(templateURL: URL, values: DD1380FormValues) throws -> Data {
        guard let doc = PDFDocument(url: templateURL), doc.pageCount == 2 else {
            throw DD1380FillError.templateUnreadable
        }
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            for annotation in page.annotations {
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
            if let label = values.cardLabel { stampLabel("DD 1380 \(label)", on: page) }
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

    /// "#2" label in the top margin, right-aligned to the card's edge (x ≈ 398 pt).
    private static func stampLabel(_ text: String, on page: PDFPage) {
        let height = page.bounds(for: .mediaBox).height
        let label = PDFAnnotation(bounds: CGRect(x: 248, y: height - 38, width: 150, height: 18),
                                  forType: .freeText, withProperties: nil)
        label.contents = text
        // A named PDF base font: the system font falls back to Times when burned in.
        label.font = UIFont(name: "Helvetica-Bold", size: 13) ?? UIFont.boldSystemFont(ofSize: 13)
        label.fontColor = .black
        label.color = .clear
        label.alignment = .right
        let border = PDFBorder()
        border.lineWidth = 0
        label.border = border
        page.addAnnotation(label)
    }
}
