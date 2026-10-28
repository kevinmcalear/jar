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

/// The glass doubles when it fills: $50, then $100, then $200. Exactly $50 is still the first glass, full. The next dollar is a bigger glass filling toward $100.
func jarCapacity(cents: Int) -> Int {
    if cents <= 0 { return 5000 }
    var capacity = 5000
    while capacity < cents {
        let next = capacity * 2
        if next <= capacity { return capacity }
        capacity = next
    }
    return capacity
}

func jarFill(cents: Int) -> Double {
    guard cents > 0 else { return 0 }
    return min(1, Double(cents) / Double(jarCapacity(cents: cents)))
}

/// Full jars the balance passes on the way up. Landing on $50 is still that jar. The next cent is the $100 jar.
func jarCrossings(from before: Int, to after: Int) -> [Int] {
    guard after > before else { return [] }
    var step = 5000
    var crossed: [Int] = []
    while step < after, crossed.count < 6 {
        if step > before { crossed.append(step) }
        let next = step * 2
        if next <= step { break }
        step = next
    }
    return crossed
}

/// What a spend takes off today's pile, and what it has to pull out of the jar once the pile is gone.
func spentSplit(amount: Int, beforeSpent: Int, cap: Int) -> (pile: Int, jar: Int) {
    let room = max(0, cap - max(0, beforeSpent))
    let fromPile = min(max(0, amount), room)
    return (fromPile, max(0, amount) - fromPile)
}

func unitRamp(_ t: Double, _ start: Double, _ end: Double) -> Double {
    guard end > start else { return t >= end ? 1 : 0 }
    let x = min(1, max(0, (t - start) / (end - start)))
    return x * x * (3 - 2 * x)
}

struct FacePose: Equatable {
    var headScale: Double
    var wiggle: Double
    var headY: Double
    var headAlpha: Double
    var fly: Double
    var billAlpha: Double
}

/// Head pops in at the top, swells and wiggles, bills fly into the face, then the head leaves off the top.
func facePose(at t: Double) -> FacePose {
    let time = min(1, max(0, t))
    let appear = unitRamp(time, 0, 0.14)
    let swell = unitRamp(time, 0.12, 0.32)
    let leave = unitRamp(time, 0.72, 1)
    let wiggling = time > 0.16 && time < 0.58
    let wiggle = wiggling ? sin((time - 0.16) / 0.42 * .pi * 4) * 14 : 0
    let headScale = 0.35 + 0.65 * appear + 0.4 * swell + 0.15 * leave
    let fly = unitRamp(time, 0.34, 0.68)
    let billAlpha = time < 0.66 ? 1 : max(0, 1 - (time - 0.66) / 0.12)
    return FacePose(headScale: headScale, wiggle: wiggle, headY: -640 * leave, headAlpha: appear, fly: fly, billAlpha: billAlpha)
}

func nextJarUpgrade(cents: Int) -> Int {
    let current = jarCapacity(cents: cents)
    let next = current * 2
    return next > current ? next : current
}

func jarSizeLine(cents: Int) -> String {
    "\(formatCents(jarCapacity(cents: cents))) jar"
}

func nextJarLine(cents: Int) -> String {
    "next jar upgrade at \(formatCents(nextJarUpgrade(cents: cents)))"
}

struct ShovePose: Equatable {
    var billY: Double
    var billAlpha: Double
    var fill: Double
    var scale: Double
    var goal: Int
    var upgraded: Bool
}

/// Leftover bills rise, then drop into the mouth. Crossing a full jar swells the glass and lets it settle back at the next goal.
func shovePose(at t: Double, beforeJar: Int, afterJar: Int) -> ShovePose {
    let time = min(1, max(0, t))
    let crossings = jarCrossings(from: beforeJar, to: afterJar)
    let startFill = jarFill(cents: beforeJar)
    let endFill = jarFill(cents: afterJar)
    let rise = unitRamp(time, 0.04, 0.38)
    let drop = unitRamp(time, 0.38, 0.62)
    let billY = 110 + (-310) * rise + 220 * drop
    let billAlpha = time < 0.55 ? 1 : max(0, 1 - (time - 0.55) / 0.18)
    var fill = startFill
    var scale = 1.0
    var goal = jarCapacity(cents: beforeJar)
    if crossings.isEmpty {
        fill = startFill + (endFill - startFill) * unitRamp(time, 0.4, 0.78)
    } else {
        let toFull = unitRamp(time, 0.28, 0.52)
        let reset = unitRamp(time, 0.52, 0.66)
        let settle = unitRamp(time, 0.66, 0.92)
        if time < 0.52 {
            fill = startFill + (1 - startFill) * toFull
        } else if time < 0.66 {
            fill = 1 - reset
        } else {
            fill = endFill * settle
        }
        let swellUp = unitRamp(time, 0.46, 0.6)
        let swellDown = unitRamp(time, 0.68, 0.92)
        scale = 1 + 0.45 * swellUp * (1 - swellDown)
        if time >= 0.6 { goal = jarCapacity(cents: afterJar) }
    }
    let passed = !crossings.isEmpty && scale > 1 && goal != jarCapacity(cents: beforeJar)
    return ShovePose(billY: billY, billAlpha: billAlpha, fill: fill, scale: scale, goal: goal, upgraded: passed)
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
/// Spends left pointing at a deleted person land on the one person who currently has none.
func faceForOrphanSpends(people: [(id: String, referenced: Bool)]) -> String? {
    let unused = people.filter { !$0.referenced }
    return unused.count == 1 ? unused[0].id : nil
}

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

/// Closed days bank into the jar. The chain resumes after the last settled day, or at the earliest closed day when none have settled yet.
func firstDayToBank(open: String, latestSettled: String?, knownDays: [String], timeZone: TimeZone) -> String? {
    if let latestSettled {
        let next = addDays(latestSettled, 1, timeZone: timeZone)
        return next < open ? next : nil
    }
    return knownDays.filter { $0 < open }.min()
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

func monthsWithDays(_ days: [String], year: Int) -> [String] {
    let prefix = String(format: "%04d-", year)
    return Set(days.filter { $0.hasPrefix(prefix) }.map { String($0.prefix(7)) }).sorted()
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

func weekRangeTitle(start: String, end: String, timeZone: TimeZone) -> String {
    let startDate = date(from: start, timeZone: timeZone) ?? Date()
    let endDate = date(from: end, timeZone: timeZone) ?? Date()
    let month = DateFormatter()
    month.locale = Locale(identifier: "en_US_POSIX")
    month.timeZone = timeZone
    month.dateFormat = "MMM"
    let day = DateFormatter()
    day.locale = Locale(identifier: "en_US_POSIX")
    day.timeZone = timeZone
    day.dateFormat = "d"
    if month.string(from: startDate) == month.string(from: endDate) {
        return "\(month.string(from: startDate)) \(day.string(from: startDate)) – \(day.string(from: endDate))"
    }
    return "\(month.string(from: startDate)) \(day.string(from: startDate)) – \(month.string(from: endDate)) \(day.string(from: endDate))"
}

struct MonthWeekSpend: Equatable, Identifiable {
    var start: String
    var end: String
    var spent: Int
    var id: String { start }
}

/// Every week that touches the month, then the month total. A week that starts in the previous month only counts days inside this month, so the weeks add up.
func monthWeeks(entries: [(day: String, amount: Int)], year: Int, month: Int, timeZone: TimeZone) -> (weeks: [MonthWeekSpend], total: Int) {
    let prefix = String(format: "%04d-%02d-", year, month)
    let weeks = weeksTouching(year: year, month: month, timeZone: timeZone).map { week in
        let spent = entries.reduce(0) { sum, entry in
            entry.day >= week.start && entry.day <= week.end && entry.day.hasPrefix(prefix) ? sum + entry.amount : sum
        }
        return MonthWeekSpend(start: week.start, end: week.end, spent: spent)
    }
    let total = entries.reduce(0) { $1.day.hasPrefix(prefix) ? $0 + $1.amount : $0 }
    return (weeks, total)
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

enum EntrySaveProblem: Equatable {
    case conflict
    case schema
    case missingReference
    case asset
    case batch
    case other
}

struct EntryRetry: Equatable {
    var retry: Bool
    var dropReferences: Bool
    var dropNames: Bool
    var dropPhoto: Bool = false
}

/// A rejected upload has to be sent again. A conflict means the server already has the record. A dangling person or category is dropped once so the spend itself still uploads. A schema rejection is sent again without the name fields. A photo CloudKit cannot read is dropped so the spend still arrives.
func entryRetry(problem: EntrySaveProblem, attempt: Int, alreadyDroppedReferences: Bool) -> EntryRetry {
    switch problem {
    case .conflict:
        return EntryRetry(retry: false, dropReferences: false, dropNames: false)
    case .missingReference:
        return EntryRetry(retry: attempt < 2, dropReferences: true, dropNames: false, dropPhoto: alreadyDroppedReferences)
    case .schema:
        return EntryRetry(retry: attempt < 2, dropReferences: alreadyDroppedReferences, dropNames: true)
    case .asset:
        return EntryRetry(retry: attempt < 2, dropReferences: alreadyDroppedReferences, dropNames: false, dropPhoto: true)
    case .batch:
        return EntryRetry(retry: attempt < 2, dropReferences: alreadyDroppedReferences, dropNames: false)
    case .other:
        return EntryRetry(retry: attempt < 2, dropReferences: true, dropNames: true, dropPhoto: true)
    }
}

/// The other phone may have deleted the duplicate person this spend points at. The sticker, then the name, picks the one still here.
func resolvedPersonID(people: [(id: String, name: String, sticker: String)], reference: String?, name: String?, sticker: String?) -> String? {
    if let reference, people.contains(where: { $0.id == reference }) { return reference }
    if let sticker, let match = people.first(where: { $0.sticker == sticker }) { return match.id }
    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmed.isEmpty, let match = people.first(where: { $0.name == trimmed }) { return match.id }
    return reference
}

/// Same for a category the other phone collapsed away. The name picks the one still here.
func resolvedCategoryID(categories: [(id: String, name: String)], reference: String?, name: String?) -> String? {
    if let reference, categories.contains(where: { $0.id == reference }) { return reference }
    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmed.isEmpty, let match = categories.first(where: { $0.name == trimmed }) { return match.id }
    return reference
}

/// The other phone may still point this spend at a person or category this phone deleted. Keep the face already on the row until the name resolves to one that is still here.
func adoptedFaceID(resolved: String?, living: [String], current: String?) -> String? {
    guard let resolved, living.contains(resolved) else { return current }
    return resolved
}

/// A household zone in the shared database means this phone joined someone else's jar.
/// An empty lookup keeps the current role: a failed fetch must not turn a participant back into an owner.
func adoptSharedZone(isOwner: Bool, zoneOwner: String?, sharedZoneOwners: [String]) -> (isOwner: Bool, zoneOwner: String?) {
    guard !sharedZoneOwners.isEmpty else { return (isOwner, zoneOwner) }
    if let zoneOwner, sharedZoneOwners.contains(zoneOwner) { return (false, zoneOwner) }
    return (false, sharedZoneOwners[0])
}
