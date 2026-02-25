import SwiftUI

struct PerkSheet: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    deckSummary
                    if let perks = character.characterData?.perks {
                        ForEach(Array(perks.enumerated()), id: \.offset) { index, perk in
                            PerkRow(
                                perk: perk,
                                selected: index < character.selectedPerks.count ? character.selectedPerks[index] : 0
                            ) {
                                gameManager.characterManager.togglePerk(at: index, for: character)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Perks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var deckSummary: some View {
        let count = character.attackModifierDeck.attackModifiers.count
        HStack {
            Text("Deck: \(count) cards")
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText)
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

struct PerkRow: View {
    let perk: PerkModel
    let selected: Int
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                checkboxes
                Text(perkDescription)
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.primaryText)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(selected > 0 ? GlavenTheme.primaryText.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var checkboxes: some View {
        HStack(spacing: 4) {
            ForEach(0..<perk.count, id: \.self) { i in
                Image(systemName: i < selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(i < selected ? Color.accentColor : GlavenTheme.secondaryText)
            }
        }
    }

    private var perkDescription: String {
        if let custom = perk.custom, !custom.isEmpty {
            return custom
        }
        guard let cards = perk.cards else { return perk.type.rawValue.capitalized }

        switch perk.type {
        case .add:
            let descs = cards.map { "\($0.count)x \(cardLabel($0.attackModifier))" }
            return "Add \(descs.joined(separator: ", "))"
        case .remove:
            let descs = cards.map { "\($0.count)x \(cardLabel($0.attackModifier))" }
            return "Remove \(descs.joined(separator: ", "))"
        case .replace:
            guard cards.count >= 2 else { return "Replace" }
            let removeDesc = "\(cards[0].count)x \(cardLabel(cards[0].attackModifier))"
            let addDescs = cards.dropFirst().map { "\($0.count)x \(cardLabel($0.attackModifier))" }
            return "Replace \(removeDesc) with \(addDescs.joined(separator: ", "))"
        case .custom:
            return perk.custom ?? "Custom"
        }
    }

    private func cardLabel(_ mod: AttackModifier) -> String {
        var parts: [String] = []

        // Value
        switch mod.type {
        case .plus0: parts.append("+0")
        case .plus1: parts.append("+1")
        case .plus2: parts.append("+2")
        case .plus3: parts.append("+3")
        case .plus4: parts.append("+4")
        case .minus1: parts.append("-1")
        case .minus2: parts.append("-2")
        case .double_: parts.append("x2")
        case .null_: parts.append("null")
        default: parts.append(mod.type.rawValue)
        }

        // Rolling
        if mod.rolling {
            parts.insert("rolling", at: 0)
        }

        // Effects
        for effect in mod.effects {
            parts.append(effect.type.rawValue.replacingOccurrences(of: "-", with: " "))
        }

        return parts.joined(separator: " ")
    }
}
