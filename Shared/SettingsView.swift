import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void

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
                        Text("SpeedReader")
                            .font(.headline)
                        Text("Сделано Владом Ситниковым.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://vladsitnikov.com")!) {
                            Label("vladsitnikov.com", systemImage: "link")
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
