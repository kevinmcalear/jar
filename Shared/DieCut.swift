import CoreGraphics
import Foundation

enum JarLogStep: Equatable {
    case category, amount, photo
}

func nextJarStep(_ step: JarLogStep, tookPhoto _: Bool) -> JarLogStep? {
    switch step {
    case .category: .amount
    case .amount: .photo
    case .photo: nil
    }
}

func sealMark(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first, first.isLetter else { return "" }
    return String(first).uppercased()
}

/// A jar spend the other phone has not already shown. Edits count, including a past day. The first download and an unchanged echo do not.
func shouldPostSpendNotice(kind: String, noticesLive: Bool, changed: Bool) -> Bool {
    kind == "jar" && noticesLive && changed
}

func spendNoticeBody(amount: Int, note: String?, left: Int, removed: Bool = false) -> String {
    if removed { return "Removed \(formatCents(amount))" }
    let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let money = "\(formatCents(amount)) · \(formatCents(left)) left"
    guard !trimmed.isEmpty else { return money }
    return "\(formatCents(amount)) · \(trimmed) · \(formatCents(left)) left"
}

func sealShapeIndex(_ name: String) -> Int {
    let total = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return total % 3
}

/// White die-cut around the mask. The photo is drawn on top of that outline, so the original stays inside it.
func dieCut(image: CGImage, mask: CGImage, stroke: CGFloat) -> CGImage? {
    let pad = Int(stroke.rounded(.up))
    guard pad > 0, image.width > 0, image.height > 0 else { return image }
    let width = image.width + pad * 2
    let height = image.height + pad * 2
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    let steps = 32
    for index in 0..<steps {
        let angle = Double(index) / Double(steps) * 2 * Double.pi
        let dx = CGFloat(cos(angle)) * stroke
        let dy = CGFloat(sin(angle)) * stroke
        let rect = CGRect(x: CGFloat(pad) + dx, y: CGFloat(pad) + dy, width: CGFloat(image.width), height: CGFloat(image.height))
        ctx.saveGState()
        ctx.clip(to: rect, mask: mask)
        ctx.fill(rect)
        ctx.restoreGState()
    }
    let base = CGRect(x: CGFloat(pad), y: CGFloat(pad), width: CGFloat(image.width), height: CGFloat(image.height))
    ctx.saveGState()
    ctx.clip(to: base, mask: mask)
    ctx.fill(base)
    ctx.draw(image, in: base)
    ctx.restoreGState()
    return ctx.makeImage()
}
