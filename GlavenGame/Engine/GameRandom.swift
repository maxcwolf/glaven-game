import Foundation

/// The random number generator behind every shuffle and random draw in the game (modifier decks,
/// monster ability decks, short-rest card loss, random rewards).
///
/// Seeded from the system generator by default. Tests reseed it so a whole scenario replays
/// identically: `GameRandom.shared = GameRandom(seed: 42)`.
struct GameRandom: RandomNumberGenerator {
    /// The generator the game draws from. Pass it as `&GameRandom.shared` to the standard
    /// library's `shuffle(using:)`, `randomElement(using:)` and `random(in:using:)`.
    static var shared = GameRandom()

    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    init() {
        var system = SystemRandomNumberGenerator()
        state = system.next()
    }

    /// A version-4 UUID drawn from the shared generator, so figures created during play (summons)
    /// get the same identifiers when a seeded game is replayed.
    static func uuid() -> UUID {
        let high = shared.next(), low = shared.next()
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: high >> (8 * i))
            bytes[i + 8] = UInt8(truncatingIfNeeded: low >> (8 * i))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40 // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// SplitMix64: small, fast and well distributed — plenty for shuffling decks.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
