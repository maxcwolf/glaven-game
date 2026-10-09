import Foundation

/// One rule explained for a player learning the game: shown as a tip the first time it comes up
/// in play, from a long-press or the "?", and in How to Play. Written in our own words.
///
/// Paragraphs are Markdown: **bold** for the term being taught, and `[word](topic:id)` links to
/// another topic.
struct LearnTopic: Identifiable, Equatable {
    enum ID: String, CaseIterable, Codable {
        // The round
        case round, cardChoice, initiative, scenarioGoal, specialRules
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
        // Between scenarios
        case levelUp, perks, enhancing, shopping, personalQuest, retirement
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
        case town = "Between Scenarios"
        case conditions = "Conditions"
    }

    /// The picture at the top of the topic's page: the game's own art where it has some, a
    /// small hex map where it doesn't.
    enum Art: Equatable {
        /// Steps or facts in a row of chips; with arrows between them when they're a sequence.
        case steps([String], arrows: Bool)
        /// The turn order as initiative chips.
        case order([(Int, String)])
        /// Ability card scans (Brute cards by id), each with a badge.
        case cards([(id: Int, badge: String)])
        /// The two played cards with the half each gives lit.
        case halves(top: Int, bottom: Int)
        /// Attack modifier cards, by type name.
        case modifiers([String])
        /// Two draws side by side, the card kept ringed.
        case advantage
        case condition(ConditionName)
        case elements
        /// An elite and a normal monster token.
        case elites
        /// A monster ability card.
        case monsterCard
        /// An attack's sum as chips.
        case sum([String])
        /// A modifier card taken out of the deck and another put in (a perk).
        case swap(from: String, to: String)
        case diagram(LearnDiagram)

        static func == (a: Art, b: Art) -> Bool {
            switch (a, b) {
            case (.steps(let x, let p), .steps(let y, let q)): return x == y && p == q
            case (.order(let x), .order(let y)): return x.map(\.0) == y.map(\.0) && x.map(\.1) == y.map(\.1)
            case (.cards(let x), .cards(let y)): return x.map(\.id) == y.map(\.id) && x.map(\.badge) == y.map(\.badge)
            case (.halves(let a1, let b1), .halves(let a2, let b2)): return a1 == a2 && b1 == b2
            case (.modifiers(let x), .modifiers(let y)): return x == y
            case (.advantage, .advantage), (.elements, .elements), (.elites, .elites), (.monsterCard, .monsterCard):
                return true
            case (.condition(let x), .condition(let y)): return x == y
            case (.sum(let x), .sum(let y)): return x == y
            case (.swap(let a1, let b1), .swap(let a2, let b2)): return a1 == a2 && b1 == b2
            case (.diagram(let x), .diagram(let y)): return x == y
            default: return false
            }
        }
    }

    let id: ID
    let chapter: Chapter
    let title: String
    let paragraphs: [String]
    var art: Art
    /// Where the rule shows up in this game.
    var onTheBoard: String

    static func topic(_ id: ID) -> LearnTopic { all.first { $0.id == id }! }

    static func topics(in chapter: Chapter) -> [LearnTopic] { all.filter { $0.chapter == chapter } }

    /// The topic for a condition, if it has one.
    static func id(for condition: ConditionName) -> ID? { ID(rawValue: condition.rawValue) }

    /// The topics before and after this one, reading the book through.
    var previous: LearnTopic? {
        guard let index = Self.all.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        return Self.all[index - 1]
    }
    var next: LearnTopic? {
        guard let index = Self.all.firstIndex(where: { $0.id == id }), index + 1 < Self.all.count else { return nil }
        return Self.all[index + 1]
    }

    /// "3 of 7" within its chapter.
    var place: (index: Int, of: Int) {
        let topics = Self.topics(in: chapter)
        return ((topics.firstIndex { $0.id == id } ?? 0) + 1, topics.count)
    }

    /// A paragraph without its Markdown, for places that show plain text.
    static func plain(_ markdown: String) -> String {
        var text = markdown.replacingOccurrences(of: "**", with: "")
        while let open = text.range(of: "["), let mid = text.range(of: "](", range: open.upperBound..<text.endIndex),
              let close = text.range(of: ")", range: mid.upperBound..<text.endIndex) {
            text.replaceSubrange(open.lowerBound..<close.upperBound, with: text[open.upperBound..<mid.lowerBound])
        }
        return text
    }

    /// Topics whose title or text holds `query`, in book order.
    static func search(_ query: String) -> [LearnTopic] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { topic in
            topic.title.lowercased().contains(q) || topic.paragraphs.contains { plain($0).lowercased().contains(q) }
        }
    }

    static let all: [LearnTopic] = [
        // MARK: The round
        LearnTopic(id: .round, chapter: .round, title: "How a round goes", paragraphs: [
            "Every round starts with each player [choosing two cards](topic:cardChoice) from their hand. Then the cards are revealed, each monster type draws an ability card, and everyone acts in [initiative](topic:initiative) order, lowest first.",
            "When everyone has acted the round ends: [elements](topic:elements) wane, and anyone may take a [short rest](topic:resting) before the next round.",
        ], art: .steps(["Choose two cards", "Reveal; monsters draw", "Act by initiative", "End of round"], arrows: true),
           onTheBoard: "The top bar says which part of the round it is, and the turn order fills in once the cards are revealed."),
        LearnTopic(id: .cardChoice, chapter: .round, title: "Choosing two cards", paragraphs: [
            "Pick two cards from your hand. The one you **lead** with sets your [initiative](topic:initiative), the big number in the middle of the card: it decides when you act this round.",
            "On your turn you perform the [top half of one card and the bottom half of the other](topic:yourTurn). Which is which is decided then, not now.",
        ], art: .cards([(1, "Lead \u{00B7} 72"), (10, "Second")]),
           onTheBoard: "The cards along the bottom: tap two, and tap a chosen one to make it the lead."),
        LearnTopic(id: .initiative, chapter: .round, title: "Initiative", paragraphs: [
            "Lower goes first. Monsters use the initiative on the ability card their type drew this round, so the order changes every round.",
            "Going early lets you strike before the monsters move. Going late lets you see what they do first.",
        ], art: .order([(10, "Brute"), (35, "Bandit Guard"), (69, "Spellweaver")]),
           onTheBoard: "The turn order across the top bar, lowest first; a tick marks those who have acted."),
        LearnTopic(id: .scenarioGoal, chapter: .round, title: "Winning a scenario", paragraphs: [
            "The goal is on the scenario brief. Unless the brief says otherwise, you win by **killing every enemy** once every room is revealed.",
            "When the goal is met, or the scenario is lost, the rest of the round is still played out.",
        ], art: .diagram(.scenarioGoal),
           onTheBoard: "The goal chip at the top: tap it to read the brief again."),
        LearnTopic(id: .specialRules, chapter: .round, title: "Special rules", paragraphs: [
            "Many scenarios change the usual rules: monsters that appear every few rounds, doors that open on their own, a figure to protect, a different way to [win](topic:scenarioGoal).",
            "The scenario brief lists them before you start. They apply on top of everything else, and win over it where the two disagree.",
        ], art: .steps(["The brief lists them", "They change the usual rules", "The goal chip shows them again"], arrows: false),
           onTheBoard: "The goal chip at the top reopens the brief with its special rules; the log notes each one as it happens."),

        // MARK: Your turn
        LearnTopic(id: .yourTurn, chapter: .turn, title: "Top of one, bottom of the other", paragraphs: [
            "On your turn, perform the **top half** of one of your cards and the **bottom half** of the other, in either order. Any part of a half may be skipped.",
            "Any half can be swapped for a basic action instead: Attack 2 for a top half, Move 2 for a bottom half.",
        ], art: .halves(top: 1, bottom: 10),
           onTheBoard: "Your two cards at the bottom, with the half being played ringed in brass; Swap Cards and Bottom First change which is which."),
        LearnTopic(id: .playedCards, chapter: .turn, title: "Where played cards go", paragraphs: [
            "After your turn your two cards go to your **discard pile**, unless the half you used shows the lost icon: then that card is **lost** for the rest of the scenario.",
            "A half with a persistent or round icon keeps its card in front of you, in your **active area**, while its effect lasts.",
        ], art: .steps(["Discard pile", "Lost (\u{2715} icon)", "Active area"], arrows: false),
           onTheBoard: "Your panel counts your hand and lost cards; a rest brings the discard pile back."),
        LearnTopic(id: .moving, chapter: .turn, title: "Moving", paragraphs: [
            "Move up to the number shown, one hex at a time. You may pass through allies but not enemies or obstacles, and you can't end on another figure.",
            "**Difficult terrain** costs two movement. A **trap** springs when you step on it; **hazardous terrain** hurts each time you enter. A Jump ignores everything but where you land, and flying ignores terrain altogether.",
        ], art: .diagram(.moving),
           onTheBoard: "The hexes you can reach light up; tap one to move there."),
        LearnTopic(id: .doors, chapter: .turn, title: "Doors and rooms", paragraphs: [
            "A character opens a closed door by moving onto it. The room behind is revealed, and its monsters appear.",
            "Monsters that appear act this round at their type's [initiative](topic:initiative), or straight after the turn if that has already passed.",
        ], art: .diagram(.doors),
           onTheBoard: "A closed door is a hex in the wall; the new monsters join the turn order and the monster panel."),
        LearnTopic(id: .loot, chapter: .turn, title: "Money and treasure", paragraphs: [
            "At the end of your turn you pick up any money token or treasure in your hex. A **Loot** action picks up money tokens within its range.",
            "Money turns into gold at the end of the scenario, win or lose.",
        ], art: .diagram(.loot),
           onTheBoard: "Coins lie on their hexes; what you pick up is counted at the end of the scenario."),
        LearnTopic(id: .experience, chapter: .turn, title: "Experience", paragraphs: [
            "An action with an experience icon gives that much experience when you perform it. Experience is kept whatever happens in the scenario, and it's how characters level up.",
        ], art: .cards([(1, "XP on the bottom half")]),
           onTheBoard: "XP in your panel, counted as you go."),
        LearnTopic(id: .items, chapter: .turn, title: "Items", paragraphs: [
            "Items are used on your turn when their moment comes: during a move, during an attack, or any time. A few are used on someone else's turn, like armour when you're attacked.",
            "A **spent** item comes back after a [long rest](topic:resting). A **consumed** item is gone for the rest of the scenario.",
        ], art: .steps(["Spent: back after a long rest", "Consumed: gone for the scenario"], arrows: false),
           onTheBoard: "Usable items appear as buttons in the turn panel when their moment comes."),
        LearnTopic(id: .summons, chapter: .turn, title: "Summons", paragraphs: [
            "A summon fights on your side but acts on its own, just before you, following the [monsters' rules](topic:focus) with your enemies as its foes. It draws from your modifier deck.",
            "It stays until it's killed, or the card that summoned it leaves your active area.",
        ], art: .diagram(.summons),
           onTheBoard: "Summons are listed under their summoner in the party panel."),

        // MARK: Attacks
        LearnTopic(id: .attacking, chapter: .attacks, title: "Attacking", paragraphs: [
            "Choose an enemy within **range** that you can [see](topic:lineOfSight). A melee attack reaches the hexes next to you; a ranged attack against an enemy next to you has [disadvantage](topic:advantage).",
            "Each target of an attack draws its own [modifier card](topic:modifiers).",
        ], art: .diagram(.attacking),
           onTheBoard: "Enemies you can attack light up, each with the damage it would take before the draw."),
        LearnTopic(id: .modifiers, chapter: .attacks, title: "Every attack draws a card", paragraphs: [
            "An attacker draws one card from its modifier deck and adds it to the attack. A **Miss** deals nothing; **\u{00D7}2** doubles it.",
            "Your own deck starts with 20 cards: mostly +0, +1 and \u{2212}1, with one +2, one \u{2212}2, one \u{00D7}2 and one Miss. [Bless](topic:bless) and [Curse](topic:curse) cards join it during play and leave once drawn. After a \u{00D7}2 or a Miss is drawn, the deck is shuffled at the end of the round.",
        ], art: .modifiers(["plus0", "plus1", "minus1", "double", "null"]),
           onTheBoard: "The modifier tray, under the party panel: the cards drawn and how the attack added up."),
        LearnTopic(id: .advantage, chapter: .attacks, title: "Advantage and disadvantage", paragraphs: [
            "With **advantage**, draw two modifier cards and use the better one. With **disadvantage**, use the worse one. If both apply, they cancel out.",
            "[Strengthen](topic:strengthen) gives advantage; [muddle](topic:muddle) gives disadvantage, and so does a ranged attack on an enemy next to the attacker.",
        ], art: .advantage,
           onTheBoard: "The modifier tray draws two cards and dims the one not used."),
        LearnTopic(id: .lineOfSight, chapter: .attacks, title: "Line of sight", paragraphs: [
            "You can target a figure if a straight line from any corner of your hex to any corner of theirs doesn't cross a **wall**. Obstacles and other figures don't block sight.",
        ], art: .diagram(.lineOfSight),
           onTheBoard: "An enemy you can't see doesn't light up when you attack."),
        LearnTopic(id: .shieldAndRetaliate, chapter: .attacks, title: "Shield, retaliate and pierce", paragraphs: [
            "**Shield** takes that much off the damage of each attack. **Pierce** ignores that much of the target's shield.",
            "**Retaliate** hits back at an attacker within its range (next to it, unless it says otherwise), after the attack.",
        ], art: .sum(["Attack 3", "+1 card", "\u{2212}1 shield", "= 3 damage"]),
           onTheBoard: "The tray's sum takes the shield off, and retaliate's damage is noted in Recent."),
        LearnTopic(id: .preventingDamage, chapter: .attacks, title: "Preventing damage", paragraphs: [
            "When damage would hit you, you may instead lose one card from your hand, or two from your discard pile, and take none of it.",
            "It saves your hit points, but it [shortens how long your hand lasts](topic:handIsAClock).",
        ], art: .steps(["2 damage coming", "Lose 1 card from hand, or 2 from discard", "No damage"], arrows: true),
           onTheBoard: "When you're hit, the damage panel offers your cards to lose instead."),
        LearnTopic(id: .pushAndPull, chapter: .attacks, title: "Push and pull", paragraphs: [
            "After the attack, **push** moves the target up to that many hexes away from the attacker, and **pull** moves it closer. It can't be moved through walls or obstacles, and a trap it's moved onto springs.",
        ], art: .diagram(.pushAndPull),
           onTheBoard: "The hexes the target can be pushed or pulled to light up; tap them in order."),

        // MARK: Monsters
        LearnTopic(id: .monstersAct, chapter: .monsters, title: "Monsters act on their own", paragraphs: [
            "Each monster type draws an **ability card** every round. It sets their [initiative](topic:initiative) and says what each of them does.",
            "On their turn, elites act first, then the normal monsters by number. Each one picks a [focus](topic:focus), moves toward it and attacks.",
        ], art: .monsterCard,
           onTheBoard: "This round's ability cards, bottom right; Pause and Fast-Forward sit beside the instruction while they act."),
        LearnTopic(id: .focus, chapter: .monsters, title: "How monsters choose", paragraphs: [
            "A monster's **focus** is the enemy it can attack with the fewest hexes of movement. On a tie it picks the enemy nearest to it, and then the one who acts first this round.",
            "It moves only as far as it needs to attack its focus (a ranged monster stays at range if it can), then attacks it, and others too if its attack has more targets.",
        ], art: .diagram(.focus),
           onTheBoard: "Tap \u{201C}Why?\u{201D} beside a monster's lines in Recent to see the choice drawn on the board."),
        LearnTopic(id: .elites, chapter: .monsters, title: "Elite and normal", paragraphs: [
            "A **gold ring** marks an elite monster: more hit points and a stronger attack than a normal one (white ring). The monster's stat card lists both.",
        ], art: .elites,
           onTheBoard: "Elites are listed first, in gold, in the monster panel."),

        // MARK: Elements
        LearnTopic(id: .elements, chapter: .elements, title: "Elements", paragraphs: [
            "Some actions **infuse** an element. It becomes strong at the end of that turn, wanes at the end of the round, and is gone at the end of the next.",
            "Other actions **consume** a strong or waning element for a bonus. Monsters consume them too.",
        ], art: .elements,
           onTheBoard: "The six elements, top right: bright and ringed when strong, half-lit when waning."),

        // MARK: Your hand
        LearnTopic(id: .handIsAClock, chapter: .hand, title: "Your hand is your clock", paragraphs: [
            "You play two cards every round, and you can only keep going while you have two to play or can [rest](topic:resting). Every rest loses one card for good, and so does every lost icon.",
            "Plan how long your hand will last: when it runs out, you're [exhausted](topic:exhaustion).",
        ], art: .steps(["Hand of 10", "8", "6", "4", "2", "Rest: all but one back"], arrows: true),
           onTheBoard: "Your panel counts the cards in your hand and the ones lost."),
        LearnTopic(id: .resting, chapter: .hand, title: "Resting", paragraphs: [
            "A **short rest** happens at the end of a round: a random card from your discard pile is lost, and the rest return to your hand.",
            "A **long rest** takes your whole turn, at initiative 99: you choose which discarded card to lose, take the others back, heal 2 and refresh your spent items.",
        ], art: .steps(["Short rest: end of round, a random card lost", "Long rest: initiative 99, you choose, heal 2"], arrows: false),
           onTheBoard: "Long Rest is beside Confirm when choosing cards; a short rest is offered when the round ends."),
        LearnTopic(id: .exhaustion, chapter: .hand, title: "Exhaustion", paragraphs: [
            "A character is exhausted when their hit points reach zero, or when they can neither play two cards nor rest. They leave the board, but keep the experience and money they've earned.",
            "If every character is exhausted, the scenario is lost.",
        ], art: .steps(["Hit points reach 0", "Or no two cards and no rest", "Off the board"], arrows: true),
           onTheBoard: "The damage panel warns when taking damage would exhaust you."),

        // MARK: Between scenarios
        LearnTopic(id: .levelUp, chapter: .town, title: "Levelling up", paragraphs: [
            "Experience earned in scenarios adds up. At 45 a character reaches level 2, at 95 level 3, then 150, 210, 275, 345, 420 and 500 for level 9.",
            "Each level gives more hit points, a new ability card of that level or lower to choose from (your hand stays the same size), and a [perk](topic:perks).",
        ], art: .order([(45, "Level 2"), (95, "Level 3"), (150, "Level 4")]),
           onTheBoard: "In town, Level Up appears on a character once they have the experience."),
        LearnTopic(id: .perks, chapter: .town, title: "Perks", paragraphs: [
            "A perk improves your [modifier deck](topic:modifiers): it takes weak cards out, adds better ones, or adds cards with effects. Each class has its own list.",
            "You earn a perk with every level, and another for every three checkmarks from battle goals.",
        ], art: .swap(from: "minus1", to: "plus1"),
           onTheBoard: "In town, a character's button shows the perks they can take; choose them on their sheet."),
        LearnTopic(id: .enhancing, chapter: .town, title: "Enhancing", paragraphs: [
            "Once the Enhancer is open, gold buys an enhancement for one of your ability cards: +1 to a number, a condition or an element added to an attack, or another hex for an area attack.",
            "It's permanent: the card keeps it for every character of that class. It costs more on higher-level cards and on cards already enhanced.",
        ], art: .sum(["Attack 3", "+1 enhancement", "= Attack 4, for good"]),
           onTheBoard: "In town, Enhance on a character opens their cards with each slot and its price."),
        LearnTopic(id: .shopping, chapter: .town, title: "The shop", paragraphs: [
            "Gold buys [items](topic:items) in town. The shop has a few copies of each, and more items as the city's prosperity grows.",
            "A character can sell an item back for half its price.",
        ], art: .steps(["Buy with gold", "More as prosperity grows", "Sell back for half"], arrows: false),
           onTheBoard: "In town, Shop on a character; their gold is beside their name."),
        LearnTopic(id: .personalQuest, chapter: .town, title: "Personal quests", paragraphs: [
            "Every character has a personal quest: a life goal of their own, like killing a number of one kind of monster or saving up gold.",
            "It fills in as you play. When it's done, the character [retires](topic:retirement).",
        ], art: .steps(["Choose a quest", "It fills in as you play", "Done: retire"], arrows: true),
           onTheBoard: "In town, each character shows their quest and how much of it is done."),
        LearnTopic(id: .retirement, chapter: .town, title: "Retirement", paragraphs: [
            "A character whose [personal quest](topic:personalQuest) is done retires: they leave the party for good, the city's prosperity rises, and the quest's reward is unlocked, often a new class.",
            "The player then starts a new character, at any level up to the city's prosperity level.",
        ], art: .steps(["Quest done", "Retire in town", "Its reward unlocked", "A new character"], arrows: true),
           onTheBoard: "In town, Retire appears on a character once their quest is done."),

        // MARK: Conditions
        LearnTopic(id: .poison, chapter: .conditions, title: "Poison", paragraphs: [
            "Every attack against a poisoned figure does **1 more damage**. A heal removes the poison instead of restoring hit points.",
        ], art: .condition(.poison), onTheBoard: "Conditions show as icons on a figure and in its panel."),
        LearnTopic(id: .wound, chapter: .conditions, title: "Wound", paragraphs: [
            "A wounded figure suffers **1 damage** at the start of each of its turns. Any heal removes the wound (and still heals).",
        ], art: .condition(.wound), onTheBoard: "Conditions show as icons on a figure and in its panel."),
        LearnTopic(id: .immobilize, chapter: .conditions, title: "Immobilize", paragraphs: [
            "An immobilized figure **can't move**. It ends at the end of the figure's next turn.",
        ], art: .condition(.immobilize), onTheBoard: "Conditions show as icons on a figure and in its panel."),
        LearnTopic(id: .disarm, chapter: .conditions, title: "Disarm", paragraphs: [
            "A disarmed figure **can't attack**. It ends at the end of the figure's next turn.",
        ], art: .condition(.disarm), onTheBoard: "Conditions show as icons on a figure and in its panel."),
        LearnTopic(id: .stun, chapter: .conditions, title: "Stun", paragraphs: [
            "A stunned figure **can't do anything** on its turn. A stunned character still plays two cards, and both are discarded. It ends at the end of the figure's next turn.",
        ], art: .condition(.stun), onTheBoard: "Conditions show as icons on a figure and in its panel."),
        LearnTopic(id: .muddle, chapter: .conditions, title: "Muddle", paragraphs: [
            "A muddled figure's attacks have [disadvantage](topic:advantage). It ends at the end of the figure's next turn.",
        ], art: .condition(.muddle), onTheBoard: "Conditions show as icons on a figure and in its panel."),
        LearnTopic(id: .curse, chapter: .conditions, title: "Curse", paragraphs: [
            "A **Curse** card, a Miss, is shuffled into the figure's [modifier deck](topic:modifiers). It leaves the deck once drawn.",
        ], art: .condition(.curse), onTheBoard: "A drawn curse shows in the modifier tray."),
        LearnTopic(id: .invisible, chapter: .conditions, title: "Invisible", paragraphs: [
            "An invisible figure **can't be targeted** or chosen as a [focus](topic:focus) by its enemies. It ends at the end of the figure's next turn.",
        ], art: .condition(.invisible), onTheBoard: "Conditions show as icons on a figure and in its panel."),
        LearnTopic(id: .strengthen, chapter: .conditions, title: "Strengthen", paragraphs: [
            "A strengthened figure's attacks have [advantage](topic:advantage). It ends at the end of the figure's next turn.",
        ], art: .condition(.strengthen), onTheBoard: "Conditions show as icons on a figure and in its panel."),
        LearnTopic(id: .bless, chapter: .conditions, title: "Bless", paragraphs: [
            "A **Bless** card, a \u{00D7}2, is shuffled into the figure's [modifier deck](topic:modifiers). It leaves the deck once drawn.",
        ], art: .condition(.bless), onTheBoard: "A drawn bless shows in the modifier tray."),
    ]
}

/// What a player has met of the rules: topics taught by a tip in play, and topics read in How
/// to Play.
struct LearnProgress: Equatable {
    var seen: Set<String> = []
    var read: Set<String> = []

    /// Met in play or read: ticked in the contents.
    func knows(_ id: LearnTopic.ID) -> Bool { seen.contains(id.rawValue) || read.contains(id.rawValue) }

    /// Came up in play but not read yet: "New".
    func isNew(_ id: LearnTopic.ID) -> Bool { seen.contains(id.rawValue) && !read.contains(id.rawValue) }

    /// "4 of 7" for a chapter.
    func count(_ chapter: LearnTopic.Chapter) -> (known: Int, of: Int) {
        let topics = LearnTopic.topics(in: chapter)
        return (topics.filter { knows($0.id) }.count, topics.count)
    }
}
