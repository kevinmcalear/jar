import SwiftUI
import UIKit

enum Flare {
    static let ground = Color(red: 0x0E / 255, green: 0x0E / 255, blue: 0x0E / 255)
    static let surface = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
    static let line = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2C / 255)
    static let paper = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255)
    static let muted = Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0x9A / 255)
    static let flare = Color(red: 1, green: 0x4D / 255, blue: 0x1C / 255)

    static func number(_ size: CGFloat) -> Font {
        .custom("Bricolage Grotesque", size: size).weight(.heavy)
    }
}

nonisolated struct JarOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 200
        let sy = rect.height / 240
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
        var path = Path()
        path.move(to: p(58, 22))
        path.addLine(to: p(142, 22))
        path.addLine(to: p(142, 32))
        path.addLine(to: p(134, 32))
        path.addLine(to: p(134, 48))
        path.addCurve(to: p(176, 108), control1: p(168, 56), control2: p(176, 80))
        path.addLine(to: p(176, 168))
        path.addCurve(to: p(100, 220), control1: p(176, 202), control2: p(148, 220))
        path.addCurve(to: p(24, 168), control1: p(52, 220), control2: p(24, 202))
        path.addLine(to: p(24, 108))
        path.addCurve(to: p(66, 48), control1: p(24, 80), control2: p(32, 56))
        path.addLine(to: p(66, 32))
        path.addLine(to: p(58, 32))
        path.closeSubpath()
        return path
    }
}

nonisolated struct WaveMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 16))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: 16), control: CGPoint(x: rect.width / 2, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct ScoreJar: View {
    var fill: Double
    var stroke: Color
    var gaps: Int
    var juice: Color = Flare.flare
    var width: CGFloat = 112

    var body: some View {
        let height = width * 240 / 200
        let dash: [CGFloat] = gaps == 0 ? [] : gaps == 1 ? [width * 1.35, width * 0.1] : [width * 0.5, width * 0.08]
        ZStack {
            JarOutline()
                .fill(juice)
                .mask(alignment: .bottom) {
                    WaveMask().frame(width: width, height: height * min(1, max(0, fill)))
                }
            JarOutline().stroke(stroke, style: StrokeStyle(lineWidth: width * 0.07, lineCap: .round, lineJoin: .round, dash: dash))
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(3))
        .accessibilityLabel(fill <= 0 ? "Empty jar" : "Jar")
    }
}

struct BillPile: View {
    var cents: Int

    var body: some View {
        let bills = pile(remainderCents: cents)
        let width = billRowWidth(bills)
        Group {
            if bills.isEmpty || width <= 0 {
                EmptyView()
            } else {
                GeometryReader { geo in
                    let scale = min(1, geo.size.width / (width + 8))
                    row(bills)
                        .frame(width: width, alignment: .leading)
                        .scaleEffect(scale, anchor: .leading)
                        .frame(width: geo.size.width, height: 48, alignment: .leading)
                }
                .frame(height: 48)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(bills))
    }

    private func row(_ bills: [BillFace]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(bills.enumerated()), id: \.offset) { index, bill in
                Text(face(bill.cents))
                    .font(Flare.number(bill.full ? 28 : 22))
                    .foregroundStyle(Flare.flare)
                    .frame(width: bill.full ? 72 : max(46, 72 * CGFloat(bill.cents) / 1000), height: 48)
                    .background(Flare.ground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Flare.paper, lineWidth: 2))
                    .rotationEffect(.degrees(Double(index) * 4 - 6))
            }
        }
    }

    private func face(_ cents: Int) -> String {
        cents.isMultiple(of: 100) ? String(cents / 100) : formatCents(cents).replacingOccurrences(of: "$", with: "")
    }

    private func label(_ bills: [BillFace]) -> String {
        let full = bills.filter(\.full).count
        guard let short = bills.last(where: { !$0.full }) else {
            return full == 1 ? "One $10 bill" : "\(countWord(full)) $10 bills"
        }
        let fullLabel = full == 1 ? "One $10 bill" : "\(countWord(full)) $10 bills"
        return "\(fullLabel) and a short \(formatCents(short.cents)) bill"
    }
}

struct PersonSticker: View {
    var sticker: String
    var name: String
    var size: CGFloat = 44

    var body: some View {
        Image("sticker-\(sticker)")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(name)
    }
}

struct CategoryMark: View {
    var builtIn: String?
    var name: String = ""
    var size: CGFloat = 28

    private var known: Bool {
        guard let builtIn else { return false }
        return builtInCategories.contains { $0.key == builtIn }
    }

    var body: some View {
        Group {
            if known, let builtIn {
                Image("cat-\(builtIn)")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else {
                CustomSeal(name: name)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct CustomSeal: View {
    var name: String

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = max(1.5, side * 0.08)
            ZStack {
                Circle()
                    .fill(Flare.ground)
                    .overlay(Circle().stroke(Flare.paper, lineWidth: line))
                    .padding(line)
                letterOrShape(side)
            }
        }
    }

    @ViewBuilder private func letterOrShape(_ side: CGFloat) -> some View {
        let letter = sealMark(name)
        if letter.isEmpty {
            sealShape(side * 0.28)
        } else {
            Text(letter)
                .font(Flare.number(side * 0.42))
                .foregroundStyle(Flare.flare)
                .minimumScaleFactor(0.5)
        }
    }

    @ViewBuilder private func sealShape(_ side: CGFloat) -> some View {
        switch sealShapeIndex(name) {
        case 1:
            Rectangle().fill(Flare.flare).frame(width: side, height: side).rotationEffect(.degrees(45))
        case 2:
            Capsule().fill(Flare.flare).frame(width: side, height: side * 0.45)
        default:
            Circle().fill(Flare.flare).frame(width: side, height: side)
        }
    }
}

struct PurchaseSticker: View {
    var data: Data
    var side: CGFloat = 48

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .accessibilityLabel("Photo")
        }
    }
}

struct MoneyPad: View {
    @Binding var typed: String

    var body: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { key in
                Button(key) { tap(key) }
                    .font(Flare.number(24))
                    .foregroundStyle(Flare.paper)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Flare.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func tap(_ key: String) {
        if key == "⌫" {
            if !typed.isEmpty { typed.removeLast() }
            return
        }
        if key == "." {
            guard !typed.contains(".") else { return }
            typed = typed.isEmpty ? "0." : typed + "."
            return
        }
        let parts = typed.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 1, parts[1].count >= 2 { return }
        if parts.count == 1, parts[0].count >= 6, !typed.contains(".") { return }
        if typed == "0" { typed = key } else { typed += key }
    }
}

func cents(typed: String) -> Int {
    if typed.isEmpty { return 0 }
    let parts = typed.split(separator: ".", omittingEmptySubsequences: false)
    let dollars = Int(parts.first ?? "0") ?? 0
    let fraction = parts.count > 1 ? String(parts[1].prefix(2)) : ""
    guard !fraction.isEmpty else { return dollars * 100 }
    let padded = fraction.padding(toLength: 2, withPad: "0", startingAt: 0)
    return dollars * 100 + (Int(padded) ?? 0)
}
