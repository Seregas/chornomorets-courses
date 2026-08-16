import Foundation
import UIKit
import Vision

/**
 Читає квитанцію просто на пристрої.

 Навмисно без сервера й без хмарних сервісів: Vision розпізнає українську
 (`uk-UA`) офлайн і безкоштовно, а платіжний документ — це те, що не варто
 без потреби ганяти чужими API.

 Важливо розуміти межі: розпізнаний скріншот НЕ є доказом оплати. Змінити
 суму в картинці — хвилина роботи. Це помічник, який заповнює поля й показує
 розбіжності, а не підстава видавати доступ автоматично; для цього потрібна
 банківська виписка.
 */
enum ReceiptScanner {
    static func scan(_ image: UIImage) async -> ReceiptFacts {
        guard let cgImage = image.cgImage else { return ReceiptFacts() }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Українська як основна, англійська — бо банки лишають латиницю в
        // назвах і сумах.
        request.recognitionLanguages = ["uk-UA", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        return ReceiptParsing.parse(lines)
    }

    static func matches(_ facts: ReceiptFacts, expectedAmount: Int?, sessionDate: Date?) -> [String] {
        ReceiptParsing.problems(facts, expectedAmount: expectedAmount, sessionDate: sessionDate)
    }
}
