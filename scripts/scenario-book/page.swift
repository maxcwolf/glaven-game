import Foundation
import PDFKit
import AppKit

// Renders one page of the scenario book (or a part of it) to a PNG, to read a map from.
//
//     swift scripts/scenario-book/page.swift <book.pdf> <page> <scale> <out.png> [x0 y0 x1 y1]
//
// `page` is the book's own page number (the notes in docs/scenario-book/gh-scenario-rules.md give
// it for every scenario). `scale` 2 is enough to read a whole page; 4–5 with a crop reads the
// coloured borders of a monster token (which say normal, elite or absent for 2, 3 and 4
// characters). The crop is given as fractions of the page, origin top-left: `0.35 0.45 0.75 0.7`.
// It also prints the first words of the page, to check it is the right one.
let args = CommandLine.arguments
guard args.count >= 5, let doc = PDFDocument(url: URL(fileURLWithPath: args[1])),
      let pageNumber = Int(args[2]), let scale = Double(args[3]), let page = doc.page(at: pageNumber - 1) else {
    print("usage: swift page.swift book.pdf page scale out.png [x0 y0 x1 y1]"); exit(1)
}
let box = page.bounds(for: .mediaBox)
var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
if args.count >= 9, let x0 = Double(args[5]), let y0 = Double(args[6]), let x1 = Double(args[7]), let y1 = Double(args[8]) {
    crop = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
}
let width = Int(box.width * crop.width * scale), height = Int(box.height * crop.height * scale)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
let cg = context.cgContext
cg.setFillColor(NSColor.white.cgColor)
cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
cg.scaleBy(x: scale, y: scale)
// top-left origin crop → PDF bottom-left origin
cg.translateBy(x: -box.width * crop.minX, y: -box.height * (1 - crop.maxY))
page.draw(with: .mediaBox, to: cg)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[4]))
print("page \(pageNumber): \(Int(box.width))x\(Int(box.height)) pt → \(width)x\(height) px; text: \((page.string ?? "").prefix(80).replacingOccurrences(of: "\n", with: " "))")
