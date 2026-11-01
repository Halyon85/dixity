import CoreGraphics
import Foundation
import Testing
@testable import Dixity

// Instrucción por app o sitio y acciones rápidas sobre una selección (30/10/2026).
@Suite(.serialized) struct InstruccionesYAcciones {
    init() { Ayudas.preparar() }

    @Test func laInstruccionDeLaAppSeSumaALaGeneral() {
        let a = Ajustes.shared, antes = a.datos
        defer { a.datos = antes }
        a.datos.instruccionesExtra = "Escribí con vos."
        a.datos.instruccionesApp = [InstruccionApp(app: "LinkedIn", texto: "Tono profesional."),
                                    InstruccionApp(app: "WhatsApp", texto: "Sin emojis."),
                                    InstruccionApp(app: "Slack", texto: "   ")]
        let linkedin = ContextoCursor(app: "Google Chrome", bundle: "com.google.Chrome", ventana: "Feed | LinkedIn")
        #expect(a.instruccionPara(linkedin) == "Escribí con vos.\nEn LinkedIn: Tono profesional.")
        #expect(a.instruccionPara(ContextoCursor(app: "WhatsApp")) == "Escribí con vos.\nEn WhatsApp: Sin emojis.")
        // Vacía no suma; fuera del navegador el título no cuenta; sin contexto, solo la general.
        #expect(a.instruccionPara(ContextoCursor(app: "Slack")) == "Escribí con vos.")
        #expect(a.instruccionPara(ContextoCursor(app: "Notas", ventana: "LinkedIn ideas")) == "Escribí con vos.")
        #expect(a.instruccionPara(nil) == "Escribí con vos.")
    }

    @Test func lasAccionesVienenConAtajosQueNoChocan() throws {
        let d = try JSONDecoder().decode(DatosAjustes.self, from: Data("{}".utf8))
        #expect(d.acciones.map(\.atajo).compactMap { $0 }.count == 2)
        let base = [d.atajoDictar, d.atajoReescribir, d.atajoPortapapeles, d.atajoReprocesar, d.atajoSumarPalabra]
        for a in d.acciones.compactMap(\.atajo) {
            #expect(a.problema(otros: base + d.acciones.compactMap(\.atajo).filter { $0 != a }) == nil)
        }
    }

    @Test func elAtajoDeUnaAccionLaDisparaYNoLlegaALaApp() {
        let monitor = MonitorAtajos()
        let id = UUID()
        monitor.atajosAccion = [id: Atajo(modificadores: [], tecla: 31)]
        var recibido: UUID?
        monitor.alEvento = { if case .accionRapida(let x) = $0 { recibido = x } }
        let tecla = CGEvent(keyboardEventSource: nil, virtualKey: 31, keyDown: true)!
        #expect(monitor.procesar(.keyDown, tecla) == nil)
        #expect(recibido == id)
    }
}
