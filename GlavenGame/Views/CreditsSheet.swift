import SwiftUI

/// Who made what: the game it's built on, the data, art, type and sound it uses. The mascot
/// lives here now — tap it.
struct CreditsSheet: View {

    /// Each credit: what it is, and who made it (and under what terms).
    static let credits: [(title: String, detail: String)] = [
        ("Gloomhaven", "Designed by Isaac Childres and published by Cephalofair Games. Glaven is a fan project, not affiliated with or endorsed by Cephalofair Games."),
        ("Game data", "Scenarios, monsters, characters and rules data from Gloomhaven Secretariat by Lurkars."),
        ("Card images", "Ability and monster card scans from gloomhaven-card-browser by cmlenius."),
        ("Type", "Pirata One and Germania One, under the SIL Open Font License."),
        ("Sound", "Effects and jingles from Kenney's RPG Audio, Impact Sounds, Interface Sounds and Music Jingles packs (CC0), kenney.nl."),
    ]

    var onDone: () -> Void = {}

    var body: some View {
        TownDialog(title: "Credits", subtitle: "Glaven \u{00B7} a Gloomhaven board game", size: CGSize(width: 780, height: 560),
                   onDone: onDone) {
            ScrollView {
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 8) {
                        LogoView(size: 120)
                            .accessibilityLabel("Glaven mascot. Tap to hear it.")
                            .accessibilityAddTraits(.isButton)
                        Text("Glaven")
                            .font(BoardTheme.display(30))
                            .foregroundStyle(BoardTheme.text)
                        TownSmallCaps(text: "Fan project")
                    }
                    .frame(width: 160)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Self.credits, id: \.title) { credit in
                            VStack(alignment: .leading, spacing: 3) {
                                TownSmallCaps(text: credit.title, lit: true)
                                Text(credit.detail)
                                    .font(BoardTheme.font(size: 14))
                                    .foregroundStyle(BoardTheme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
        }
    }
}
