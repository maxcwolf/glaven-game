import AVFoundation

/// The board's sound cues. The audio is from Kenney's CC0 packs, some of it layered, pitched or
/// given a room, plus a synthesised choir (see Resources/Sounds/CREDITS.txt and
/// docs/sound-design.md), shipped as `<cue>-<n>.m4a` with one or more variants.
enum BoardSound: String, CaseIterable {
    case step, hit, heavyHit = "hit-heavy", blocked, miss, death, land, heal, loot, door, teleport
    /// Shield takes some of an attack that still does damage.
    case shield
    case retaliate
    /// A hindering condition lands, or a helpful one: the shared cues for conditions without
    /// their own (see `condition(_:)`).
    case harm, boon
    case wound, poison, stun, immobilize, disarm, muddle, curse, strengthen, bless
    /// An attack modifier card is drawn; a modifier deck is reshuffled at the end of the round.
    case card, shuffle
    case trap
    /// A character is exhausted (a monster or summon dying is `death`).
    case exhaust
    /// A summon is placed, or a monster is spawned or summoned mid-scenario.
    case summon
    /// An element is infused; an element is consumed.
    case infuse, consume
    /// A character rests; a card goes to the lost pile.
    case rest, lose
    /// The round's cards are revealed; a character's turn begins.
    case round, turn
    /// The player's own taps: a card picked in hand, the round's cards locked in, an attack
    /// target chosen, the turn ended, and a tap that isn't a valid choice.
    case cardPick = "card-pick", cardConfirm = "card-confirm", target, endTurn = "end-turn", invalid
    /// Jingles: a scenario begins, is won, is lost.
    case start, victory, defeat

    /// The cue for a condition landing: its own where it has one, else the shared hindrance or
    /// boon cue.
    static func condition(_ condition: ConditionName) -> BoardSound {
        switch condition {
        case .wound, .wound_x: return .wound
        case .poison, .poison_x: return .poison
        case .stun: return .stun
        case .immobilize: return .immobilize
        case .disarm: return .disarm
        case .muddle: return .muddle
        case .curse: return .curse
        case .strengthen: return .strengthen
        case .bless: return .bless
        default: return condition.isPositive ? .boon : .harm
        }
    }

    /// Whether this is one of the condition cues.
    var isCondition: Bool {
        switch self {
        case .harm, .boon, .wound, .poison, .stun, .immobilize, .disarm, .muddle, .curse, .strengthen, .bless:
            return true
        default:
            return false
        }
    }

    /// Playback gain. The audio is mastered at the level it plays (impacts loudest, the player's
    /// own taps quietest; SoundAssetTests holds the mix), so cues play as they are. Footsteps,
    /// kept from the first sound pass, sit well under everything else.
    var volume: Float { self == .step ? 0.44 : 1 }

    /// The bundled files for this cue, in variant order (looked up once, not on every footstep).
    var files: [URL] { Self.bundledFiles[self] ?? [] }

    private static let bundledFiles: [BoardSound: [URL]] = Dictionary(uniqueKeysWithValues: allCases.map { sound in
        (sound, (0..<8).compactMap {
            appResourceBundle.url(forResource: "\(sound.rawValue)-\($0)", withExtension: "m4a", subdirectory: "Sounds")
        })
    })
}

/// Decides when a cue sounds, so cues raised in the same instant are heard as a sequence rather
/// than a pile-up: a trap snaps, then the hit lands, then the poison; a card is slapped down, the
/// round's drum follows, then the turn bell. A cue repeated in the same instant (one hit for each
/// target of an area attack played at full speed) sounds once.
struct BoardSoundMixer {
    /// When each cue last started, or is due to start.
    private var lastStart: [BoardSound: TimeInterval] = [:]

    /// The same cue again this soon is one sound, not two.
    static let repeatWindow: TimeInterval = 0.08

    /// How long to hold `sound`, raised at `now`, before it plays; nil to drop it.
    mutating func admit(_ sound: BoardSound, at now: TimeInterval) -> TimeInterval? {
        var start = now
        for (earlier, gap) in Self.follows(sound) {
            if let began = lastStart[earlier] { start = max(start, began + gap) }
        }
        let key = Self.repeatKey(sound)
        if let began = lastStart[key], abs(start - began) < Self.repeatWindow { return nil }
        lastStart[key] = start
        if key != sound { lastStart[sound] = start }
        return start - now
    }

    /// A light and a heavy hit in the same instant are one impact.
    private static func repeatKey(_ sound: BoardSound) -> BoardSound {
        sound == .heavyHit ? .hit : sound
    }

    private static let impacts: [BoardSound] = [.hit, .heavyHit, .trap, .blocked, .shield]
    private static let conditions = BoardSound.allCases.filter(\.isCondition)

    /// The cues `sound` waits for, and how long after each began it may start.
    private static func follows(_ sound: BoardSound) -> [(BoardSound, TimeInterval)] {
        switch sound {
        case .hit, .heavyHit:
            return [(.trap, 0.1), (.shield, 0.1), (.retaliate, 0.12)]
        case .retaliate:
            return [(.hit, 0.15)]
        case .exhaust:
            return [(.hit, 0.1)]
        case .lose:
            return [(.rest, 0.4), (.endTurn, 0.3)]
        case .round:
            return [(.cardConfirm, 0.35)]
        case .turn:
            return [(.round, 0.7), (.endTurn, 0.35)]
        case _ where sound.isCondition:
            // After the blow that carried it, and one condition after another.
            return impacts.map { ($0, 0.15) } + conditions.filter { $0 != sound }.map { ($0, 0.15) }
        default:
            return []
        }
    }
}

/// Plays board sounds when the player has sound effects on. Variants take turns rather than
/// being picked at random, so cosmetic sound never draws from the game's seeded randomness.
@MainActor
enum BoardSoundPlayer {
    private static var players: [URL: AVAudioPlayer] = [:]
    private static var nextVariant: [BoardSound: Int] = [:]
    private static var sessionReady = false
    private static var mixer = BoardSoundMixer()

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

    /// Every cue asked for, heard or not (for tests of the cues views raise themselves).
    static var onRequest: ((BoardSound) -> Void)?

    static func play(_ sound: BoardSound) {
        onRequest?(sound)
        guard !isSilenced, SoundPlayer.settingsManager?.soundEffects ?? true,
              let delay = mixer.admit(sound, at: ProcessInfo.processInfo.systemUptime) else { return }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { start(sound) }
        } else {
            start(sound)
        }
    }

    private static func start(_ sound: BoardSound) {
        guard SoundPlayer.settingsManager?.soundEffects ?? true, let url = nextFile(for: sound) else { return }
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
