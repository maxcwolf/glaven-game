import SwiftUI

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 16)

                    // App logo
                    if let logoImage = ImageLoader.logo() {
                        #if os(macOS)
                        Image(nsImage: logoImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        #else
                        Image(uiImage: logoImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        #endif
                    }

                    // App name & version
                    VStack(spacing: 4) {
                        Text("Glaven")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(GlavenTheme.primaryText)

                        Text("Companion App for Gloomhaven")
                            .font(.subheadline)
                            .foregroundStyle(GlavenTheme.secondaryText)

                        Text("Version 1.0")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText.opacity(0.7))
                            .padding(.top, 2)
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 10) {
                        infoRow(title: "Supported Editions",
                                detail: "Gloomhaven, Frosthaven, Jaws of the Lion")

                        infoRow(title: "Based On",
                                detail: "Gloomhaven Secretariat by Lurkars")

                        infoRow(title: "Platform",
                                detail: "macOS 14+ / iPadOS 17+")
                    }
                    .padding()
                    .background(GlavenTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Credits
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Credits")
                            .font(.headline)
                            .foregroundStyle(GlavenTheme.primaryText)

                        Text("Game data and army design by Cephalofair Games. Scenario data from Gloomhaven Secretariat project.")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)

                        Text("This app is a fan project and is not affiliated with or endorsed by Cephalofair Games.")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText.opacity(0.7))
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(GlavenTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer(minLength: 16)
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 360, minHeight: 400)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func infoRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(GlavenTheme.secondaryText)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.primaryText)
        }
    }
}
