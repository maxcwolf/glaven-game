import AVFoundation
#if os(iOS)
import UIKit
import AudioToolbox
#elseif os(macOS)
import AppKit
#endif

enum SoundEffect {
    case tap
    case toggle
    case cardFlip
    case healthDown
    case healthUp
    case death
    case phaseChange
    case coin
    case error
}

enum SoundPlayer {
    private static var player: AVAudioPlayer?
    private static var playedLaunchSting = false
    static weak var settingsManager: SettingsManager?

    /// What one effect does: a sound, a haptic tap, both or neither.
    struct Feedback: Equatable {
        var systemSound: UInt32?
        var haptic: Bool
    }

    /// The feedback for `effect` under the player's settings. Sound and haptics have separate
    /// toggles. The Mac has no effect sounds yet (it used to play the system alert beep, which
    /// sounds like an error), so it stays silent there.
    static func feedback(for effect: SoundEffect, soundEffects: Bool, haptics: Bool) -> Feedback {
        #if os(iOS)
        let sound: UInt32?
        switch effect {
        case .tap, .cardFlip, .phaseChange: sound = 1104
        case .coin: sound = 1057
        default: sound = nil
        }
        return Feedback(systemSound: soundEffects ? sound : nil, haptic: haptics)
        #else
        return Feedback(systemSound: nil, haptic: false)
        #endif
    }

    /// Whether the launch sting plays: once per launch, and only with sound effects on.
    static func shouldPlayLaunchSting(soundEffects: Bool, alreadyPlayed: Bool) -> Bool {
        soundEffects && !alreadyPlayed
    }

    /// Play the "Glaven" sting: once at launch, or again when `replay` is set (tapping the logo).
    static func playGlayvin(replay: Bool = false) {
        guard !BoardSoundPlayer.isSilenced, shouldPlayLaunchSting(soundEffects: settingsManager?.soundEffects ?? true,
                                    alreadyPlayed: playedLaunchSting && !replay) else { return }
        playedLaunchSting = true
        guard let url = appResourceBundle.url(forResource: "glayvin", withExtension: "mp3", subdirectory: "Sounds") else {
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            // Silently fail — sound is non-critical
        }
    }

    static func play(_ effect: SoundEffect) {
        let feedback = feedback(for: effect,
                                soundEffects: settingsManager?.soundEffects ?? true,
                                haptics: settingsManager?.hapticFeedback ?? true)
        #if os(iOS)
        if let sound = feedback.systemSound {
            AudioServicesPlaySystemSound(sound)
        }
        guard feedback.haptic else { return }
        switch effect {
        case .tap, .healthUp, .coin:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .toggle:
            UISelectionFeedbackGenerator().selectionChanged()
        case .cardFlip:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .healthDown:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .death:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .phaseChange:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #else
        _ = feedback
        #endif
    }
}
