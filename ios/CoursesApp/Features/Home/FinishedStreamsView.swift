import SwiftUI

/// Курси, які вже завершилися.
///
/// Окремим екраном, бо на «Навчанні» має бути видно те, чим живеш зараз.
/// Пройдені курси нікуди не діваються — до їхніх записів повертаються місяцями,
/// — але щодня вони лише відсувають униз те, що триває.
struct FinishedStreamsView: View {
    @Environment(\.repository) private var repo
    @State private var state: LoadState<[EnrolledStream]> = .loading

    var body: some View {
        LoadStateView(state: state, retry: { Task { await load() } }) { items in
            if items.isEmpty {
                ContentUnavailableView(
                    "Завершених курсів немає", systemImage: "checkmark.seal",
                    description: Text("Тут зʼявляться курси, які ви пройшли."))
            } else {
                List(items) { item in
                    NavigationLink(value: Route.stream(item.streamId)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.courseTitle).font(.subheadline.weight(.medium))
                            Text("\(item.streamTitle) · \(item.sessionsPassed) занять")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Завершені")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do { state = .loaded(try await repo.home().streams.filter { $0.status == .finished }) }
        catch { state = .from(error) }
    }
}
