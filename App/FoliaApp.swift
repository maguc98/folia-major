import SwiftUI

@main
struct FoliaApp: App {
    var body: some Scene {
        WindowGroup {
            FoliaHostView()
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
        }
    }
}
