import SwiftUI

struct MonthView: View {
    @Environment(AppModel.self) private var model
    @State private var month = Date()
    @State private var openDate: String?

    var body: some View {
        let parts = monthParts
        ScrollView {
            VStack(spacing: 14) {
                ForEach(weeksTouching(year: parts.year, month: parts.month, timeZone: model.timeZone), id: \.start) { week in
                    weekCard(week)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Flare.ground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationSubtitle("Weeks in this month")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }
        }
    }

    private var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = model.timeZone
        formatter.dateFormat = "MMMM"
        return formatter.string(from: month)
    }

    private var monthParts: (year: Int, month: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.timeZone
        return (calendar.component(.year, from: month), calendar.component(.month, from: month))
    }

    private func shift(_ delta: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.timeZone
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
        openDate = nil
    }

    private func weekCard(_ week: (start: String, end: String)) -> some View {
        let days = daysFrom(week.start, until: addDays(week.end, 1, timeZone: model.timeZone), timeZone: model.timeZone)
        let jarEntries = model.snapshot.entries.filter { $0.kind == "jar" && days.contains($0.day) }
        let outside = model.snapshot.entries.filter { $0.kind == "outside" && days.contains($0.day) }
        let outsideTotal = outside.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rangeTitle(week))
                        .font(.headline)
                        .foregroundStyle(Flare.paper)
                    Text(jarNote(days: days, jarEntries: jarEntries))
                        .font(.subheadline)
                        .foregroundStyle(jarEntries.isEmpty ? Flare.muted : Flare.paper)
                    if outsideTotal > 0 {
                        Text("Outside \(formatCents(outsideTotal))")
                            .font(.subheadline)
                            .foregroundStyle(Flare.muted)
                    }
                }
                Spacer()
                heads(jarEntries)
            }
            if days.contains(where: { canEditJarDay($0, open: model.openDate) }) || !jarEntries.isEmpty {
                HStack {
                    ForEach(days, id: \.self) { day in
                        dayCell(day, entries: jarEntries.filter { $0.day == day })
                    }
                }
                if let openDate, days.contains(openDate) {
                    dayDetail(openDate)
                }
            }
        }
        .padding(16)
        .background(Flare.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(jarEntries.isEmpty ? Flare.line : Flare.flare, lineWidth: jarEntries.isEmpty ? 1 : 1.5))
    }

    @ViewBuilder private func heads(_ entries: [Entry]) -> some View {
        let sums = Dictionary(grouping: entries, by: \.personID).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let ranked = sums.sorted { $0.value > $1.value }
        if let first = ranked.first, let person = model.snapshot.people.first(where: { $0.id == first.key }) {
            let trailing = ranked.dropFirst().first
            let second = trailing.flatMap { pair in model.snapshot.people.first { $0.id == pair.key } }
            let tie = second != nil && trailing?.value == first.value
            HStack(alignment: .bottom, spacing: 10) {
                if let second, !tie {
                    PersonSticker(sticker: second.sticker, name: second.displayName, size: 48)
                }
                PersonSticker(sticker: person.sticker, name: person.displayName, size: tie ? 64 : 76)
                if tie, let second {
                    PersonSticker(sticker: second.sticker, name: second.displayName, size: 64)
                }
            }
        }
    }

    private func dayCell(_ day: String, entries: [Entry]) -> some View {
        let leader = leaderID(entries)
        let person = model.snapshot.people.first { $0.id == leader }
        return Button {
            guard canEditJarDay(day, open: model.openDate) else { return }
            openDate = openDate == day ? nil : day
        } label: {
            VStack(spacing: 4) {
                Text(letter(day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Flare.muted)
                if let person {
                    PersonSticker(sticker: person.sticker, name: person.displayName, size: 28)
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!canEditJarDay(day, open: model.openDate))
        .accessibilityLabel(person == nil ? "\(letter(day)), nothing logged" : "\(letter(day)), \(person?.displayName ?? "") spent more")
    }

    private func dayDetail(_ day: String) -> some View {
        let jar = model.snapshot.entries.filter { $0.day == day && $0.kind == "jar" }
        let outside = model.snapshot.entries.filter { $0.day == day && $0.kind == "outside" }
        return VStack(alignment: .leading, spacing: 8) {
            Text(weekday(day)).font(.subheadline.weight(.semibold)).foregroundStyle(Flare.muted)
            ForEach(jar) { entry in
                let person = model.snapshot.people.first { $0.id == entry.personID }
                let category = model.snapshot.categories.first { $0.id == entry.categoryID }
                HStack(spacing: 8) {
                    PersonSticker(sticker: person?.sticker ?? "kevin", name: person?.displayName ?? "", size: 32)
                    CategoryMark(builtIn: category?.builtIn, name: category?.name ?? "", size: 22)
                    VStack(alignment: .leading) {
                        Text(person?.displayName ?? "").foregroundStyle(Flare.paper).lineLimit(1)
                        Text(category?.name ?? "").font(.caption).foregroundStyle(Flare.muted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let photo = entry.photo { PurchaseSticker(data: photo, side: 40) }
                    Text(formatCents(entry.amount)).foregroundStyle(Flare.paper).lineLimit(1).layoutPriority(1)
                }
                .contextMenu {
                    Button("Change amount") { model.editEntryID = entry.id }
                    Button("Delete", role: .destructive) { model.deleteEntry(entry.id) }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { model.deleteEntry(entry.id) }
                }
            }
            if jar.isEmpty {
                Text("Nothing logged").font(.subheadline).foregroundStyle(Flare.muted)
            }
            if canEditJarDay(day, open: model.openDate) {
                Button("Add something") { model.openAdd(on: day) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Flare.paper)
            }
            ForEach(outside) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text("Outside").foregroundStyle(Flare.muted)
                        Text(Chip(rawValue: entry.chip ?? "")?.title ?? "").font(.caption).foregroundStyle(Flare.muted)
                    }
                    Spacer()
                    Text(formatCents(entry.amount)).foregroundStyle(Flare.muted)
                }
            }
        }
    }

    private func jarNote(days: [String], jarEntries: [Entry]) -> String {
        if jarEntries.isEmpty { return "Nothing logged" }
        let open = model.openDate
        if days.contains(open), model.snapshot.days.first(where: { $0.date == open })?.settled != true {
            let settled = model.settledScore
            let projected = project(jar: settled.jar, debt: settled.debt, cap: model.todayCap, spent: model.todaySpent)
            if projected.jar > settled.jar {
                return "\(formatCents(projected.jar - settled.jar)) still to shove in · \(formatCents(settled.jar)) in the jar"
            }
            return "\(formatCents(settled.jar)) in the jar"
        }
        let through = days.filter { day in model.snapshot.days.contains { $0.date == day && $0.settled } }
        let score = replay(through.map { day in
            (cap: model.snapshot.days.first { $0.date == day }?.cap ?? 0, spent: model.jarSpent(day))
        })
        if score.debt > 0 { return "Jar ended \(formatCents(score.debt)) in the hole" }
        return "\(formatCents(score.jar)) in the jar"
    }

    private func leaderID(_ entries: [Entry]) -> String? {
        Dictionary(grouping: entries, by: \.personID).mapValues { $0.reduce(0) { $0 + $1.amount } }.max { $0.value < $1.value }?.key
    }

    private func letter(_ day: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = model.timeZone
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date(from: day, timeZone: model.timeZone) ?? Date()).uppercased()
    }

    private func weekday(_ day: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = model.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date(from: day, timeZone: model.timeZone) ?? Date())
    }

    private func rangeTitle(_ week: (start: String, end: String)) -> String {
        let start = date(from: week.start, timeZone: model.timeZone) ?? Date()
        let end = date(from: week.end, timeZone: model.timeZone) ?? Date()
        let month = DateFormatter()
        month.locale = Locale(identifier: "en_US_POSIX")
        month.timeZone = model.timeZone
        month.dateFormat = "MMM"
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = model.timeZone
        day.dateFormat = "d"
        if month.string(from: start) == month.string(from: end) {
            return "\(month.string(from: start)) \(day.string(from: start)) – \(day.string(from: end))"
        }
        return "\(month.string(from: start)) \(day.string(from: start)) – \(month.string(from: end)) \(day.string(from: end))"
    }
}
