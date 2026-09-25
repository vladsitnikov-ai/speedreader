import SwiftUI

/// Edits the bibliographic details of a book so quotes can cite a specific edition and page.
struct BookInfoView: View {
    let onSave: (_ title: String, _ author: String, _ publisher: String, _ year: String) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var author: String
    @State private var publisher: String
    @State private var year: String

    init(
        book: Book,
        onSave: @escaping (_ title: String, _ author: String, _ publisher: String, _ year: String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
        _publisher = State(initialValue: book.publisher)
        _year = State(initialValue: book.year)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Отмена", action: onCancel)
                Spacer()
                Text("Сведения об издании")
                    .font(.headline)
                Spacer()
                Button("Сохранить") {
                    onSave(title, author, publisher, year)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            Divider()

            Form {
                Section {
                    TextField("Название", text: $title)
                    TextField("Автор", text: $author)
                    TextField("Издательство", text: $publisher)
                    TextField("Год издания", text: $year)
                } footer: {
                    Text("Эти данные попадут в ссылку при копировании цитат: «цитата» — Автор. Название. Издательство, год, с. N.")
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }
}
