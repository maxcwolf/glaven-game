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
    static weak var settingsManager: SettingsManager?

    static func playGlayvin() {
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
        guard settingsManager?.soundEffects != false else { return }

        #if os(iOS)
        switch effect {
        case .tap:
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            AudioServicesPlaySystemSound(1104)
        case .toggle:
            let gen = UISelectionFeedbackGenerator()
            gen.selectionChanged()
        case .cardFlip:
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            AudioServicesPlaySystemSound(1104)
        case .healthDown:
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.impactOccurred()
        case .healthUp:
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
        case .death:
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.impactOccurred()
            let notif = UINotificationFeedbackGenerator()
            notif.notificationOccurred(.error)
        case .phaseChange:
            let gen = UIImpactFeedbackGenerator(style: .rigid)
            gen.impactOccurred()
            AudioServicesPlaySystemSound(1104)
        case .coin:
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            AudioServicesPlaySystemSound(1057)
        case .error:
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.error)
        }
        #else
        // macOS: audio-only fallback for effects that have audio
        switch effect {
        case .tap, .cardFlip, .phaseChange:
            NSSound.beep()
        case .coin:
            NSSound.beep()
        default:
            break
        }
        #endif
    }
}
