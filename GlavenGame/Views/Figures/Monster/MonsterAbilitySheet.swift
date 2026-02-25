import SwiftUI

struct MonsterAbilitySheet: View {
    let ability: AbilityModel
    let monster: GameMonster
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editionTheme) private var theme

    private var hasBottomActions: Bool {
        if let ba = ability.bottomActions, !ba.isEmpty { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Monster name (above card)
                Text(monster.name.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(theme.titleFont(size: 20))
                    .foregroundStyle(GlavenTheme.secondaryText)
                    .padding(.bottom, 8)

                // Card container with texture
                VStack(spacing: 12) {
                    // Initiative badge
                    Text("\(ability.initiative)")
                        .font(theme.titleFont(size: 48))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )

                    // Ability name
                    if let name = ability.name, !name.isEmpty {
                        Text(name)
                            .font(theme.titleFont(size: 22))
                            .foregroundStyle(.white)
                    }

                    // Actions
                    VStack(alignment: .leading, spacing: 8) {
                        if let actions = ability.actions {
                            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                                if action.hidden != true {
                                    MonsterActionRow(action: action, monster: monster, indent: 0, overrideType: nil)
                                        .scaleEffect(1.5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                }
                            }
                        }

                        if let bottomActions = ability.bottomActions, !bottomActions.isEmpty {
                            Divider().background(Color.white.opacity(0.3)).padding(.vertical, 4)
                            ForEach(Array(bottomActions.enumerated()), id: \.offset) { _, action in
                                if action.hidden != true {
                                    MonsterActionRow(action: action, monster: monster, indent: 0, overrideType: nil)
                                        .scaleEffect(1.5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 30)

                    // Footer badges
                    footerBadges
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .background(
                    MonsterAbilityCardBackground(hasBottomActions: hasBottomActions)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 20)
                .frame(maxWidth: 360)

                Spacer()

                Text("Tap anywhere to dismiss")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(.bottom, 20)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }

    @ViewBuilder
    private var footerBadges: some View {
        let showFooter = ability.shuffle == true || ability.lost == true || ability.persistent == true
        if showFooter {
            HStack(spacing: 16) {
                if ability.shuffle == true {
                    sheetBadge("arrow.triangle.2.circlepath", label: "Shuffle")
                }
                if ability.lost == true {
                    sheetBadge("xmark.circle", label: "Lost")
                }
                if ability.persistent == true {
                    sheetBadge("infinity", label: "Persistent")
                }
            }
        }
    }

    @ViewBuilder
    private func sheetBadge(_ icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(label)
                .font(.system(size: 14))
        }
        .foregroundStyle(GlavenTheme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}
