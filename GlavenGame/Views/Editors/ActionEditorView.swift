import SwiftUI

/// Inline editor for a single ActionModel. Used within Deck and Monster editors.
struct ActionEditorView: View {
    @Binding var action: ActionModel
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Type", selection: $action.type) {
                    ForEach(ActionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .frame(maxWidth: 160)

                if onDelete != nil {
                    Spacer()
                    Button(role: .destructive) { onDelete?() } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("Value", text: Binding(
                    get: { action.value?.stringValue ?? (action.value.map { "\($0.intValue ?? 0)" } ?? "") },
                    set: {
                        if let intVal = Int($0) {
                            action.value = .int(intVal)
                        } else if !$0.isEmpty {
                            action.value = .string($0)
                        } else {
                            action.value = nil
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 100)

                Picker("", selection: Binding(
                    get: { action.valueType ?? .fixed },
                    set: { action.valueType = $0 == .fixed ? nil : $0 }
                )) {
                    Text("—").tag(ActionValueType.fixed)
                    ForEach(ActionValueType.allCases, id: \.self) { vt in
                        Text(vt.rawValue).tag(vt)
                    }
                }
                .frame(maxWidth: 100)

                Toggle("Small", isOn: Binding(
                    get: { action.small ?? false },
                    set: { action.small = $0 ? true : nil }
                ))
                .toggleStyle(.switch)
                .font(.caption)
            }

            // Sub-actions
            if let subs = action.subActions, !subs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sub-actions")
                        .font(.caption2)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    ForEach(Array(subs.enumerated()), id: \.offset) { index, _ in
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(GlavenTheme.secondaryText)
                            ActionEditorView(
                                action: Binding(
                                    get: { action.subActions?[index] ?? ActionModel(type: .attack) },
                                    set: { action.subActions?[index] = $0 }
                                ),
                                onDelete: {
                                    action.subActions?.remove(at: index)
                                    if action.subActions?.isEmpty == true { action.subActions = nil }
                                }
                            )
                        }
                    }
                }
                .padding(.leading, 12)
            }

            Button {
                if action.subActions == nil { action.subActions = [] }
                action.subActions?.append(ActionModel(type: .attack))
            } label: {
                Label("Add Sub-action", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(GlavenTheme.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Full-screen Action Editor sheet for standalone use and editing from other editors.
struct ActionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var action: ActionModel = ActionModel(type: .attack)
    @State private var jsonOutput: String = ""

    var body: some View {
        NavigationStack {
            HSplitOrVStack {
                // Input side
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Action Editor")
                            .font(.headline)

                        ActionEditorView(action: $action)
                    }
                    .padding()
                }

                Divider()

                // JSON output side
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("JSON Output")
                            .font(.headline)
                        Spacer()
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(jsonOutput, forType: .string)
                            #else
                            UIPasteboard.general.string = jsonOutput
                            #endif
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                    }

                    ScrollView {
                        Text(jsonOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Action Editor")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: action) { _, _ in updateJSON() }
            .onAppear { updateJSON() }
        }
    }

    private func updateJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(action),
           let str = String(data: data, encoding: .utf8) {
            jsonOutput = str
        }
    }
}

/// Layout helper that uses HSplitView on macOS, VStack on iOS.
struct HSplitOrVStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(macOS)
        HSplitView { content }
        #else
        VStack(spacing: 0) { content }
        #endif
    }
}
