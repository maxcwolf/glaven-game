import SwiftUI

/// What the party protects is about to suffer damage and a scenario rule lets a card spare it
/// (the captive Orchids; the crystal, twice): let it suffer — the usual answer, so the main
/// button — or lose one card from any character's hand. Losing a card is choose-then-confirm,
/// as on the damage sheet, which this sits beside.
struct SaveChoiceSheet: View {
    let pending: BoardCoordinator.PendingSave
    @Bindable var coordinator: BoardCoordinator
    @Environment(GameManager.self) private var gameManager
    @State private var shownHand: String?
    @State private var selectedCard: Int?

    private let cardHeight: CGFloat = 200

    /// The main button: the damage stands.
    static func sufferTitle(_ pending: BoardCoordinator.PendingSave) -> String {
        pending.destroys ? "Let It Be Destroyed" : "Let It Suffer \(pending.damage)"
    }

    /// What losing a card does, and how often it can still be done.
    static func offer(_ pending: BoardCoordinator.PendingSave) -> String {
        let limit: String
        switch pending.left {
        case nil: limit = ""
        case 1?: limit = " This is the last time."
        case let left?: limit = " \(left) times left."
        }
        return "Lose one card from any hand and it suffers none." + limit
    }

    private var hand: (characterID: String, cards: [Int])? {
        pending.hands.first { $0.characterID == shownHand } ?? pending.hands.first
    }

    private func character(_ id: String) -> GameCharacter? {
        gameManager.game.characters.first { $0.id == id }
    }

    private func characterName(_ id: String) -> String {
        character(id).map { GameText.characterName($0, labels: gameManager.editionStore) } ?? id
    }

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 18) {
                summary.frame(width: 230)
                hands
            }
            .padding(18)
            .background(Color(red: 0.09, green: 0.07, blue: 0.06).opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.54, green: 0.23, blue: 0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 16, y: -4)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color.black.opacity(0.25).ignoresSafeArea())
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(pending.name) is hit")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color(red: 0.89, green: 0.64, blue: 0.61))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pending.damage) damage")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("from \(pending.sourceDescription)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                Text("HP \(pending.health) \u{2192} \(max(0, pending.health - pending.damage))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }
            if pending.destroys {
                Label(pending.losesTheScenario ? "This destroys \(pending.name): the scenario is lost"
                                               : "This destroys \(pending.name)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.48))
            }
            Button {
                coordinator.resolvePendingSave(by: nil, losing: nil)
            } label: {
                Text(Self.sufferTitle(pending))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(pending.destroys ? .gray : Color(red: 0.78, green: 0.57, blue: 0.18))
            .keyboardShortcut(selectedCard == nil && !pending.destroys ? .defaultAction : nil)

            if let cardId = selectedCard, let hand {
                Button(role: .destructive) {
                    coordinator.resolvePendingSave(by: hand.characterID, losing: cardId)
                } label: {
                    Text("Lose \(cardName(cardId, of: hand.characterID))")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                Text("Lost cards can\u{2019}t be used again this scenario.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var hands: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.offer(pending))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            if pending.hands.count > 1 {
                HStack(spacing: 8) {
                    ForEach(pending.hands, id: \.characterID) { entry in
                        let shown = entry.characterID == hand?.characterID
                        Button {
                            shownHand = entry.characterID
                            selectedCard = nil
                        } label: {
                            Text("\(characterName(entry.characterID)) \u{00B7} \(entry.cards.count)")
                                .font(.subheadline.weight(shown ? .bold : .regular))
                                .foregroundStyle(shown ? Color.black : .white)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(shown ? Color(red: 0.78, green: 0.57, blue: 0.18) : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(characterName(entry.characterID))\u{2019}s hand, \(entry.cards.count) cards")
                        .accessibilityAddTraits(shown ? .isSelected : [])
                    }
                }
            } else if let hand {
                Text("\(characterName(hand.characterID))\u{2019}s hand")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let hand {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(hand.cards, id: \.self) { cardButton($0, of: hand.characterID) }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardButton(_ cardId: Int, of characterID: String) -> some View {
        let selected = selectedCard == cardId
        return Button {
            withAnimation(.snappy) { selectedCard = selected ? nil : cardId }
        } label: {
            cardFace(cardId, of: characterID)
                .frame(height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color(red: 0.89, green: 0.33, blue: 0.29) : .clear, lineWidth: 3))
                .offset(y: selected ? -10 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cardName(cardId, of: characterID))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? "Selected. Use Lose to confirm." : "Select to lose this card and spare \(pending.name)")
    }

    @ViewBuilder
    private func cardFace(_ cardId: Int, of characterID: String) -> some View {
        if let character = character(characterID) {
            if let image = ImageLoader.abilityCardImage(edition: character.edition, cardId: cardId) {
                #if os(macOS)
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                #else
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                #endif
            } else if let card = ability(cardId, of: character) {
                BoardAbilityCardView(card: card, characterColor: Color(hex: character.color) ?? .blue,
                                     highlight: .none, width: 130, height: cardHeight,
                                     labelResolver: { gameManager.editionStore.resolveCustomText($0, edition: character.edition) })
            }
        }
    }

    private func ability(_ cardId: Int, of character: GameCharacter) -> AbilityModel? {
        gameManager.editionStore.deckData(name: character.characterData?.deck ?? character.name, edition: character.edition)?
            .abilities.first { $0.cardId == cardId }
    }

    private func cardName(_ cardId: Int, of characterID: String) -> String {
        character(characterID).flatMap { ability(cardId, of: $0)?.name } ?? "Card \(cardId)"
    }
}
