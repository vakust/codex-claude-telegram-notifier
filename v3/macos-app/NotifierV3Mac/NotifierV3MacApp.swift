import SwiftUI

@main
struct NotifierV3MacApp: App {
    @StateObject private var viewModel = FeedViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 620)
        }
    }
}
