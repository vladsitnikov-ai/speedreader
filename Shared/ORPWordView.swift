import SwiftUI

/// Shows a single word with its Optimal Recognition Point (ORP) letter
/// centered and highlighted, so the reader's eyes never need to move —
/// classic RSVP / Spritz-style layout.
struct ORPWordView: View {
    let word: String
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

    var body: some View {
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
            .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
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
    ORPWordView(word: "Читалка")
        .padding()
}
