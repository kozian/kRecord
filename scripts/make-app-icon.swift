#!/usr/bin/env swift
// Builds kRecord/Assets.xcassets/AppIcon.appiconset from one square artwork PNG.
//
//     swift scripts/make-app-icon.swift design/AppleIcon-1024.png
//
// The artwork is a rounded "plate" drawn on an opaque background. The script finds the plate's
// edges and corner radius, cuts it out, scales it to the 824 x 824 body of Apple's macOS icon grid
// on a transparent 1024 x 1024 canvas with a soft shadow, and writes all ten sizes plus
// Contents.json. Uses only AppKit / Core Graphics.

import AppKit

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-app-icon.swift <artwork.png> [appiconset-dir]\n".utf8))
    exit(1)
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments.count > 2
    ? CommandLine.arguments[2] : "kRecord/Assets.xcassets/AppIcon.appiconset")

guard let source = NSBitmapImageRep(data: try Data(contentsOf: input)), let sourceImage = source.cgImage else {
    fatalError("cannot read \(input.path)")
}
let width = source.pixelsWide
let height = source.pixelsHigh

func luminance(_ x: Int, _ y: Int) -> Double {
    let color = source.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
    return Double(0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent) * 255
}

/// First index from the start of `points` where luminance jumps from the background level.
func edge(_ points: [(Int, Int)]) -> Int {
    let background = luminance(points[0].0, points[0].1)
    for (index, point) in points.enumerated() where abs(luminance(point.0, point.1) - background) > 35 {
        return index
    }
    fatalError("no plate edge found")
}

// Plate edges, measured along a row and a column away from the artwork in the middle.
let probeRow = height / 4
let probeColumn = width / 2
let left = edge((0..<width / 2).map { ($0, probeRow) })
let right = width - 1 - edge((0..<width / 2).map { (width - 1 - $0, probeRow) })
let top = edge((0..<height / 2).map { (probeColumn, $0) })
let bottom = height - 1 - edge((0..<height / 2).map { (probeColumn, height - 1 - $0) })
// Corner: where the diagonal from the image corner meets the plate; for a circular corner of
// radius r that is at left + r * (1 - 1/sqrt(2)).
let diagonal = edge((0..<min(width, height) / 2).map { ($0, $0) })
let cornerFraction = Double(diagonal - left) / (1 - 1 / 2.squareRoot()) / Double(right - left)
print("plate: x \(left)...\(right), y \(top)...\(bottom), corner \(Int(cornerFraction * 100))% of width")

// MARK: Master 1024 x 1024

let canvas = 1024
let body = 824.0
let inset = 2.0 // trims the outermost anti-aliased pixels of the drawn edge
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

let master = makeContext(canvas)
master.interpolationQuality = .high
let origin = (Double(canvas) - body) / 2
let bodyRect = CGRect(x: origin, y: origin, width: body, height: body)
let radius = cornerFraction * body
let plate = CGPath(roundedRect: bodyRect.insetBy(dx: inset, dy: inset),
                   cornerWidth: radius - inset, cornerHeight: radius - inset, transform: nil)

// Shadow per Apple's macOS icon template: soft, slightly below the plate.
master.saveGState()
master.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
master.addPath(plate)
master.setFillColor(NSColor.black.cgColor)
master.fillPath()
master.restoreGState()

// The plate itself, stretched from its measured bounds onto the body square.
master.saveGState()
master.addPath(plate)
master.clip()
let crop = sourceImage.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))!
master.draw(crop, in: bodyRect)
master.restoreGState()

let masterImage = master.makeImage()!

// MARK: All sizes

func writePNG(_ image: CGImage, size: Int, to url: URL) throws {
    let context = makeContext(size)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try writePNG(masterImage, size: pixels, to: output.appending(path: name))
        images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appending(path: "Contents.json"))
print("wrote \(images.count) images to \(output.path)")
