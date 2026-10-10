import XCTest
import AVFoundation
@testable import GlavenGameLib

/// The bundled audio is mastered at the level it plays. These tests measure every file the way
/// the sound audit did and hold the mix in place: variants of a cue match, the big moments are
/// the loud ones, and nothing cosmetic sits on top of a blow.
final class SoundAssetTests: XCTestCase {

    /// How loud a file plays, in dB: the loudest 100 ms of the signal, weighted roughly as the
    /// ear hears it (rumble below 100 Hz counts for less, presence above 1.5 kHz for more).
    private static func level(of url: URL, gain: Float) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let frames = Int(buffer.frameLength), channels = Int(format.channelCount)
        let data = try XCTUnwrap(buffer.floatChannelData)
        var mono = [Double](repeating: 0, count: frames)
        for channel in 0..<channels {
            for frame in 0..<frames { mono[frame] += Double(data[channel][frame]) / Double(channels) }
        }
        let rate = format.sampleRate
        let weighted = zip(butterworthHighPass(mono, cutoff: 100, rate: rate),
                           highPass(mono, cutoff: 1500, rate: rate)).map { $0 + 0.6 * $1 }
        let window = Int(rate * 0.1)
        var loudest = 0.0
        var start = 0
        repeat {
            let slice = weighted[start..<min(frames, start + window)]
            loudest = max(loudest, (slice.reduce(0) { $0 + $1 * $1 } / Double(max(1, slice.count))).squareRoot())
            start += window / 4
        } while start + window <= frames
        return 20 * log10(max(loudest, 1e-9)) + 20 * log10(Double(gain))
    }

    /// Second-order Butterworth high-pass.
    private static func butterworthHighPass(_ x: [Double], cutoff: Double, rate: Double) -> [Double] {
        let w = 2 * Double.pi * cutoff / rate, alpha = sin(w) / (2 * 0.5.squareRoot()), c = cos(w)
        let a0 = 1 + alpha
        let b = [(1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0], a = [-2 * c / a0, (1 - alpha) / a0]
        var y = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let x1 = i > 0 ? x[i - 1] : 0, x2 = i > 1 ? x[i - 2] : 0
            let y1 = i > 0 ? y[i - 1] : 0, y2 = i > 1 ? y[i - 2] : 0
            y[i] = b[0] * x[i] + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2
        }
        return y
    }

    /// One-pole high-pass.
    private static func highPass(_ x: [Double], cutoff: Double, rate: Double) -> [Double] {
        let rc = 1 / (2 * Double.pi * cutoff), dt = 1 / rate, a = rc / (rc + dt)
        var y = [Double](repeating: 0, count: x.count)
        for i in 1..<max(1, x.count) { y[i] = a * (y[i - 1] + x[i] - x[i - 1]) }
        return y
    }

    private static var measured: [BoardSound: [Double]] = [:]

    private func levels(_ sound: BoardSound) throws -> [Double] {
        if let known = Self.measured[sound] { return known }
        let levels = try sound.files.map { try Self.level(of: $0, gain: sound.volume) }
        Self.measured[sound] = levels
        return levels
    }

    private func level(_ sound: BoardSound) throws -> Double {
        let all = try levels(sound)
        return all.reduce(0, +) / Double(all.count)
    }

    /// Regression: the three card-draw variants were 12 dB apart and the two coin variants 10 dB,
    /// so every other draw or pickup was close to silent.
    func testVariantsOfACueMatchInLevel() throws {
        for sound in BoardSound.allCases {
            let all = try levels(sound)
            let spread = (all.max() ?? 0) - (all.min() ?? 0)
            XCTAssertLessThanOrEqual(spread, 3, "\(sound) variants play within 3 dB of each other, not \(all.map { String(format: "%.1f", $0) })")
        }
    }

    /// Regression: a heavy hit was no louder than a light one, and a trap was quieter than both.
    func testTheBigMomentsAreTheLoudOnes() throws {
        let hit = try level(.hit)
        XCTAssertGreaterThanOrEqual(try level(.heavyHit), hit + 1.5, "a heavy hit is clearly bigger")
        XCTAssertGreaterThanOrEqual(try level(.trap), hit, "a trap is at least a hit")
        XCTAssertGreaterThanOrEqual(try level(.exhaust), hit, "a character going down is at least a hit")
    }

    /// Regression: the chime for a helpful condition was the loudest sound in the game.
    func testConditionsSitUnderTheBlowThatCarriesThem() throws {
        let hit = try level(.hit)
        for sound in BoardSound.allCases where sound.isCondition {
            XCTAssertLessThanOrEqual(try level(sound), hit - 2, "\(sound)")
        }
    }

    func testThePlayersOwnTapsAreTheQuietCues() throws {
        let hit = try level(.hit)
        for sound in [BoardSound.cardPick, .cardConfirm, .target, .endTurn, .invalid, .card, .shuffle, .rest, .lose] {
            XCTAssertLessThanOrEqual(try level(sound), hit - 5, "\(sound)")
        }
        let step = try level(.step)
        for sound in BoardSound.allCases where sound != .step {
            XCTAssertGreaterThan(try level(sound), step, "footsteps sit under \(sound)")
        }
    }

    func testNothingIsLouderThanAHeavyHitByMuch() throws {
        let ceiling = try level(.heavyHit) + 1.5
        for sound in BoardSound.allCases {
            for (index, level) in try levels(sound).enumerated() {
                XCTAssertLessThanOrEqual(level, ceiling, "\(sound.rawValue)-\(index)")
            }
        }
    }

    /// A cue is over quickly: nothing but a jingle runs past two and a half seconds.
    func testCuesAreShort() throws {
        for sound in BoardSound.allCases {
            for url in sound.files {
                let file = try AVAudioFile(forReading: url)
                let seconds = Double(file.length) / file.processingFormat.sampleRate
                XCTAssertLessThanOrEqual(seconds, 2.5, url.lastPathComponent)
                XCTAssertGreaterThan(seconds, 0.03, url.lastPathComponent)
            }
        }
    }

    /// Prints the mix, for docs/sound-design.md: `SOUND_LEVELS=1 swift test --filter testPrintTheMix`.
    func testPrintTheMix() throws {
        guard ProcessInfo.processInfo.environment["SOUND_LEVELS"] == "1" else { return }
        for sound in BoardSound.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let all = try levels(sound).map { String(format: "%.1f", $0) }.joined(separator: ", ")
            print("LEVEL \(sound.rawValue): \(all)")
        }
    }
}
