import SwiftUI

/// Standalone Attack Modifier deck builder/viewer.
/// Shows character perk-based deck compositions and allows building custom decks.
struct AttackModifierToolSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEdition: String = "gh"
    @State private var selectedCharacter: CharacterData?
    @State private var selectedPerks: [Int] = []
    @State private var customDeck: [AttackModifier] = AttackModifier.defaultMonsterDeck()

    private var editions: [String] {
        gameManager.editionStore.editions.map(\.edition)
    }

    private var characters: [CharacterData] {
        gameManager.editionStore.characters(for: selectedEdition)
            .filter { !($0.locked ?? false) || !($0.spoiler ?? false) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    editionPicker
                    characterPicker

                    if let char = selectedCharacter {
                        perkSection(char)
                    }

                    deckCompositionSection
                    deckStatisticsSection
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Attack Modifier Builder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") { resetDeck() }
                }
            }
            .onChange(of: selectedEdition) { _, _ in
                selectedCharacter = nil
                selectedPerks = []
                resetDeck()
            }
        }
    }

    // MARK: - Edition Picker

    @ViewBuilder
    private var editionPicker: some View {
        HStack {
            Text("Edition")
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText)
            Spacer()
            Picker("Edition", selection: $selectedEdition) {
                ForEach(editions, id: \.self) { edition in
                    Text(edition.uppercased()).tag(edition)
                }
            }
            .pickerStyle(.menu)
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Character Picker

    @ViewBuilder
    private var characterPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Character")
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Default monster deck
                    Button {
                        selectedCharacter = nil
                        selectedPerks = []
                        resetDeck()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "pawprint.fill")
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(selectedCharacter == nil ? Color.red.opacity(0.3) : Color.clear)
                                .clipShape(Circle())
                            Text("Monster")
                                .font(.caption2)
                        }
                        .foregroundStyle(selectedCharacter == nil ? GlavenTheme.primaryText : GlavenTheme.secondaryText)
                    }
                    .buttonStyle(.plain)

                    ForEach(characters) { char in
                        Button {
                            selectedCharacter = char
                            selectedPerks = Array(repeating: 0, count: char.perks?.count ?? 0)
                            rebuildDeck()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(selectedCharacter?.name == char.name
                                        ? (Color(hex: char.color ?? "4488cc") ?? .blue).opacity(0.3)
                                        : Color.clear)
                                    .clipShape(Circle())
                                Text(char.name.replacingOccurrences(of: "-", with: " ").capitalized)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(width: 60)
                            .foregroundStyle(selectedCharacter?.name == char.name ? GlavenTheme.primaryText : GlavenTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Perk Section

    @ViewBuilder
    private func perkSection(_ char: CharacterData) -> some View {
        if let perks = char.perks, !perks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Perks")
                    .font(.headline)
                    .foregroundStyle(GlavenTheme.primaryText)

                ForEach(Array(perks.enumerated()), id: \.offset) { index, perk in
                    HStack {
                        // Perk count stepper
                        let maxCount = perk.count ?? 1
                        let currentCount = index < selectedPerks.count ? selectedPerks[index] : 0

                        Button {
                            if index < selectedPerks.count {
                                selectedPerks[index] = max(0, currentCount - 1)
                                rebuildDeck()
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(currentCount > 0 ? .red : .gray)
                        }
                        .buttonStyle(.plain)
                        .disabled(currentCount <= 0)

                        Text("\(currentCount)/\(maxCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(GlavenTheme.primaryText)
                            .frame(width: 35)

                        Button {
                            if index < selectedPerks.count {
                                selectedPerks[index] = min(maxCount, currentCount + 1)
                                rebuildDeck()
                            }
                        } label: {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(currentCount < maxCount ? .green : .gray)
                        }
                        .buttonStyle(.plain)
                        .disabled(currentCount >= maxCount)

                        Text(perkDescription(perk))
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                            .lineLimit(2)

                        Spacer()
                    }
                }
            }
            .padding()
            .background(GlavenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Deck Composition

    @ViewBuilder
    private var deckCompositionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deck Composition (\(customDeck.count) cards)")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            let grouped = Dictionary(grouping: customDeck) { cardGroupKey($0) }
            let sorted = grouped.sorted { a, b in cardSortOrder(a.key) < cardSortOrder(b.key) }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)], spacing: 8) {
                ForEach(sorted, id: \.key) { key, cards in
                    if let sample = cards.first {
                        VStack(spacing: 4) {
                            AttackModifierCardView(modifier: sample, size: 60)
                            HStack(spacing: 2) {
                                Text("x\(cards.count)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(GlavenTheme.primaryText)
                                if sample.rolling {
                                    Image(systemName: "arrow.forward.circle")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.yellow)
                                }
                                if sample.shuffle {
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.orange)
                                }
                            }
                            if !sample.effects.isEmpty {
                                Text(sample.effects.map { $0.type.rawValue }.joined(separator: ", "))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.purple)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Statistics

    @ViewBuilder
    private var deckStatisticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            let positive = customDeck.filter { $0.value > 0 && !$0.type.isSpecial }.count
            let negative = customDeck.filter { $0.value < 0 && !$0.type.isSpecial }.count
            let neutral = customDeck.filter { $0.value == 0 && !$0.type.isSpecial && $0.type != .double_ && $0.type != .null_ }.count
            let special = customDeck.filter { $0.type == .double_ || $0.type == .null_ }.count
            let rolling = customDeck.filter { $0.rolling }.count
            let withEffects = customDeck.filter { !$0.effects.isEmpty }.count

            let avgValue: Double = customDeck.isEmpty ? 0 :
                Double(customDeck.filter { !$0.type.isSpecial && $0.type != .double_ && $0.type != .null_ }
                    .reduce(0) { $0 + $1.value }) / Double(max(1, customDeck.count))

            HStack(spacing: 16) {
                statBadge(value: "\(positive)", label: "Positive", color: .green)
                statBadge(value: "\(negative)", label: "Negative", color: .red)
                statBadge(value: "\(neutral)", label: "Neutral", color: .gray)
                statBadge(value: "\(special)", label: "x2/Miss", color: .yellow)
            }

            HStack(spacing: 16) {
                statBadge(value: "\(rolling)", label: "Rolling", color: .orange)
                statBadge(value: "\(withEffects)", label: "Effects", color: .purple)
                statBadge(value: String(format: "%.1f", avgValue), label: "Avg Mod", color: .cyan)
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GlavenTheme.secondaryText)
        }
        .frame(minWidth: 50)
    }

    // MARK: - Helpers

    private func resetDeck() {
        customDeck = AttackModifier.defaultMonsterDeck()
    }

    private func rebuildDeck() {
        guard let char = selectedCharacter, let perks = char.perks else {
            resetDeck()
            return
        }

        var deck = AttackModifier.defaultMonsterDeck()
        for (index, perk) in perks.enumerated() {
            let times = index < selectedPerks.count ? selectedPerks[index] : 0
            guard times > 0 else { continue }
            for _ in 0..<times {
                applyPerk(perk, to: &deck)
            }
        }
        customDeck = deck
    }

    private func applyPerk(_ perk: PerkModel, to deck: inout [AttackModifier]) {
        guard let cards = perk.cards else { return }
        switch perk.type {
        case .add:
            for perkCard in cards {
                for _ in 0..<perkCard.count {
                    deck.append(perkCard.attackModifier)
                }
            }
        case .remove:
            for perkCard in cards {
                for _ in 0..<perkCard.count {
                    if let idx = deck.firstIndex(where: { matchesPerkCard($0, perkCard.attackModifier) }) {
                        deck.remove(at: idx)
                    }
                }
            }
        case .replace:
            guard cards.count >= 2 else { return }
            let removeCard = cards[0]
            for _ in 0..<removeCard.count {
                if let idx = deck.firstIndex(where: { matchesPerkCard($0, removeCard.attackModifier) }) {
                    deck.remove(at: idx)
                }
            }
            for addCard in cards.dropFirst() {
                for _ in 0..<addCard.count {
                    deck.append(addCard.attackModifier)
                }
            }
        case .custom:
            break
        }
    }

    private func matchesPerkCard(_ card: AttackModifier, _ template: AttackModifier) -> Bool {
        card.type == template.type
            && card.value == template.value
            && card.valueType == template.valueType
            && card.effects == template.effects
            && card.rolling == template.rolling
    }

    private func perkDescription(_ perk: PerkModel) -> String {
        guard let cards = perk.cards else { return perk.type.rawValue.capitalized }
        let parts = cards.map { card -> String in
            let count = card.count > 1 ? "\(card.count)x " : ""
            let mod = card.attackModifier
            var desc = "\(count)\(mod.displayText)"
            if mod.rolling { desc += " rolling" }
            if !mod.effects.isEmpty {
                desc += " " + mod.effects.map(\.type.rawValue).joined(separator: "/")
            }
            return desc
        }
        return "\(perk.type.rawValue.capitalized): " + parts.joined(separator: " → ")
    }

    private func cardGroupKey(_ card: AttackModifier) -> String {
        "\(card.type.rawValue)-\(card.value)-\(card.rolling)-\(card.effects.map(\.type.rawValue).joined())"
    }

    private func cardSortOrder(_ key: String) -> Int {
        if key.contains("null") { return 0 }
        if key.contains("minus2") { return 1 }
        if key.contains("minus1") { return 2 }
        if key.contains("plus0") { return 3 }
        if key.contains("plus1") { return 4 }
        if key.contains("plus2") { return 5 }
        if key.contains("plus3") { return 6 }
        if key.contains("plus4") { return 7 }
        if key.contains("double") { return 8 }
        if key.contains("bless") { return 9 }
        if key.contains("curse") { return 10 }
        return 11
    }
}
