import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private func makeColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

private func drawLineGrid(
    context: CGContext,
    rect: CGRect,
    step: CGFloat,
    lineWidth: CGFloat,
    color: CGColor
) {
    context.saveGState()
    context.setStrokeColor(color)
    context.setLineWidth(lineWidth)
    
    var x = rect.minX
    while x <= rect.maxX {
        context.move(to: CGPoint(x: x, y: rect.minY))
        context.addLine(to: CGPoint(x: x, y: rect.maxY))
        context.strokePath()
        x += step
    }
    
    var y = rect.minY
    while y <= rect.maxY {
        context.move(to: CGPoint(x: rect.minX, y: y))
        context.addLine(to: CGPoint(x: rect.maxX, y: y))
        context.strokePath()
        y += step
    }
    
    context.restoreGState()
}

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift generate_app_icon.swift <output_png_path>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let size: CGFloat = 1024
let inset: CGFloat = 56
let cornerRadius: CGFloat = 230

guard
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    fputs("Failed to create graphics context.\n", stderr)
    exit(2)
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high

let canvasRect = CGRect(x: 0, y: 0, width: size, height: size)
context.clear(canvasRect)

let iconRect = canvasRect.insetBy(dx: inset, dy: inset)
let roundedIconPath = CGPath(
    roundedRect: iconRect,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)

context.saveGState()
context.addPath(roundedIconPath)
context.clip()

let gradientColors: [CGColor] = [
    makeColor(28, 33, 44),
    makeColor(12, 16, 23)
]
guard let bgGradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: [0.0, 1.0]) else {
    fputs("Failed to create gradient.\n", stderr)
    exit(2)
}
context.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
    end: CGPoint(x: iconRect.midX, y: iconRect.minY),
    options: []
)

let gridRect = iconRect.insetBy(dx: 78, dy: 88)
context.setFillColor(makeColor(16, 21, 31))
context.fill(gridRect)

drawLineGrid(
    context: context,
    rect: gridRect,
    step: 48,
    lineWidth: 1.5,
    color: makeColor(47, 58, 77, 0.35)
)
drawLineGrid(
    context: context,
    rect: gridRect,
    step: 96,
    lineWidth: 2.0,
    color: makeColor(77, 92, 119, 0.55)
)

let points: [CGPoint] = [
    CGPoint(x: gridRect.minX + 18, y: gridRect.minY + 180),
    CGPoint(x: gridRect.minX + 90, y: gridRect.minY + 180),
    CGPoint(x: gridRect.minX + 140, y: gridRect.minY + 420),
    CGPoint(x: gridRect.minX + 200, y: gridRect.minY + 150),
    CGPoint(x: gridRect.minX + 280, y: gridRect.minY + 150),
    CGPoint(x: gridRect.minX + 360, y: gridRect.minY + 620),
    CGPoint(x: gridRect.minX + 430, y: gridRect.minY + 110),
    CGPoint(x: gridRect.minX + 540, y: gridRect.minY + 110),
    CGPoint(x: gridRect.minX + 620, y: gridRect.minY + 500),
    CGPoint(x: gridRect.minX + 700, y: gridRect.minY + 240),
    CGPoint(x: gridRect.minX + 760, y: gridRect.minY + 240),
    CGPoint(x: gridRect.maxX - 18, y: gridRect.minY + 240)
]

func strokeWave(lineWidth: CGFloat, color: CGColor, shadowBlur: CGFloat = 0, shadowColor: CGColor? = nil) {
    context.saveGState()
    if shadowBlur > 0 {
        context.setShadow(offset: .zero, blur: shadowBlur, color: shadowColor)
    }
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(color)
    if let first = points.first {
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }
    context.restoreGState()
}

strokeWave(
    lineWidth: 24,
    color: makeColor(58, 252, 170),
    shadowBlur: 18,
    shadowColor: makeColor(104, 255, 192, 0.7)
)
strokeWave(lineWidth: 10, color: makeColor(188, 255, 229, 0.95))

context.restoreGState()

context.addPath(roundedIconPath)
context.setLineWidth(3.0)
context.setStrokeColor(makeColor(129, 146, 179, 0.35))
context.strokePath()

guard let cgImage = context.makeImage() else {
    fputs("Failed to create CGImage.\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

guard
    let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fputs("Failed to create PNG destination.\n", stderr)
    exit(2)
}

CGImageDestinationAddImage(destination, cgImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Failed to finalize PNG output.\n", stderr)
    exit(2)
}

print("Generated icon PNG: \(outputPath)")
