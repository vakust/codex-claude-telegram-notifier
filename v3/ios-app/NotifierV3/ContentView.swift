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
            return "Codex controls"
        case .cloudCode:
            return "Cloud Code controls"
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
    @State private var codexCustomText: String = ""
    @State private var ccCustomText: String = ""
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

    private var topEventId: String? {
        filteredEvents.first?.id
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

                VStack(spacing: 10) {
                    headerCard
                    toolbarRow

                    if showSettings {
                        settingsCard
                    }

                    actionsCard
                    statusCard
                    feedList
                }
                .padding(12)
            }
            .navigationTitle("Notifier V3")
            .simultaneousGesture(
                TapGesture().onEnded {
                    hideKeyboard()
                }
            )
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
            HStack(spacing: 8) {
                Label(vm.statusText, systemImage: vm.isBusy ? "bolt.fill" : "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(vm.isBusy ? .orange : .green)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("events: \(vm.events.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Connection")
                .font(.headline)
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            Button(showSettings ? "Hide Settings" : "Show Settings") {
                hideKeyboard()
                showSettings.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Refresh Feed") {
                hideKeyboard()
                Task { await vm.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
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
                    hideKeyboard()
                    Task { await vm.pairDevice(pairCode: pairCode) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(vm.isBusy)
            }
        }
    }

    private var actionsCard: some View {
        GroupBox("Actions") {
            VStack(alignment: .leading, spacing: 8) {
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
                    codexActions
                case .cloudCode:
                    cloudCodeActions
                case .all:
                    allActions
                }
            }
        }
    }

    private var codexActions: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                actionButton("Continue") {
                    Task { await vm.send(target: "codex", action: "continue") }
                }
                actionButton("Fix+Retest") {
                    Task { await vm.send(target: "codex", action: "fix_retest") }
                }
            }
            HStack(spacing: 6) {
                actionButton("Shot") {
                    Task { await vm.send(target: "codex", action: "shot") }
                }
                actionButton("Last Text") {
                    Task { await vm.send(target: "codex", action: "last_text") }
                }
            }
            HStack(spacing: 6) {
                TextField("Custom", text: $codexCustomText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                actionButton("Send") {
                    sendCustom(target: "codex", text: codexCustomText)
                    codexCustomText = ""
                }
                .frame(maxWidth: 84)
                .disabled(vm.isBusy || codexCustomText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var cloudCodeActions: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                actionButton("CC Continue") {
                    Task { await vm.send(target: "cc", action: "continue") }
                }
                actionButton("CC Fix+Retest") {
                    Task { await vm.send(target: "cc", action: "fix_retest") }
                }
            }
            HStack(spacing: 6) {
                actionButton("Shot CC") {
                    Task { await vm.send(target: "cc", action: "shot") }
                }
                actionButton("CC Last Text") {
                    Task { await vm.send(target: "cc", action: "last_text") }
                }
            }
            HStack(spacing: 6) {
                TextField("Custom", text: $ccCustomText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                actionButton("Send") {
                    sendCustom(target: "cc", text: ccCustomText)
                    ccCustomText = ""
                }
                .frame(maxWidth: 84)
                .disabled(vm.isBusy || ccCustomText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var allActions: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                actionButton("Shot Codex") {
                    Task { await vm.send(target: "codex", action: "shot") }
                }
                actionButton("Shot CC") {
                    Task { await vm.send(target: "cc", action: "shot") }
                }
            }
            HStack(spacing: 6) {
                actionButton("Codex Last") {
                    Task { await vm.send(target: "codex", action: "last_text") }
                }
                actionButton("CC Last") {
                    Task { await vm.send(target: "cc", action: "last_text") }
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
        ScrollViewReader { proxy in
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
                        .id(event.id)
                    }
                }
                .padding(.bottom, 8)
            }
            .onChange(of: topEventId) { newId in
                guard let newId else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newId, anchor: .top)
                }
            }
            .onChange(of: selectedTab) { _ in
                guard let newId = filteredEvents.first?.id else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newId, anchor: .top)
                }
            }
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            hideKeyboard()
            action()
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 34)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(vm.isBusy)
    }

    private func sendCustom(target: String, text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        hideKeyboard()
        Task {
            await vm.send(target: target, action: "custom", customText: value)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct EventRow: View {
    let event: FeedEvent
    let baseURL: String
    let onTapImage: (EventImageRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(event.sourceLabel) | \(event.event_type)")
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
        .background(.white.opacity(0.93))
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
                        .frame(maxWidth: .infinity)
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
                    .frame(maxWidth: .infinity)
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
                        ZoomableImageContainer {
                            image
                                .resizable()
                                .scaledToFit()
                        }
                    case .failure:
                        Text("Image failed to load")
                            .foregroundStyle(.white)
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .inline(let data):
                if let uiImage = UIImage(data: data) {
                    ZoomableImageContainer {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    }
                }
            }

            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding()
        }
    }
}

private struct ZoomableImageContainer<Content: View>: View {
    let content: Content
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale)
            .offset(offset)
            .background(Color.black)
            .simultaneousGesture(magnificationGesture)
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 2) {
                if scale > 1.01 {
                    resetZoom()
                } else {
                    scale = 2
                    lastScale = 2
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, min(lastScale * value, 5))
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 {
                    resetZoom()
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                if scale <= 1.01 {
                    resetZoom()
                } else {
                    lastOffset = offset
                }
            }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
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
        let base = baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
