import SwiftUI

struct CharacterView: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @Environment(\.editionTheme) private var theme
    @Environment(\.isCompact) private var isCompact
    @State private var showInitiativeInput = false
    @State private var showConditions = false
    @State private var showDetail = false
    @State private var showCharacterSheet = false
    @State private var showPerks = false
    @State private var showBattleGoal = false
    @State private var showAbilityCards = false
    @State private var showRetirement = false
    @State private var showHandManagement = false
    @State private var showFullView = false
    @State private var showEnhancements = false
    @State private var xpDragStart = 0
    @State private var lootDragStart = 0
    @State private var isDraggingXP = false
    @State private var isDraggingLoot = false
    @State private var activeGlow: Double = 0.4

    private var isDrawPhase: Bool {
        gameManager.game.state == .draw
    }

    private var needsInitiative: Bool {
        isDrawPhase
            && !character.exhausted
            && !character.absent
            && !character.longRest
            && character.initiative <= 0
    }

    private var initiativeText: String {
        String(format: "%02d", character.initiative)
    }

    private var characterColor: Color {
        Color(hex: character.color) ?? .blue
    }

    private var displayName: String {
        character.title.isEmpty
            ? character.name.replacingOccurrences(of: "-", with: " ").capitalized
            : character.title
    }

    var body: some View {
        VStack(spacing: 0) {
            compactBar
            if showDetail {
                CharacterDetailSection(
                    character: character,
                    showCharacterSheet: $showCharacterSheet,
                    showPerks: $showPerks,
                    showBattleGoal: $showBattleGoal,
                    showConditions: $showConditions,
                    showAbilityCards: $showAbilityCards,
                    showHandManagement: $showHandManagement
                )
            }
        }
        .background(
            ZStack {
                GlavenTheme.cardBackground
                // Character color fill — softer in light mode for text contrast
                characterColor.opacity(GlavenTheme.isLight ? 0.18 : 0.35)
                // Subtle depth gradient
                LinearGradient(
                    colors: GlavenTheme.isLight
                        ? [Color.white.opacity(0.15), Color.clear, Color.black.opacity(0.06)]
                        : [GlavenTheme.primaryText.opacity(0.05), Color.clear, Color.black.opacity(0.15)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                // Character mat texture (subtle so color shows through)
                if let mat = ImageLoader.characterMat() {
                    platformImage(mat)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(GlavenTheme.isLight ? 0.08 : 0.15)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(character.active ? characterColor : characterColor.opacity(0.4), lineWidth: character.active ? 2 : 1)
        )
        .shadow(color: character.active ? characterColor.opacity(activeGlow) : Color.black.opacity(0.3), radius: character.active ? 8 : 4)
        .opacity(character.exhausted ? 0.6 : 1.0)
        .saturation(character.exhausted ? 0.15 : 1.0)
        .animateIf(gameManager.settingsManager.animations, .easeInOut(duration: 0.3), value: character.exhausted)
        .onChange(of: character.active) { _, isActive in
            if isActive {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    activeGlow = 0.8
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    activeGlow = 0.4
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(displayName), health \(character.health) of \(character.maxHealth), level \(character.level)\(character.exhausted ? ", exhausted" : "")")
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDetail.toggle()
            }
        }
        .onTapGesture(count: 2) {
            if gameManager.game.state == .next {
                gameManager.roundManager.toggleFigure(.character(character))
            }
        }
        .contextMenu {
            characterContextMenu
        }
        .sheet(isPresented: $showInitiativeInput) {
            InitiativeInputView(initiative: character.initiative) { newInit in
                gameManager.characterManager.setInitiative(newInit, for: character)
            }
        }
        .popover(isPresented: $showConditions) {
            ConditionsView(entity: character, availableConditions: gameManager.game.conditions)
        }
        .sheet(isPresented: $showCharacterSheet) {
            CharacterSheetView(character: character)
        }
        .sheet(isPresented: $showPerks) {
            PerkSheet(character: character)
        }
        .sheet(isPresented: $showBattleGoal) {
            BattleGoalSheet(character: character)
        }
        .sheet(isPresented: $showAbilityCards) {
            AbilityCardsSheet(character: character)
        }
        .sheet(isPresented: $showRetirement) {
            RetirementSheet(character: character)
        }
        .sheet(isPresented: $showHandManagement) {
            HandManagementSheet(character: character)
        }
        .sheet(isPresented: $showFullView) {
            CharacterFullView(character: character)
        }
        .sheet(isPresented: $showEnhancements) {
            EnhancementSheet(character: character)
        }
    }

    // MARK: - Compact Bar

    @ViewBuilder
    private var compactBar: some View {
        if isCompact {
            VStack(spacing: 4 * scale) {
                HStack(spacing: 6 * scale) {
                    initiativeSection
                    thumbnailSection
                    nameSection
                    Spacer()
                    statusBadges
                }
                HStack(spacing: 8 * scale) {
                    healthSection
                    xpSection
                    lootSection
                    Spacer()
                    conditionsIndicator
                }
            }
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 6 * scale)
        } else {
            HStack(spacing: 10 * scale) {
                initiativeSection
                thumbnailSection
                nameSection
                Spacer()
                healthSection
                xpSection
                lootSection
                conditionsIndicator
                statusBadges
                // Large decorative character icon
                GameIcon(
                    image: characterIconImage,
                    fallbackSystemName: "person.fill",
                    size: 36,
                    color: characterColor.opacity(GlavenTheme.isLight ? 0.8 : 0.5)
                )
            }
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 8 * scale)
        }
    }

    @ViewBuilder
    private var initiativeSection: some View {
        if isDrawPhase && !character.exhausted && !character.absent {
            Button {
                if character.longRest {
                    character.longRest = false
                    gameManager.characterManager.setInitiative(0, for: character)
                } else {
                    showInitiativeInput = true
                }
            } label: {
                Text(character.longRest ? "99" : character.initiative > 0 ? initiativeText : "??")
                    .font(theme.titleFont(size: 22 * scale))
                    .foregroundStyle(needsInitiative ? GlavenTheme.primaryText.opacity(0.5) : GlavenTheme.primaryText)
                    .frame(width: 40 * scale, height: 40 * scale)
                    .background(needsInitiative ? Color.red.opacity(0.3) : characterColor.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(needsInitiative ? Color.red : characterColor.opacity(0.5), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(character.longRest ? "Long rest, initiative 99" : character.initiative > 0 ? "Initiative \(character.initiative)" : "Set initiative")
            .accessibilityHint("Double tap to change initiative")
        } else if character.initiative > 0 {
            Text(initiativeText)
                .font(theme.titleFont(size: 22 * scale))
                .foregroundStyle(GlavenTheme.primaryText)
                .frame(width: 40 * scale, height: 40 * scale)
                .background(characterColor.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Initiative \(character.initiative)")
        }
    }

    @ViewBuilder
    private var thumbnailSection: some View {
        ThumbnailImage(
            image: ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
            size: 40,
            cornerRadius: 8,
            fallbackColor: characterColor
        )
    }

    @ViewBuilder
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                GameIcon(
                    image: characterIconImage,
                    fallbackSystemName: "person.fill",
                    size: 16,
                    color: characterColor
                )
                Text(displayName)
                    .font(.system(size: 15 * scale, weight: .semibold))
                    .foregroundStyle(GlavenTheme.primaryText)
                    .lineLimit(1)
                if let identities = character.characterData?.identities, identities.count > 1 {
                    Button {
                        gameManager.characterManager.cycleIdentity(character)
                    } label: {
                        Text(identities[character.identity].capitalized)
                            .font(.system(size: 9 * scale, weight: .bold))
                            .foregroundStyle(characterColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(characterColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var characterIconImage: PlatformImage? {
        // Try custom icon name from data, then default {edition}-{name}
        if let iconName = character.characterData?.icon {
            // icon field may be just a name or include edition prefix
            if let img = ImageLoader.characterIcon(edition: character.edition, name: iconName) {
                return img
            }
            // Try as a full filename (no edition prefix)
            if let img = loadIconByName(iconName) {
                return img
            }
        }
        return ImageLoader.characterIcon(edition: character.edition, name: character.name)
    }

    private func loadIconByName(_ name: String) -> PlatformImage? {
        // Try loading from the icons directory with just the name
        let bundle = appResourceBundle
        if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Images/character/icons") {
            #if os(macOS)
            return NSImage(contentsOf: url)
            #else
            return (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
            #endif
        }
        return nil
    }

    @ViewBuilder
    private var healthSection: some View {
        HStack(spacing: 3) {
            GameIcon(image: ImageLoader.statusIcon("health"), fallbackSystemName: "heart.fill", size: 14, color: .red)
            Text("\(character.health)/\(character.maxHealth)")
                .font(.system(size: 15 * scale, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(GlavenTheme.primaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Health \(character.health) of \(character.maxHealth)")
    }

    @ViewBuilder
    private var xpSection: some View {
        HStack(spacing: 2) {
            GameIcon(image: ImageLoader.statusIcon("experience"), fallbackSystemName: "star.fill", size: 14, color: .blue)
            Text("\(character.experience)")
                .font(.system(size: 12 * scale))
                .monospacedDigit()
                .foregroundStyle(isDraggingXP ? Color.blue : Color.secondary)
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if !isDraggingXP {
                        isDraggingXP = true
                        xpDragStart = character.experience
                    }
                    let delta = Int(value.translation.width / 20)
                    let newXP = max(0, xpDragStart + delta)
                    gameManager.characterManager.addXP(newXP - character.experience, to: character)
                }
                .onEnded { _ in
                    isDraggingXP = false
                }
        )
    }

    @ViewBuilder
    private var lootSection: some View {
        HStack(spacing: 2) {
            GameIcon(image: ImageLoader.statusIcon("loot"), fallbackSystemName: "dollarsign.circle.fill", size: 14, color: .yellow)
            Text("\(character.loot)")
                .font(.system(size: 12 * scale))
                .monospacedDigit()
                .foregroundStyle(isDraggingLoot ? Color.yellow : Color.secondary)
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if !isDraggingLoot {
                        isDraggingLoot = true
                        lootDragStart = character.loot
                    }
                    let delta = Int(value.translation.width / 20)
                    let newLoot = max(0, lootDragStart + delta)
                    gameManager.characterManager.addLoot(newLoot - character.loot, to: character)
                }
                .onEnded { _ in
                    isDraggingLoot = false
                }
        )
    }

    @ViewBuilder
    private var conditionsIndicator: some View {
        if !character.entityConditions.isEmpty {
            HStack(spacing: 1) {
                ForEach(character.entityConditions.prefix(3)) { condition in
                    BundledImage(
                        ImageLoader.conditionIcon(condition.name.rawValue),
                        size: 14,
                        systemName: "bolt.fill"
                    )
                }
                if character.entityConditions.count > 3 {
                    Text("+\(character.entityConditions.count - 3)")
                        .font(.system(size: 9 * scale, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadges: some View {
        if character.exhausted {
            Text("X")
                .font(.system(size: 11 * scale, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20 * scale, height: 20 * scale)
                .background(Color.red.opacity(0.6))
                .clipShape(Circle())
        }
        if character.longRest {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 11 * scale))
                .foregroundStyle(GlavenTheme.positive)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var characterContextMenu: some View {
        if isDrawPhase && !character.exhausted && !character.absent {
            Button {
                character.longRest.toggle()
                if character.longRest {
                    gameManager.characterManager.setInitiative(99, for: character)
                } else {
                    gameManager.characterManager.setInitiative(0, for: character)
                }
            } label: {
                Label(character.longRest ? "Cancel Rest" : "Long Rest", systemImage: "bed.double.fill")
            }
        }
        Button { showDetail.toggle() } label: {
            Label(showDetail ? "Collapse" : "Expand", systemImage: showDetail ? "chevron.up" : "chevron.down")
        }
        Button { showCharacterSheet = true } label: {
            Label("Character Sheet", systemImage: "person.text.rectangle")
        }
        Button { showFullView = true } label: {
            Label("Full View", systemImage: "rectangle.expand.vertical")
        }
        if let identities = character.characterData?.identities, identities.count > 1 {
            Button {
                gameManager.characterManager.cycleIdentity(character)
            } label: {
                Label("Switch Identity (\(identities[character.identity].capitalized))", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        Button { showAbilityCards = true } label: {
            Label("Ability Cards", systemImage: "rectangle.portrait.on.rectangle.portrait")
        }
        Button { showEnhancements = true } label: {
            Label("Enhancements", systemImage: "sparkles")
        }
        Button { showHandManagement = true } label: {
            Label("Hand Management", systemImage: "hand.raised")
        }
        Button { showPerks = true } label: {
            Label("Perks", systemImage: "list.bullet.rectangle")
        }
        Button { showBattleGoal = true } label: {
            Label("Battle Goal", systemImage: "flag")
        }
        Button { showConditions = true } label: {
            Label("Conditions", systemImage: "cross.circle")
        }
        Divider()
        Button {
            gameManager.characterManager.toggleExhausted(character)
        } label: {
            Label(character.exhausted ? "Revive" : "Exhaust", systemImage: character.exhausted ? "heart.fill" : "heart.slash")
        }
        Button {
            gameManager.characterManager.toggleAbsent(character)
        } label: {
            Label(character.absent ? "Return" : "Set Absent", systemImage: character.absent ? "person.fill" : "person.slash")
        }
        Divider()
        Button { showRetirement = true } label: {
            Label("Retire Character", systemImage: "flag.checkered")
        }
        Button(role: .destructive) {
            gameManager.characterManager.removeCharacter(character)
        } label: {
            Label("Remove Character", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func platformImage(_ img: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: img)
        #else
        Image(uiImage: img)
        #endif
    }
}

// Color extension for hex parsing
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        guard hexSanitized.count == 6, let int = UInt64(hexSanitized, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
