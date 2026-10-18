import Foundation
import IConKit

/// Persists the arrangement in UserDefaults.
struct ArrangementStore {
    private let key = "arrangement"

    func load() -> Arrangement {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arrangement = try? JSONDecoder().decode(Arrangement.self, from: data)
        else { return Arrangement() }
        return arrangement
    }

    func save(_ arrangement: Arrangement) {
        UserDefaults.standard.set(try? JSONEncoder().encode(arrangement), forKey: key)
    }
}
