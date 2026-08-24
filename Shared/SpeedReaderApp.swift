import SwiftUI

@main
struct SpeedReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 640, height: 580)
        #endif
    }
}
