import UIKit
import TCCCReports

enum DD1380RenderError: Error { case emptyOutput }

/// Vector-rendered DD Form 1380 layout.
///
/// ⚠️ FALLBACK renderer — this is a clean, legible facsimile-style layout, NOT
/// the official DD Form 1380 PDF template (none is bundled in the app target).
/// Every value comes from `DD1380CardData` (deterministically mapped from
/// structured state); the renderer invents nothing. Two pages: front (§A–C),
/// back (§D–H). Layout constants live in `L` so coordinates are centralized.
enum DD1380PDFRenderer {

    static func render(_ card: DD1380CardData) throws -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: L.page)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            drawFront(card)
            ctx.beginPage()
            drawBack(card)
        }
        guard !data.isEmpty else { throw DD1380RenderError.emptyOutput }
        return data
    }

    // MARK: - Layout constants (centralized field map)

    private enum L {
        static let page = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter
        static let margin: CGFloat = 36
        static var contentWidth: CGFloat { page.width - margin * 2 }
        static var right: CGFloat { page.width - margin }

        static let banner = UIFont.boldSystemFont(ofSize: 11)
        static let title = UIFont.boldSystemFont(ofSize: 14)
        static let section = UIFont.boldSystemFont(ofSize: 10)
        static let label = UIFont.boldSystemFont(ofSize: 7.5)
        static let value = UIFont.systemFont(ofSize: 9.5)
        static let small = UIFont.systemFont(ofSize: 8)
        static let mono = UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)

        static let ink = UIColor.black
        static let muted = UIColor.darkGray
        static let rule = UIColor(white: 0.55, alpha: 1)
    }

    // MARK: - Pages

    private static func drawFront(_ card: DD1380CardData) {
        var y = L.margin
        y = drawBanner(top: y)
        drawText("DD FORM 1380 — TCCC CASUALTY CARD", at: CGPoint(x: L.margin, y: y), font: L.title)
        y += 22

        // §A header
        y = sectionHeader("A · HEADER", y: y)
        y = row([("BATTLE ROSTER #", card.battleRosterNumber),
                 ("EVAC", card.evacCategory?.rawValue ?? ""),
                 ("GENDER", card.sex?.rawValue ?? "")], y: y)
        y = row([("NAME (Last, First)", card.nameLastFirst),
                 ("LAST 4", card.last4)], y: y)
        y = row([("DATE", card.dateDDMMMYY),
                 ("TIME", card.timeHHMM),
                 ("SERVICE", card.service)], y: y)
        y = row([("UNIT", card.unit),
                 ("ALLERGIES", card.allergies)], y: y)
        y += 6

        // §B mechanism / injury / tourniquets
        y = sectionHeader("B · MECHANISM OF INJURY", y: y)
        let m = card.mechanisms
        y = checkboxRow([("Artillery", m.artillery), ("Blunt", m.blunt), ("Burn", m.burn),
                         ("Fall", m.fall), ("Grenade", m.grenade), ("GSW", m.gsw)], y: y)
        y = checkboxRow([("IED", m.ied), ("Landmine", m.landmine), ("MVC", m.mvc),
                         ("RPG", m.rpg), ("Other", m.other)], y: y)
        if m.other, !m.otherText.isEmpty {
            y = labeled("Other (specify)", m.otherText, y: y)
        }
        y += 4
        drawText("TOURNIQUETS", at: CGPoint(x: L.margin, y: y), font: L.label, color: L.muted)
        y += 11
        if card.tourniquets.isEmpty {
            y = valueLine("—", y: y)
        } else {
            for tq in card.tourniquets {
                let loc = tq.limb?.rawValue ?? (tq.locationText ?? "—")
                let parts = ["Loc: \(loc)", "Type: \(tq.type ?? "—")", "Time: \(tq.timeHHMM ?? "—")"]
                y = valueLine(parts.joined(separator: "    "), y: y)
            }
        }
        y += 6

        // §C vitals grid
        y = sectionHeader("C · SIGNS & SYMPTOMS", y: y)
        drawSectionCGrid(card.sectionCReadings, top: y)

        drawFooter(page: "FRONT · 1 of 2", casualtyHint: card.nameLastFirst)
    }

    private static func drawBack(_ card: DD1380CardData) {
        var y = L.margin
        y = drawBanner(top: y)

        // §D header repeat
        y = sectionHeader("D · HEADER (repeat)", y: y)
        y = row([("BATTLE ROSTER #", card.battleRosterNumber),
                 ("EVAC", card.evacCategory?.rawValue ?? "")], y: y)
        y += 6

        // §E treatments
        y = sectionHeader("E · TREATMENTS", y: y)
        let t = card.treatments
        y = checkboxRow([("TQ Extremity", t.tqExtremity), ("TQ Junctional", t.tqJunctional),
                         ("TQ Truncal", t.tqTruncal)], y: y)
        y = checkboxRow([("Dressing Hemostatic", t.dressingHemostatic),
                         ("Pressure", t.dressingPressure), ("Other", t.dressingOther)], y: y)
        y = checkboxRow([("Airway Intact", t.airwayIntact), ("NPA", t.airwayNPA),
                         ("CRIC", t.airwayCRIC), ("ET-Tube", t.airwayETTube), ("SGA", t.airwaySGA)], y: y)
        y = checkboxRow([("O2", t.breathingO2), ("Needle-D", t.breathingNeedleD),
                         ("Chest-Tube", t.breathingChestTube), ("Chest-Seal", t.breathingChestSeal)], y: y)
        y = treatmentRows("FLUIDS", card.fluids, y: y)
        y = treatmentRows("BLOOD PRODUCTS", card.bloodProducts, y: y)
        y += 6

        // §F meds + other
        y = sectionHeader("F · MEDICATIONS & OTHER", y: y)
        if card.medications.isEmpty {
            y = valueLine("Meds: —", y: y)
        } else {
            for med in card.medications {
                let parts = ["[\(med.category.rawValue.uppercased())] \(med.name)",
                             "Dose: \(med.dose ?? "—")", "Route: \(med.route ?? "—")",
                             "Time: \(med.timeHHMM ?? "—")"]
                y = valueLine(parts.joined(separator: "   "), y: y)
            }
        }
        let o = card.otherTreatments
        y += 2
        y = checkboxRow([("Combat-Pill-Pack", o.combatPillPack), ("Eye-Shield R", o.eyeShieldRight),
                         ("Eye-Shield L", o.eyeShieldLeft), ("Splint", o.splint),
                         ("Hypothermia-Prev", o.hypothermiaPrevention)], y: y)
        if o.hypothermiaPrevention, !o.hypothermiaType.isEmpty {
            y = labeled("Hypothermia type", o.hypothermiaType, y: y)
        }
        y += 6

        // §G notes
        y = sectionHeader("G · NOTES", y: y)
        y = drawNotes(card.notes, top: y)
        y += 6

        // §H responder
        y = sectionHeader("H · FIRST RESPONDER", y: y)
        y = row([("NAME (Last, First)", card.firstResponderName),
                 ("LAST 4", card.firstResponderLast4)], y: y)

        drawFooter(page: "BACK · 2 of 2", casualtyHint: card.nameLastFirst)
    }

    // MARK: - Primitives

    private static func drawBanner(top: CGFloat) -> CGFloat {
        let rect = CGRect(x: L.margin, y: top, width: L.contentWidth, height: 16)
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: rect).fill()
        drawText("FALLBACK LAYOUT · NOT AN OFFICIAL DD FORM 1380 FACSIMILE · CUI WHEN FILLED",
                 at: CGPoint(x: L.margin + 4, y: top + 3), font: L.banner, color: L.muted)
        return top + 22
    }

    private static func sectionHeader(_ title: String, y: CGFloat) -> CGFloat {
        hline(at: y)
        drawText(title, at: CGPoint(x: L.margin, y: y + 3), font: L.section)
        return y + 18
    }

    /// A row of label/value cells spread across the content width.
    private static func row(_ cells: [(String, String)], y: CGFloat) -> CGFloat {
        guard !cells.isEmpty else { return y }
        let cellW = L.contentWidth / CGFloat(cells.count)
        for (i, cell) in cells.enumerated() {
            let x = L.margin + cellW * CGFloat(i)
            drawText(cell.0, at: CGPoint(x: x, y: y), font: L.label, color: L.muted)
            drawText(cell.1.isEmpty ? "—" : cell.1,
                     at: CGPoint(x: x, y: y + 9), font: L.value,
                     maxWidth: cellW - 6)
        }
        return y + 24
    }

    private static func labeled(_ label: String, _ value: String, y: CGFloat) -> CGFloat {
        drawText(label, at: CGPoint(x: L.margin, y: y), font: L.label, color: L.muted)
        drawText(value, at: CGPoint(x: L.margin, y: y + 9), font: L.value, maxWidth: L.contentWidth)
        return y + 22
    }

    private static func valueLine(_ value: String, y: CGFloat) -> CGFloat {
        drawText(value, at: CGPoint(x: L.margin, y: y), font: L.mono, maxWidth: L.contentWidth)
        return y + 13
    }

    /// Checkboxes flowed left→right, wrapping is the caller's job (fixed rows).
    private static func checkboxRow(_ boxes: [(String, Bool)], y: CGFloat) -> CGFloat {
        var x = L.margin
        for (title, checked) in boxes {
            let boxRect = CGRect(x: x, y: y + 1, width: 9, height: 9)
            let path = UIBezierPath(rect: boxRect)
            L.rule.setStroke(); path.lineWidth = 0.8; path.stroke()
            if checked {
                drawText("X", at: CGPoint(x: x + 1.2, y: y - 1.5), font: L.label, color: L.ink)
            }
            let labelX = x + 13
            drawText(title, at: CGPoint(x: labelX, y: y), font: L.small)
            let w = title.size(withAttributes: [.font: L.small]).width
            x = labelX + w + 14
            if x > L.right - 40 { /* let it run; rows are pre-sized */ }
        }
        return y + 16
    }

    private static func treatmentRows(_ title: String, _ entries: [DD1380FluidEntry], y: CGFloat) -> CGFloat {
        var yy = y
        drawText(title, at: CGPoint(x: L.margin, y: yy), font: L.label, color: L.muted)
        yy += 11
        if entries.isEmpty {
            yy = valueLine("—", y: yy)
        } else {
            for e in entries {
                let parts = [e.name, "Vol: \(e.volume ?? "—")", "Route: \(e.route ?? "—")", "Time: \(e.timeHHMM ?? "—")"]
                yy = valueLine(parts.joined(separator: "   "), y: yy)
            }
        }
        return yy + 2
    }

    private static func drawSectionCGrid(_ readings: [DD1380SectionCReading], top: CGFloat) {
        let rows = ["Time", "Pulse", "BP", "RR", "SpO2", "AVPU", "Pain"]
        let labelW: CGFloat = 70
        let colCount = 4
        let colW = (L.contentWidth - labelW) / CGFloat(colCount)
        let rowH: CGFloat = 16
        var y = top

        func cell(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, font: UIFont, bold: Bool = false) {
            drawText(text, at: CGPoint(x: x + 3, y: y + 3), font: bold ? L.label : L.mono, maxWidth: w - 6)
        }

        // header row
        cell("READING", x: L.margin, y: y, w: labelW, font: L.label, bold: true)
        for c in 0..<colCount {
            let x = L.margin + labelW + colW * CGFloat(c)
            cell("#\(c + 1)", x: x, y: y, w: colW, font: L.label, bold: true)
        }
        y += rowH

        for (ri, rowLabel) in rows.enumerated() {
            // grid lines
            L.rule.setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: L.margin, y: y)); line.addLine(to: CGPoint(x: L.right, y: y))
            line.lineWidth = 0.4; line.stroke()

            cell(rowLabel, x: L.margin, y: y, w: labelW, font: L.label, bold: true)
            for c in 0..<colCount {
                let x = L.margin + labelW + colW * CGFloat(c)
                let val = readings.indices.contains(c) ? valueFor(row: ri, reading: readings[c]) : ""
                cell(val, x: x, y: y, w: colW, font: L.mono)
            }
            y += rowH
        }
        // column separators
        L.rule.setStroke()
        for c in 0...colCount {
            let x = L.margin + labelW + colW * CGFloat(c)
            let v = UIBezierPath()
            v.move(to: CGPoint(x: x, y: top + rowH)); v.addLine(to: CGPoint(x: x, y: y))
            v.lineWidth = 0.4; v.stroke()
        }
    }

    private static func valueFor(row: Int, reading r: DD1380SectionCReading) -> String {
        switch row {
        case 0: return r.timeHHMM
        case 1: return r.pulse ?? ""
        case 2: return r.bloodPressure ?? ""
        case 3: return r.respiratoryRate ?? ""
        case 4: return r.spo2 ?? ""
        case 5: return r.avpu ?? ""
        case 6: return r.pain ?? ""
        default: return ""
        }
    }

    private static func drawNotes(_ notes: String, top: CGFloat) -> CGFloat {
        let text = notes.isEmpty ? "—" : notes
        // Bounded rect clips/wraps deterministically; back-page notes get ~6 lines.
        let rect = CGRect(x: L.margin, y: top, width: L.contentWidth, height: 90)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: L.value, .foregroundColor: L.ink, .paragraphStyle: style,
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
        return top + 92
    }

    private static func drawFooter(page: String, casualtyHint: String) {
        let y = L.page.height - L.margin
        hline(at: y - 4)
        drawText("DD-1380 (fallback) · \(page)", at: CGPoint(x: L.margin, y: y), font: L.small, color: L.muted)
        let hint = casualtyHint.isEmpty ? "" : "Casualty: \(casualtyHint)"
        let w = hint.size(withAttributes: [.font: L.small]).width
        drawText(hint, at: CGPoint(x: L.right - w, y: y), font: L.small, color: L.muted)
    }

    // MARK: - Text helpers

    private static func drawText(_ text: String, at point: CGPoint, font: UIFont,
                                 color: UIColor = L.ink, maxWidth: CGFloat? = nil) {
        guard !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let maxWidth {
            let rect = CGRect(x: point.x, y: point.y, width: maxWidth, height: font.lineHeight + 2)
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
            var a = attrs; a[.paragraphStyle] = style
            (text as NSString).draw(in: rect, withAttributes: a)
        } else {
            (text as NSString).draw(at: point, withAttributes: attrs)
        }
    }

    private static func hline(at y: CGFloat) {
        L.rule.setStroke()
        let p = UIBezierPath()
        p.move(to: CGPoint(x: L.margin, y: y)); p.addLine(to: CGPoint(x: L.right, y: y))
        p.lineWidth = 0.6; p.stroke()
    }
}
