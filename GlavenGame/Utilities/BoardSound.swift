import AVFoundation

/// The board's sound cues. The audio is Kenney's RPG, impact, interface and jingle packs (CC0; see
/// Resources/Sounds/CREDITS.txt), shipped as `<cue>-<n>.m4a` with one or more variants.
enum BoardSound: String, CaseIterable {
    case step, hit, heavyHit = "hit-heavy", blocked, miss, death, land, heal, loot, door, teleport
    /// A hindering condition lands (stun, poison…) or a helpful one (strengthen, bless…).
    case harm, boon
    /// An attack modifier card is drawn.
    case card
    case trap
    /// A character's turn begins.
    case turn
    /// Jingles: a scenario begins, is won, is lost.
    case start, victory, defeat

    /// Footsteps sit under everything else.
    var volume: Float { self == .step ? 0.35 : 0.8 }

    /// The bundled files for this cue, in variant order (looked up once, not on every footstep).
    var files: [URL] { Self.bundledFiles[self] ?? [] }

    private static let bundledFiles: [BoardSound: [URL]] = Dictionary(uniqueKeysWithValues: allCases.map { sound in
        (sound, (0..<8).compactMap {
            appResourceBundle.url(forResource: "\(sound.rawValue)-\($0)", withExtension: "m4a", subdirectory: "Sounds")
        })
    })
}

/// Plays board sounds when the player has sound effects on. Variants take turns rather than
/// being picked at random, so cosmetic sound never draws from the game's seeded randomness.
@MainActor
enum BoardSoundPlayer {
    private static var players: [URL: AVAudioPlayer] = [:]
    private static var nextVariant: [BoardSound: Int] = [:]
    private static var sessionReady = false

    /// The file a cue plays next, cycling through its variants.
    static func nextFile(for sound: BoardSound) -> URL? {
        let files = sound.files
        guard !files.isEmpty else { return nil }
        let index = nextVariant[sound, default: 0] % files.count
        nextVariant[sound] = index + 1
        return files[index]
    }

    /// Silent under the test runner: tests show the board in real views, and their door
    /// openings and hits used to play through the speakers of whoever ran the suite. Silent in a
    /// soak run (`GLAVEN_SOAK=1`) too, which plays game after game for hours.
    static let isSilenced = NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["GLAVEN_SOAK"] == "1"

    /// Sounds actually started (for tests).
    private(set) static var playedCount = 0

    static func play(_ sound: BoardSound) {
        guard !isSilenced, SoundPlayer.settingsManager?.soundEffects ?? true,
              let url = nextFile(for: sound) else { return }
        playedCount += 1
        prepareSession()
        let player: AVAudioPlayer
        if let cached = players[url] {
            player = cached
        } else {
            guard let loaded = try? AVAudioPlayer(contentsOf: url) else { return }
            loaded.prepareToPlay()
            players[url] = loaded
            player = loaded
        }
        player.volume = sound.volume
        player.currentTime = 0
        player.play()
    }

    /// Board sounds mix with other audio and respect the silent switch.
    private static func prepareSession() {
        guard !sessionReady else { return }
        sessionReady = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        #endif
    }
}
