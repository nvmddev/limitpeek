import SwiftUI

/// The app icon in one colour: the robot's head and hands over the ledge, eyes
/// punched out. The numbers are the 1024pt design space
/// `scripts/IconRenderer.swift` draws in, flipped into SwiftUI's y-down
/// coordinates, so the glyph and the icon stay the same mark. Change one and
/// the other needs the same edit.
struct AppGlyph: Shape {
    /// Tighter than the icon's 1024pt square: the rounded body and the padding
    /// around it are the icon's frame, not part of the drawing.
    private static let designBox = CGRect(x: 194, y: 180, width: 636, height: 522)
    private static let ledgeTop = 616.0

    static let aspectRatio = designBox.width / designBox.height

    func path(in rect: CGRect) -> Path {
        let box = Self.designBox
        let scale = min(rect.width / box.width, rect.height / box.height)
        let fit = CGAffineTransform(translationX: rect.midX - box.midX * scale,
                                    y: rect.midY - box.midY * scale)
            .scaledBy(x: scale, y: scale)
        return Self.design.applying(fit)
    }

    private static var design: Path {
        var path = Path()

        // Head, cut flat where the ledge crosses it — the peeking trick.
        path.addPath(roundedTop(CGRect(x: 302, y: 324, width: 420, height: ledgeTop - 324),
                                radius: 112))

        // Antenna.
        path.addRect(CGRect(x: 504, y: 236, width: 16, height: 96))
        path.addEllipse(in: CGRect(x: 476, y: 180, width: 72, height: 72))

        // The ledge, with the hands hooked over its edge.
        path.addRect(CGRect(x: 194, y: ledgeTop, width: 636, height: 86))
        for handX in [194.0, 734.0] {
            path.addPath(roundedTop(CGRect(x: handX, y: 572, width: 96, height: ledgeTop - 572),
                                    radius: 34))
        }

        // Holes, because the eyes are the dark of the icon, not the light.
        var eyes = Path()
        for eyeX in [412.0, 612.0] {
            eyes.addEllipse(in: CGRect(x: eyeX - 54, y: 410, width: 108, height: 108))
        }
        return path.subtracting(eyes)
    }

    private static func roundedTop(_ rect: CGRect, radius: Double) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                              control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                              control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
