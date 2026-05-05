import Foundation
import MapKit
import UIKit
import UnpluggedShared

enum ShareRecapImageRenderer {
    private static let canvasWidth: CGFloat = 1080
    private static let primaryColor = UIColor(red: 0, green: 53.0 / 255.0, blue: 107.0 / 255.0, alpha: 1)
    private static let surfaceColor = UIColor(red: 0, green: 40.0 / 255.0, blue: 82.0 / 255.0, alpha: 1)
    private static let secondaryColor = UIColor(red: 135.0 / 255.0, green: 193.0 / 255.0, blue: 168.0 / 255.0, alpha: 1)
    private static let whiteColor = UIColor.white
    private static let mutedWhiteColor = UIColor.white.withAlphaComponent(0.68)
    private static let destructiveColor = UIColor(red: 220.0 / 255.0, green: 53.0 / 255.0, blue: 69.0 / 255.0, alpha: 1)

    static func renderPNGData(for recap: SessionRecapResponse) async throws -> Data {
        let mapImageData = await mapSnapshotImage(for: recap)?.pngData()

        return try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true

                let mapImage = mapImageData.flatMap(UIImage.init(data:))
                let canvasSize = canvasSize(for: recap, includesMap: mapImage != nil)
                let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
                let image = renderer.image { context in
                    drawBackground(in: context.cgContext, size: canvasSize)
                    drawCard(for: recap, mapImage: mapImage, in: context.cgContext, canvasSize: canvasSize)
                }

                guard let data = image.pngData() else {
                    throw ShareRecapImageRendererError.encodingFailed
                }
                return data
            }
        }.value
    }

    private static func canvasSize(for recap: SessionRecapResponse, includesMap: Bool) -> CGSize {
        let cardWidth = canvasWidth - 128
        let chipRows = chipRowCount(
            for: chipLabels(for: recap),
            availableWidth: cardWidth - 112
        )

        var contentHeight: CGFloat = 52
        if hasMemoryImageData(in: recap) {
            contentHeight += 430 + 40
        }
        if includesMap {
            contentHeight += 300 + 40
        }
        contentHeight += 54
        contentHeight += 92
        contentHeight += 142
        contentHeight += 60

        if hasDescription(in: recap) {
            contentHeight += 124
        }

        if chipRows > 0 {
            contentHeight += CGFloat(chipRows) * 54
            contentHeight += CGFloat(chipRows - 1) * 16
        }
        contentHeight += 52

        let height = min(max(contentHeight + 128, 704), 1700)
        return CGSize(width: canvasWidth, height: ceil(height))
    }

    private static func drawBackground(in context: CGContext, size: CGSize) {
        primaryColor.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }

    private static func drawCard(
        for recap: SessionRecapResponse,
        mapImage: UIImage?,
        in context: CGContext,
        canvasSize: CGSize
    ) {
        let cardRect = CGRect(x: 64, y: 64, width: canvasSize.width - 128, height: canvasSize.height - 128)
        surfaceColor.setFill()
        UIBezierPath(roundedRect: cardRect, cornerRadius: 40).fill()

        var y = cardRect.minY + 52
        if let image = firstMemoryImage(from: recap) {
            let photoRect = CGRect(x: cardRect.minX + 40, y: y, width: cardRect.width - 80, height: 430)
            drawImage(image, aspectFillIn: photoRect, cornerRadius: 28, context: context)
            y = photoRect.maxY + 40
        }
        if let mapImage {
            let mapRect = CGRect(x: cardRect.minX + 40, y: y, width: cardRect.width - 80, height: 300)
            drawImage(mapImage, aspectFillIn: mapRect, cornerRadius: 28, context: context)
            drawMapPin(in: mapRect)
            y = mapRect.maxY + 40
        }

        drawText(
            "UNPLUGGED",
            in: CGRect(x: cardRect.minX + 56, y: y, width: 360, height: 36),
            font: .systemFont(ofSize: 28, weight: .bold),
            color: mutedWhiteColor,
            kern: 2
        )

        drawStatus(recap, cardRect: cardRect, y: y)
        y += 54

        let title = recap.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        drawText(
            title?.isEmpty == false ? title! : "Unplugged Session",
            in: CGRect(x: cardRect.minX + 56, y: y, width: cardRect.width - 112, height: 74),
            font: .systemFont(ofSize: 46, weight: .semibold),
            color: whiteColor
        )
        y += 92

        drawText(
            TimeInterval(recap.actualFocusedSeconds).humanReadable,
            in: CGRect(x: cardRect.minX + 56, y: y, width: cardRect.width - 112, height: 150),
            font: .systemFont(ofSize: 126, weight: .bold),
            color: whiteColor
        )
        y += 142

        drawText(
            "Time Locked In",
            in: CGRect(x: cardRect.minX + 60, y: y, width: cardRect.width - 120, height: 42),
            font: .systemFont(ofSize: 30, weight: .semibold),
            color: mutedWhiteColor
        )
        y += 60

        if let description = recap.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            let rect = CGRect(x: cardRect.minX + 56, y: y, width: cardRect.width - 112, height: 118)
            drawText(
                description,
                in: rect,
                font: .systemFont(ofSize: 30, weight: .regular),
                color: UIColor.white.withAlphaComponent(0.82)
            )
            y += 124
        }

        _ = drawChips(for: recap, cardRect: cardRect, y: y)
    }

    private static func mapSnapshotImage(for recap: SessionRecapResponse) async -> UIImage? {
        guard let latitude = recap.latitude,
              let longitude = recap.longitude,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        options.size = CGSize(width: canvasWidth - 208, height: 300)
        options.scale = 2
        options.mapType = .standard

        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start(with: DispatchQueue.global(qos: .userInitiated)) { snapshot, _ in
                continuation.resume(returning: snapshot?.image)
            }
        }
    }

    private static func drawStatus(_ recap: SessionRecapResponse, cardRect: CGRect, y: CGFloat) {
        let text = recap.endedEarly ? "ENDED EARLY" : "COMPLETED"
        let color = recap.endedEarly ? destructiveColor : secondaryColor
        let font = UIFont.systemFont(ofSize: 24, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: primaryColor
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let rect = CGRect(
            x: cardRect.maxX - textSize.width - 96,
            y: y - 4,
            width: textSize.width + 40,
            height: 42
        )
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
        (text as NSString).draw(
            in: rect.insetBy(dx: 20, dy: 7),
            withAttributes: attributes
        )
    }

    @discardableResult
    private static func drawChips(for recap: SessionRecapResponse, cardRect: CGRect, y: CGFloat) -> CGFloat {
        var currentX = cardRect.minX + 56
        var currentY = y
        let maxX = cardRect.maxX - 56
        let chipSpacing: CGFloat = 14
        let rowSpacing: CGFloat = 16
        let chipHeight: CGFloat = 54

        let chips = chipLabels(for: recap)
        for chip in chips {
            let width = chipWidth(for: chip)
            if currentX + width > maxX {
                currentX = cardRect.minX + 56
                currentY += chipHeight + rowSpacing
            }

            drawChip(chip, rect: CGRect(x: currentX, y: currentY, width: width, height: chipHeight))
            currentX += width + chipSpacing
        }

        return currentY + chipHeight
    }

    private static func chipLabels(for recap: SessionRecapResponse) -> [String] {
        var labels = [
            "\(recap.participants.count) \(recap.participants.count == 1 ? "member" : "members")",
            "\(recap.jailbreaks.count) \(recap.jailbreaks.count == 1 ? "break" : "breaks")",
            plannedLabel(for: recap)
        ]
        if recap.durationSeconds != nil {
            labels.append("\(Int((recap.completionRate * 100).rounded()))% complete")
        }
        if let weather = recap.weather {
            labels.append(weatherLabel(weather))
        }
        if recap.latitude != nil, recap.longitude != nil {
            labels.append("Location added")
        }
        return labels
    }

    private static func chipWidth(for text: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 25, weight: .semibold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return min(max(width + 42, 128), 420)
    }

    private static func chipRowCount(for labels: [String], availableWidth: CGFloat) -> Int {
        guard !labels.isEmpty else { return 0 }

        var rows = 1
        var currentWidth: CGFloat = 0
        let chipSpacing: CGFloat = 14

        for label in labels {
            let width = chipWidth(for: label)
            let proposedWidth = currentWidth == 0 ? width : currentWidth + chipSpacing + width
            if proposedWidth > availableWidth, currentWidth > 0 {
                rows += 1
                currentWidth = width
            } else {
                currentWidth = proposedWidth
            }
        }

        return rows
    }

    private static func drawChip(_ text: String, rect: CGRect) {
        UIColor.white.withAlphaComponent(0.12).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
        drawText(
            text,
            in: rect.insetBy(dx: 21, dy: 12),
            font: .systemFont(ofSize: 25, weight: .semibold),
            color: UIColor.white.withAlphaComponent(0.82)
        )
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        kern: CGFloat = 0
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: kern
        ]
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: attributes,
            context: nil
        )
    }

    private static func drawImage(
        _ image: UIImage,
        aspectFillIn rect: CGRect,
        cornerRadius: CGFloat,
        context: CGContext
    ) {
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        image.draw(in: CGRect(origin: origin, size: size))
        context.restoreGState()
    }

    private static func drawMapPin(in rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let shadowRect = CGRect(x: center.x - 28, y: center.y + 16, width: 56, height: 16)
        UIColor.black.withAlphaComponent(0.28).setFill()
        UIBezierPath(ovalIn: shadowRect).fill()

        let pinRect = CGRect(x: center.x - 26, y: center.y - 58, width: 52, height: 52)
        destructiveColor.setFill()
        UIBezierPath(ovalIn: pinRect).fill()

        let point = UIBezierPath()
        point.move(to: CGPoint(x: center.x, y: center.y + 22))
        point.addLine(to: CGPoint(x: center.x - 15, y: center.y - 14))
        point.addLine(to: CGPoint(x: center.x + 15, y: center.y - 14))
        point.close()
        destructiveColor.setFill()
        point.fill()

        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: center.x - 9, y: center.y - 41, width: 18, height: 18)).fill()
    }

    private static func firstMemoryImage(from recap: SessionRecapResponse) -> UIImage? {
        recap.memoryPhotos
            .lazy
            .compactMap(\.thumbnailData)
            .compactMap(UIImage.init(data:))
            .first
    }

    private static func hasMemoryImageData(in recap: SessionRecapResponse) -> Bool {
        recap.memoryPhotos.contains { $0.thumbnailData != nil }
    }

    private static func hasDescription(in recap: SessionRecapResponse) -> Bool {
        guard let description = recap.description?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !description.isEmpty
    }

    private static func plannedLabel(for recap: SessionRecapResponse) -> String {
        guard let duration = recap.durationSeconds else {
            return "\(TimeInterval(recap.actualFocusedSeconds).humanReadable) locked"
        }
        return "\(TimeInterval(duration).humanReadable) planned"
    }

    private static func weatherLabel(_ weather: SessionWeatherSnapshot) -> String {
        if let temp = weather.temperatureFahrenheit {
            return "\(Int(temp.rounded()))°F \(weather.summary)"
        }
        return weather.summary
    }
}

private enum ShareRecapImageRendererError: Error {
    case encodingFailed
}
