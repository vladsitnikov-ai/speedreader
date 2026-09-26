import SwiftUI

/// Shows a single word. With `highlightPivot` on, the Optimal Recognition Point (ORP)
/// letter is centered and highlighted with fixation ticks — classic RSVP / Spritz-style
/// layout. Off (the default), the word is simply centered.
struct ORPWordView: View {
    let word: String
    var highlightPivot: Bool = false
    var fontSize: CGFloat = 56

    private var pivotIndex: Int {
        switch word.count {
        case 0, 1: return 0
        case 2...5: return 1
        case 6...9: return 2
        case 10...13: return 3
        default: return 4
        }
    }

    private var prefix: String {
        guard !word.isEmpty, pivotIndex > 0 else { return "" }
        return String(word.prefix(pivotIndex))
    }

    private var pivot: String {
        guard !word.isEmpty else { return "" }
        let idx = word.index(word.startIndex, offsetBy: min(pivotIndex, word.count - 1))
        return String(word[idx])
    }

    private var suffix: String {
        guard !word.isEmpty, pivotIndex + 1 < word.count else { return "" }
        let idx = word.index(word.startIndex, offsetBy: pivotIndex + 1)
        return String(word[idx...])
    }

    private var wordFont: Font {
        .system(size: fontSize, weight: .semibold, design: .monospaced)
    }

    var body: some View {
        Group {
            if highlightPivot {
                pivotLayout
            } else {
                Text(word)
                    .font(wordFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var pivotLayout: some View {
        VStack(spacing: 6) {
            tick
            HStack(spacing: 0) {
                Text(prefix)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(pivot)
                    .foregroundColor(.accentColor)
                    .fixedSize()
                Text(suffix)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(wordFont)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            tick
        }
    }

    private var tick: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.7))
            .frame(width: 2, height: 10)
    }
}

#Preview {
    VStack(spacing: 40) {
        ORPWordView(word: "SpeedReader")
        ORPWordView(word: "SpeedReader", highlightPivot: true)
    }
    .padding()
}
