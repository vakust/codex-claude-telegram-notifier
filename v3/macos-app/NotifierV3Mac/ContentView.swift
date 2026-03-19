import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: FeedViewModel
    @State private var pairCode: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notifier V3 - macOS")
                .font(.title2)
                .bold()

            HStack {
                Text("API URL")
                    .frame(width: 90, alignment: .leading)
                TextField("http://127.0.0.1:8787", text: Binding(
                    get: { viewModel.apiURL },
                    set: { viewModel.updateApiURL($0) }
                ))
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Token")
                    .frame(width: 90, alignment: .leading)
                TextField("dev-mobile-token", text: Binding(
                    get: { viewModel.token },
                    set: { viewModel.updateToken($0) }
                ))
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Pair Code")
                    .frame(width: 90, alignment: .leading)
                TextField("123-456", text: $pairCode)
                    .textFieldStyle(.roundedBorder)
                Button("Pair Device") {
                    Task { await viewModel.pairDevice(pairCode: pairCode) }
                }
            }

            HStack(spacing: 8) {
                Button("Refresh") {
                    Task { await viewModel.refreshFeed() }
                }
                Button("Codex Continue") {
                    Task { await viewModel.sendCommand(target: "codex", action: "continue") }
                }
                Button("CC Continue") {
                    Task { await viewModel.sendCommand(target: "cc", action: "continue") }
                }
                Spacer()
            }

            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Workspace: \(viewModel.workspaceId.isEmpty ? "(not paired)" : viewModel.workspaceId)")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(viewModel.feedItems) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(item.source):\(item.type)")
                        .font(.headline)
                    Text(item.ts)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .task {
            await viewModel.bootstrap()
        }
    }
}
