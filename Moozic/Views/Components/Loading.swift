import SwiftUI

/// Loads a value once (and on pull-to-refresh), showing progress and errors.
struct LoadingView<Value, Content: View>: View {
    @EnvironmentObject private var session: SessionStore
    let load: (APIClient) async throws -> Value
    @ViewBuilder let content: (Value) -> Content

    @State private var value: Value? = nil
    @State private var error: Error? = nil

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if let error {
                ErrorStateView(error: error) { await reload() }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if value == nil { await reload() } }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard let api = session.api else { return }
        do {
            value = try await load(api)
            error = nil
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error
        }
    }
}

struct ErrorStateView: View {
    let error: Error
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 4) {
                Text(error.localizedDescription)
                if let id = (error as? APIError)?.requestId {
                    Text("Request \(id)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            }
        } actions: {
            Button("Try Again") { Task { await retry() } }
                .buttonStyle(.bordered)
        }
    }
}

/// Offset/limit pagination for the list endpoints (`{ items, total, limit, offset }`).
@MainActor
final class PagedList<Item: Decodable & Identifiable>: ObservableObject where Item.ID: Hashable {
    @Published private(set) var items: [Item] = []
    @Published private(set) var total: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private let pageSize: Int
    private var fetch: ((APIClient, _ limit: Int, _ offset: Int) async throws -> Page<Item>)?
    private var api: APIClient?
    private var generation = 0

    init(pageSize: Int = 60) {
        self.pageSize = pageSize
    }

    var hasMore: Bool { total.map { items.count < $0 } ?? true }
    var isEmpty: Bool { total == 0 }

    func reload(api: APIClient?, fetch: @escaping (APIClient, Int, Int) async throws -> Page<Item>) async {
        guard let api else { return }
        self.api = api
        self.fetch = fetch
        generation += 1
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let page = try await fetch(api, pageSize, 0)
            guard current == generation else { return }
            items = page.items
            total = page.total
            error = nil
        } catch {
            guard current == generation, !(error is CancellationError) else { return }
            self.error = error
        }
    }

    func loadMoreIfNeeded(after item: Item) async {
        guard let position = items.firstIndex(where: { $0.id == item.id }), position >= items.count - 10 else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, hasMore, let api, let fetch else { return }
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let page = try await fetch(api, pageSize, items.count)
            guard current == generation else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            total = page.items.isEmpty ? items.count : page.total
        } catch {
            if current == generation { self.error = error }
        }
    }
}
