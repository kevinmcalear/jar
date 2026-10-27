import Foundation

enum PileBoard {
    static let suite = "group.com.kevinmcalear.dailyjar"
    static let add = URL(string: "jar://add")!
    private static let key = "left"

    // ponytail: the widget shows the last leftover this phone wrote. It does not open the store. A shared database would refresh it without launching Jar.
    static func write(_ cents: Int) {
        UserDefaults(suiteName: suite)?.set(cents, forKey: key)
    }

    static func read() -> Int? {
        guard let defaults = UserDefaults(suiteName: suite), defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }
}

func pileLeftCents(cap: Int, spent: Int) -> Int {
    max(0, cap - spent)
}
