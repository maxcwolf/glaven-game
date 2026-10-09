import Foundation

/// One rule explained for a player learning the game: shown as a tip the first time it comes up
/// in play, from a long-press or the "?", and in the How to Play sheet. Written in our own words.
struct LearnTopic: Identifiable, Equatable {
    enum ID: String, CaseIterable, Codable {
        // The round
        case round, cardChoice, initiative, scenarioGoal
        // Your turn
        case yourTurn, playedCards, moving, doors, loot, experience, items, summons
        // Attacks
        case attacking, modifiers, advantage, lineOfSight, shieldAndRetaliate, preventingDamage, pushAndPull
        // Monsters
        case monstersAct, focus, elites
        // Elements
        case elements
        // Your hand
        case handIsAClock, resting, exhaustion
        // Conditions
        case poison, wound, immobilize, disarm, stun, muddle, curse, invisible, strengthen, bless
    }

    enum Chapter: String, CaseIterable {
        case round = "The Round"
        case turn = "Your Turn"
        case attacks = "Attacks"
        case monsters = "Monsters"
        case elements = "Elements"
        case hand = "Your Hand"
        case conditions = "Conditions"
    }

    let id: ID
    let chapter: Chapter
    let title: String
    let paragraphs: [String]

    static func topic(_ id: ID) -> LearnTopic { all.first { $0.id == id }! }

    static func topics(in chapter: Chapter) -> [LearnTopic] { all.filter { $0.chapter == chapter } }

    /// The topic for a condition, if it has one.
    static func id(for condition: ConditionName) -> ID? { ID(rawValue: condition.rawValue) }

    static let all: [LearnTopic] = [
        // MARK: The round
        LearnTopic(id: .round, chapter: .round, title: "How a round goes", paragraphs: [
            "Every round starts with each player choosing two cards from their hand. Then the cards are revealed, each monster type draws an ability card, and everyone acts in initiative order, lowest first.",
            "When everyone has acted the round ends: elements wane, and anyone may take a short rest before the next round.",
        ]),
        LearnTopic(id: .cardChoice, chapter: .round, title: "Choosing two cards", paragraphs: [
            "Pick two cards from your hand. The one you lead with sets your initiative, the big number in the middle of the card: it decides when you act this round.",
            "On your turn you perform the top half of one card and the bottom half of the other. Which is which is decided then, not now.",
        ]),
        LearnTopic(id: .initiative, chapter: .round, title: "Initiative", paragraphs: [
            "Lower goes first. Monsters use the initiative on the ability card their type drew this round, so the order changes every round.",
            "Going early lets you strike before the monsters move. Going late lets you see what they do first.",
        ]),
        LearnTopic(id: .scenarioGoal, chapter: .round, title: "Winning a scenario", paragraphs: [
            "The goal is on the scenario brief (the chip at the top of the screen). Unless the brief says otherwise, you win by killing every enemy once every room is revealed.",
            "When the goal is met, or the scenario is lost, the rest of the round is still played out.",
        ]),

        // MARK: Your turn
        LearnTopic(id: .yourTurn, chapter: .turn, title: "Top of one, bottom of the other", paragraphs: [
            "On your turn, perform the top half of one of your cards and the bottom half of the other, in either order. Any part of a half may be skipped.",
            "Any half can be swapped for a basic action instead: Attack 2 for a top half, Move 2 for a bottom half.",
        ]),
        LearnTopic(id: .playedCards, chapter: .turn, title: "Where played cards go", paragraphs: [
            "After your turn your two cards go to your discard pile, unless the half you used shows the lost icon: then that card is lost for the rest of the scenario.",
            "A half with a persistent or round icon keeps its card in front of you, in your active area, while its effect lasts.",
        ]),
        LearnTopic(id: .moving, chapter: .turn, title: "Moving", paragraphs: [
            "Move up to the number shown, one hex at a time. You may pass through allies but not enemies or obstacles, and you can't end on another figure.",
            "Difficult terrain costs two movement. A trap springs when you step on it; hazardous terrain hurts each time you enter. A Jump ignores everything but where you land, and flying ignores terrain altogether.",
        ]),
        LearnTopic(id: .doors, chapter: .turn, title: "Doors and rooms", paragraphs: [
            "A character opens a closed door by moving onto it. The room behind is revealed, and its monsters appear.",
            "Monsters that appear act this round at their type's initiative, or straight after the turn if that has already passed.",
        ]),
        LearnTopic(id: .loot, chapter: .turn, title: "Money and treasure", paragraphs: [
            "At the end of your turn you pick up any money token or treasure in your hex. A Loot action picks up money tokens within its range.",
            "Money turns into gold at the end of the scenario, win or lose.",
        ]),
        LearnTopic(id: .experience, chapter: .turn, title: "Experience", paragraphs: [
            "An action with an experience icon gives that much experience when you perform it. Experience is kept whatever happens in the scenario, and it's how characters level up.",
        ]),
        LearnTopic(id: .items, chapter: .turn, title: "Items", paragraphs: [
            "Items are used on your turn when their moment comes: during a move, during an attack, or any time. A few are used on someone else's turn, like armour when you're attacked.",
            "A spent item comes back after a long rest. A consumed item is gone for the rest of the scenario.",
        ]),
        LearnTopic(id: .summons, chapter: .turn, title: "Summons", paragraphs: [
            "A summon fights on your side but acts on its own, just before you, following the monsters' rules with your enemies as its foes. It draws from your modifier deck.",
            "It stays until it's killed, or the card that summoned it leaves your active area.",
        ]),

        // MARK: Attacks
        LearnTopic(id: .attacking, chapter: .attacks, title: "Attacking", paragraphs: [
            "Choose an enemy within range that you can see. A melee attack reaches the hexes next to you; a ranged attack against an enemy next to you has disadvantage.",
            "Each target of an attack draws its own modifier card.",
        ]),
        LearnTopic(id: .modifiers, chapter: .attacks, title: "Every attack draws a card", paragraphs: [
            "An attacker draws one card from its modifier deck and adds it to the attack. A Miss deals nothing; ×2 doubles it.",
            "Your own deck starts with 20 cards: mostly +0, +1 and −1, with one +2, one −2, one ×2 and one Miss. Bless and Curse cards join it during play and leave once drawn. After a ×2 or a Miss is drawn, the deck is shuffled at the end of the round.",
        ]),
        LearnTopic(id: .advantage, chapter: .attacks, title: "Advantage and disadvantage", paragraphs: [
            "With advantage, draw two modifiers and use the better one. With disadvantage, use the worse one. If both apply, they cancel out.",
            "Strengthen gives advantage; muddle gives disadvantage, and so does a ranged attack on an enemy next to the attacker.",
        ]),
        LearnTopic(id: .lineOfSight, chapter: .attacks, title: "Line of sight", paragraphs: [
            "You can target a figure if a straight line from any corner of your hex to any corner of theirs doesn't cross a wall. Obstacles and other figures don't block sight.",
        ]),
        LearnTopic(id: .shieldAndRetaliate, chapter: .attacks, title: "Shield, retaliate and pierce", paragraphs: [
            "Shield takes that much off the damage of each attack. Pierce ignores that much of the target's shield.",
            "Retaliate hits back at an attacker within its range (next to it, unless it says otherwise), after the attack.",
        ]),
        LearnTopic(id: .preventingDamage, chapter: .attacks, title: "Preventing damage", paragraphs: [
            "When damage would hit you, you may instead lose one card from your hand, or two from your discard pile, and take none of it.",
            "It saves your hit points, but it shortens how long your hand lasts.",
        ]),
        LearnTopic(id: .pushAndPull, chapter: .attacks, title: "Push and pull", paragraphs: [
            "After the attack, push moves the target up to that many hexes away from the attacker, and pull moves it closer. It can't be moved through walls or obstacles, and a trap it's moved onto springs.",
        ]),

        // MARK: Monsters
        LearnTopic(id: .monstersAct, chapter: .monsters, title: "Monsters act on their own", paragraphs: [
            "Each monster type draws an ability card every round. It sets their initiative and says what each of them does.",
            "On their turn, elites act first, then the normal monsters by number. Each one picks a focus, moves toward it and attacks.",
        ]),
        LearnTopic(id: .focus, chapter: .monsters, title: "How monsters choose", paragraphs: [
            "A monster's focus is the enemy it can attack with the fewest hexes of movement. On a tie it picks the enemy nearest to it, and then the one who acts first this round.",
            "It moves only as far as it needs to attack its focus (a ranged monster stays at range if it can), then attacks it, and others too if its attack has more targets.",
        ]),
        LearnTopic(id: .elites, chapter: .monsters, title: "Elite and normal", paragraphs: [
            "A gold ring marks an elite monster: more hit points and a stronger attack than a normal one (white ring). The monster's stat card lists both.",
        ]),

        // MARK: Elements
        LearnTopic(id: .elements, chapter: .elements, title: "Elements", paragraphs: [
            "Some actions infuse an element. It becomes strong at the end of that turn, wanes at the end of the round, and is gone at the end of the next.",
            "Other actions consume a strong or waning element for a bonus. Monsters consume them too.",
        ]),

        // MARK: Your hand
        LearnTopic(id: .handIsAClock, chapter: .hand, title: "Your hand is your clock", paragraphs: [
            "You play two cards every round, and you can only keep going while you have two to play or can rest. Every rest loses one card for good, and so does every lost icon.",
            "Plan how long your hand will last: when it runs out, you're exhausted.",
        ]),
        LearnTopic(id: .resting, chapter: .hand, title: "Resting", paragraphs: [
            "A short rest happens at the end of a round: a random card from your discard pile is lost, and the rest return to your hand.",
            "A long rest takes your whole turn, at initiative 99: you choose which discarded card to lose, take the others back, heal 2 and refresh your spent items.",
        ]),
        LearnTopic(id: .exhaustion, chapter: .hand, title: "Exhaustion", paragraphs: [
            "A character is exhausted when their hit points reach zero, or when they can neither play two cards nor rest. They leave the board, but keep the experience and money they've earned.",
            "If every character is exhausted, the scenario is lost.",
        ]),

        // MARK: Conditions
        LearnTopic(id: .poison, chapter: .conditions, title: "Poison", paragraphs: [
            "Every attack against a poisoned figure does 1 more damage. A heal removes the poison instead of restoring hit points.",
        ]),
        LearnTopic(id: .wound, chapter: .conditions, title: "Wound", paragraphs: [
            "A wounded figure suffers 1 damage at the start of each of its turns. Any heal removes the wound (and still heals).",
        ]),
        LearnTopic(id: .immobilize, chapter: .conditions, title: "Immobilize", paragraphs: [
            "An immobilized figure can't move. It ends at the end of the figure's next turn.",
        ]),
        LearnTopic(id: .disarm, chapter: .conditions, title: "Disarm", paragraphs: [
            "A disarmed figure can't attack. It ends at the end of the figure's next turn.",
        ]),
        LearnTopic(id: .stun, chapter: .conditions, title: "Stun", paragraphs: [
            "A stunned figure can't do anything on its turn. A stunned character still plays two cards, and both are discarded. It ends at the end of the figure's next turn.",
        ]),
        LearnTopic(id: .muddle, chapter: .conditions, title: "Muddle", paragraphs: [
            "A muddled figure's attacks have disadvantage. It ends at the end of the figure's next turn.",
        ]),
        LearnTopic(id: .curse, chapter: .conditions, title: "Curse", paragraphs: [
            "A Curse card, a Miss, is shuffled into the figure's modifier deck. It leaves the deck once drawn.",
        ]),
        LearnTopic(id: .invisible, chapter: .conditions, title: "Invisible", paragraphs: [
            "An invisible figure can't be targeted or chosen as a focus by its enemies. It ends at the end of the figure's next turn.",
        ]),
        LearnTopic(id: .strengthen, chapter: .conditions, title: "Strengthen", paragraphs: [
            "A strengthened figure's attacks have advantage. It ends at the end of the figure's next turn.",
        ]),
        LearnTopic(id: .bless, chapter: .conditions, title: "Bless", paragraphs: [
            "A Bless card, a ×2, is shuffled into the figure's modifier deck. It leaves the deck once drawn.",
        ]),
    ]
}
