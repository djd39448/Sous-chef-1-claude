import SwiftUI

// Sous Chef — native iOS app.
// A SwiftUI port of the "Sous Chef iOS" design (warm culinary aesthetic:
// cream / terracotta / sage, serif display + SF Pro body).
@main
struct SousChefApp: App {
    @State private var auth = AuthModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
        }
    }
}
