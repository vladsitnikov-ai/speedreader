import SwiftUI

struct ReaderView: View {
    @ObservedObject var engine: RSVPEngine
    let documentTitle: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            header

            Spacer(minLength: 0)

            displayArea
                .frame(maxWidth: .infinity, minHeight: 140)

            Spacer(minLength: 0)

            progressBar
            transportControls
            speedControls
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private var displayArea: some View {
        if let chunk = engine.currentChunk {
            ORPWordView(word: chunk.text)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                Text("Готово")
                    .font(.title2)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Label("Библиотека", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Text(documentTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Color.clear.frame(width: 90)
        }
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { engine.progress },
                    set: { engine.seek(to: $0) }
                ),
                in: 0...1
            )
            HStack {
                Text("\(min(engine.currentIndex + 1, engine.chunks.count)) / \(max(engine.chunks.count, 1))")
                Spacer()
                Text("\(Int(engine.wordsPerMinute)) слов/мин")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var transportControls: some View {
        HStack(spacing: 32) {
            Button(action: engine.restart) {
                Image(systemName: "backward.end.fill")
            }
            Button(action: engine.stepBackward) {
                Image(systemName: "backward.frame.fill")
            }
            Button(action: engine.togglePlay) {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
            }
            Button(action: engine.stepForward) {
                Image(systemName: "forward.frame.fill")
            }
        }
        .font(.system(size: 22))
        .buttonStyle(.plain)
    }

    private var speedControls: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "tortoise.fill")
                    .foregroundStyle(.secondary)
                Slider(value: $engine.wordsPerMinute, in: 100...900, step: 10)
                Image(systemName: "hare.fill")
                    .foregroundStyle(.secondary)
            }
            Stepper(
                "Слов за раз: \(engine.wordsPerChunk)",
                value: $engine.wordsPerChunk,
                in: 1...4
            )
        }
    }
}
