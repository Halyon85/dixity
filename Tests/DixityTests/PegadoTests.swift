import Testing
@testable import Dixity

// Lo que se pega (Prompts.sinControles, Motor.copiarEnVezDePegar): sin caracteres de control y sin reescrituras de
// varias líneas en una terminal. Auditoría de seguridad del 23/10/2026.
@Suite struct PegadoSeguro {
    init() { Ayudas.preparar() }

    @Test func laSalidaDeLaIANoTraeControles() {
        let s = Prompts.limpiarSalida("Revisá el login\u{1b}[201~\necho C\u{3}\r\nlisto")
        #expect(!s.unicodeScalars.contains { $0.value == 0x1b || $0.value == 0x03 || $0 == "\r" })
        #expect(s.contains("\n"))
    }

    @Test func losEmojisYAcentosQuedan() {
        #expect(Prompts.sinControles("Listo 👨‍💻 ¿mañana?") == "Listo 👨‍💻 ¿mañana?")
    }

    @Test func unaReescrituraDeVariasLineasEnTerminalNoSePega() {
        #expect(Motor.copiarEnVezDePegar("echo uno\necho dos", modo: .reescritura, bundle: "com.apple.Terminal"))
        #expect(!Motor.copiarEnVezDePegar("una línea", modo: .reescritura, bundle: "com.apple.Terminal"))
        #expect(!Motor.copiarEnVezDePegar("echo uno\necho dos", modo: .reescritura, bundle: "com.apple.TextEdit"))
        #expect(!Motor.copiarEnVezDePegar("1. uno\n2. dos", modo: .dictado, bundle: "com.apple.Terminal"))
    }

    // Cuándo se avisa que el dictado no entró (Cursor.pegar). En Google con Chrome el foco llegaba como un recuadro
    // genérico que no cambia aunque el texto entre, y se mostraba el error y se copiaba en falso (revisión del 01/11).
    @Test func soloSeAvisaQueNoEntroSiSeMirabaUnaCajaDeTexto() {
        #expect(Cursor.sinCambio(mirandoTexto: true) == .noEntro)
        #expect(Cursor.sinCambio(mirandoTexto: false) == .sinSaber)
    }
}
