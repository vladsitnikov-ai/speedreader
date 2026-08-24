import Foundation

#if os(macOS)
import AppKit

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
#else
import UIKit

func copyToClipboard(_ text: String) {
    UIPasteboard.general.string = text
}
#endif
