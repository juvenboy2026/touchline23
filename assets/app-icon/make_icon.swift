// Draws Touchline 23's App icons. Project-owned artwork: a centre circle and
// centre line on a pitch-green field, enclosing the number 23. No game image,
// logo or font file ships with it (the text is drawn with a system font).
//
//   swift assets/app-icon/make_icon.swift
//
// Writes touchline23.png (opaque square, for iOS, which rounds it itself) and
// touchline23-mac.png (rounded with transparent corners, for macOS).
import AppKit
import CoreGraphics
import CoreText
import Foundation

let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let size = 1024

func context(_ pixels: Int) -> CGContext {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let c = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("no bitmap context")
    }
    return c
}

func rounded(_ c: CGContext, inset: CGFloat, radius: CGFloat) {
    let r = CGRect(x: inset, y: inset, width: CGFloat(size) - 2 * inset, height: CGFloat(size) - 2 * inset)
    c.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    c.clip()
}

func pitch(_ c: CGContext) {
    // Deep green field, lighter at the top.
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [CGColor(red: 0.10, green: 0.42, blue: 0.30, alpha: 1),
                  CGColor(red: 0.03, green: 0.16, blue: 0.11, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)),
                         end: CGPoint(x: CGFloat(size), y: 0), options: [])
    // Mown stripes.
    c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.045))
    for band in 0..<8 where band % 2 == 0 {
        c.fill(CGRect(x: CGFloat(band) * CGFloat(size) / 8, y: 0,
                      width: CGFloat(size) / 8, height: CGFloat(size)))
    }
}

func markings(_ c: CGContext) {
    let mid = CGFloat(size) / 2
    let line = CGColor(red: 1, green: 1, blue: 1, alpha: 0.92)
    c.setStrokeColor(line)
    c.setFillColor(line)
    // The centre circle, as on the field's halfway line.
    c.setLineWidth(24)
    c.strokeEllipse(in: CGRect(x: mid - 340, y: mid - 340, width: 680, height: 680))
}

func number(_ c: CGContext) {
    // 23 inside the circle, drawn as two glyph paths so the icon needs no font file.
    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 330, nil)
    let text = NSAttributedString(string: "23", attributes: [
        kCTFontAttributeName as NSAttributedString.Key: font,
        kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
    ])
    let ctLine = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(ctLine, .useGlyphPathBounds)
    c.textPosition = CGPoint(x: CGFloat(size) / 2 - bounds.midX, y: CGFloat(size) / 2 - bounds.midY)
    CTLineDraw(ctLine, c)
}

func write(_ c: CGContext, to name: String) {
    guard let image = c.makeImage() else { fatalError("no image") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try! data.write(to: here.appendingPathComponent(name))
    print("wrote \(name) (\(size)x\(size))")
}

// iOS: an opaque square; the system rounds the corners.
let square = context(size)
pitch(square)
markings(square)
number(square)
write(square, to: "touchline23.png")

// macOS: rounded, with the corners left transparent.
let mac = context(size)
rounded(mac, inset: 44, radius: 210)
pitch(mac)
// Markings are clipped to the rounded field: draw them through the same clip.
markings(mac)
number(mac)
write(mac, to: "touchline23-mac.png")
