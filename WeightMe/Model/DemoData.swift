import Foundation

/// Realistic-looking multi-year history used for demo mode, previews and seeding the simulator.
enum DemoData {
    static func entries(endingAt end: Date = .now, seed: UInt64 = 42) -> [WeightEntry] {
        var rng = SeededGenerator(seed: seed)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: end)
        let totalDays = 4 * 365 + 120
        let start = calendar.date(byAdding: .day, value: -totalDays, to: today)!

        // Piecewise-linear "true weight" in lb: lose, plateau, regain, lose again.
        let knots: [(day: Int, lb: Double)] = [
            (0, 236), (200, 204), (330, 198), (520, 212), (640, 214), (900, 192), (1100, 186), (1300, 190), (totalDays, 181.5),
        ]
        func trueWeight(_ day: Int) -> Double {
            for i in 1..<knots.count where day <= knots[i].day {
                let a = knots[i - 1], b = knots[i]
                let t = Double(day - a.day) / Double(b.day - a.day)
                return a.lb + (b.lb - a.lb) * t
            }
            return knots.last!.lb
        }

        var result: [WeightEntry] = []
        for day in 0...totalDays {
            // A ~3 month gap with no data at all (stopped tracking).
            if (560...650).contains(day) { continue }
            let date = calendar.date(byAdding: .day, value: day, to: start)!
            let weekday = calendar.component(.weekday, from: date)
            let weekendBump = (weekday == 1 || weekday == 2) ? 0.9 : 0
            let noise = Double.random(in: -1.4...1.4, using: &rng) + weekendBump

            let source: (name: String, bundle: String, own: Bool, skip: Double, hour: Int)
            switch day {
            case ..<700: source = ("Lose It!", "com.fitnow.loseit", false, 0.25, 7)
            case ..<(totalDays - 60): source = ("Withings", "com.withings.wiScaleNG", false, 0.12, 6)
            default: source = ("WeightMe", "com.vladf1.WeightMe", true, 0.1, 7)
            }
            if Double.random(in: 0...1, using: &rng) < source.skip { continue }
            let minute = Int.random(in: 0..<50, using: &rng)
            let stamp = calendar.date(bySettingHour: source.hour, minute: minute, second: 0, of: date)!
            let lb = (trueWeight(day) + noise) * 10
            result.append(WeightEntry(date: stamp, kg: WeightUnit.pounds.kilograms(from: lb.rounded() / 10),
                                      sourceName: source.name, sourceBundleID: source.bundle, isOwn: source.own))
            // Occasional second weigh-in later the same day.
            if Double.random(in: 0...1, using: &rng) < 0.06 {
                let evening = calendar.date(bySettingHour: 21, minute: minute, second: 0, of: date)!
                let lb2 = ((trueWeight(day) + noise + 1.6) * 10).rounded() / 10
                result.append(WeightEntry(date: evening, kg: WeightUnit.pounds.kilograms(from: lb2),
                                          sourceName: "Health", sourceBundleID: "com.apple.Health", isOwn: false))
            }
        }
        return result
    }
}

/// Small deterministic PRNG (SplitMix64) so demo data is identical between runs.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
