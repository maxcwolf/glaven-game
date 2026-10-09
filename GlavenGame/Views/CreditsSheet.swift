import SwiftUI

/// Who made what: the game it's built on, the data, art, type and sound it uses. The mascot
/// lives here now — tap it.
struct CreditsSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Each credit: what it is, and who made it (and under what terms).
    static let credits: [(title: String, detail: String)] = [
        ("Gloomhaven", "Designed by Isaac Childres and published by Cephalofair Games. Glaven is a fan project, not affiliated with or endorsed by Cephalofair Games."),
        ("Game data", "Scenarios, monsters, characters and rules data from Gloomhaven Secretariat by Lurkars."),
        ("Card images", "Ability and monster card scans from gloomhaven-card-browser by cmlenius."),
        ("Type", "Pirata One and Germania One, under the SIL Open Font License."),
        ("Sound", "Effects and jingles from Kenney's RPG Audio, Impact Sounds, Interface Sounds and Music Jingles packs (CC0), kenney.nl."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    LogoView(size: 120)
                        .accessibilityLabel("Glaven mascot. Tap to hear it.")
                        .accessibilityAddTraits(.isButton)
                    VStack(spacing: 4) {
                        Text("Glaven")
                            .font(GlavenFont.title(size: 44))
                            .foregroundStyle(BoardTheme.text)
                        Text("A Gloomhaven board game")
                            .font(.subheadline)
                            .foregroundStyle(BoardTheme.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Self.credits, id: \.title) { credit in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(credit.title.uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BoardTheme.brass)
                                Text(credit.detail)
                                    .font(.body)
                                    .foregroundStyle(BoardTheme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 560, alignment: .leading)
                    .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(BoardTheme.sheet)
            .navigationTitle("Credits")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}
