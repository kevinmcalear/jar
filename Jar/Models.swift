import Foundation

struct HouseholdSettings: Equatable {
    var timezone: String
    var closeHour: Int
    var usualCap: Int
    var usualCapChangedAt: String
    var usualCapSetBy: String?
    var savingsGoal: Int?
    var kdfSalt: Data?
    var kdfIterations: Int?
    var verifier: Data?
    var holderID: String?
    var isOwner: Bool
    var zoneOwner: String?
}

struct Person: Identifiable, Equatable {
    var id: String
    var displayName: String
    var sticker: String
}

struct JarCategory: Identifiable, Equatable {
    var id: String
    var name: String
    var enabled: Bool
    var builtIn: String?
    var sort: Int
    var updatedAt: String
}

struct DayRow: Identifiable, Equatable {
    var id: String { date }
    var date: String
    var cap: Int
    var settled: Bool
}

struct Entry: Identifiable, Equatable {
    var id: String
    var day: String
    var personID: String?
    var amount: Int
    var kind: String
    var categoryID: String?
    var chip: String?
    var rhythm: String?
    var note: String?
    var photo: Data?
    var createdAt: String
    var updatedAt: String
    var originLocal: Bool
}

struct MoneyRow: Identifiable, Equatable {
    var id: String
    var name: String
    var amount: Int
    var rhythm: String
}

struct Snapshot: Equatable {
    var settings: HouseholdSettings?
    var people: [Person] = []
    var categories: [JarCategory] = []
    var days: [DayRow] = []
    var entries: [Entry] = []
    var income: [MoneyRow] = []
    var bills: [MoneyRow] = []
    var pourSeen: Set<String> = []
}

enum Chip: String, CaseIterable, Identifiable {
    case groceries, flight, home, health, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .groceries: "Groceries"
        case .flight: "Flight"
        case .home: "Home"
        case .health: "Health"
        case .other: "Other"
        }
    }
    var defaultRhythm: PayRhythm { self == .groceries ? .weekly : .once }
}

enum Picture: Equatable {
    case quiet(cap: Int)
    case growing(remainder: Int, shove: Int, cap: Int)
    case borrowing(amount: Int)
    case exact(cap: Int)
    case hole(debt: Int, remainder: Int)
    case climb(debt: Int, days: Int, usualCap: Int, remainder: Int)
}

let builtInCategories: [(key: String, name: String)] = [
    ("worklunch", "Work lunch"),
    ("cocktails", "Cocktails"),
    ("coffee", "Coffee"),
    ("date", "Date"),
    ("friends", "Friends"),
    ("wine", "Wine"),
    ("eating", "Eating out"),
    ("delivery", "Delivery"),
    ("snacks", "Snacks"),
    ("blowdry", "Blow-dries"),
    ("activity", "Activity"),
    ("clothes", "Clothes"),
]

func stamp(_ date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

func rhythmTitle(_ raw: String) -> String {
    switch PayRhythm(rawValue: raw) {
    case .weekly: "Weekly"
    case .biweekly: "Every two weeks"
    case .twiceMonth: "Twice a month"
    case .monthly: "Monthly"
    case .once, nil: "Once"
    }
}

func closeClock(_ hour: Int) -> String {
    let wrapped = ((hour % 24) + 24) % 24
    let suffix = wrapped < 12 ? "am" : "pm"
    let face = wrapped % 12 == 0 ? 12 : wrapped % 12
    return "\(face)\(suffix)"
}

func countWord(_ value: Int) -> String {
    let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
    return value >= 0 && value < words.count ? words[value] : String(value)
}
