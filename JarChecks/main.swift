import CoreGraphics
import CryptoKit
import Foundation

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
check(replay([(cap: 5000, spent: 4500)]).jar == 500, "five dollars left banks")
check(firstDayToBank(open: "2026-10-27", latestSettled: nil, knownDays: ["2026-10-26", "2026-10-27"], timeZone: tz) == "2026-10-26", "an unsettled yesterday still banks")
check(firstDayToBank(open: "2026-10-27", latestSettled: "2026-10-24", knownDays: [], timeZone: tz) == "2026-10-25", "resume after the last closed day")
check(firstDayToBank(open: "2026-10-27", latestSettled: nil, knownDays: ["2026-10-27"], timeZone: tz) == nil, "today stays open")
check(firstDayToBank(open: "2026-10-27", latestSettled: "2026-10-26", knownDays: ["2026-10-26"], timeZone: tz) == nil, "yesterday already banked")

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
check(adoptSharedZone(isOwner: true, zoneOwner: nil, sharedZoneOwners: []).isOwner, "no share stays owner")
check(adoptSharedZone(isOwner: false, zoneOwner: "kevin", sharedZoneOwners: []).zoneOwner == "kevin", "failed lookup keeps participant")
let joined = adoptSharedZone(isOwner: true, zoneOwner: nil, sharedZoneOwners: ["kevin"])
check(!joined.isOwner && joined.zoneOwner == "kevin", "shared zone joins their jar")
check(adoptSharedZone(isOwner: false, zoneOwner: "kevin", sharedZoneOwners: ["bridget", "kevin"]).zoneOwner == "kevin", "keeps the zone already joined")
check(entryRetry(problem: .schema, attempt: 0, alreadyDroppedReferences: false) == EntryRetry(retry: true, dropReferences: false, dropNames: true), "a schema rejection is sent again without the names")
check(!entryRetry(problem: .conflict, attempt: 0, alreadyDroppedReferences: false).retry, "the server copy is already there")
check(entryRetry(problem: .missingReference, attempt: 0, alreadyDroppedReferences: false) == EntryRetry(retry: true, dropReferences: true, dropNames: false), "a missing person does not block the spend")
let household = [(id: "kevin", name: "Kevin", sticker: "kevin"), (id: "bridget", name: "Bridget", sticker: "bridget")]
check(resolvedPersonID(people: household, reference: "missing", name: "Bridget", sticker: "bridget") == "bridget", "a missing person id uses her sticker")
check(resolvedPersonID(people: household, reference: "kevin", name: "Bridget", sticker: "bridget") == "kevin", "a real person id stays")
let lunch = [(id: "lunch", name: "Work lunch"), (id: "gifts", name: "Gifts")]
check(resolvedCategoryID(categories: lunch, reference: "missing", name: "Work lunch") == "lunch", "a missing category id uses its name")
check(resolvedCategoryID(categories: lunch, reference: "gifts", name: "Work lunch") == "gifts", "a real category id stays")
check(!entryRetry(problem: .missingReference, attempt: 1, alreadyDroppedReferences: true).retry, "a bare spend is not retried forever")
check(!entryRetry(problem: .batch, attempt: 2, alreadyDroppedReferences: false).retry, "give up after two failures")

let snacks = project(jar: 0, debt: 0, cap: 5000, spent: 600)
check(5000 - 600 == 4400, "remainder")
check(pile(remainderCents: 4400).filter(\.full).count == 4 && pile(remainderCents: 4400).last?.cents == 400, "short bill")
check(billRowWidth(pile(remainderCents: 5000)) == 392, "five bills")
check(billRowWidth(pile(remainderCents: 4400)) == 366, "short bill width")
check(billRowWidth([]) == 0, "no bills")
check(isCloudKitShareURL(URL(string: "https://www.icloud.com/share/0abc")!), "icloud share link")
check(!isCloudKitShareURL(URL(string: "jar://add")!), "widget link is not a share")
check(!isCloudKitShareURL(URL(string: "https://www.icloud.com/notes/")!), "other icloud page")
check(shouldPromptToUnlock(passphraseReset: false, hasKey: false), "face id when the key is missing")
check(!shouldPromptToUnlock(passphraseReset: true, hasKey: false), "passphrase instead of a face id loop")
check(!shouldPromptToUnlock(passphraseReset: false, hasKey: true), "loaded key skips face id")
check(canEditJarDay("2026-10-26", open: "2026-10-27"), "yesterday can change")
check(canEditJarDay("2026-10-20", open: "2026-10-27"), "an older day can change")
check(canEditJarDay("2026-10-27", open: "2026-10-27"), "today can change")
check(!canEditJarDay("2026-10-28", open: "2026-10-27"), "tomorrow stays put")
let coffee = [
    DuplicateRow(id: "hers", updatedAt: "2026-10-27T12:00:00.000Z", uses: 0),
    DuplicateRow(id: "his", updatedAt: "2026-10-26T12:00:00.000Z", uses: 2),
]
check(keptDuplicate(coffee) == "his", "keep the category spends use")
check(keptDuplicate([
    DuplicateRow(id: "older-empty", updatedAt: "2026-10-20T12:00:00.000Z", uses: 0),
    DuplicateRow(id: "newer-used", updatedAt: "2026-10-27T12:00:00.000Z", uses: 3),
]) == "newer-used", "spends beat an older empty copy")
check(keptDuplicate([
    DuplicateRow(id: "later", updatedAt: "2026-10-27T12:00:00.000Z", uses: 0),
    DuplicateRow(id: "earlier", updatedAt: "2026-10-26T12:00:00.000Z", uses: 0),
]) == "earlier", "unused tie keeps the older copy")
check(keptDuplicate([
    DuplicateRow(id: "b", updatedAt: "", uses: 0),
    DuplicateRow(id: "a", updatedAt: "", uses: 0),
]) == "a", "equal people keep the smaller id")
check(keptDuplicate([DuplicateRow(id: "only", updatedAt: "2026-10-26T12:00:00.000Z", uses: 1)]) == "only", "one copy stays")
check(keptDuplicate([]) == nil, "nothing to keep")
check(faceForOrphanSpends(people: [(id: "kevin", referenced: true), (id: "bridget", referenced: false)]) == "bridget", "orphaned spends belong to the person with none")
check(faceForOrphanSpends(people: [(id: "kevin", referenced: true), (id: "bridget", referenced: true)]) == nil, "everyone already has spends")
check(faceForOrphanSpends(people: [(id: "kevin", referenced: false), (id: "bridget", referenced: false)]) == nil, "two empty people stay put")
check(snacks.jar == 4400 && snacks.debt == 0, "projected bank")
check(replay([]).jar == 0 && replay([]).debt == 0, "open day stays unsettled")

check(nextJarStep(.category, tookPhoto: false) == .amount, "category then amount")
check(nextJarStep(.amount, tookPhoto: false) == .photo, "amount then photo")
check(nextJarStep(.photo, tookPhoto: false) == nil, "skip photo saves")
check(nextJarStep(.photo, tookPhoto: true) == nil, "a photo saves as a sticker")
check(pileLeftCents(cap: 5000, spent: 600) == 4400, "pile left")
check(pileLeftCents(cap: 5000, spent: 5000) == 0, "pile gone")
check(pileLeftCents(cap: 5000, spent: 8000) == 0, "overspend leaves an empty pile")
check(shouldPostSpendNotice(kind: "jar", noticesLive: true, changed: true), "a new or edited jar spend")
check(!shouldPostSpendNotice(kind: "outside", noticesLive: true, changed: true), "outside is quiet")
check(!shouldPostSpendNotice(kind: "jar", noticesLive: true, changed: false), "unchanged spend is quiet")
check(!shouldPostSpendNotice(kind: "jar", noticesLive: false, changed: true), "first sync is quiet")
check(spendNoticeBody(amount: 650, note: nil, left: 2150) == "$6.50 · $21.50 left", "notice is the amount and what is left")
check(spendNoticeBody(amount: 650, note: "iced latte", left: 2150) == "$6.50 · iced latte · $21.50 left", "notice includes the note")
check(spendNoticeBody(amount: 650, note: "  ", left: 2150) == "$6.50 · $21.50 left", "a blank note stays out")
check(spendNoticeBody(amount: 650, note: "iced latte", left: 2150, removed: true) == "Removed $6.50", "a removed spend says so")
check(sealMark("  snacks ") == "S", "seal letter")
check(sealMark("!!!") == "", "seal shape when there is no letter")

let red = solidImage(CGColor(red: 1, green: 0, blue: 0, alpha: 1), width: 8, height: 8)
let mask = grayMask(width: 8, height: 8) { x, y in (2..<6).contains(x) && (2..<6).contains(y) }
if let red, let mask, let cut = dieCut(image: red, mask: mask, stroke: 2), let bytes = rgba(cut) {
    check(cut.width == 12 && cut.height == 12, "die-cut pad")
    var clear = 0, white = 0, subject = 0
    for index in stride(from: 0, to: bytes.count, by: 4) {
        let r = bytes[index], g = bytes[index + 1], b = bytes[index + 2], a = bytes[index + 3]
        if a < 10 { clear += 1 }
        else if r > 230 && g > 230 && b > 230 { white += 1 }
        else if r > 200 && g < 80 && a > 200 { subject += 1 }
    }
    check(clear > 0 && white > 0 && subject > 0, "die-cut keeps the photo inside a white edge")
} else {
    check(false, "die-cut image")
}
print("ok")

func solidImage(_ color: CGColor, width: Int, height: Int) -> CGImage? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(color)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()
}

func grayMask(width: Int, height: Int, includes: (Int, Int) -> Bool) -> CGImage? {
    let space = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue), let data = ctx.data else { return nil }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
    for y in 0..<height {
        for x in 0..<width {
            pixels[y * width + x] = includes(x, y) ? 255 : 0
        }
    }
    return ctx.makeImage()
}

func rgba(_ image: CGImage) -> [UInt8]? {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}
