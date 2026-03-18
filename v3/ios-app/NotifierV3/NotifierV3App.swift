import SwiftUI

@main
struct NotifierV3App: App {
    @StateObject private var vm = FeedViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
        }
    }
}
