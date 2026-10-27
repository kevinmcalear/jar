import Foundation

// Integer cents. $50 is 5000. No floats in the money.

struct BillFace: Equatable {
    var cents: Int
    var full: Bool
}

struct ShovePlan: Equatable {
    var plays: Bool
    var tappable: Bool
    var text: String
    var billCents: Int
    var beforeJar: Int
    var afterJar: Int
}

enum PayRhythm: String, Equatable {
    case weekly
    case biweekly
    case twiceMonth
    case monthly
    case once
}

func settle(jar: Int, debt: Int, cap: Int, spent: Int) -> (jar: Int, debt: Int) {
    let remainder = cap - spent
    if remainder >= 0 {
        let pay = min(debt, remainder)
        return (jar + (remainder - pay), debt - pay)
    }
    let over = -remainder
    let take = min(jar, over)
    return (jar - take, debt + (over - take))
}

func project(jar: Int, debt: Int, cap: Int, spent: Int) -> (jar: Int, debt: Int) {
    settle(jar: jar, debt: debt, cap: cap, spent: spent)
}

func replay(_ days: [(cap: Int, spent: Int)]) -> (jar: Int, debt: Int) {
    days.reduce((jar: 0, debt: 0)) { pair, day in
        settle(jar: pair.jar, debt: pair.debt, cap: day.cap, spent: day.spent)
    }
}

func pile(remainderCents: Int) -> [BillFace] {
    guard remainderCents > 0 else { return [] }
    let fullCount = remainderCents / 1000
    let rest = remainderCents % 1000
    var bills = Array(repeating: BillFace(cents: 1000, full: true), count: fullCount)
    if rest > 0 {
        bills.append(BillFace(cents: rest, full: false))
    }
    return bills
}

func billRowWidth(_ bills: [BillFace]) -> CGFloat {
    let widths = bills.map { bill -> CGFloat in bill.full ? 72 : max(46, 72 * CGFloat(bill.cents) / 1000) }
    return widths.reduce(0, +) + CGFloat(max(0, bills.count - 1)) * 8
}

/// Face ID cannot open a household whose passphrase changed. Prompting again just retriggers itself when the sheet dismisses.
func shouldPromptToUnlock(passphraseReset: Bool, hasKey: Bool) -> Bool {
    !passphraseReset && !hasKey
}

func canEditJarDay(_ day: String, open: String) -> Bool {
    day <= open
}

struct DuplicateRow: Equatable {
    var id: String
    var updatedAt: String
    var uses: Int
}

/// One row per built-in. The copy spends already point at wins. A tie keeps the older row, then the smaller id.
func keptDuplicate(_ rows: [DuplicateRow]) -> String? {
    guard !rows.isEmpty else { return nil }
    return rows.max { a, b in
        if a.uses != b.uses { return a.uses < b.uses }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.id > b.id
    }?.id
}

func isCloudKitShareURL(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
    let shareHost = host == "www.icloud.com" || host == "icloud.com" || host == "share.icloud.com"
    return shareHost && url.path.lowercased().contains("/share")
}

func quietDayCount(debt: Int, usualCap: Int) -> Int {
    guard usualCap > 0, debt > 0 else { return 0 }
    return (debt + usualCap - 1) / usualCap
}

func divRoundHalfAway(_ numerator: Int, _ divisor: Int) -> Int {
    precondition(divisor > 0)
    let negative = numerator < 0
    let value = negative ? -numerator : numerator
    let quotient = value / divisor
    let remainder = value % divisor
    let rounded = quotient + (remainder * 2 >= divisor ? 1 : 0)
    return negative ? -rounded : rounded
}

func monthlyCents(amount: Int, rhythm: PayRhythm) -> Int {
    switch rhythm {
    case .weekly:
        return divRoundHalfAway(amount * 52, 12)
    case .biweekly:
        return divRoundHalfAway(amount * 26, 12)
    case .twiceMonth:
        return amount * 2
    case .monthly:
        return amount
    case .once:
        return 0
    }
}

func yearCents(amount: Int, rhythm: PayRhythm) -> Int {
    switch rhythm {
    case .weekly: return amount * 52
    case .biweekly: return amount * 26
    case .twiceMonth: return amount * 24
    case .monthly: return amount * 12
    case .once: return amount
    }
}

func habitFunCents(daysInYear: Int, usualCap: Int, openedCaps: [Int]) -> Int {
    let rest = max(0, daysInYear - openedCaps.count)
    return openedCaps.reduce(0, +) + rest * usualCap
}

func actualFunCents(closedJarSpends: Int, todayCap: Int, daysAfterToday: Int, usualCap: Int) -> Int {
    closedJarSpends + todayCap + max(0, daysAfterToday) * usualCap
}

func realityLeft(income: Int, fun: Int, outside: Int, bills: Int) -> Int {
    income - fun - outside - bills
}

/// The plan's $50 month test. `habitMonthly` is repeating outside already turned into a month.
func fiftyDollarMonthLeft(days: Int, incomeMonthly: Int, billsMonthly: Int, habitMonthly: Int, oneTime: Int) -> Int {
    realityLeft(income: incomeMonthly, fun: 5000 * days, outside: habitMonthly + oneTime, bills: billsMonthly)
}

func formatCents(_ cents: Int, nearestDollar: Bool = false) -> String {
    let shown: Int
    if nearestDollar {
        let negative = cents < 0
        let dollars = divRoundHalfAway(negative ? -cents : cents, 100)
        shown = negative ? -dollars * 100 : dollars * 100
    } else {
        shown = cents
    }
    let negative = shown < 0
    let absolute = negative ? -shown : shown
    let dollars = absolute / 100
    let rem = absolute % 100
    let body = groupThousands(dollars)
    if nearestDollar || rem == 0 {
        return (negative ? "-" : "") + "$" + body
    }
    return (negative ? "-" : "") + "$" + body + String(format: ".%02d", rem)
}

func groupThousands(_ value: Int) -> String {
    let digits = String(value)
    var out = ""
    for (index, character) in digits.reversed().enumerated() {
        if index > 0, index % 3 == 0 { out.append(",") }
        out.append(character)
    }
    return String(out.reversed())
}

func openDay(now: Date, timeZone: TimeZone, closeHour: Int) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let shifted = calendar.date(byAdding: .hour, value: -closeHour, to: now) ?? now
    return formatDay(shifted, timeZone: timeZone)
}

func formatDay(_ date: Date, timeZone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

func date(from day: String, timeZone: TimeZone) -> Date? {
    let pieces = day.split(separator: "-")
    guard pieces.count == 3, let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else {
        return nil
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: DateComponents(year: year, month: month, day: day))
}

func addDays(_ day: String, _ count: Int, timeZone: TimeZone) -> String {
    guard let date = date(from: day, timeZone: timeZone) else { return day }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let next = calendar.date(byAdding: .day, value: count, to: date) ?? date
    return formatDay(next, timeZone: timeZone)
}

func daysFrom(_ start: String, until end: String, timeZone: TimeZone) -> [String] {
    guard start < end else { return [] }
    var day = start
    var result: [String] = []
    while day < end, result.count < 4000 {
        result.append(day)
        day = addDays(day, 1, timeZone: timeZone)
    }
    return result
}

func daysInYear(_ year: Int, timeZone: TimeZone) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    guard let date = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
          let range = calendar.range(of: .day, in: .year, for: date) else { return 365 }
    return range.count
}

func daysInMonth(year: Int, month: Int, timeZone: TimeZone) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
          let range = calendar.range(of: .day, in: .month, for: date) else { return 30 }
    return range.count
}

func yearNumber(_ day: String) -> Int {
    Int(day.prefix(4)) ?? 0
}

func daysAfter(_ day: String, throughYear year: Int, timeZone: TimeZone) -> Int {
    let end = String(format: "%04d-01-01", year + 1)
    return daysFrom(addDays(day, 1, timeZone: timeZone), until: end, timeZone: timeZone).count
}

func weekInterval(containing day: String, timeZone: TimeZone) -> (start: String, end: String) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = date(from: day, timeZone: timeZone) ?? Date()
    let weekday = calendar.component(.weekday, from: date)
    let fromMonday = (weekday + 5) % 7
    let start = calendar.date(byAdding: .day, value: -fromMonday, to: date) ?? date
    let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
    return (formatDay(start, timeZone: timeZone), formatDay(end, timeZone: timeZone))
}

func weeksTouching(year: Int, month: Int, timeZone: TimeZone) -> [(start: String, end: String)] {
    let first = String(format: "%04d-%02d-01", year, month)
    let last = String(format: "%04d-%02d-%02d", year, month, daysInMonth(year: year, month: month, timeZone: timeZone))
    var week = weekInterval(containing: first, timeZone: timeZone)
    var result = [week]
    while week.end < last, result.count < 6 {
        week = weekInterval(containing: addDays(week.start, 7, timeZone: timeZone), timeZone: timeZone)
        result.append(week)
    }
    return result
}

func shovePlan(
    beforeJar: Int,
    beforeDebt: Int,
    afterJar: Int,
    afterDebt: Int,
    days: [(cap: Int, spent: Int)]
) -> ShovePlan {
    let quiet = !days.isEmpty && days.allSatisfy { $0.spent == 0 }
    let banked = afterJar - beforeJar
    if quiet, beforeDebt == 0, afterDebt == 0, banked > 0 {
        let when = days.count == 1 ? "yesterday" : "those days"
        return ShovePlan(
            plays: true,
            tappable: true,
            text: "Nothing was logged \(when), so \(formatCents(banked)) went into the jar. Tap if that's wrong.",
            billCents: banked,
            beforeJar: beforeJar,
            afterJar: afterJar
        )
    }
    if afterJar == beforeJar, afterDebt == beforeDebt {
        let text: String
        if days.count == 1, let day = days.first, day.cap > 0, day.spent == day.cap {
            text = "Yesterday used the whole allowance."
        } else {
            text = ""
        }
        return ShovePlan(plays: false, tappable: false, text: text, billCents: 0, beforeJar: beforeJar, afterJar: afterJar)
    }
    if afterDebt > beforeDebt {
        return ShovePlan(
            plays: true,
            tappable: false,
            text: "While we slept, the hole grew to \(formatCents(afterDebt)).",
            billCents: 0,
            beforeJar: beforeJar,
            afterJar: afterJar
        )
    }
    if afterJar < beforeJar {
        return ShovePlan(
            plays: true,
            tappable: false,
            text: "While we slept, the jar covered \(formatCents(beforeJar - afterJar)).",
            billCents: 0,
            beforeJar: beforeJar,
            afterJar: afterJar
        )
    }
    if afterDebt < beforeDebt, afterJar == beforeJar {
        return ShovePlan(
            plays: true,
            tappable: false,
            text: "While we slept, \(formatCents(beforeDebt - afterDebt)) paid the hole.",
            billCents: 0,
            beforeJar: beforeJar,
            afterJar: afterJar
        )
    }
    return ShovePlan(
        plays: true,
        tappable: false,
        text: "While we slept, \(formatCents(max(0, banked))) went into the jar.",
        billCents: max(0, banked),
        beforeJar: beforeJar,
        afterJar: afterJar
    )
}

/// A household zone in the shared database means this phone joined someone else's jar.
/// An empty lookup keeps the current role: a failed fetch must not turn a participant back into an owner.
func adoptSharedZone(isOwner: Bool, zoneOwner: String?, sharedZoneOwners: [String]) -> (isOwner: Bool, zoneOwner: String?) {
    guard !sharedZoneOwners.isEmpty else { return (isOwner, zoneOwner) }
    if let zoneOwner, sharedZoneOwners.contains(zoneOwner) { return (false, zoneOwner) }
    return (false, sharedZoneOwners[0])
}
