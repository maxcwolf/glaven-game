import SwiftUI

/// A city or road event: the card's story and its two options; then the outcome, with any choice
/// it asks for; then what it did.
struct EventSheet: View {
    @Environment(GameManager.self) private var gameManager
    let deck: EventCardManager.Deck
    let onDone: () -> Void

    @State private var option: String?
    @State private var choices = EventCardManager.Choices()
    @State private var resolution: EventCardManager.Resolution?

    private var manager: EventCardManager { gameManager.eventCardManager }

    var body: some View {
        ZStack {
            BoardTheme.scrim.ignoresSafeArea()
            if let event = manager.topCard(deck) ?? resolvedEvent {
                VStack(alignment: .leading, spacing: 16) {
                    header(event)
                    // Event texts fit an iPad without scrolling (the longest is about 800 characters).
                    VStack(alignment: .leading, spacing: 16) {
                            if let resolution {
                                result(resolution)
                            } else if let option, let outcome = manager.outcome(event, option: option) {
                                outcomeView(event, option: option, outcome: outcome)
                            } else {
                                Text(event.narrative ?? "")
                                    .font(.body)
                                    .foregroundStyle(BoardTheme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                ForEach(event.options ?? [], id: \.label) { opt in
                                    optionButton(opt, available: manager.outcome(event, option: opt.label ?? "") != nil)
                                }
                            }
                    }
                    footer(event)
                }
                .padding(28)
                .frame(maxWidth: 640)
                .fixedSize(horizontal: false, vertical: true)
                .boardPanel()
                .padding(24)
                .onAppear { resolvedEvent = event }
            } else {
                // An empty deck: nothing to resolve.
                Color.clear.onAppear(perform: onDone)
            }
        }
    }

    /// Kept so the result can still show after the card leaves the top of the deck.
    @State private var resolvedEvent: EventCardData?

    private func header(_ event: EventCardData) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(deck == .city ? "City Event" : "Road Event", systemImage: deck == .city ? "building.2.fill" : "road.lanes")
                .font(BoardTheme.display(30))
                .foregroundStyle(BoardTheme.text)
            Spacer()
            Text(event.cardId)
                .font(.headline.monospacedDigit())
                .foregroundStyle(BoardTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    /// An option the party can't take (it needs something they don't have) is shown but greyed.
    private func optionButton(_ opt: EventOption, available: Bool) -> some View {
        Button {
            withAnimation(.snappy) { option = opt.label }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(opt.label ?? "")
                    .font(BoardTheme.display(26))
                    .foregroundStyle(BoardTheme.brass)
                Text(opt.narrative ?? "")
                    .font(.body)
                    .foregroundStyle(BoardTheme.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !available {
                    Text("Not possible")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BoardTheme.secondaryText)
                }
            }
            .padding(14)
            .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.medium).stroke(BoardTheme.border))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.5)
        .accessibilityLabel("Option \(opt.label ?? ""): \(opt.narrative ?? "")\(available ? "" : ", not possible")")
    }

    @ViewBuilder
    private func outcomeView(_ event: EventCardData, option: String, outcome: EventOutcome) -> some View {
        Text(outcome.narrative ?? "")
            .font(.body)
            .foregroundStyle(BoardTheme.text)
            .fixedSize(horizontal: false, vertical: true)
        let chooseSets = manager.choices(in: outcome)
        ForEach(Array(chooseSets.enumerated()), id: \.offset) { index, effects in
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("CHOOSE ONE")
                Picker("Choose one", selection: chosen(index)) {
                    ForEach(Array(effects.enumerated()), id: \.offset) { pick, effect in
                        Text(manager.describe(effect)).tag(pick)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        if manager.asksForOneCharacter(outcome) {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("WHICH CHARACTER")
                Picker("Which character", selection: oneCharacter) {
                    ForEach(party, id: \.id) { Text(manager.name($0)).tag($0.id) }
                }
                .pickerStyle(.segmented)
            }
        }
        ForEach(party, id: \.id) { character in
            let needed = manager.discardRequirements(event, option: option, choices: choices)[character.id] ?? 0
            if needed > 0 { discardPicker(character, count: needed) }
        }
    }

    private func discardPicker(_ character: GameCharacter, count: Int) -> some View {
        let cards = gameManager.characterManager.abilities(for: character).filter { card in
            card.cardId.map(character.handCards.contains) ?? false
        }
        let picked = choices.discards[character.id] ?? []
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("\(manager.name(character).uppercased()) DISCARDS \(count) · \(picked.count) CHOSEN")
            FlowLayout(spacing: 6) {
                ForEach(cards) { card in
                    let id = card.cardId ?? 0
                    let isPicked = picked.contains(id)
                    Button(card.name ?? "Card \(id)") {
                        var list = choices.discards[character.id] ?? []
                        if isPicked { list.removeAll { $0 == id } } else if list.count < count { list.append(id) }
                        choices.discards[character.id] = list
                    }
                    .buttonStyle(.bordered)
                    .tint(isPicked ? BoardTheme.brass : .gray)
                    .accessibilityAddTraits(isPicked ? .isSelected : [])
                }
            }
        }
    }

    private func result(_ resolution: EventCardManager.Resolution) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(resolution.narrative)
                .font(.body)
                .foregroundStyle(BoardTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            sectionTitle("WHAT HAPPENS")
            ForEach(resolution.effects, id: \.self) { line in
                Text(line).font(.body.weight(.semibold)).foregroundStyle(BoardTheme.text)
            }
        }
    }

    @ViewBuilder
    private func footer(_ event: EventCardData) -> some View {
        HStack {
            if option != nil && resolution == nil {
                Button("Back") { withAnimation(.snappy) { option = nil; choices = .init() } }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if resolution != nil {
                Button("Continue", action: onDone)
                    .buttonStyle(.borderedProminent).tint(BoardTheme.brass)
                    .keyboardShortcut(.defaultAction)
            } else if let option {
                Button("Accept") {
                    withAnimation(.snappy) { resolution = manager.resolve(deck, option: option, choices: choices) }
                    gameManager.saveGame()
                }
                .buttonStyle(.borderedProminent).tint(BoardTheme.brass)
                .disabled(!discardsComplete(event, option: option))
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }

    private var party: [GameCharacter] { gameManager.game.characters.filter { !$0.absent } }

    private func discardsComplete(_ event: EventCardData, option: String) -> Bool {
        manager.discardRequirements(event, option: option, choices: choices).allSatisfy { id, count in
            let hand = party.first { $0.id == id }?.handCards.count ?? 0
            return (choices.discards[id]?.count ?? 0) == min(count, hand)
        }
    }

    private func chosen(_ index: Int) -> Binding<Int> {
        Binding(get: { index < choices.chosen.count ? choices.chosen[index] : 0 },
                set: { value in
                    while choices.chosen.count <= index { choices.chosen.append(0) }
                    choices.chosen[index] = value
                })
    }

    private var oneCharacter: Binding<String> {
        Binding(get: { choices.oneCharacter ?? party.first?.id ?? "" }, set: { choices.oneCharacter = $0 })
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(BoardTheme.brass)
    }
}
