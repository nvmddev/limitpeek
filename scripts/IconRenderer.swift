// Draws the app icon: a robot peeking over a ledge.
//
//   swift scripts/IconRenderer.swift <size> <out.png>
//
// Everything is laid out in a 1024pt design space and scaled to the requested
// size, so the same code renders every icon variant.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let design = 1024.0

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let bodyInset = 100.0
let bodyRect = CGRect(x: bodyInset, y: bodyInset,
                      width: design - 2 * bodyInset, height: design - 2 * bodyInset)
let cornerRadius = 185.0

let ledgeTop = 408.0
let cream = rgb(0.949, 0.937, 0.914)
let ink = rgb(0.106, 0.102, 0.157)
let coral = rgb(0.910, 0.510, 0.353)

func draw(into ctx: CGContext) {
    let body = CGPath(roundedRect: bodyRect, cornerWidth: cornerRadius,
                      cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(body)
    ctx.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [rgb(0.365, 0.341, 0.729), rgb(0.153, 0.137, 0.361)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: design),
                           end: CGPoint(x: 0, y: 0),
                           options: [])

    // Head, drawn first so the ledge can cut it off.
    let head = CGRect(x: 302, y: 292, width: 420, height: 408)
    ctx.setFillColor(cream)
    ctx.addPath(CGPath(roundedRect: head, cornerWidth: 112, cornerHeight: 112, transform: nil))
    ctx.fillPath()

    // Antenna.
    ctx.setFillColor(cream)
    ctx.fill(CGRect(x: 504, y: 692, width: 16, height: 96))
    ctx.setFillColor(coral)
    ctx.fillEllipse(in: CGRect(x: 476, y: 772, width: 72, height: 72))

    for eyeX in [412.0, 612.0] {
        ctx.setFillColor(ink)
        ctx.fillEllipse(in: CGRect(x: eyeX - 54, y: 506, width: 108, height: 108))
        ctx.setFillColor(rgb(1, 1, 1, 0.9))
        ctx.fillEllipse(in: CGRect(x: eyeX - 42, y: 566, width: 34, height: 34))
    }

    // The ledge occludes the lower half of the head — that is the whole trick.
    ctx.setFillColor(rgb(0.216, 0.196, 0.451))
    ctx.fill(CGRect(x: 0, y: 0, width: design, height: ledgeTop))
    ctx.setFillColor(rgb(1, 1, 1, 0.28))
    ctx.fill(CGRect(x: 0, y: ledgeTop - 12, width: design, height: 12))

    // Hands hooked over the edge.
    ctx.setFillColor(cream)
    for handX in [194.0, 734.0] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: handX, y: ledgeTop - 34, width: 96, height: 78),
                           cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.fillPath()
    }
}

let args = CommandLine.arguments
guard args.count == 3, let size = Int(args[1]) else {
    FileHandle.standardError.write(Data("usage: IconRenderer.swift <size> <out.png>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: args[2])

guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write(Data("could not create context\n".utf8))
    exit(1)
}
ctx.interpolationQuality = .high
ctx.setAllowsAntialiasing(true)
ctx.scaleBy(x: Double(size) / design, y: Double(size) / design)
draw(into: ctx)

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
    FileHandle.standardError.write(Data("could not write \(out.path)\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("could not finalize \(out.path)\n".utf8))
    exit(1)
}
