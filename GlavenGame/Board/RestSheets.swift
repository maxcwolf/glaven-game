import SwiftUI

/// A rest at the board, docked at the bottom like the damage choice so the board stays in view:
/// what the rest does on the left, the cards it concerns on the right.
private struct RestSheet<Summary: View, Cards: View>: View {
    @ViewBuilder let summary: Summary
    @ViewBuilder let cards: Cards

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 20) {
                summary
                    .frame(width: 250, alignment: .leading)
                cards
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(BoardTheme.sheet.opacity(0.97), in: RoundedRectangle(cornerRadius: BoardTheme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.large).stroke(BoardTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 16, y: -4)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color.black.opacity(0.25).ignoresSafeArea())
    }
}

/// The left column's heading: "End of round · Spellweaver", then "Short Rest".
private struct RestHeading: View {
    let kicker: String
    let title: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker)
                .font(BoardTheme.font(size: 12, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(BoardTheme.brass)
            Label(title, systemImage: systemImage)
                .font(BoardTheme.display(28))
                .foregroundStyle(BoardTheme.text)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// A line of what the rest does: "Take back 4 discarded cards".
private struct RestLine: View {
    let text: String
    var emphasis = false

    var body: some View {
        Text(text)
            .font(BoardTheme.font(size: 14, weight: emphasis ? .semibold : .regular))
            .foregroundStyle(emphasis ? BoardTheme.text : BoardTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A discard card as the rest sheets show it, its name as the accessibility label.
private struct RestCard: View {
    let card: AbilityModel
    let character: GameCharacter
    let labels: EditionDataStore
    var height: CGFloat = 190

    var body: some View {
        Group {
            if let cardId = card.cardId, let image = ImageLoader.abilityCardImage(edition: character.edition, cardId: cardId) {
                #if os(macOS)
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                #else
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                #endif
            } else {
                BoardAbilityCardView(card: card, characterColor: Color(hex: character.color) ?? .blue,
                                     highlight: .none, width: height * 0.6, height: height,
                                     labelResolver: { labels.resolveCustomText($0, edition: character.edition) })
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// The sheets' words, kept here so they can be checked without drawing them.
enum RestText {
    /// "End of round · Spellweaver".
    static func kicker(_ name: String) -> String { "End of round \u{00B7} \(name)" }

    /// "Take back your 4 discarded cards; one of them, at random, is lost."
    static func shortRestLines(discards: Int, hand: Int) -> [String] {
        ["Take back your \(discards) discarded cards. One of them, chosen at random, is lost.",
         "Hand \(hand) \u{2192} \(hand + discards - 1)"]
    }

    static func longRestLines(discards: Int, hand: Int) -> [String] {
        ["Heal 2 and refresh your spent items.",
         "Choose one of your \(discards) discarded cards to lose, and take back the rest.",
         "Hand \(hand) \u{2192} \(hand + discards - 1)"]
    }

    /// Once the re-draw is used, the button gives way to this.
    static let redrawUsed = "Redrawn once: a rest allows one."
}

/// "Spellweaver — Short Rest" at the end of the round: rest or not, then (resting) the random
/// card to lose, once redrawn for 1 damage if the player likes (GH p.25).
struct ShortRestSheet: View {
    let pending: BoardCoordinator.PendingShortRest
    let character: GameCharacter
    let coordinator: BoardCoordinator
    @Environment(GameManager.self) private var gameManager

    var body: some View {
        let labels = gameManager.editionStore
        let name = GameText.characterName(character, labels: labels)
        RestSheet {
            VStack(alignment: .leading, spacing: 10) {
                RestHeading(kicker: RestText.kicker(name), title: "Short Rest", systemImage: "moon.zzz.fill")
                if pending.committed {
                    let lost = ability(pending.randomCardId)?.name ?? "This card"
                    RestLine(text: "\(lost) is lost; the rest come back to the hand.", emphasis: true)
                    Button {
                        coordinator.resolveShortRest()
                    } label: {
                        Label("Lose \(lost)", systemImage: "checkmark")
                            .lineLimit(1)
                    }
                    .buttonStyle(.boardPrimary)
                    .keyboardShortcut(.defaultAction)
                    if pending.rerollUsed {
                        RestLine(text: RestText.redrawUsed)
                    } else {
                        Button {
                            coordinator.rerollShortRest()
                        } label: {
                            Label("Suffer 1 Damage, Draw Again", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.boardQuiet)
                        RestLine(text: "HP \(character.health) \u{2192} \(max(0, character.health - 1)), once per rest.")
                    }
                } else {
                    ForEach(RestText.shortRestLines(discards: character.discardedCards.count,
                                                    hand: character.handCards.count), id: \.self) { RestLine(text: $0) }
                    HStack(spacing: 10) {
                        Button {
                            coordinator.commitShortRest()
                        } label: {
                            Label("Rest", systemImage: "moon.zzz.fill")
                        }
                        .buttonStyle(.boardPrimary)
                        .keyboardShortcut(.defaultAction)
                        Button {
                            coordinator.skipShortRest()
                        } label: {
                            Label("Skip", systemImage: "forward.fill")
                        }
                        .buttonStyle(.boardQuiet)
                    }
                }
            }
        } cards: {
            VStack(alignment: .leading, spacing: 8) {
                // The random card is only revealed once the player has decided to rest (p.25).
                if pending.committed, let card = ability(pending.randomCardId) {
                    RestLine(text: "Drawn at random to lose", emphasis: true)
                    Button { coordinator.showCardPreview(cardId: pending.randomCardId) } label: {
                        RestCard(card: card, character: character, labels: labels, height: 220)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(BoardTheme.defeat, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(card.name ?? "Card"), to be lost")
                    .accessibilityHint("Shows the card full size")
                } else {
                    RestLine(text: "Your discard pile", emphasis: true)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(character.discardedCards, id: \.self) { cardId in
                                if let card = ability(cardId) {
                                    Button { coordinator.showCardPreview(cardId: cardId) } label: {
                                        RestCard(card: card, character: character, labels: labels)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(card.name ?? "Card")
                                    .accessibilityHint("Shows the card full size")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func ability(_ cardId: Int) -> AbilityModel? {
        gameManager.editionStore.deckData(name: character.characterData?.deck ?? character.name,
                                          edition: character.edition)?.abilities.first { $0.cardId == cardId }
    }
}

/// A long rest, on the character's turn: choose the discard to lose (choose, then confirm), and
/// the rest come back; the heal and refreshed items come with it (GH p.25).
struct LongRestSheet: View {
    let character: GameCharacter
    let coordinator: BoardCoordinator
    @Environment(GameManager.self) private var gameManager
    @State private var chosen: Int?

    var body: some View {
        let labels = gameManager.editionStore
        let name = GameText.characterName(character, labels: labels)
        RestSheet {
            VStack(alignment: .leading, spacing: 10) {
                RestHeading(kicker: "Initiative 99 \u{00B7} \(name)", title: "Long Rest", systemImage: "bed.double.fill")
                ForEach(RestText.longRestLines(discards: character.discardedCards.count,
                                               hand: character.handCards.count), id: \.self) { RestLine(text: $0) }
                let cardName = chosen.flatMap { character.discardedCards.indices.contains($0) ? ability(character.discardedCards[$0])?.name : nil }
                Button {
                    if let chosen { coordinator.resolveLongRest(characterID: character.id, discardIndex: chosen) }
                } label: {
                    Label(cardName.map { "Lose \($0)" } ?? "Choose a Card to Lose", systemImage: "checkmark")
                        .lineLimit(1)
                }
                .buttonStyle(.boardPrimary)
                .disabled(cardName == nil)
                .keyboardShortcut(.defaultAction)
                RestLine(text: "Lost cards can\u{2019}t be used again this scenario.")
            }
        } cards: {
            VStack(alignment: .leading, spacing: 8) {
                RestLine(text: "Your discard pile: tap the card to lose", emphasis: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(character.discardedCards.enumerated()), id: \.offset) { index, cardId in
                            if let card = ability(cardId) {
                                let selected = chosen == index
                                Button {
                                    withAnimation(.snappy) { chosen = selected ? nil : index }
                                } label: {
                                    RestCard(card: card, character: character, labels: labels)
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .stroke(selected ? BoardTheme.defeat : .clear, lineWidth: 3))
                                        .overlay(alignment: .bottom) {
                                            if selected {
                                                Text("Lose this card")
                                                    .font(BoardTheme.font(size: 12, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(BoardTheme.defeat, in: Capsule())
                                                    .offset(y: 12)
                                            }
                                        }
                                        .offset(y: selected ? -10 : 0)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(card.name ?? "Card")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                                .accessibilityHint(selected ? "Chosen. Use Lose to confirm." : "Choose this card to lose")
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func ability(_ cardId: Int) -> AbilityModel? {
        gameManager.editionStore.deckData(name: character.characterData?.deck ?? character.name,
                                          edition: character.edition)?.abilities.first { $0.cardId == cardId }
    }
}
