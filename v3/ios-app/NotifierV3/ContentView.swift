import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: FeedViewModel
    @State private var pairCode: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GroupBox("Connection") {
                    TextField("API URL", text: Binding(
                        get: { vm.apiURL },
                        set: { vm.updateApiURL($0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    TextField("Mobile Token", text: Binding(
                        get: { vm.token },
                        set: { vm.updateToken($0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    TextField("Pair Code (e.g. 123-456)", text: $pairCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Button("Pair Device") {
                            Task { await vm.pairDevice(pairCode: pairCode) }
                        }
                        Button("Refresh") {
                            Task { await vm.refresh() }
                        }
                        Spacer()
                        Text(vm.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("Workspace: \(vm.workspaceId.isEmpty ? "(not paired)" : vm.workspaceId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Quick Actions") {
                    HStack {
                        Button("Codex Continue") {
                            Task { await vm.send(target: "codex", action: "continue") }
                        }
                        Button("CC Continue") {
                            Task { await vm.send(target: "cc", action: "continue") }
                        }
                    }
                    HStack {
                        Button("Shot Codex") {
                            Task { await vm.send(target: "codex", action: "shot") }
                        }
                        Button("Shot CC") {
                            Task { await vm.send(target: "cc", action: "shot") }
                        }
                    }
                }

                List(vm.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(event.source.uppercased()) - \(event.event_type)")
                            .font(.headline)
                        Text(event.created_at)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let payload = event.payload, !payload.isEmpty {
                            Text(payload.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Notifier v3")
        }
        .task {
            await vm.bootstrap()
        }
    }
}
