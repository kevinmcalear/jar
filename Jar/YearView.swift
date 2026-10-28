import SwiftUI

struct YearView: View {
    @Environment(AppModel.self) private var model
    @State private var draft: MoneyDraft?
    @State private var year = 0

    var body: some View {
        let report = YearReport.make(model)
        let shown = year == 0 ? yearNumber(model.openDate) : year
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                monthTotals(shown)
                if report.ready {
                    Text(formatCents(report.left, nearestDollar: true))
                        .font(Flare.number(64))
                        .foregroundStyle(Flare.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(model.snapshot.settings?.usualCap == 5000 ? "left if the $50 habit holds" : "left if the daily habit holds")
                        .font(.title3)
                        .foregroundStyle(Flare.muted)
                    VStack(spacing: 0) {
                        line("Income", report.income)
                        line("Daily habit", report.habit)
                        line("Outside", report.outside)
                        line("Bills", report.bills)
                        if let goal = report.goal { line("Goal", goal) }
                    }
                    .background(Flare.surface, in: RoundedRectangle(cornerRadius: 16))
                    verdict(report)
                    Text("This year, with what you've actually spent, you would keep \(formatCents(report.actual, nearestDollar: true)).")
                        .font(.body)
                        .foregroundStyle(Flare.muted)
                } else {
                    Text("Type what comes in, and the bills that always go out.")
                        .font(.title3)
                        .foregroundStyle(Flare.paper)
                }
                Text("Since we started, the jar is at \(formatCents(model.settledScore.jar)).")
                    .font(.subheadline)
                    .foregroundStyle(Flare.muted)
                moneyList(income: true)
                moneyList(income: false)
                HStack {
                    Button("Add income") { draft = MoneyDraft(income: true) }
                    Button("Add a bill") { draft = MoneyDraft(income: false) }
                }
                .buttonStyle(.bordered)
                .tint(Flare.paper)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Flare.ground.ignoresSafeArea())
        .navigationTitle(String(shownYear))
        .navigationSubtitle(yearSpentLine)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { shiftYear(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous year")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { shiftYear(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next year")
            }
        }
        .sheet(item: $draft) { draft in
            MoneyEditor(draft: draft) { name, amount, rhythm in
                model.addMoney(income: draft.income, name: name, amount: amount, rhythm: rhythm)
            }
        }
    }

    private var shownYear: Int { year == 0 ? yearNumber(model.openDate) : year }

    private var yearSpentLine: String {
        let prefix = String(format: "%04d-", shownYear)
        let total = model.snapshot.entries.reduce(0) { sum, entry in
            entry.kind == "jar" && entry.day.hasPrefix(prefix) ? sum + entry.amount : sum
        }
        return "\(formatCents(total)) spent"
    }

    private func shiftYear(_ delta: Int) {
        year = shownYear + delta
    }

    private func monthTotals(_ year: Int) -> some View {
        let days = model.snapshot.entries.map(\.day) + model.snapshot.days.map(\.date)
        let months = monthsWithDays(days, year: year)
        let jar = model.snapshot.entries.filter { $0.kind == "jar" }.map { (day: $0.day, amount: $0.amount) }
        return VStack(spacing: 12) {
            if months.isEmpty {
                Text("Nothing logged")
                    .font(.subheadline)
                    .foregroundStyle(Flare.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Flare.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            ForEach(months, id: \.self) { prefix in
                let parts = prefix.split(separator: "-")
                let month = Int(parts.last ?? "") ?? 1
                let report = monthWeeks(entries: jar, year: year, month: month, timeZone: model.timeZone)
                VStack(alignment: .leading, spacing: 0) {
                    Text(monthTitle(prefix))
                        .font(.headline)
                        .foregroundStyle(Flare.paper)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                    ForEach(report.weeks) { week in
                        HStack {
                            Text(weekRangeTitle(start: week.start, end: week.end, timeZone: model.timeZone))
                                .foregroundStyle(Flare.muted)
                            Spacer()
                            Text(formatCents(week.spent))
                                .foregroundStyle(Flare.paper)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                    HStack {
                        Text("\(monthTitle(prefix)) total").foregroundStyle(Flare.paper)
                        Spacer()
                        Text(formatCents(report.total)).foregroundStyle(Flare.paper)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Flare.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func monthTitle(_ prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = model.timeZone
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date(from: prefix + "-01", timeZone: model.timeZone) ?? Date())
    }

    private func line(_ title: String, _ cents: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(Flare.paper)
            Spacer()
            Text(formatCents(cents, nearestDollar: true)).foregroundStyle(Flare.paper)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder private func verdict(_ report: YearReport) -> some View {
        let positive = report.actual > 0
        let clears = report.goal.map { report.actual >= $0 } ?? positive
        VStack(alignment: .leading, spacing: 6) {
            if let goal = report.goal, clears {
                Text("Yes. You would clear the \(formatCents(goal, nearestDollar: true)) goal.")
            } else if let goal = report.goal {
                Text("You would be \(formatCents(max(0, goal - report.actual), nearestDollar: true)) short of the goal.")
            } else if report.left > 0 {
                Text("Yes. You would keep \(formatCents(report.left, nearestDollar: true)).")
            } else {
                Text("You would be \(formatCents(max(0, -report.left), nearestDollar: true)) short.")
            }
        }
        .font(Flare.number(22))
        .foregroundStyle(clears && (report.goal != nil || report.left > 0) ? Flare.ground : Flare.ground)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((clears && (report.goal != nil || report.left > 0) ? Flare.flare : Flare.flare), in: RoundedRectangle(cornerRadius: 16))
    }

    private func moneyList(income: Bool) -> some View {
        let rows = income ? model.snapshot.income : model.snapshot.bills
        return VStack(alignment: .leading, spacing: 8) {
            if !rows.isEmpty {
                Text(income ? "Income" : "Bills").font(.headline).foregroundStyle(Flare.paper)
            }
            ForEach(rows) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.name).foregroundStyle(Flare.paper)
                        Text(rhythmTitle(row.rhythm)).font(.caption).foregroundStyle(Flare.muted)
                    }
                    Spacer()
                    Text(formatCents(row.amount)).foregroundStyle(Flare.paper)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { model.deleteMoney(income: income, id: row.id) }
                }
            }
        }
    }
}

struct MoneyDraft: Identifiable {
    let id = UUID()
    var income: Bool
}

struct MoneyEditor: View {
    var draft: MoneyDraft
    var save: (String, Int, PayRhythm) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var typed = ""
    @State private var rhythm: PayRhythm = .monthly

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField(draft.income ? "Name" : "Bill", text: $name)
                    .padding(12)
                    .background(Flare.surface, in: RoundedRectangle(cornerRadius: 12))
                Text(typed.isEmpty ? "$0" : "$\(typed)")
                    .font(Flare.number(48))
                    .foregroundStyle(Flare.paper)
                Picker("Rhythm", selection: $rhythm) {
                    Text("Weekly").tag(PayRhythm.weekly)
                    Text("Every two weeks").tag(PayRhythm.biweekly)
                    Text("Twice a month").tag(PayRhythm.twiceMonth)
                    Text("Monthly").tag(PayRhythm.monthly)
                }
                .pickerStyle(.segmented)
                MoneyPad(typed: $typed)
                Spacer()
            }
            .padding(20)
            .background(Flare.ground.ignoresSafeArea())
            .navigationTitle(draft.income ? "Income" : "Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(name, cents(typed: typed), rhythm)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct YearReport {
    var income = 0
    var habit = 0
    var outside = 0
    var bills = 0
    var left = 0
    var actual = 0
    var goal: Int?
    var ready = false

    static func make(_ model: AppModel) -> YearReport {
        let year = yearNumber(model.openDate)
        let usual = model.snapshot.settings?.usualCap ?? 5000
        let income = model.snapshot.income.reduce(0) { $0 + yearCents(amount: $1.amount, rhythm: PayRhythm(rawValue: $1.rhythm) ?? .monthly) }
        let bills = model.snapshot.bills.reduce(0) { $0 + yearCents(amount: $1.amount, rhythm: PayRhythm(rawValue: $1.rhythm) ?? .monthly) }
        let opened = model.snapshot.days.filter { yearNumber($0.date) == year }.map(\.cap)
        let habit = habitFunCents(daysInYear: daysInYear(year, timeZone: model.timeZone), usualCap: usual, openedCaps: opened)
        let outside = outsideYear(model, year)
        let left = realityLeft(income: income, fun: habit, outside: outside, bills: bills)
        let settledDates = Set(model.snapshot.days.filter { $0.settled && yearNumber($0.date) == year }.map(\.date))
        let closed = model.snapshot.entries.filter { $0.kind == "jar" && settledDates.contains($0.day) }.reduce(0) { $0 + $1.amount }
        let actualFun = actualFunCents(closedJarSpends: closed, todayCap: model.todayCap, daysAfterToday: daysAfter(model.openDate, throughYear: year, timeZone: model.timeZone), usualCap: usual)
        return YearReport(income: income, habit: habit, outside: outside, bills: bills, left: left, actual: realityLeft(income: income, fun: actualFun, outside: outside, bills: bills), goal: model.snapshot.settings?.savingsGoal, ready: !model.snapshot.income.isEmpty || !model.snapshot.bills.isEmpty)
    }
}

private func outsideYear(_ model: AppModel, _ year: Int) -> Int {
    // ponytail: one habit per chip, latest row. Summing every weekly log would multiply the year.
    var habits: [String: Entry] = [:]
    var once = 0
    for entry in model.snapshot.entries where entry.kind == "outside" && yearNumber(entry.day) == year {
        let rhythm = PayRhythm(rawValue: entry.rhythm ?? "") ?? .once
        if rhythm == .once {
            once += entry.amount
        } else if let chip = entry.chip {
            if entry.createdAt > (habits[chip]?.createdAt ?? "") { habits[chip] = entry }
        }
    }
    return habits.values.reduce(once) { $0 + yearCents(amount: $1.amount, rhythm: PayRhythm(rawValue: $1.rhythm ?? "") ?? .once) }
}
