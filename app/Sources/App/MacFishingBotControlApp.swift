import SwiftUI

@main
struct MacFishingBotControlApp: App {
    var body: some Scene {
        WindowGroup("異環釣魚助手") {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
