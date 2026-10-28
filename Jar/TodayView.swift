import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let picture = model.picture
        let climb = picture.climbs
        let ink = climb ? Flare.ground : Flare.paper
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headline(picture, ink: ink)
                if case .climb(let debt, let days, let usual, let remainder) = picture {
                    ScoreJar(fill: 0, stroke: Flare.ground, gaps: 3, width: 168)
                    Text("Climb back \(formatCents(debt)).")
                        .font(Flare.number(52))
                        .foregroundStyle(Flare.ground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Text(climbSentence(days: days, usual: usual))
                        .font(Flare.number(22))
                        .foregroundStyle(Flare.ground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if remainder > 0 {
                        Text("\(formatCents(remainder)) left today")
                            .font(.title3)
                            .foregroundStyle(Flare.ground.opacity(0.8))
                        BillPile(cents: remainder)
                    }
                    Text("if the day ended now")
                        .font(.subheadline)
                        .foregroundStyle(Flare.ground.opacity(0.75))
                } else {
                    pile(picture)
                    caption(picture)
                    scoreLine(picture, ink: ink)
                    if model.todaySpent > 0 {
                        Text("\(formatCents(model.todaySpent)) spent")
                            .font(.subheadline)
                            .foregroundStyle(climb ? Flare.ground : Flare.muted)
                    }
                }
                rows
                // ponytail: the button is hidden until outside logging comes back. OutsideSheet is still on RootView via outsideToken.
                outside
                if let note = model.morningNote {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Flare.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background((climb ? Flare.flare : Flare.ground).ignoresSafeArea())
        .navigationTitle("Today")
        .navigationSubtitle(model.todaySubtitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(climb ? .light : .dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.settingsToken = SheetToken() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
    }

    @ViewBuilder private func headline(_ picture: Picture, ink: Color) -> some View {
        switch picture {
        case .hole(let debt, _):
            Text("In the hole by \(formatCents(debt)).")
                .font(Flare.number(44))
                .foregroundStyle(Flare.flare)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("if the day ended now")
                .font(.subheadline)
                .foregroundStyle(Flare.muted)
        case .climb:
            EmptyView()
        case .quiet(let cap):
            Text(formatCents(cap))
                .font(Flare.number(84))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("for today")
                .font(.title3)
                .foregroundStyle(Flare.muted)
        case .growing(let remainder, _, _):
            Text(formatCents(max(0, remainder)))
                .font(Flare.number(84))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("left of \(formatCents(model.todayCap))")
                .font(.title3)
                .foregroundStyle(Flare.muted)
        case .borrowing, .exact:
            Text(formatCents(0))
                .font(Flare.number(84))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("left of \(formatCents(model.todayCap))")
                .font(.title3)
                .foregroundStyle(Flare.muted)
        }
    }

    @ViewBuilder private func pile(_ picture: Picture) -> some View {
        switch picture {
        case .quiet(let cap):
            BillPile(cents: cap)
        case .growing(let remainder, _, _):
            BillPile(cents: max(0, remainder))
        case .hole(_, let remainder):
            if remainder > 0 {
                Text(formatCents(remainder))
                    .font(Flare.number(36))
                    .foregroundStyle(Flare.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                BillPile(cents: remainder)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func caption(_ picture: Picture) -> some View {
        switch picture {
        case .quiet(let cap):
            Text("A quiet day shoves \(formatCents(cap)) in at \(closeClock(model.snapshot.settings?.closeHour ?? 4)).")
                .font(Flare.number(20))
                .foregroundStyle(Flare.flare)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .growing(_, let shove, _):
            Text("If the day ended now, \(formatCents(shove)) gets shoved in.")
                .font(Flare.number(20))
                .foregroundStyle(Flare.flare)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .borrowing(let amount):
            Text("Borrowing \(formatCents(amount)) from the jar.")
                .font(Flare.number(28))
                .foregroundStyle(Flare.flare)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .exact(let cap):
            Text("Today used the whole \(formatCents(cap)).")
                .font(Flare.number(20))
                .foregroundStyle(Flare.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .hole, .climb:
            EmptyView()
        }
    }

    @ViewBuilder private func scoreLine(_ picture: Picture, ink: Color) -> some View {
        let settled = model.settledScore
        HStack(spacing: 14) {
            switch picture {
            case .hole:
                ScoreJar(fill: 0, stroke: Flare.paper, gaps: 1, width: 72)
            default:
                ScoreJar(fill: jarFill(cents: settled.jar), stroke: Flare.paper, gaps: settled.jar == 0 ? 1 : 0, width: 72)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatCents(settled.jar))
                        .font(Flare.number(28))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if case .hole = picture {
                        EmptyView()
                    } else {
                        Text(jarSizeLine(cents: settled.jar))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                    }
                }
                Text("in the jar")
                    .font(.subheadline)
                    .foregroundStyle(Flare.muted)
                if case .hole = picture {
                    EmptyView()
                } else {
                    Text(nextJarLine(cents: settled.jar))
                        .font(.subheadline)
                        .foregroundStyle(Flare.muted)
                }
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 8) {
            ForEach(model.snapshot.entries.filter { $0.day == model.openDate && $0.kind == "jar" }) { entry in
                jarRow(entry)
            }
        }
    }

    private func jarRow(_ entry: Entry) -> some View {
        let person = model.snapshot.people.first { $0.id == entry.personID }
        let category = model.snapshot.categories.first { $0.id == entry.categoryID }
        return HStack(spacing: 10) {
            if let person {
                PersonSticker(sticker: person.sticker, name: person.displayName)
            } else {
                CustomSeal(name: "").frame(width: 44, height: 44)
            }
            CategoryMark(builtIn: category?.builtIn, name: category?.name ?? "")
            VStack(alignment: .leading, spacing: 2) {
                Text(person?.displayName ?? "")
                    .foregroundStyle(Flare.paper)
                    .lineLimit(1)
                Text(category?.name ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Flare.muted)
                    .lineLimit(1)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Flare.muted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let photo = entry.photo { PurchaseSticker(data: photo) }
            Text(formatCents(entry.amount))
                .font(Flare.number(20))
                .foregroundStyle(Flare.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)
        }
        .padding(12)
        .background(Flare.surface, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button("Change amount") { model.editEntryID = entry.id }
            Button("Delete", role: .destructive) { model.deleteEntry(entry.id) }
        }
        .swipeActions {
            Button("Delete", role: .destructive) { model.deleteEntry(entry.id) }
        }
    }

    @ViewBuilder private var outside: some View {
        let week = weekInterval(containing: model.openDate, timeZone: model.timeZone)
        let rows = model.snapshot.entries.filter { $0.kind == "outside" && $0.day >= week.start && $0.day <= week.end }
        if let latest = rows.max(by: { $0.createdAt < $1.createdAt }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Outside")
                            .foregroundStyle(Flare.paper)
                        Text(outsideCaption(latest, count: rows.count, total: rows.reduce(0) { $0 + $1.amount }))
                            .font(.subheadline)
                            .foregroundStyle(Flare.muted)
                    }
                    Spacer()
                    Text(formatCents(latest.amount))
                        .font(Flare.number(20))
                        .foregroundStyle(Flare.paper)
                }
                .padding(12)
                .background(Flare.surface, in: RoundedRectangle(cornerRadius: 16))
                ForEach(rows.sorted { $0.createdAt < $1.createdAt }) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Chip(rawValue: entry.chip ?? "")?.title ?? "Outside")
                                .foregroundStyle(Flare.paper)
                            if let note = entry.note {
                                Text(note).font(.subheadline).foregroundStyle(Flare.muted)
                            }
                        }
                        Spacer()
                        Text(formatCents(entry.amount)).foregroundStyle(Flare.muted)
                    }
                    .padding(.horizontal, 4)
                    .swipeActions {
                        Button("Delete", role: .destructive) { model.deleteEntry(entry.id) }
                    }
                }
            }
        }
    }

    private func outsideCaption(_ entry: Entry, count: Int, total: Int) -> String {
        let chip = Chip(rawValue: entry.chip ?? "")?.title.lowercased() ?? "outside"
        if count > 1 {
            return "\(chip) · does not move the jar · \(formatCents(total)) this week"
        }
        return "\(chip) · does not move the jar"
    }

    private func climbSentence(days: Int, usual: Int) -> String {
        let word = countWord(days)
        let unit = days == 1 ? "day clears" : "days clear"
        return "\(word) quiet \(formatCents(usual)) \(unit) it."
    }
}
