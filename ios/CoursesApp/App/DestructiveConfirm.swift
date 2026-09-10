import SwiftUI

/**
 Підтвердження деструктивної дії.

 З'явилося після того, як людина відписалася від курсу, просто тапнувши по
 його назві в Налаштуваннях: рядок `Form` з однією кнопкою віддає їй тап
 усього рядка, тож «Відписатися» спрацьовувало без наміру й без запитання.
 Підписка з оплатами зникала мовчки.

 Тому дві речі разом: кнопки в рядках роблять `.borderless`, щоб тап ловила
 сама кнопка, а не рядок, — і жодна незворотна дія не виконується без
 запитання. Дія тримається відкладеною тут, бо `Button` усередині `Menu`
 не може показати діалог сам: його вішають на екран через
 `.destructiveConfirm(...)`.
 */
@MainActor
@Observable
final class DestructiveConfirm {
    struct Pending: Identifiable {
        let id = UUID()
        let title: String
        let message: String?
        let confirmTitle: String
        let action: () -> Void
    }

    var pending: Pending?

    /// `confirmTitle` — те, що станеться: «Видалити», «Відписатися». Не «Так»:
    /// у діалозі має бути видно дію, а не згоду взагалі.
    func ask(
        _ title: String,
        message: String? = nil,
        confirmTitle: String = "Видалити",
        action: @escaping () -> Void
    ) {
        pending = Pending(
            title: title, message: message, confirmTitle: confirmTitle, action: action)
    }
}

extension View {
    func destructiveConfirm(_ confirm: DestructiveConfirm) -> some View {
        modifier(DestructiveConfirmModifier(confirm: confirm))
    }
}

private struct DestructiveConfirmModifier: ViewModifier {
    @Bindable var confirm: DestructiveConfirm

    func body(content: Content) -> some View {
        content.confirmationDialog(
            confirm.pending?.title ?? "",
            isPresented: Binding(
                get: { confirm.pending != nil },
                set: { if !$0 { confirm.pending = nil } }),
            titleVisibility: .visible,
            presenting: confirm.pending
        ) { pending in
            Button(pending.confirmTitle, role: .destructive) {
                pending.action()
                confirm.pending = nil
            }
            Button("Скасувати", role: .cancel) { confirm.pending = nil }
        } message: { pending in
            if let message = pending.message { Text(message) }
        }
    }
}
