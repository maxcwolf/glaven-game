import SwiftUI

/// How a character takes a hit: suffer the damage (the usual choice, so it is the main button)
/// or lose one card from hand, or two from the discard pile, to prevent all of it (GH p.22).
/// Losing a card is always choose-then-confirm. The sheet docks at the bottom and leaves the
/// board visible above it.
struct DamageChoiceSheet: View {
    let pending: BoardCoordinator.PendingDamage
    let character: GameCharacter
    @Bindable var coordinator: BoardCoordinator
    @Environment(GameManager.self) private var gameManager
    @State private var selectedCard: Int?

    private let cardHeight: CGFloat = 200

    enum ReturnKey: Equatable { case takeDamage, loseCard, nothing }

    /// What Return does: confirms the card chosen to lose; otherwise takes the damage — unless
    /// that exhausts the character, which only a deliberate click does.
    static func returnKey(selectedCard: Int?, exhausts: Bool) -> ReturnKey {
        if selectedCard != nil { return .loseCard }
        return exhausts ? .nothing : .takeDamage
    }

    var body: some View {
        let outcome = coordinator.damageOutcome(pending)
        let losable = coordinator.losableHandCards(of: character)
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 18) {
                summary(outcome)
                    .frame(width: 230)
                if !losable.isEmpty {
                    handCards(losable)
                } else if character.discardedCards.count >= 2 {
                    discardChoice
                } else {
                    Text("No cards can be lost to prevent this damage.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    private func summary(_ outcome: BoardCoordinator.DamageOutcome?) -> some View {
        let returnKey = Self.returnKey(selectedCard: selectedCard, exhausts: outcome?.exhausts == true)
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(GameText.characterName(character, labels: gameManager.editionStore)) is hit")
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
                if let outcome {
                    Text("HP \(outcome.healthBefore) \u{2192} \(outcome.healthAfter)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            if outcome?.exhausts == true {
                Label("Taking this exhausts \(GameText.characterName(character, labels: gameManager.editionStore))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.48))
            }
            Button {
                coordinator.resolvePendingDamage(choice: .takeDamage)
            } label: {
                Text("Take \(pending.damage) Damage")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(outcome?.exhausts == true ? .gray : Color(red: 0.78, green: 0.57, blue: 0.18))
            .keyboardShortcut(returnKey == .takeDamage ? .defaultAction : nil)

            if let cardId = selectedCard {
                Button(role: .destructive) {
                    coordinator.resolvePendingDamage(choice: .loseHandCard(cardId: cardId))
                } label: {
                    Text("Lose \(cardName(cardId))")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .keyboardShortcut(returnKey == .loseCard ? .defaultAction : nil)
                Text("Lost cards can\u{2019}t be used again this scenario.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func handCards(_ losable: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or lose one card from your hand to prevent it all")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(losable, id: \.self) { cardId in
                        cardButton(cardId)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 2)
            }
            if character.discardedCards.count >= 2 {
                discardChoice
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardButton(_ cardId: Int) -> some View {
        let selected = selectedCard == cardId
        return Button {
            withAnimation(.snappy) { selectedCard = selected ? nil : cardId }
        } label: {
            cardFace(cardId)
                .frame(height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color(red: 0.89, green: 0.33, blue: 0.29) : .clear, lineWidth: 3))
                .overlay(alignment: .bottom) {
                    if selected {
                        Text("Lose this card")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.64, green: 0.16, blue: 0.13))
                            .clipShape(Capsule())
                            .offset(y: 12)
                    }
                }
                .offset(y: selected ? -10 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cardName(cardId))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? "Selected. Use Lose to confirm." : "Select to lose this card instead of taking the damage")
    }

    @ViewBuilder
    private func cardFace(_ cardId: Int) -> some View {
        if let image = ImageLoader.abilityCardImage(edition: character.edition, cardId: cardId) {
            #if os(macOS)
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            #else
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            #endif
        } else if let card = ability(cardId) {
            BoardAbilityCardView(card: card, characterColor: Color(hex: character.color) ?? .blue,
                                 highlight: .none, width: 130, height: cardHeight,
                                 labelResolver: { gameManager.editionStore.resolveCustomText($0, edition: character.edition) })
        }
    }

    private var discardChoice: some View {
        DiscardCardPicker(
            character: character,
            deckData: deckData,
            characterColor: Color(hex: character.color) ?? .blue,
            onConfirm: { indices in
                coordinator.resolvePendingDamage(choice: .loseDiscardCards(indices: indices))
            },
            labelResolver: { gameManager.editionStore.resolveCustomText($0, edition: character.edition) },
            onPreviewCard: nil
        )
    }

    private var deckData: DeckData? {
        gameManager.editionStore.deckData(name: character.characterData?.deck ?? character.name, edition: character.edition)
    }

    private func ability(_ cardId: Int) -> AbilityModel? {
        deckData?.abilities.first { $0.cardId == cardId }
    }

    private func cardName(_ cardId: Int) -> String {
        ability(cardId)?.name ?? "Card \(cardId)"
    }
}
