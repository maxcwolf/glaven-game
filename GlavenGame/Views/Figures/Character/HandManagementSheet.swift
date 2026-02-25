import SwiftUI

struct HandManagementSheet: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0

    private var allAbilities: [AbilityModel] {
        guard let deckName = character.characterData?.deck ?? character.characterData?.name else { return [] }
        return gameManager.editionStore.abilities(forDeck: deckName, edition: character.edition)
            .filter { ability in
                let lvl = ability.level?.intValue ?? 1
                return lvl <= character.level
            }
            .sorted { ($0.level?.intValue ?? 0) < ($1.level?.intValue ?? 0) }
    }

    private var handAbilities: [AbilityModel] {
        allAbilities.filter { character.handCards.contains($0.id) }
    }

    private var discardedAbilities: [AbilityModel] {
        allAbilities.filter { character.discardedCards.contains($0.id) }
    }

    private var lostAbilities: [AbilityModel] {
        allAbilities.filter { character.lostCards.contains($0.id) }
    }

    private var availableAbilities: [AbilityModel] {
        let usedIds = Set(character.handCards + character.discardedCards + character.lostCards)
        return allAbilities.filter { !usedIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    Text("Hand (\(handAbilities.count))").tag(0)
                    Text("Discard (\(discardedAbilities.count))").tag(1)
                    Text("Lost (\(lostAbilities.count))").tag(2)
                    Text("Pool").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch selectedTab {
                case 0: cardList(handAbilities, zone: .hand)
                case 1: cardList(discardedAbilities, zone: .discard)
                case 2: cardList(lostAbilities, zone: .lost)
                case 3: cardList(availableAbilities, zone: .pool)
                default: cardList(handAbilities, zone: .hand)
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Hand Management")
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
                    Menu {
                        Button("Fill Hand") { fillHand() }
                        Button("Short Rest (random discard)") { shortRest() }
                        Button("Long Rest (choose discard)") { /* handled by selecting cards */ }
                        Divider()
                        Button("Reset All") { resetHand() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private enum CardZone {
        case hand, discard, lost, pool
    }

    @ViewBuilder
    private func cardList(_ abilities: [AbilityModel], zone: CardZone) -> some View {
        if abilities.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: emptyIcon(zone))
                    .font(.system(size: 40))
                    .foregroundStyle(GlavenTheme.secondaryText)
                Text(emptyMessage(zone))
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(abilities) { ability in
                    cardRow(ability, zone: zone)
                }
            }
        }
    }

    @ViewBuilder
    private func cardRow(_ ability: AbilityModel, zone: CardZone) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ability.name ?? "Card \(ability.id)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.primaryText)
                    if let level = ability.level {
                        Text("Lv\(level.intValue)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(GlavenTheme.accentText.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text("Init \(ability.initiative)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(GlavenTheme.secondaryText)

                    if ability.lost == true {
                        Label("Lost", systemImage: "xmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    if ability.persistent == true {
                        Label("Persistent", systemImage: "infinity")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            // Action buttons based on zone
            switch zone {
            case .hand:
                Button { moveCard(ability.id, from: .hand, to: .discard) } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                Button { moveCard(ability.id, from: .hand, to: .lost) } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

            case .discard:
                Button { moveCard(ability.id, from: .discard, to: .hand) } label: {
                    Image(systemName: "arrow.up.circle")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                Button { moveCard(ability.id, from: .discard, to: .lost) } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

            case .lost:
                Button { moveCard(ability.id, from: .lost, to: .hand) } label: {
                    Image(systemName: "arrow.uturn.up.circle")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

            case .pool:
                Button { moveCard(ability.id, from: .pool, to: .hand) } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.accentText)
                }
                .buttonStyle(.plain)
                .disabled(character.handCards.count >= character.handSize)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func moveCard(_ cardId: Int, from: CardZone, to: CardZone) {
        // Remove from source
        switch from {
        case .hand: character.handCards.removeAll { $0 == cardId }
        case .discard: character.discardedCards.removeAll { $0 == cardId }
        case .lost: character.lostCards.removeAll { $0 == cardId }
        case .pool: break
        }

        // Add to destination
        switch to {
        case .hand: character.handCards.append(cardId)
        case .discard: character.discardedCards.append(cardId)
        case .lost: character.lostCards.append(cardId)
        case .pool: break
        }
    }

    private func fillHand() {
        // Move all discarded cards back to hand
        character.handCards.append(contentsOf: character.discardedCards)
        character.discardedCards.removeAll()
    }

    private func shortRest() {
        // Move all discard to hand, then randomly lose one
        character.handCards.append(contentsOf: character.discardedCards)
        character.discardedCards.removeAll()

        if !character.handCards.isEmpty {
            let randomIndex = Int.random(in: 0..<character.handCards.count)
            let lostCard = character.handCards.remove(at: randomIndex)
            character.lostCards.append(lostCard)
        }
    }

    private func resetHand() {
        character.handCards.removeAll()
        character.discardedCards.removeAll()
        character.lostCards.removeAll()
    }

    // MARK: - Helpers

    private func emptyIcon(_ zone: CardZone) -> String {
        switch zone {
        case .hand: return "hand.raised"
        case .discard: return "arrow.down.doc"
        case .lost: return "xmark.bin"
        case .pool: return "rectangle.stack"
        }
    }

    private func emptyMessage(_ zone: CardZone) -> String {
        switch zone {
        case .hand: return "No cards in hand"
        case .discard: return "No discarded cards"
        case .lost: return "No lost cards"
        case .pool: return "All cards assigned"
        }
    }
}
