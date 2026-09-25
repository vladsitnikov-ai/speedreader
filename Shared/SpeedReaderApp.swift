import SwiftUI

@main
struct SpeedReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1440, height: 900)
        #endif
    }
}
