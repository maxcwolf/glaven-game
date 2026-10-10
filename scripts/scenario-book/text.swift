import Foundation
import PDFKit

// Writes the text of every page of the scenario book to <dir>/p<N>.txt, to search for a rule's
// exact wording (the columns of a page come out interleaved, so read the page image for anything
// that matters).
//
//     swift scripts/scenario-book/text.swift <book.pdf> <dir>
let args = CommandLine.arguments
guard args.count >= 3, let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    print("usage: swift text.swift book.pdf dir"); exit(1)
}
try? FileManager.default.createDirectory(atPath: args[2], withIntermediateDirectories: true)
for i in 0..<doc.pageCount {
    let text = doc.page(at: i)?.string ?? ""
    try! text.write(toFile: "\(args[2])/p\(i + 1).txt", atomically: true, encoding: .utf8)
}
print("\(doc.pageCount) pages")
