import Foundation
import Testing
@testable import Dixity

// A mano y en la Mac (IA de Apple, sin clave ni gasto): `DIXITY_PRUEBA_REAL=1 ./probar.sh --filter PreguntarDeVerdad`.
// Son los dos pedidos reales del 31/10/2026 que fallaron: había texto seleccionado y la IA contestó que no veía
// ninguno, porque la selección hablaba de "texto seleccionado" y se la tomó como instrucción, no como el texto.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DIXITY_PRUEBA_REAL"] != nil && IAApple.disponible))
struct PreguntarDeVerdad {
    init() { Ayudas.preparar() }

    private let seleccion = "Con un texto seleccionado: «resumime esto», «¿qué dice acá?», «traducilo al inglés», «respondele que sí pero el lunes», «explicame esto». Todo esto anda.• Sin selección: escribir algo («un mail para pedir presupuesto»), preguntas cortas («¿cómo se dice “plazo de entrega” en inglés?») o un comando («un comando para ver mi IP»).• Ajustar: volvés a mantener ⌃⌥P y decís «más corto»."

    private func preguntar(_ pedido: String) async throws -> String {
        let usuario = Prompts.usuarioRespuesta(pedido: pedido, seleccion: seleccion, anterior: nil, contexto: nil, terminos: [], extra: "")
        let r = Prompts.limpiarSalida(try await IAApple.completar(sistema: Prompts.sistemaRespuesta, usuario: usuario))
        print("«\(pedido)» → \(r)")
        return r
    }

    private func diceQueNoHayTexto(_ r: String) -> Bool {
        let l = r.lowercased()
        return ["no veo", "no hay texto", "no text", "pegalo", "send me the text", "paste"].contains { l.contains($0) }
    }

    @Test func traduceLoSeleccionado() async throws {
        let r = try await preguntar("Traducí esto al inglés.")
        #expect(!diceQueNoHayTexto(r))
        #expect(r.lowercased().contains("selected") || r.lowercased().contains("summarize"))
    }

    @Test func resumeLoSeleccionado() async throws {
        let r = try await preguntar("resumime este texto")
        #expect(!diceQueNoHayTexto(r))
        // La IA de Apple es chica y resume mal este texto (contesta "Todo esto anda."): acá solo se mira que no diga
        // que no hay texto. La calidad del resumen se prueba con la IA de la nube, en uso real.
    }
}
