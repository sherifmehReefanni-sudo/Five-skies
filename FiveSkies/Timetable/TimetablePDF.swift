import UIKit

/// What the PDF says about how the times were made.
struct TimetableDocumentInfo: Sendable {
    let placeLabel: String
    let methodName: String
    let asrRuleName: String
    let timeZone: TimeZone
    let locale: Locale
}

/// Draws the timetable as a US Letter portrait PDF, one page per month, with plain strings and rectangles.
enum TimetablePDF {
    static let title = "Five Skies prayer timetable"
    static let footer = "Calculated on your iPhone with the adhan-swift library. Check with your local mosque."
    /// US Letter portrait in points.
    static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

    /// The PDF bytes: one page per month in `months`.
    static func data(months: [TimetableMonth], info: TimetableDocumentInfo) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Five Skies"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let painter = TimetablePagePainter(info: info, pageCount: months.count)
        return renderer.pdfData { context in
            for (index, month) in months.enumerated() {
                context.beginPage()
                painter.draw(month, pageNumber: index + 1)
            }
        }
    }

    /// "Five Skies timetable 2026-12.pdf" or "Five Skies timetable 2026.pdf".
    static func fileName(for selection: TimetableSelection, scope: TimetableScope) -> String {
        switch scope {
        case .month:
            let month = selection.month < 10 ? "0\(selection.month)" : "\(selection.month)"
            return "Five Skies timetable \(selection.year)-\(month).pdf"
        case .year:
            return "Five Skies timetable \(selection.year).pdf"
        }
    }

    /// Renders the PDF into the temporary directory and returns its file URL.
    static func writeFile(months: [TimetableMonth], info: TimetableDocumentInfo, fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data(months: months, info: info).write(to: url, options: .atomic)
        return url
    }
}

/// Lays out one month page. Body text is 10 pt, the footer 9 pt.
private struct TimetablePagePainter {
    let info: TimetableDocumentInfo
    let pageCount: Int

    let margin: CGFloat = 40
    let rowHeight: CGFloat = 17
    let headerHeight: CGFloat = 20
    let dateWidth: CGFloat = 84
    let hijriWidth: CGFloat = 52

    let ink = UIColor(red: 0.08, green: 0.07, blue: 0.16, alpha: 1)
    let indigo = UIColor(red: 0x2B / 255, green: 0x2A / 255, blue: 0x7A / 255, alpha: 1)
    let muted = UIColor(red: 0.33, green: 0.32, blue: 0.42, alpha: 1)
    let zebra = UIColor(red: 0.94, green: 0.94, blue: 0.98, alpha: 1)

    var contentWidth: CGFloat {
        TimetablePDF.pageRect.width - margin * 2
    }

    func draw(_ month: TimetableMonth, pageNumber: Int) {
        let timeFormat = TimetableTimeFormat(timeZone: info.timeZone, locale: info.locale, includesPeriod: true)
        let left = margin
        var y = margin

        drawText(TimetablePDF.title, in: CGRect(x: left, y: y, width: contentWidth, height: 26),
                 font: .systemFont(ofSize: 20, weight: .heavy), color: indigo, alignment: .left)
        y += 32

        let infoLines = [
            "Place: \(info.placeLabel)",
            "Time zone: \(info.timeZone.identifier)",
            "Calculation method: \(info.methodName)",
            "Asr: \(info.asrRuleName)"
        ]
        for line in infoLines {
            drawText(line, in: CGRect(x: left, y: y, width: contentWidth, height: 14),
                     font: .systemFont(ofSize: 10, weight: .regular), color: muted, alignment: .left)
            y += 14
        }
        y += 10

        drawText(month.title, in: CGRect(x: left, y: y, width: contentWidth * 0.5, height: 22),
                 font: .systemFont(ofSize: 15, weight: .bold), color: ink, alignment: .left)
        drawText(month.hijriTitle, in: CGRect(x: left + contentWidth * 0.5, y: y, width: contentWidth * 0.5, height: 22),
                 font: .systemFont(ofSize: 10, weight: .semibold), color: muted, alignment: .right)
        y += 26

        let columns = columnFrames(left: left)
        fill(CGRect(x: left, y: y, width: contentWidth, height: headerHeight), color: indigo)
        let headerFont = UIFont.systemFont(ofSize: 10, weight: .bold)
        for (index, title) in TimetableBuilder.columnTitles.enumerated() where index < columns.count {
            let frame = columns[index]
            drawText(title, in: CGRect(x: frame.minX, y: y, width: frame.width, height: headerHeight),
                     font: headerFont, color: .white, alignment: index == 0 ? .left : .center, inset: 6)
        }
        y += headerHeight

        let bodyFont = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let dateFont = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        for (rowIndex, row) in month.rows.enumerated() {
            let rowRect = CGRect(x: left, y: y, width: contentWidth, height: rowHeight)
            if rowIndex % 2 == 1 {
                fill(rowRect, color: zebra)
            }
            var cells = ["\(row.weekdayName) \(row.gregorianDay)", "\(row.hijriDay)"]
            cells.append(contentsOf: row.times.map { timeFormat.string($0) })
            for (index, text) in cells.enumerated() where index < columns.count {
                let frame = columns[index]
                drawText(text, in: CGRect(x: frame.minX, y: y, width: frame.width, height: rowHeight),
                         font: index == 0 ? dateFont : bodyFont,
                         color: index == 1 ? muted : ink,
                         alignment: index == 0 ? .left : .center,
                         inset: 6)
            }
            y += rowHeight
        }
        fill(CGRect(x: left, y: y, width: contentWidth, height: 1), color: indigo)

        let footerY = TimetablePDF.pageRect.height - margin - 14
        let footerFont = UIFont.systemFont(ofSize: 9, weight: .regular)
        drawText(TimetablePDF.footer, in: CGRect(x: left, y: footerY, width: contentWidth - 70, height: 14),
                 font: footerFont, color: muted, alignment: .left)
        drawText("Page \(pageNumber) of \(pageCount)", in: CGRect(x: left + contentWidth - 70, y: footerY, width: 70, height: 14),
                 font: footerFont, color: muted, alignment: .right)
    }

    /// Date, Hijri, then six equal time columns across the content width.
    private func columnFrames(left: CGFloat) -> [CGRect] {
        let timeWidth = (contentWidth - dateWidth - hijriWidth) / 6
        var frames = [
            CGRect(x: left, y: 0, width: dateWidth, height: 0),
            CGRect(x: left + dateWidth, y: 0, width: hijriWidth, height: 0)
        ]
        for index in 0..<6 {
            frames.append(CGRect(x: left + dateWidth + hijriWidth + CGFloat(index) * timeWidth, y: 0, width: timeWidth, height: 0))
        }
        return frames
    }

    private func fill(_ rect: CGRect, color: UIColor) {
        color.setFill()
        UIBezierPath(rect: rect).fill()
    }

    /// One line of text, vertically centred in `rect`, truncated if it is too long.
    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment,
        inset: CGFloat = 0
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let lineHeight = ceil(font.lineHeight)
        let textRect = CGRect(
            x: rect.minX + inset,
            y: rect.minY + (rect.height - lineHeight) / 2,
            width: max(0, rect.width - inset * 2),
            height: lineHeight
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
