import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

precondition(CommandLine.arguments.count == 2, "usage: generate-lenso-app-icon.swift OUTPUT_DIR")

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let pixelSize = 1024
let canvas = CGFloat(pixelSize)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
let context = CGContext(
    data: nil,
    width: pixelSize,
    height: pixelSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo
)!

func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
context.saveGState()
let backgroundRect = CGRect(x: 72, y: 72, width: 880, height: 880)
let backgroundPath = CGPath(
    roundedRect: backgroundRect,
    cornerWidth: 220,
    cornerHeight: 220,
    transform: nil
)
context.addPath(backgroundPath)
context.clip()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(0.043, 0.282, 0.757), rgb(0.000, 0.157, 0.545)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 72, y: 952),
    end: CGPoint(x: 952, y: 72),
    options: []
)
context.restoreGState()

let lensCenter = CGPoint(x: canvas / 2, y: canvas / 2)
let ringRadius: CGFloat = 304
let ringWidth: CGFloat = 112

context.setStrokeColor(rgb(1, 1, 1))
context.setLineWidth(ringWidth)
context.setLineCap(.round)
context.setStrokeColor(rgb(1, 1, 1))
context.setLineWidth(ringWidth)
context.setLineCap(.butt)

context.beginPath()
context.addArc(
    center: lensCenter,
    radius: ringRadius,
    startAngle: radians(100),
    endAngle: radians(282),
    clockwise: false
)
context.strokePath()

context.beginPath()
context.addArc(
    center: lensCenter,
    radius: ringRadius,
    startAngle: radians(292),
    endAngle: radians(461),
    clockwise: false
)
context.strokePath()

let lensRect = CGRect(x: lensCenter.x - 104, y: lensCenter.y - 104, width: 208, height: 208)
context.setFillColor(rgb(0.000, 0.157, 0.545))
context.fillEllipse(in: lensRect)
context.setStrokeColor(rgb(1, 1, 1))
context.setLineWidth(48)
context.strokeEllipse(in: lensRect)

let outputURL = outputDirectory.appendingPathComponent("icon_1024.png")
let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination), "failed to write \(outputURL.path)")
