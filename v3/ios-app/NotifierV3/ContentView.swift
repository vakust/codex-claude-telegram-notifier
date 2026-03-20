import SwiftUI
import UIKit

private enum ScreenTab: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case cloudCode = "Cloud Code"
    case all = "All"

    var id: String { rawValue }
    var subtitle: String {
        switch self {
        case .codex:
            return "Commands + screenshots"
        case .cloudCode:
            return "Screenshot monitoring"
        case .all:
            return "Unified feed"
        }
    }
}

private enum EventImageRef {
    case remote(URL)
    case inline(Data)
}

private struct ZoomImagePayload: Identifiable {
    let id = UUID()
    let source: EventImageRef
}

struct ContentView: View {
    @EnvironmentObject var vm: FeedViewModel
    @State private var pairCode: String = ""
    @State private var showSettings: Bool = false
    @State private var selectedTab: ScreenTab = .codex
    @State private var zoomPayload: ZoomImagePayload?

    private var filteredEvents: [FeedEvent] {
        switch selectedTab {
        case .codex:
            return vm.events.filter { $0.source.lowercased() == "codex" }
        case .cloudCode:
            return vm.events.filter { $0.source.lowercased() == "cc" }
        case .all:
            return vm.events
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.95, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    headerCard
                    toolbarRow

                    if showSettings {
                        settingsCard
                    }

                    tabCard
                    statusCard
                    feedList
                }
                .padding(12)
            }
            .navigationTitle("Notifier V3")
        }
        .sheet(item: $zoomPayload) { payload in
            FullscreenImageView(payload: payload)
        }
        .task {
            await vm.bootstrap()
        }
    }

    private var headerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Remote cockpit for Codex + Cloud Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Label(vm.statusText, systemImage: vm.isBusy ? "bolt.fill" : "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(vm.isBusy ? .orange : .green)
                    Spacer()
                    Text("events: \(vm.events.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Text("Connection")
                .font(.headline)
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            Button(showSettings ? "Hide Settings" : "Show Settings") {
                showSettings.toggle()
            }
            .buttonStyle(.bordered)

            Button("Refresh Feed") {
                Task { await vm.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isBusy)
        }
    }

    private var settingsCard: some View {
        GroupBox("Device Pairing") {
            VStack(spacing: 8) {
                TextField("API URL", text: Binding(
                    get: { vm.apiURL },
                    set: { vm.updateApiURL($0) }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

                TextField("Mobile Token", text: Binding(
                    get: { vm.token },
                    set: { vm.updateToken($0) }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

                TextField("Pair Code (e.g. 123-456)", text: $pairCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button("Pair Device") {
                    Task { await vm.pairDevice(pairCode: pairCode) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(vm.isBusy)
            }
        }
    }

    private var tabCard: some View {
        GroupBox("Actions") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Target", selection: $selectedTab) {
                    ForEach(ScreenTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedTab.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch selectedTab {
                case .codex:
                    HStack(spacing: 8) {
                        actionButton("Continue") {
                            Task { await vm.send(target: "codex", action: "continue") }
                        }
                        actionButton("Fix+Retest") {
                            Task { await vm.send(target: "codex", action: "fix_retest") }
                        }
                        actionButton("Shot") {
                            Task { await vm.send(target: "codex", action: "shot") }
                        }
                    }
                case .cloudCode:
                    HStack(spacing: 8) {
                        actionButton("Shot CC") {
                            Task { await vm.send(target: "cc", action: "shot") }
                        }
                    }
                case .all:
                    HStack(spacing: 8) {
                        actionButton("Shot Codex") {
                            Task { await vm.send(target: "codex", action: "shot") }
                        }
                        actionButton("Shot CC") {
                            Task { await vm.send(target: "cc", action: "shot") }
                        }
                    }
                }
            }
        }
    }

    private var statusCard: some View {
        GroupBox("State") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace: \(vm.workspaceId.isEmpty ? "(not paired)" : vm.workspaceId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Status: \(vm.statusText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if filteredEvents.isEmpty {
                    Text("No events in \(selectedTab.rawValue) yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }

                ForEach(filteredEvents) { event in
                    EventRow(
                        event: event,
                        baseURL: vm.apiURL,
                        onTapImage: { ref in zoomPayload = ZoomImagePayload(source: ref) }
                    )
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .disabled(vm.isBusy)
    }
}

private struct EventRow: View {
    let event: FeedEvent
    let baseURL: String
    let onTapImage: (EventImageRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(event.sourceLabel) - \(event.event_type)")
                .font(.headline)
            Text(event.created_at)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let payloadText = event.payloadText {
                Text(payloadText)
                    .font(.subheadline)
            } else if let summary = event.payloadSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let refString = event.imageReference,
               let imageRef = resolveImageRef(refString: refString, baseURL: baseURL) {
                imagePreview(imageRef)
            }
        }
        .padding(10)
        .background(.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func imagePreview(_ ref: EventImageRef) -> some View {
        switch ref {
        case .remote(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .onTapGesture { onTapImage(ref) }
                case .failure:
                    Text("Image failed to load")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
        case .inline(let data):
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .onTapGesture { onTapImage(ref) }
            }
        }
    }
}

private struct FullscreenImageView: View {
    let payload: ZoomImagePayload
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            switch payload.source {
            case .remote(let url):
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Text("Image failed to load").foregroundStyle(.white)
                    default:
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .inline(let data):
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding()
        }
    }
}

private func resolveImageRef(refString: String, baseURL: String) -> EventImageRef? {
    let trimmed = refString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
       let url = URL(string: trimmed) {
        return .remote(url)
    }
    if trimmed.hasPrefix("/") {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let url = URL(string: "\(base)\(trimmed)") {
            return .remote(url)
        }
    }
    if trimmed.hasPrefix("data:image/"), let payload = trimmed.split(separator: ",", maxSplits: 1).last {
        if let data = Data(base64Encoded: String(payload)) {
            return .inline(data)
        }
    }
    if trimmed.count > 200, let data = Data(base64Encoded: trimmed) {
        return .inline(data)
    }
    return nil
}
