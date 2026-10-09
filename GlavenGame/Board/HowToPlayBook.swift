import SwiftUI

// MARK: - Rules text

/// A topic's Markdown as styled text: bold terms, and brass underlined links to other topics
/// (opened through `openURL` with the "topic:" scheme).
enum LearnText {
    static func attributed(_ markdown: String) -> AttributedString {
        var text = (try? AttributedString(markdown: markdown,
                                          options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
        for run in text.runs where run.link != nil {
            text[run.range].foregroundColor = BoardTheme.brass
            text[run.range].underlineStyle = .single
        }
        return text
    }

    /// The topic a "topic:" link opens.
    static func topic(of url: URL) -> LearnTopic.ID? {
        guard url.scheme == "topic" else { return nil }
        return LearnTopic.ID(rawValue: String(url.absoluteString.dropFirst("topic:".count)))
    }
}

// MARK: - The book

/// How to Play: the contents down the left (chapters, ticks for what's been met, a search), one
/// topic at a time on the right with the game's art or a hex diagram, and Previous and Next to
/// read it through. On a narrow window the contents and the page take turns.
struct HowToPlayBook: View {
    let coordinator: BoardCoordinator
    @State private var current: LearnTopic.ID
    @State private var query = ""
    @State private var showingContents = false

    init(coordinator: BoardCoordinator, topic: LearnTopic.ID?) {
        self.coordinator = coordinator
        _current = State(initialValue: topic ?? LearnTopic.all[0].id)
    }

    static let compactWidth: CGFloat = 760

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 32, 1240)
            let height = min(geo.size.height - 32, 900)
            let compact = width < Self.compactWidth
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)   // the book's close button does it
                HStack(spacing: 0) {
                    if !compact || showingContents {
                        contents
                            .frame(width: compact ? width : 320)
                    }
                    if !compact {
                        Rectangle().fill(BoardTheme.border.opacity(0.5)).frame(width: 1)
                    }
                    if !compact || !showingContents {
                        page(compact: compact)
                    }
                }
                .frame(width: width, height: height)
                .background(BoardTheme.sheet, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(BoardTheme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let id = LearnText.topic(of: url) else { return .systemAction }
            go(to: id)
            return .handled
        })
        .onAppear { coordinator.markRead(current) }
        .onChange(of: current) { _, id in coordinator.markRead(id) }
    }

    private func go(to id: LearnTopic.ID) {
        withAnimation(.snappy) {
            current = id
            showingContents = false
        }
    }

    private func close() { coordinator.howToPlay = nil }

    // MARK: Contents

    private var contents: some View {
        let progress = coordinator.learnProgress
        let topic = LearnTopic.topic(current)
        return VStack(alignment: .leading, spacing: 0) {
            Text("How to Play")
                .font(BoardTheme.display(30))
                .foregroundStyle(BoardTheme.text)
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(BoardTheme.secondaryText)
                TextField("Search the rules", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(BoardTheme.text)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(BoardTheme.secondaryText)
                        .accessibilityLabel("Clear the search")
                }
            }
            .font(BoardTheme.font(size: 15))
            .padding(.horizontal, 12).frame(height: 38)
            .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16).padding(.bottom, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        ForEach(LearnTopic.Chapter.allCases, id: \.self) { chapter in
                            chapterHeader(chapter, open: chapter == topic.chapter, progress: progress)
                            if chapter == topic.chapter {
                                ForEach(LearnTopic.topics(in: chapter)) { row($0, progress: progress) }
                            }
                        }
                    } else {
                        let found = LearnTopic.search(query)
                        if found.isEmpty {
                            Text("Nothing found").font(BoardTheme.font(size: 14)).foregroundStyle(BoardTheme.secondaryText)
                                .padding(20)
                        }
                        ForEach(found) { row($0, progress: progress, showChapter: true) }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(BoardTheme.panel)
    }

    private func chapterHeader(_ chapter: LearnTopic.Chapter, open: Bool, progress: LearnProgress) -> some View {
        let count = progress.count(chapter)
        return Button {
            if !open, let first = LearnTopic.topics(in: chapter).first { go(to: first.id) }
        } label: {
            HStack {
                Text(chapter.rawValue.uppercased())
                    .font(BoardTheme.font(size: 12, weight: .bold)).kerning(1.2)
                    .foregroundStyle(open ? BoardTheme.brass : BoardTheme.secondaryText)
                Spacer()
                Text("\(count.known) of \(count.of)")
                    .font(BoardTheme.font(size: 12).monospacedDigit())
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chapter.rawValue), \(count.known) of \(count.of) met")
    }

    private func row(_ topic: LearnTopic, progress: LearnProgress, showChapter: Bool = false) -> some View {
        let lit = topic.id == current
        let known = progress.knows(topic.id)
        return Button { go(to: topic.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: known ? "checkmark.circle.fill" : "circle")
                    .font(BoardTheme.font(size: 14))
                    .foregroundStyle(lit ? BoardTheme.sheet : (known ? BoardTheme.brass.opacity(0.8) : BoardTheme.secondaryText.opacity(0.5)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(topic.title)
                        .font(BoardTheme.font(size: 15, weight: lit ? .semibold : .regular))
                        .foregroundStyle(lit ? BoardTheme.sheet : BoardTheme.text)
                        .lineLimit(1)
                    if showChapter {
                        Text(topic.chapter.rawValue)
                            .font(BoardTheme.font(size: 11))
                            .foregroundStyle(lit ? BoardTheme.sheet.opacity(0.8) : BoardTheme.secondaryText)
                    }
                }
                Spacer(minLength: 4)
                if progress.isNew(topic.id) && !lit {
                    Text("NEW").font(BoardTheme.font(size: 11, weight: .bold))
                        .foregroundStyle(BoardTheme.brass)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(BoardTheme.brass, lineWidth: 1))
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(lit ? BoardTheme.brass : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .accessibilityLabel(topic.title)
        .accessibilityValue(known ? "met" : "not met yet")
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    // MARK: Page

    private func page(compact: Bool) -> some View {
        GeometryReader { geo in
            pageContent(compact: compact, width: geo.size.width)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    private func pageContent(compact: Bool, width: CGFloat) -> some View {
        let topic = LearnTopic.topic(current)
        let place = topic.place
        let margin: CGFloat = compact ? 24 : 64
        // The picture fits the page: never wider than the text column, or the page itself.
        let artWidth = max(200, min(620, width - margin * 2) - 36)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                if compact {
                    Button { withAnimation(.snappy) { showingContents = true } } label: {
                        Label("Contents", systemImage: "list.bullet")
                    }
                    .buttonStyle(.boardQuietCompact)
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(BoardTheme.font(size: 15, weight: .semibold))
                        .foregroundStyle(BoardTheme.text)
                        .frame(width: 36, height: 36)
                        .background(BoardTheme.raised, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close How to Play")
            }
            .padding(.top, 12).padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("\(topic.chapter.rawValue.uppercased()) \u{00B7} \(place.index) OF \(place.of)")
                        .font(BoardTheme.font(size: 13, weight: .bold)).kerning(1.5)
                        .foregroundStyle(BoardTheme.brass)
                    Text(topic.title)
                        .font(BoardTheme.display(compact ? 34 : 44))
                        .foregroundStyle(BoardTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    LearnArtView(art: topic.art, width: artWidth)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(topic.paragraphs, id: \.self) { paragraph in
                            Text(LearnText.attributed(paragraph))
                                .font(BoardTheme.font(size: 19, design: .serif))
                                .lineSpacing(6)
                                .foregroundStyle(BoardTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "eye").foregroundStyle(BoardTheme.brass)
                            .accessibilityHidden(true)
                        Text("On the board: \(topic.onTheBoard)")
                            .font(BoardTheme.font(size: 14))
                            .foregroundStyle(BoardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                }
                .padding(.horizontal, margin)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(current)   // each topic starts at its top
            footer(topic)
        }
        .frame(maxWidth: .infinity)
    }

    private func footer(_ topic: LearnTopic) -> some View {
        HStack(alignment: .bottom) {
            if let previous = topic.previous {
                navButton("Previous", previous, leading: true)
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            Spacer()
            if let next = topic.next {
                navButton("Next", next, leading: false)
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 18)
        .overlay(alignment: .top) { Rectangle().fill(BoardTheme.border.opacity(0.4)).frame(height: 1) }
    }

    private func navButton(_ label: String, _ topic: LearnTopic, leading: Bool) -> some View {
        Button { go(to: topic.id) } label: {
            VStack(alignment: leading ? .leading : .trailing, spacing: 2) {
                Text(label).font(BoardTheme.font(size: 12)).foregroundStyle(BoardTheme.secondaryText)
                Text(leading ? "\u{2039}  \(topic.title)" : "\(topic.title)  \u{203A}")
                    .font(BoardTheme.font(size: 16, weight: .semibold))
                    .foregroundStyle(BoardTheme.brass)
                    .lineLimit(1)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(topic.title)")
    }
}

// MARK: - The pictures

/// A topic's picture: the game's own art, or a small hex diagram.
struct LearnArtView: View {
    let art: LearnTopic.Art
    /// The room the picture has (inside its own padding).
    var width: CGFloat = 584

    var body: some View {
        content
            .padding(18)
            .background(BoardTheme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var content: some View {
        switch art {
        case .steps(let steps, let arrows):
            FlowLayout(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 8) {
                        chip(step, lit: arrows && index == steps.count - 1)
                        if arrows && index < steps.count - 1 {
                            Image(systemName: "arrow.right").foregroundStyle(BoardTheme.brass)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        case .order(let order):
            FlowLayout(spacing: 10) {
                ForEach(Array(order.enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Text("\(entry.0)")
                                .font(BoardTheme.font(size: 15, weight: .bold).monospacedDigit())
                                .foregroundStyle(BoardTheme.sheet)
                                .padding(.horizontal, 7)
                                .frame(minWidth: 30, minHeight: 30)
                                .background(BoardTheme.brass, in: Capsule())
                            Text(entry.1).font(BoardTheme.font(size: 15, weight: .medium)).foregroundStyle(BoardTheme.text)
                        }
                        .padding(.trailing, 12).padding(4)
                        .background(BoardTheme.raised, in: Capsule())
                        if index < order.count - 1 {
                            Image(systemName: "arrow.right").foregroundStyle(BoardTheme.secondaryText).accessibilityHidden(true)
                        }
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        case .cards(let cards):
            HStack(spacing: 14) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    VStack(spacing: 8) {
                        abilityCard(card.id).frame(height: 200)
                        Text(card.badge)
                            .font(BoardTheme.font(size: 12, weight: .bold))
                            .foregroundStyle(BoardTheme.sheet)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(BoardTheme.brass, in: Capsule())
                    }
                }
            }
        case .halves(let top, let bottom):
            HStack(spacing: 14) {
                half(top, lit: .top, caption: "Its top half")
                half(bottom, lit: .bottom, caption: "Its bottom half")
            }
        case .modifiers(let types):
            FlowLayout(spacing: 10) {
                ForEach(types, id: \.self) { type in
                    if let kind = AttackModifierType(rawValue: type) {
                        AttackModifierCardView(modifier: AttackModifier(type: kind), size: 78)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        case .advantage:
            FlowLayout(spacing: 28) {
                draw("Advantage", keep: 0, note: "keep the better")
                draw("Disadvantage", keep: 1, note: "keep the worse")
            }
            .frame(width: width, alignment: .leading)
        case .condition(let condition):
            HStack(spacing: 18) {
                BundledImage(ImageLoader.conditionIcon(condition.rawValue), size: 72, systemName: "circle")
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(condition.isNegative ? "Negative condition" : "Positive condition")
                        .font(BoardTheme.font(size: 14, weight: .semibold)).foregroundStyle(BoardTheme.text)
                    Text("Shown beside the figure\u{2019}s token and in its panel")
                        .font(BoardTheme.font(size: 13)).foregroundStyle(BoardTheme.secondaryText)
                }
            }
        case .elements:
            HStack(spacing: 20) {
                element(.fire, .strong, "Strong")
                element(.ice, .waning, "Waning")
                element(.air, .inert, "Inert")
            }
        case .elites:
            HStack(spacing: 28) {
                token(ring: BoardTheme.victory, label: "Elite \u{00B7} gold ring")
                token(ring: .white, label: "Normal \u{00B7} white ring")
            }
        case .monsterCard:
            HStack(spacing: 16) {
                AsyncImage(url: ImageLoader.monsterAbilityCardURL(deckName: "guard", cardIndex: 0)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(BoardTheme.raised)
                            .overlay(Image(systemName: "rectangle.portrait.on.rectangle.portrait").foregroundStyle(BoardTheme.secondaryText))
                    }
                }
                .frame(width: 150, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("A Bandit Guard ability card")
                Text("Its number is their initiative this round; its actions change their stat card\u{2019}s Move and Attack.")
                    .font(BoardTheme.font(size: 14)).foregroundStyle(BoardTheme.secondaryText)
                    .frame(maxWidth: 260, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .sum(let parts):
            FlowLayout(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    chip(part, lit: index == parts.count - 1)
                }
            }
            .frame(width: width, alignment: .leading)
        case .diagram(let diagram):
            HexDiagramView(diagram: diagram, maxWidth: min(width, 600))
        case .swap(let from, let to):
            HStack(spacing: 18) {
                if let out = AttackModifierType(rawValue: from) {
                    VStack(spacing: 6) {
                        AttackModifierCardView(modifier: AttackModifier(type: out), size: 78)
                            .opacity(0.4)
                            .overlay(Image(systemName: "xmark").font(BoardTheme.font(size: 34, weight: .bold))
                                .foregroundStyle(BoardTheme.defeat))
                        Text("Taken out").font(BoardTheme.font(size: 13)).foregroundStyle(BoardTheme.secondaryText)
                    }
                }
                Image(systemName: "arrow.right").font(BoardTheme.font(size: 20, weight: .semibold))
                    .foregroundStyle(BoardTheme.brass)
                    .accessibilityHidden(true)
                if let into = AttackModifierType(rawValue: to) {
                    VStack(spacing: 6) {
                        AttackModifierCardView(modifier: AttackModifier(type: into), size: 78)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(BoardTheme.brass, lineWidth: 2.5))
                        Text("Put in").font(BoardTheme.font(size: 13)).foregroundStyle(BoardTheme.brass)
                    }
                }
            }
        }
    }

    private func chip(_ text: String, lit: Bool) -> some View {
        Text(text)
            .font(BoardTheme.font(size: 14, weight: lit ? .bold : .medium))
            .foregroundStyle(lit ? BoardTheme.sheet : BoardTheme.text)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(lit ? BoardTheme.brass : BoardTheme.raised, in: Capsule())
            .overlay(Capsule().stroke(lit ? .clear : BoardTheme.border.opacity(0.6), lineWidth: 1))
    }

    @ViewBuilder
    private func abilityCard(_ id: Int) -> some View {
        if let image = ImageLoader.abilityCardImage(edition: "gh", cardId: id) {
            #if os(macOS)
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            #else
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            #endif
        } else {
            RoundedRectangle(cornerRadius: 8).fill(BoardTheme.raised).aspectRatio(0.72, contentMode: .fit)
        }
    }

    private enum Half { case top, bottom }

    private func half(_ id: Int, lit: Half, caption: String) -> some View {
        VStack(spacing: 8) {
            abilityCard(id)
                .frame(height: 200)
                .overlay {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Rectangle().fill(.black.opacity(lit == .bottom ? 0.62 : 0))
                            Rectangle().fill(.black.opacity(lit == .top ? 0.62 : 0))
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(caption).font(BoardTheme.font(size: 13)).foregroundStyle(BoardTheme.brass)
        }
    }

    private func draw(_ title: String, keep: Int, note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(BoardTheme.font(size: 14, weight: .semibold)).foregroundStyle(BoardTheme.text)
            HStack(spacing: 10) {
                ForEach(Array([AttackModifierType.plus1, .minus1].enumerated()), id: \.offset) { index, type in
                    AttackModifierCardView(modifier: AttackModifier(type: type), size: 78)
                        .opacity(index == keep ? 1 : 0.35)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(index == keep ? BoardTheme.brass : .clear, lineWidth: 2.5))
                }
            }
            Text(note).font(BoardTheme.font(size: 13)).foregroundStyle(BoardTheme.brass)
        }
    }

    private func element(_ type: ElementType, _ state: ElementState, _ label: String) -> some View {
        VStack(spacing: 6) {
            CompactElement(element: ElementModel(type: type, state: state)).scaleEffect(1.5).frame(width: 48, height: 48)
            Text(label).font(BoardTheme.font(size: 13)).foregroundStyle(BoardTheme.secondaryText)
        }
    }

    private func token(ring: Color, label: String) -> some View {
        VStack(spacing: 8) {
            BundledImage(ImageLoader.monsterThumbnail(edition: "gh", name: "bandit-guard"), size: 64, systemName: "person.circle")
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().stroke(ring, lineWidth: 3.5))
            Text(label).font(BoardTheme.font(size: 13)).foregroundStyle(BoardTheme.secondaryText)
        }
    }
}

// MARK: - Hex diagrams

/// A small hex map drawn for a rule: floor, walls and terrain, figures as tokens, a move as a
/// dashed arrow, lines of sight, numbers in hexes.
struct HexDiagramView: View {
    let diagram: LearnDiagram
    var maxWidth: CGFloat = 600

    private var size: CGFloat { min((maxWidth - 4) / (sqrt(3) * (CGFloat(diagram.cols) + 0.5)), 40) }
    private var frameSize: CGSize {
        CGSize(width: sqrt(3) * size * (CGFloat(diagram.cols) + 0.5) + 4,
               height: size * (1.5 * CGFloat(diagram.rows) + 0.5) + 4)
    }

    func center(_ hex: LearnDiagram.Hex) -> CGPoint {
        let w = sqrt(3) * size
        return CGPoint(x: 2 + w * (CGFloat(hex.col) + 0.5 + (hex.row & 1 == 1 ? 0.5 : 0)),
                       y: 2 + size + 1.5 * size * CGFloat(hex.row))
    }

    private func hexPath(_ hex: LearnDiagram.Hex, inset: CGFloat = 1) -> Path {
        let c = center(hex), r = size - inset
        var path = Path()
        for i in 0..<6 {
            let angle = CGFloat.pi / 180 * (60 * CGFloat(i) - 30)
            let p = CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    var body: some View {
        Canvas { context, _ in
            let brass = BoardTheme.brass
            // Floor, walls, lit hexes.
            for hex in diagram.hexes {
                let terrain = diagram.terrain[hex]
                let fill: Color = terrain == .wall ? Color.black.opacity(0.85)
                    : diagram.lit.contains(hex) ? brass.opacity(0.22) : Color(red: 0.22, green: 0.18, blue: 0.14)
                context.fill(hexPath(hex), with: .color(fill))
                context.stroke(hexPath(hex), with: .color(terrain == .wall ? .black : Color.white.opacity(0.12)), lineWidth: 1)
            }
            // Terrain symbols.
            for (hex, terrain) in diagram.terrain where terrain != .wall {
                let symbol: (String, Color)
                switch terrain {
                case .obstacle: symbol = ("mountain.2.fill", Color(white: 0.6))
                case .trap: symbol = ("burst.fill", Color(red: 0.86, green: 0.33, blue: 0.27))
                case .hazard: symbol = ("flame.fill", .orange)
                case .difficult: symbol = ("water.waves", Color(red: 0.45, green: 0.65, blue: 0.85))
                case .door: symbol = ("door.left.hand.open", brass)
                case .coin: symbol = ("circle.fill", BoardTheme.victory)
                case .treasure: symbol = ("shippingbox.fill", brass)
                case .wall: continue
                }
                if terrain == .difficult {
                    context.fill(hexPath(hex), with: .color(Color(red: 0.45, green: 0.65, blue: 0.85).opacity(0.18)))
                }
                // Under a number or a figure, the symbol moves to the hex's foot.
                let crowded = diagram.labels[hex] != nil || diagram.figures[hex] != nil
                let scale: CGFloat = terrain == .coin ? 0.5 : (crowded ? 0.42 : 0.8)
                var image = context.resolve(Image(systemName: symbol.0))
                image.shading = .color(symbol.1)
                let side = size * scale
                let c = CGPoint(x: center(hex).x, y: center(hex).y + (crowded ? size * 0.55 : 0))
                context.draw(image, in: CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side))
            }
            // The move.
            if diagram.path.count > 1 {
                var path = Path()
                path.addLines(diagram.path.map(center))
                context.stroke(path, with: .color(brass), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 5]))
                // Onto a figure, the head stops at its edge.
                let last = diagram.path.last!
                arrowhead(context, from: center(diagram.path[diagram.path.count - 2]), to: center(last), color: brass,
                          back: diagram.figures[last] != nil ? size * 0.66 : size * 0.15)
            }
            // Lines of sight and arrows.
            for line in diagram.lines {
                let a = center(line.from), b = center(line.to)
                var path = Path()
                path.move(to: a); path.addLine(to: b)
                switch line.style {
                case .sight:
                    context.stroke(path, with: .color(brass), lineWidth: 2)
                case .blocked:
                    let red = Color(red: 0.86, green: 0.33, blue: 0.27)
                    context.stroke(path, with: .color(red), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    var cross = context.resolve(Image(systemName: "xmark.circle.fill"))
                    cross.shading = .color(red)
                    context.draw(cross, in: CGRect(x: mid.x - 9, y: mid.y - 9, width: 18, height: 18))
                case .arrow:
                    context.stroke(path, with: .color(brass), style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                    arrowhead(context, from: a, to: b, color: brass, back: size * 0.7)
                }
            }
            // Figures.
            for (hex, figure) in diagram.figures {
                let c = center(hex), r = size * 0.62
                let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                let label: String
                switch figure {
                case .hero(let l):
                    label = l
                    context.fill(circle, with: .color(Color(red: 0.25, green: 0.45, blue: 0.7)))
                    context.stroke(circle, with: .color(.white.opacity(0.9)), lineWidth: 2)
                case .summon(let l):
                    label = l
                    context.fill(circle, with: .color(Color(red: 0.3, green: 0.55, blue: 0.35)))
                    context.stroke(circle, with: .color(.white.opacity(0.9)), lineWidth: 2)
                case .enemy(let l):
                    label = l
                    context.fill(circle, with: .color(Color(red: 0.55, green: 0.18, blue: 0.15)))
                    context.stroke(circle, with: .color(.white), lineWidth: 2)
                case .elite(let l):
                    label = l
                    context.fill(circle, with: .color(Color(red: 0.55, green: 0.18, blue: 0.15)))
                    context.stroke(circle, with: .color(BoardTheme.victory), lineWidth: 3)
                case .ghost(let l):
                    label = l
                    context.stroke(circle, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                context.draw(Text(label).font(BoardTheme.font(size: max(11, size * 0.55), weight: .bold))
                    .foregroundColor(figure == .ghost(label) ? .white.opacity(0.5) : .white), at: c)
            }
            // The focus ring.
            if let ring = diagram.ring {
                let c = center(ring), r = size * 0.85
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(brass), lineWidth: 3)
            }
            // Labels: a small pill in the hex (over any path), or under a figure.
            for (hex, text) in diagram.labels {
                var c = center(hex)
                if diagram.figures[hex] != nil { c.y += size * 0.95 }
                let label = context.resolve(Text(text).font(BoardTheme.font(size: max(11, size * 0.42), weight: .bold))
                    .foregroundColor(brass))
                let measured = label.measure(in: CGSize(width: 200, height: 50))
                let pill = CGRect(x: c.x - measured.width / 2 - 6, y: c.y - measured.height / 2 - 2,
                                  width: measured.width + 12, height: measured.height + 4)
                context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(BoardTheme.sheet))
                context.stroke(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(brass.opacity(0.6)), lineWidth: 1)
                context.draw(label, at: c)
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .accessibilityHidden(true)   // the topic's text says what it shows
    }

    private func arrowhead(_ context: GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color, back: CGFloat = 0) {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let tip = CGPoint(x: b.x - cos(angle) * back, y: b.y - sin(angle) * back)
        let length = size * 0.45
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - length * cos(angle - 0.45), y: tip.y - length * sin(angle - 0.45)))
        head.addLine(to: CGPoint(x: tip.x - length * cos(angle + 0.45), y: tip.y - length * sin(angle + 0.45)))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}
