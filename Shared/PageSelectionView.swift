import SwiftUI
import PDFKit

struct PageSelectionView: View {
    let book: Book
    let pdfURL: URL
    let onConfirm: ([Int]) -> Void
    let onCancel: () -> Void

    @State private var document: PDFDocument?
    @State private var selected: Set<Int> = []
    @State private var rangeStart: String = "1"
    @State private var rangeEnd: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            rangeBar
            Divider()

            if let document {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 14)], spacing: 18) {
                        ForEach(0..<document.pageCount, id: \.self) { index in
                            PageThumbnailCell(
                                document: document,
                                index: index,
                                isSelected: selected.contains(index)
                            ) {
                                toggle(index)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                Spacer()
                ProgressView("Открываю PDF…")
                Spacer()
            }

            Divider()
            footer
        }
        .task {
            if document == nil {
                document = PDFDocument(url: pdfURL)
                if let count = document?.pageCount {
                    rangeEnd = "\(count)"
                    if book.selectedPages.isEmpty {
                        selected = Set(0..<count)
                    } else {
                        selected = Set(book.selectedPages)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 560)
        #endif
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Label("Библиотека", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 2) {
                Text("Выберите страницы")
                    .font(.headline)
                Text("Отметьте текст, который хотите читать — без оглавлений и техстраниц")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Color.clear.frame(width: 90)
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    private var rangeBar: some View {
        HStack(spacing: 10) {
            Text("С")
            TextField("1", text: $rangeStart)
                .frame(width: 56)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .textFieldStyle(.roundedBorder)
            Text("по")
            TextField("", text: $rangeEnd)
                .frame(width: 56)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .textFieldStyle(.roundedBorder)
            Button("Применить") { applyRange() }
                .buttonStyle(.bordered)

            Spacer()

            Button("Все") { if let c = document?.pageCount { selected = Set(0..<c) } }
                .buttonStyle(.borderless)
            Button("Никакие") { selected.removeAll() }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Text("\(selected.count) из \(document?.pageCount ?? book.pageCount) страниц выбрано")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Начать чтение") {
                onConfirm(selected.sorted())
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
        .padding()
    }

    private func toggle(_ index: Int) {
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
    }

    private func applyRange() {
        guard let count = document?.pageCount else { return }
        let start = max(1, Int(rangeStart) ?? 1)
        let end = min(count, Int(rangeEnd) ?? count)
        guard start <= end else { return }
        selected = Set((start - 1)..<end)
    }
}

private struct PageThumbnailCell: View {
    let document: PDFDocument
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void

    @State private var image: PlatformImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(platformImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.12))
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: isSelected ? 3 : 1)
                )

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(4)
                }
            }
            Text("\(index + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .task(id: index) {
            guard image == nil, let page = document.page(at: index) else { return }
            image = page.thumbnail(of: CGSize(width: 220, height: 300), for: .mediaBox)
        }
    }
}
