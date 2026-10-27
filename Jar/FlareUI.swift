import SwiftUI

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(bills))
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
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(Flare.ground)
            Circle().stroke(Flare.paper, lineWidth: 1.5)
            mark
            accent
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var mark: some View {
        let style = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        switch builtIn {
        case "cocktails", "date": CocktailGlass().stroke(Flare.paper, style: style)
        case "blowdry": Capsule().stroke(Flare.paper, style: style)
        case "eating": Bowl().stroke(Flare.paper, style: style)
        case "snacks", "delivery": Bag().stroke(Flare.paper, style: style)
        case "worklunch": RoundedRectangle(cornerRadius: 3).stroke(Flare.paper, style: style)
        case "friends": Circle().stroke(Flare.paper, style: style)
        case "wine": WineGlass().stroke(Flare.paper, style: style)
        case "coffee": CoffeeCup().stroke(Flare.paper, style: style)
        default: Circle().stroke(Flare.paper, style: style)
        }
    }

    @ViewBuilder private var accent: some View {
        Circle().fill(Flare.flare).frame(width: size * 0.22, height: size * 0.22)
    }
}

nonisolated struct CocktailGlass: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 6, y: rect.minY + 8))
        path.addLine(to: CGPoint(x: rect.maxX - 6, y: rect.minY + 8))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + 2))
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.midX, y: rect.midY + 2))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 8))
        return path
    }
}

nonisolated struct Bowl: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.28, startAngle: .degrees(200), endAngle: .degrees(-20), clockwise: false)
        return path
    }
}

nonisolated struct Bag: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 8, y: rect.minY + 12))
        path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 12))
        path.addLine(to: CGPoint(x: rect.maxX - 6, y: rect.maxY - 8))
        path.addLine(to: CGPoint(x: rect.minX + 6, y: rect.maxY - 8))
        path.closeSubpath()
        return path
    }
}

nonisolated struct WineGlass: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 8, y: rect.minY + 6))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 6), control: CGPoint(x: rect.midX, y: rect.midY + 6))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 7))
        return path
    }
}

nonisolated struct CoffeeCup: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect.insetBy(dx: 8, dy: 10).offsetBy(dx: -2, dy: 2), cornerSize: CGSize(width: 4, height: 4))
        return path
    }
}

struct PhotoFrame: View {
    var body: some View {
        Text("Photo")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Flare.flare)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Flare.flare, lineWidth: 1))
            .accessibilityLabel("Photo")
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
