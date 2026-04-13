import SwiftUI

/// Read-only audit trail of mill/yard/schedule mutations. Server captures
/// IP + action + entity + pretty-printed details on every create/update/
/// delete. Loads 100 at a time with a "Load more" control.
struct ActivityLogView: View {
    @Environment(AppConfiguration.self) private var config

    @State private var events: [ActivityEvent] = []
    @State private var total: Int = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var expandedIds: Set<String> = []

    private let pageSize = 100

    var body: some View {
        List {
            Section {
                Text("Audit trail of all changes. User identity will populate once SSO is connected.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if isLoading && events.isEmpty {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if let err = errorMessage, events.isEmpty {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            } else if events.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Create or edit a mill, yard, or schedule to see entries here.")
                    )
                }
            } else {
                Section {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                } header: {
                    HStack {
                        Text("\(events.count) of \(total) events")
                        Spacer()
                    }
                    .font(.caption)
                }

                if events.count < total {
                    Section {
                        Button {
                            Task { await load(offset: events.count) }
                        } label: {
                            if isLoading {
                                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                            } else {
                                HStack { Spacer(); Text("Load more"); Spacer() }
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .navigationTitle("Activity Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await reload() } } label: {
                    if isLoading && !events.isEmpty { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(isLoading)
            }
        }
        .task { if events.isEmpty { await reload() } }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private func eventRow(_ event: ActivityEvent) -> some View {
        let isExpanded = expandedIds.contains(event.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                actionBadge(event.action)
                Text(event.entity.rawValue).font(.caption.weight(.semibold))
                Spacer()
                Text(event.relativeTime).font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                Label(event.ip.isEmpty ? "—" : event.ip, systemImage: "network")
                    .font(.caption2).foregroundStyle(.secondary)
                if let user = event.user, !user.isEmpty {
                    Label(user, systemImage: "person.crop.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Label("no user", systemImage: "person.crop.circle.dashed")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !event.detailsText.isEmpty {
                Button {
                    if isExpanded { expandedIds.remove(event.id) } else { expandedIds.insert(event.id) }
                } label: {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        Text(isExpanded ? "Hide details" : "Show details")
                    }
                    .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.carterBlue)
                if isExpanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(event.detailsText)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func actionBadge(_ action: ActivityEvent.Action) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch action {
            case .create: return ("CREATE", Color.green.opacity(0.15),  .green)
            case .update: return ("UPDATE", Color.blue.opacity(0.15),   .blue)
            case .delete: return ("DELETE", Color.red.opacity(0.15),    .red)
            case .login:  return ("LOGIN",  Color.gray.opacity(0.15),   .secondary)
            case .logout: return ("LOGOUT", Color.gray.opacity(0.15),   .secondary)
            }
        }()
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(bg))
            .foregroundStyle(fg)
    }

    @MainActor
    private func reload() async {
        events = []
        total = 0
        expandedIds.removeAll()
        await load(offset: 0)
    }

    @MainActor
    private func load(offset: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let service = MillsYardsService(baseURL: config.intelliShiftBaseURL)
            let resp = try await service.fetchActivity(limit: pageSize, offset: offset)
            if offset == 0 { events = resp.events }
            else { events.append(contentsOf: resp.events) }
            total = resp.total
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
