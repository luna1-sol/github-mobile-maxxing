import SwiftUI

/// Loading state of a screen section. A refresh keeps the previous value visible (stale-while-revalidate).
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

}

/// Runs `operation` and writes its outcome through `state` (a `@State` binding, so `.loading` shows at once).
/// A refresh keeps the previous value on failure. Cancellation (view disappeared, `.task(id:)` restarted)
/// leaves the state unchanged so a stale request can never overwrite a newer one.
func loadState<Value>(_ state: Binding<LoadState<Value>>, _ operation: () async throws -> Value) async {
    if state.wrappedValue.value == nil { state.wrappedValue = .loading }
    do {
        let result = try await operation()
        try Task.checkCancellation()
        state.wrappedValue = .loaded(result)
    } catch is CancellationError {
        return
    } catch let error as URLError where error.code == .cancelled {
        return
    } catch {
        if state.wrappedValue.value == nil { state.wrappedValue = .failed(error.localizedDescription) }
    }
}

/// Like `loadState`, but for switching what is shown (a filter or tab changed): the previous content stays
/// on screen until the new result arrives and is then always replaced, by the new value or by the error.
/// Keeping the list mounted also keeps the navigation bar's large title attached to it.
func replaceState<Value>(_ state: Binding<LoadState<Value>>, _ operation: () async throws -> Value) async {
    do {
        let result = try await operation()
        try Task.checkCancellation()
        state.wrappedValue = .loaded(result)
    } catch is CancellationError {
        return
    } catch let error as URLError where error.code == .cancelled {
        return
    } catch {
        state.wrappedValue = .failed(error.localizedDescription)
    }
}

/// Renders loading / error / empty / content for a `LoadState`.
struct AsyncContent<Value, Content: View>: View {
    let state: LoadState<Value>
    var isEmpty: (Value) -> Bool = { _ in false }
    var emptyTitle: LocalizedStringKey = "Nothing here"
    var emptySystemImage = "tray"
    var retry: (() async -> Void)?
    /// Dims the current content and shows a spinner while a replacement is loading.
    var isRefreshing = false
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                if let retry {
                    Button("Retry") { Task { await retry() } }
                        .buttonStyle(.glassProminent)
                }
            }
        case .loaded(let value):
            Group {
                if isEmpty(value) {
                    ContentUnavailableView(emptyTitle, systemImage: emptySystemImage)
                } else {
                    content(value)
                }
            }
            .opacity(isRefreshing ? 0.4 : 1)
            .allowsHitTesting(!isRefreshing)
            .overlay {
                if isRefreshing { ProgressView().controlSize(.large) }
            }
            .animation(.easeInOut(duration: 0.15), value: isRefreshing)
        }
    }
}

extension AsyncContent {
    init(
        _ state: LoadState<Value>,
        isEmpty: @escaping (Value) -> Bool = { _ in false },
        emptyTitle: LocalizedStringKey = "Nothing here",
        emptySystemImage: String = "tray",
        retry: (() async -> Void)? = nil,
        isRefreshing: Bool = false,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.state = state
        self.isRefreshing = isRefreshing
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.retry = retry
        self.content = content
    }

    init(
        _ state: LoadState<Value>,
        emptyTitle: LocalizedStringKey = "Nothing here",
        emptySystemImage: String = "tray",
        retry: (() async -> Void)? = nil,
        isRefreshing: Bool = false,
        @ViewBuilder content: @escaping (Value) -> Content
    ) where Value: Collection {
        self.state = state
        self.isRefreshing = isRefreshing
        self.isEmpty = { $0.isEmpty }
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.retry = retry
        self.content = content
    }
}

/// Shows transient errors from user actions (comment, merge, star...) as an alert.
struct ErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "Something went wrong",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
            presenting: message
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}
