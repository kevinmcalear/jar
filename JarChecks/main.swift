import Foundation
import CryptoKit

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}

let week: [(cap: Int, spent: Int)] = [
    (5000, 0),
    (5000, 0),
    (5000, 0),
    (5000, 2000),
    (10000, 4000),
    (5000, 9000),
    (5000, 28000),
]
let weekScore = replay(week)
check(weekScore.jar == 0 && weekScore.debt == 3000, "sample week")

let loud = week + [
    (5000, 20000),
    (5000, 0),
    (5000, 0),
    (5000, 2000),
    (5000, 0),
    (5000, 0),
]
let loudDays = [
    (0, 18000),
    (0, 13000),
    (0, 8000),
    (0, 5000),
    (0, 0),
    (5000, 0),
]
var running = replay(week)
for (index, day) in loud.dropFirst(week.count).enumerated() {
    running = settle(jar: running.jar, debt: running.debt, cap: day.cap, spent: day.spent)
    check(running.jar == loudDays[index].0 && running.debt == loudDays[index].1, "loud day \(index)")
    check(running.jar >= 0 && running.debt >= 0 && (running.jar == 0 || running.debt == 0), "invariant \(index)")
}

check(pile(remainderCents: 3200) == [BillFace(cents: 1000, full: true), BillFace(cents: 1000, full: true), BillFace(cents: 1000, full: true), BillFace(cents: 200, full: false)], "32 pile")
check(pile(remainderCents: 5000).count == 5 && pile(remainderCents: 5000).allSatisfy(\.full), "50 pile")
check(pile(remainderCents: 0).isEmpty && pile(remainderCents: -100).isEmpty, "empty pile")
check(pile(remainderCents: 6400) == Array(repeating: BillFace(cents: 1000, full: true), count: 6) + [BillFace(cents: 400, full: false)], "64 pile")
check(quietDayCount(debt: 8000, usualCap: 5000) == 2, "two quiet days")
check(quietDayCount(debt: 18000, usualCap: 5000) == 4, "four quiet days")
check(quietDayCount(debt: 5000, usualCap: 5000) == 1, "one quiet day")

let open = project(jar: 14000, debt: 0, cap: 5000, spent: 1800)
check(open.jar == 17200 && open.debt == 0, "monday projection")
check(replay([]).jar == 0, "open day does not settle")

let tz = TimeZone(identifier: "America/New_York")!
func at(_ day: String, _ hour: Int, _ minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = tz
    let parts = day.split(separator: "-").compactMap { Int($0) }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute))!
}
check(openDay(now: at("2026-10-26", 23, 40), timeZone: tz, closeHour: 4) == "2026-10-26", "late monday")
check(openDay(now: at("2026-10-27", 1, 10), timeZone: tz, closeHour: 4) == "2026-10-26", "after midnight")
check(openDay(now: at("2026-10-27", 3, 59), timeZone: tz, closeHour: 4) == "2026-10-26", "before close")
check(openDay(now: at("2026-10-27", 4, 0), timeZone: tz, closeHour: 4) == "2026-10-27", "at close")
check(openDay(now: at("2026-10-27", 7, 0), timeZone: tz, closeHour: 4) == "2026-10-27", "tuesday coffee")

check(daysInYear(2026, timeZone: tz) == 365, "2026 length")
check(weekInterval(containing: "2026-10-26", timeZone: tz) == ("2026-10-26", "2026-11-01"), "monday week")
check(weeksTouching(year: 2026, month: 10, timeZone: tz).count == 5, "october weeks")
check(weeksTouching(year: 2026, month: 10, timeZone: tz).first?.start == "2026-09-28", "october starts midweek")

let income = yearCents(amount: 300_000, rhythm: .twiceMonth) + yearCents(amount: 200_000, rhythm: .twiceMonth)
let bills = yearCents(amount: 262_000, rhythm: .monthly)
let outside = yearCents(amount: 11_000, rhythm: .weekly) + 35_000
let fun = habitFunCents(daysInYear: 365, usualCap: 5000, openedCaps: [])
let yearLeft = realityLeft(income: income, fun: fun, outside: outside, bills: bills)
check(income == 12_000_000, "income year")
check(bills == 3_144_000, "bills year")
check(outside == 607_000, "outside year")
check(fun == 1_825_000, "habit year")
check(yearLeft == 6_424_000, "year left")

let groceriesMonth = monthlyCents(amount: 11_000, rhythm: .weekly)
check(groceriesMonth == 47_667, "groceries month")
let monthLeft = fiftyDollarMonthLeft(days: 30, incomeMonthly: 1_000_000, billsMonthly: 262_000, habitMonthly: groceriesMonth, oneTime: 35_000)
check(monthLeft == 505_333, "month left")
check(formatCents(monthLeft, nearestDollar: true) == "$5,053", "month headline")
check(formatCents(47_667, nearestDollar: true) == "$477", "groceries headline")
check(formatCents(6_424_000, nearestDollar: true) == "$64,240", "year headline")
check(formatCents(600) == "$6", "whole dollars")
check(formatCents(650) == "$6.50", "cents")

let short = fiftyDollarMonthLeft(days: 30, incomeMonthly: 400_000, billsMonthly: 260_000, habitMonthly: groceriesMonth, oneTime: 0)
check(short == -57_667, "short month")
check(formatCents(-short, nearestDollar: true) == "$577", "short headline")

let shove = shovePlan(beforeJar: 14000, beforeDebt: 0, afterJar: 17200, afterDebt: 0, days: [(5000, 1800)])
check(shove.plays && shove.billCents == 3200 && shove.text.contains("$32"), "shove 32")
let forgotten = shovePlan(beforeJar: 0, beforeDebt: 0, afterJar: 5000, afterDebt: 0, days: [(5000, 0)])
check(forgotten.tappable && forgotten.text.contains("Nothing was logged"), "forgotten day")
let exact = shovePlan(beforeJar: 14000, beforeDebt: 0, afterJar: 14000, afterDebt: 0, days: [(5000, 5000)])
check(!exact.plays && exact.text.contains("whole allowance"), "exact cap")

let salt = Data((0..<16).map { UInt8($0) })
let key = deriveHouseholdKey(passphrase: "test-passphrase", salt: salt)
let sealed = try sealField(centsPlaintext(600), record: "entry-1", field: "amount", key: key)
let opened = try openField(sealed, record: "entry-1", field: "amount", key: key)
let pasted = try? openField(sealed, record: "entry-2", field: "amount", key: key)
check(sealed != centsPlaintext(600), "ciphertext")
check(cents(from: opened) == 600, "round trip")
check(pasted == nil, "associated data")
let verifier = try sealField(householdVerifier, record: "settings", field: "verifier", key: key)
let verified = try openField(verifier, record: "settings", field: "verifier", key: key)
check(verified == householdVerifier, "verifier")
let wrong = deriveHouseholdKey(passphrase: "nope", salt: salt)
let rejected = try? openField(verifier, record: "settings", field: "verifier", key: wrong)
check(rejected == nil, "wrong passphrase")

let snacks = project(jar: 0, debt: 0, cap: 5000, spent: 600)
check(5000 - 600 == 4400, "remainder")
check(pile(remainderCents: 4400).filter(\.full).count == 4 && pile(remainderCents: 4400).last?.cents == 400, "short bill")
check(snacks.jar == 4400 && snacks.debt == 0, "projected bank")
check(replay([]).jar == 0 && replay([]).debt == 0, "open day stays unsettled")
print("ok")
