import Foundation
import FoundationModels

// Pasar en limpio con el modelo de lenguaje que trae macOS 26 (Apple Intelligence), en la Mac y sin clave.
// Medido el 21/10: ~8 MB de memoria y ~2 s, pero tiende a "mejorar" el texto (cambia el voseo, reformula):
// queda como opción para quien no quiera mandar nada afuera; por defecto sigue una IA en la nube.
enum IAApple {
    static var disponible: Bool {
        if #available(macOS 26, *), case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func completar(sistema: String, usuario: String) async throws -> String {
        guard #available(macOS 26, *), disponible else { throw ErrorApp.sinIAApple }
        let opciones = GenerationOptions(temperature: 0.2)
        do {
            return try await LanguageModelSession(instructions: sistema).respond(to: usuario, options: opciones).content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Su ventana es chica (~4.000 tokens): se reintenta con el final del pedido, donde está lo dictado.
            return try await LanguageModelSession(instructions: sistema).respond(to: String(usuario.suffix(4000)), options: opciones).content
        }
    }
}
