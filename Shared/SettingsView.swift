import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(LocalizedStringKey(theme.label)).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Highlight the fixation letter", isOn: $settings.highlightPivot)
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Colors the letter in each word that's easiest to fixate on (ORP) and shows marks above and below it. Off by default — the word is just shown centered.")
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SpeedReader \(Self.versionString)")
                            .font(.headline)
                        Text("Created by Vlad Sitnikov.")
                            .font(.body)
                        Text("The idea for this app was inspired by Anton Bulanov and his new book “The Nature of Cunning”.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://vladsitnikov.com")!) {
                            Label("vladsitnikov.com", systemImage: "link")
                        }
                        Link(destination: URL(string: "https://github.com/vladsitnikov-ai/speedreader")!) {
                            Label("Source code & updates", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.title2.bold())
            Spacer()
            Button("Done", action: onClose)
        }
        .padding()
    }
}
