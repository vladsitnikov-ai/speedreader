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
                Section("Оформление") {
                    Picker("Тема", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Подсвечивать букву фиксации", isOn: $settings.highlightPivot)
                } header: {
                    Text("Чтение")
                } footer: {
                    Text("Выделяет цветом букву в слове, на которой удобнее всего фиксировать взгляд (ORP), и показывает метки над и под ней. По умолчанию выключено — слово просто показывается по центру.")
                }

                Section("О приложении") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SpeedReader \(Self.versionString)")
                            .font(.headline)
                        Text("Автор — Влад Ситников.")
                            .font(.body)
                        Text("Идея приложения вдохновлена Антоном Булановым и его новой книгой «Природа хитрости».")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://vladsitnikov.com")!) {
                            Label("vladsitnikov.com", systemImage: "link")
                        }
                        Link(destination: URL(string: "https://github.com/vladsitnikov-ai/speedreader")!) {
                            Label("Исходный код и обновления", systemImage: "chevron.left.forwardslash.chevron.right")
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
            Text("Настройки")
                .font(.title2.bold())
            Spacer()
            Button("Готово", action: onClose)
        }
        .padding()
    }
}
