import AVFoundation
import Foundation
import Speech

// Voz a texto con el motor que trae macOS 26 o más nuevo (SpeechAnalyzer). Corre en un servicio del sistema:
// a Dixity casi no le suma memoria (~7 MB contra 40–80 MB de Parakeet) y no hay que bajar nada si el español
// ya está instalado. Medido el 21/10: siempre en español, buena puntuación, pero peor que Parakeet con palabras
// en inglés ("prount" por prompt). Por eso se le pasa el diccionario como palabras esperadas.
enum VozApple {
    static var disponible: Bool {
        if #available(macOS 26, *) { return SpeechTranscriber.isAvailable }
        return false
    }

    static func transcribir(wav: Data, idioma: Idioma, terminos: [String]) async throws -> String {
        guard #available(macOS 26, *), SpeechTranscriber.isAvailable else { throw ErrorApp.sinMotorApple }
        let pedido: Locale = switch idioma {
        case .es: Locale(identifier: "es-AR")
        case .en: Locale(identifier: "en-US")
        case .automatico: Locale.current
        }
        var locale = await SpeechTranscriber.supportedLocale(equivalentTo: pedido)
        if locale == nil { locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "es-AR")) }
        guard let locale else { throw ErrorApp.sinMotorApple }
        guard await SpeechTranscriber.installedLocales.contains(locale) else { throw ErrorApp.sinMotorApple }

        // El analizador lee de un archivo: va a la carpeta temporal y se borra al terminar.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dixis-\(UUID().uuidString).wav")
        try wav.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let transcriptor = SpeechTranscriber(locale: locale, preset: .transcription)
        let analizador = SpeechAnalyzer(modules: [transcriptor])
        if !terminos.isEmpty {
            let contexto = AnalysisContext()
            contexto.contextualStrings[.general] = Array(terminos.prefix(100))
            try? await analizador.setContext(contexto)
        }
        let archivo = try AVAudioFile(forReading: url)
        async let texto: String = transcriptor.results.reduce("") { $0 + String($1.text.characters) }
        if let fin = try await analizador.analyzeSequence(from: archivo) {
            try await analizador.finalizeAndFinish(through: fin)
        } else {
            await analizador.cancelAndFinishNow()
        }
        return try await texto.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
