import CoreGraphics
import Foundation
import Testing
@testable import Dixity

// Tanda 3 (30/10/2026): Preguntar con la respuesta a la vista antes de pegar, y aprender de lo que corregís a mano.
@Suite(.serialized) struct RespuestaYCorrecciones {
    init() {
        Ayudas.preparar()
        Diccionario.shared.terminos = []
    }

    private func tecla(_ codigo: CGKeyCode, banderas: CGEventFlags = []) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: codigo, keyDown: true)!
        e.flags = banderas
        return e
    }

    // MARK: Preguntar

    @Test func elAtajoDePreguntarNoChocaConLosDemas() throws {
        let d = try JSONDecoder().decode(DatosAjustes.self, from: Data("{}".utf8))
        let otros = [d.atajoDictar, d.atajoReescribir, d.atajoPortapapeles, d.atajoReprocesar, d.atajoSumarPalabra]
            + d.acciones.compactMap(\.atajo)
        #expect(d.atajoPreguntar == .preguntarPredeterminado)
        #expect(d.atajoPreguntar.problema(otros: otros) == nil)
    }

    @Test func conLaRespuestaAbiertaReturnPegaYNoLlegaALaApp() {
        let m = MonitorAtajos()
        var vistos: [String] = []
        m.alEvento = { vistos.append("\($0)") }
        // Cerrada: ↩ es de la app.
        #expect(m.procesar(.keyDown, tecla(36)) != nil)
        m.capturaRespuesta = true
        #expect(m.procesar(.keyDown, tecla(36)) == nil)
        #expect(m.procesar(.keyDown, tecla(76)) == nil)   // el Enter del teclado numérico
        #expect(vistos == ["confirmar", "confirmar"])
    }

    @Test func escribirEnOtroLadoCierraLaRespuestaPeroUnAtajoNo() {
        let m = MonitorAtajos()
        m.capturaRespuesta = true
        var vistos: [String] = []
        m.alEvento = { vistos.append("\($0)") }
        #expect(m.procesar(.keyDown, tecla(0)) != nil)   // una "a": llega a la app y avisa
        #expect(vistos == ["teclaSuelta"])
        vistos = []
        // ⌘C con la ventanita abierta: se copia en la app sin cerrarla.
        let cmd = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true)!
        cmd.type = .flagsChanged
        cmd.flags = CGEventFlags(rawValue: Modificador.cmdIzq.mascara | CGEventFlags.maskCommand.rawValue)
        _ = m.procesar(.flagsChanged, cmd)
        #expect(m.procesar(.keyDown, tecla(8, banderas: .maskCommand)) != nil)
        #expect(vistos.isEmpty)
    }

    @Test func alAjustarLaIARecibeLaRespuestaAnteriorYLaSeleccion() {
        let u = Prompts.usuarioRespuesta(pedido: "más corto", seleccion: "¿Llegás el jueves?",
                                         anterior: (pedido: "respondele que sí", texto: "¡Sí, el jueves llego sin problema!"),
                                         contexto: ContextoCursor(app: "WhatsApp"), terminos: [], extra: "Escribí con vos.")
        #expect(u.contains("<texto_seleccionado>\n¿Llegás el jueves?\n</texto_seleccionado>"))
        #expect(u.contains("<respuesta_anterior>\n¡Sí, el jueves llego sin problema!\n</respuesta_anterior>"))
        #expect(u.contains("<preferencias>\nEscribí con vos.\n</preferencias>"))
        #expect(u.hasSuffix("<pedido>\nmás corto\n</pedido>"))
    }

    @Test func unaRespuestaNoSeAprendeComoDictado() {
        let r = Ayudas.registro("", final: "El informe de Trevalix7 queda para el lunes.", modo: .respuesta)
        Sugerencias.shared.aprender(de: r, proyecto: nil)
        #expect(!Sugerencias.shared.lista.contains { $0.texto == "Trevalix7" })
        #expect(!Diccionario.shared.terminos.contains { $0.texto == "Trevalix7" })
    }

    // MARK: Lo que corregís a mano

    @Test func loQueQuedoEnLugarDeLoPegado() {
        #expect(Correcciones.medio(antes: "Hola. ", despues: " Chau", ahora: "Hola. probando Dixity Chau") == "probando Dixity")
        #expect(Correcciones.medio(antes: "Hola. ", despues: "", ahora: "Hola. probando y sigo escribiendo") == "probando y sigo escribiendo")
        // Lo mandaste o lo borraste: ya no está lo de antes.
        #expect(Correcciones.medio(antes: "Hola. ", despues: "", ahora: "") == nil)
    }

    @Test func unNombreCorregidoSeSugiereConSuAlias() {
        let c = Correcciones.cambios(pegado: "Estoy probando dick city en la Mac.", corregido: "Estoy probando Dixity en la Mac.")
        #expect(c.map(\.nuevo) == ["Dixity"])
        #expect(c.map(\.viejo) == ["dick city"])
        // A principio de oración también, si juntaste palabras.
        let inicio = Correcciones.cambios(pegado: "Dick City anda bien.", corregido: "Dixity anda bien.")
        #expect(inicio.map(\.nuevo) == ["Dixity"])
    }

    @Test func noSeSugiereLoQueNoEsCorregirUnNombre() {
        // Cambio de sentido, palabra común, solo tildes o mayúsculas, y escribir de más después.
        #expect(Correcciones.cambios(pegado: "Nos vemos el martes a la tarde.", corregido: "Nos vemos el jueves a la tarde.").isEmpty)
        #expect(Correcciones.cambios(pegado: "Te dejo la casa ordenada.", corregido: "Te dejo la cosa ordenada.").isEmpty)
        #expect(Correcciones.cambios(pegado: "Cerré la sesion.", corregido: "Cerré la sesión.").isEmpty)
        #expect(Correcciones.cambios(pegado: "Mañana lo vemos.", corregido: "Mañana lo vemos. Y le aviso a Caro.").isEmpty)
        // Reescribiste casi todo: no es una corrección.
        #expect(Correcciones.cambios(pegado: "Pasame el informe de Halion mañana temprano",
                                     corregido: "Mandame el resumen de Halyon el lunes a la tarde").isEmpty)
    }

    @Test func laCorreccionQuedaComoSugerenciaAunqueAprendaSolo() {
        let a = Ajustes.shared, antes = a.datos
        defer { a.datos = antes }
        a.datos.aprenderSolo = true
        Sugerencias.shared.aprenderCorreccion([(nuevo: "Qorvana", viejo: "corbana")])
        #expect(Sugerencias.shared.lista.contains { $0.texto == "Qorvana" && $0.alias == ["corbana"] && $0.origen == "a mano" })
        #expect(!Diccionario.shared.terminos.contains { $0.texto == "Qorvana" })
        // Si el nombre ya está con ese alias, no se vuelve a sugerir.
        Diccionario.shared.agregar("Prulex", alias: ["pru lex"])
        Sugerencias.shared.aprenderCorreccion([(nuevo: "Prulex", viejo: "pru lex")])
        #expect(!Sugerencias.shared.lista.contains { $0.texto == "Prulex" })
    }
}
