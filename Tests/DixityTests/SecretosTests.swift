import AppKit
import Testing
@testable import Dixity

// Contraseñas y claves (Secretos, Cursor, Motor.guardarRastro): no se guardan, no se mandan y no se resucitan.
// Auditoría de seguridad del 23/10/2026.
@Suite(.serialized) struct ContrasenasYClaves {
    init() { Ayudas.preparar() }

    @Test func seTapanLasClavesDeLaPantalla() {
        // La clave falsa va partida: así ningún buscador de claves (ni el exportador) la toma por real.
        let t = Secretos.tapar("OPENAI_API_KEY = sk-" + "proj-abc123def456ghi789\nmi contraseña: Tr0ub4dor&3 ok\nhola Juan")
        #expect(!t.contains("sk-proj-abc123"))
        #expect(!t.contains("Tr0ub4dor"))
        #expect(t.contains("hola Juan"))
    }

    @Test func unCampoDeContrasenaNoDejaRastro() {
        Historial.shared.vaciar()
        var c = ContextoCursor(app: "Safari")
        c.secreto = true
        Motor.guardarRastro(Ayudas.registro("mi clave es perro azul cuarenta y dos"), texto: "mi clave es perro azul cuarenta y dos", contexto: c)
        #expect(Historial.shared.registros.isEmpty)
        #expect(Memoria.shared.pendientes.isEmpty)
        #expect(!Portapapeles.shared.elementos.contains { $0.texto?.contains("perro azul") == true })
    }

    @Test func unaContrasenaCopiadaNoSeVuelveAEscribir() {
        let oculta: [[NSPasteboard.PasteboardType: Data]] = [[.string: Data("dummy-secret-123".utf8),
                                                               NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"): Data()]]
        let comun: [[NSPasteboard.PasteboardType: Data]] = [[.string: Data("hola".utf8)]]
        #expect(!Cursor.restaurable(oculta))
        #expect(Cursor.restaurable(comun))
    }

    @Test func lasMarcasViejasDeGestoresTambienCuentan() {
        #expect(Secretos.marcasPrivadas.contains("net.antelle.keeweb"))
        #expect(Secretos.marcasPrivadas.contains("de.petermaurer.TransientPasteboardType"))
    }
}
