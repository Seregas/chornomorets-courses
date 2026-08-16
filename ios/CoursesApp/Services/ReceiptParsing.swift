import Foundation

/// Те, що вдалося прочитати з квитанції.
struct ReceiptFacts: Codable, Hashable {
    var amount: Int?
    /// Дата платежу, як її написано в квитанції.
    var date: String?
    /// Рядок призначення — саме він містить курс, дату заняття й прізвище.
    var purpose: String?
    /// Повний текст — щоб адмін звірив очима, якщо розбір схибив.
    var text: String = ""

    var isEmpty: Bool { amount == nil && date == nil && purpose == nil }
}

/**
 Розбір рядків квитанції. Без UIKit і Vision навмисно: так його можна
 ганяти на справжніх текстах окремо від застосунку.
 */
enum ReceiptParsing {
    /// Рядки, після яких призначення платежу вже скінчилося.
    private static let sectionBreaks = ["комісія", "статус", "отримувач", "iban", "код"]

    static func parse(_ lines: [String]) -> ReceiptFacts {
        var facts = ReceiptFacts()
        facts.text = lines.joined(separator: "\n")
        // Найбільша сума, а не перша: у квитанції поруч стоїть «Комісія 0,00 ₴»,
        // і взяти перше-ліпше означає записати нуль.
        facts.amount = lines.compactMap(amount(in:)).max()
        facts.date = lines.compactMap(date(in:)).first
        facts.purpose = purpose(in: lines)
        return facts
    }

    /// «2 100,00 ₴», «2100 грн» → 2100. Копійки відкидаємо: у нас цілі гривні.
    static func amount(in line: String) -> Int? {
        let lower = line.lowercased()
        guard lower.contains("₴") || lower.contains("грн") || lower.contains("uah") else { return nil }
        guard let match = line.range(of: #"\d[\d  ]*([.,]\d{2})?"#, options: .regularExpression) else {
            return nil
        }
        let whole = line[match].split(separator: ",").first
            .map(String.init) ?? String(line[match])
        let digits = whole.split(separator: ".").first.map(String.init) ?? whole
        return Int(digits.filter(\.isNumber))
    }

    static func date(in line: String) -> String? {
        if let m = line.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) {
            return String(line[m])
        }
        return nil
    }

    /**
     Призначення платежу. У квитанції це заголовок і кілька рядків під ним —
     саме там лежать назва курсу, дата заняття й прізвище, тобто все, за чим
     оплату взагалі можна зіставити.
     */
    static func purpose(in lines: [String]) -> String? {
        guard let start = lines.firstIndex(where: { isPurposeMarker($0) }) else { return nil }
        // Якщо знайшли сам заголовок — вміст починається з наступного рядка.
        let headerOnly = lines[start].lowercased().contains("призначення")
            && lines[start].count < 30
        var collected: [String] = headerOnly ? [] : [lines[start]]

        for line in lines.dropFirst(start + 1) {
            let lower = line.lowercased()
            if sectionBreaks.contains(where: lower.contains) { break }
            if amount(in: line) != nil { break }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            collected.append(line)
            if collected.count >= 4 { break }
        }
        let joined = collected.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined
    }

    private static func isPurposeMarker(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("призначення")
            || lower.contains("консультацій")
            || lower.contains("тренинг")
            || lower.contains("тренінг")
            || lower.contains("лекц")
    }

    /// Чи збігається прочитане з очікуваним. Порожній список — усе гаразд.
    static func problems(_ facts: ReceiptFacts, expectedAmount: Int?, sessionDate: Date?) -> [String] {
        var problems: [String] = []
        if facts.amount == nil {
            problems.append("не видно суми")
        } else if let expectedAmount, let got = facts.amount, got != expectedAmount {
            problems.append("сума \(got) ₴ замість \(expectedAmount) ₴")
        }
        if let sessionDate {
            let f = DateFormatter()
            f.dateFormat = "dd.MM"
            let day = f.string(from: sessionDate)
            if facts.purpose?.contains(day) != true {
                problems.append("у призначенні немає дати заняття (\(day))")
            }
        }
        return problems
    }
}
