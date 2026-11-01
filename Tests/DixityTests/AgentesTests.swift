import Foundation
import Testing
@testable import Dixity

// Tanda 4 (30/10/2026): Claude Code y Codex por voz con el atajo de Preguntar, y cuánto te queda de cada uno.
@Suite(.serialized) struct ClaudeYCodexPorVoz {
    init() { Ayudas.preparar() }

    private let tarea = Agentes.Tarea(agente: .claude, pedido: "¿qué hace Motor?", seleccion: "", carpeta: URL(fileURLWithPath: "/tmp"))

    @Test func reconoceElPedidoSoloSiArrancaConElNombre() {
        #expect(Agente.detectar("Claude, ¿qué hace el archivo Motor?")?.agente == .claude)
        #expect(Agente.detectar("Claude, ¿qué hace el archivo Motor?")?.resto == "¿qué hace el archivo Motor?")
        #expect(Agente.detectar("Cloud: revisá por qué falla el login")?.agente == .claude)   // como lo suele escribir la voz
        #expect(Agente.detectar("Che Códex, mirá los tests del login")?.agente == .codex)
        #expect(Agente.detectar("¿Qué es Claude Code?") == nil)
        #expect(Agente.detectar("Claude") == nil)
        #expect(Agente.detectar("Respondele que el jueves puedo") == nil)
    }

    @Test func distingueLaConsultaDeUsoDeUnaTarea() {
        #expect(Agente.consulta("¿Cuánto me queda de Claude?") == .claude)
        #expect(Agente.consulta("Codex, ¿cuánto me queda?") == .codex)
        #expect(Agente.consulta("¿Cuánto límite me queda en Codex esta semana?") == .codex)
        #expect(Agente.consulta("Claude, arreglá el límite de caracteres del formulario de login") == nil)
        #expect(Agente.consulta("¿Cuánto me queda para terminar?") == nil)
    }

    @Test func leeCuantoQuedaDeClaude() throws {
        let archivo = Ayudas.carpeta.appendingPathComponent("claude-\(UUID().uuidString).json")
        let ahora = Date(timeIntervalSince1970: 1_793_400_000)
        let json: [String: Any] = ["otro": 1, "cachedUsageUtilization": [
            "fetchedAtMs": (ahora.timeIntervalSince1970 - 240) * 1000,
            "utilization": ["five_hour": ["utilization": 4, "resets_at": "2026-10-31T06:09:59.673689+00:00"],
                            "seven_day": ["utilization": 12, "resets_at": "2026-11-06T14:59:59.673706+00:00"]]]]
        try JSONSerialization.data(withJSONObject: json).write(to: archivo)
        let r = Agentes.usoClaude(archivo, ahora: ahora)
        #expect(r.hasPrefix("Claude: usaste 4 % de la sesión de 5 horas"))
        #expect(r.contains("12 % de la semana"))
        #expect(r.contains("se renueva"))
        #expect(r.contains("Dato de hace 4 minutos"))
        #expect(Agentes.usoClaude(Ayudas.carpeta.appendingPathComponent("no-existe.json"), ahora: ahora).hasPrefix("No encontré"))
    }

    @Test func leeCuantoQuedaDeCodexDeLaUltimaSesion() throws {
        let base = Ayudas.carpeta.appendingPathComponent("codex-\(UUID().uuidString)")
        let dia = base.appendingPathComponent("2026/10/30")
        try FileManager.default.createDirectory(at: dia, withIntermediateDirectories: true)
        let vieja = #"{"timestamp":"2026-10-29T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":90.0,"window_minutes":10080,"resets_at":1793819613}}}}"#
        let nueva = #"{"timestamp":"2026-10-30T20:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40.0,"window_minutes":10080,"resets_at":1793819613},"secondary":null}}}"#
        try ("{\"type\":\"session_meta\"}\n" + vieja + "\n").write(to: dia.appendingPathComponent("rollout-2026-10-30T09-00-00-a.jsonl"), atomically: true, encoding: .utf8)
        try (vieja + "\n" + nueva + "\n{\"type\":\"otro\"}\n").write(to: dia.appendingPathComponent("rollout-2026-10-30T17-29-30-b.jsonl"), atomically: true, encoding: .utf8)
        // La sesión más nueva a veces no trae el dato (sesiones cortas o internas): vale la anterior que lo tenga.
        let otroDia = base.appendingPathComponent("2026/10/31")
        try FileManager.default.createDirectory(at: otroDia, withIntermediateDirectories: true)
        try "{\"type\":\"session_meta\"}\n".write(to: otroDia.appendingPathComponent("rollout-2026-10-31T01-00-00-c.jsonl"), atomically: true, encoding: .utf8)
        let r = Agentes.usoCodex(base, ahora: Date(timeIntervalSince1970: 1_793_412_000))
        #expect(r.hasPrefix("Codex: usaste 40 % de la semana"))
        #expect(Agentes.usoCodex(base.appendingPathComponent("nada"), ahora: Date()).hasPrefix("No encontré"))
    }

    @Test func leerNuncaDejaEditarYHaceloNuncaDaPermisosTotales() {
        let leer = Agentes.argumentos(tarea, hacer: false)
        #expect(leer.contains("plan") && !leer.contains("acceptEdits"))
        #expect(leer.contains("Edit Write NotebookEdit"))
        // --disallowedTools junta todas las palabras que le siguen: si el pedido iba justo después, Claude se lo tomaba
        // como otra herramienta y no recibía nada (lo encontró la prueba de verdad, 30/10/2026).
        if let i = leer.firstIndex(of: "--disallowedTools") { #expect(i + 2 < leer.count - 1 && leer[i + 2].hasPrefix("--")) }
        var conSesion = tarea
        conSesion.sesion = "abc"
        let hacer = Agentes.argumentos(conSesion, hacer: true)
        #expect(hacer.contains("acceptEdits") && hacer.contains("--resume") && hacer.last == "Hacelo.")
        let codex = Agentes.Tarea(agente: .codex, pedido: "mirá el login", seleccion: "", carpeta: URL(fileURLWithPath: "/tmp/proy"))
        #expect(Agentes.argumentos(codex, hacer: false).contains("read-only"))
        #expect(Agentes.argumentos(codex, hacer: true).contains("workspace-write"))
        for a in [leer, hacer, Agentes.argumentos(codex, hacer: true)] {
            #expect(!a.contains { $0.contains("dangerous") || $0.contains("bypass") || $0 == "danger-full-access" })
        }
    }

    @Test func alAgenteSoloLeVaLoDichoYLaSeleccionConTope() {
        var t = tarea
        t.seleccion = String(repeating: "a", count: 9000)
        let p = Agentes.pedido(t)
        #expect(p.hasPrefix("¿qué hace Motor?\n\nTexto seleccionado:\n"))
        #expect(p.count < 4100)
        #expect(Agentes.pedido(tarea) == "¿qué hace Motor?")
    }

    @Test func entiendeLaRespuestaYLosErroresDeClaude() {
        let salida = "[mcp-sdk] SEP-2352: aviso\n{\"result\":\"hola\",\"is_error\":false,\"session_id\":\"s1\"}"
        #expect(Agentes.respuestaJSON(salida)?["session_id"] as? String == "s1")
        #expect(Agentes.motivo("SEP-2352 algo\nNot logged in · Please run /login", agente: .claude).contains("no tiene la sesión iniciada"))
        #expect(Agentes.motivo("Workspace not trusted.", agente: .codex) == "Workspace not trusted.")
    }
}

// A mano y con la suscripción: `DIXITY_PRUEBA_REAL=1 swift test --filter AgentesDeVerdad`. Pregunta en solo lectura
// sobre esta misma carpeta y mira que el proyecto no cambie.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DIXITY_PRUEBA_REAL"] != nil))
struct AgentesDeVerdad {
    @Test(arguments: [Agente.claude, .codex]) func respondeSinTocarNada(_ a: Agente) async throws {
        let carpeta = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let antes = try FileManager.default.attributesOfItem(atPath: carpeta.appendingPathComponent("Sources/Dixity/Agentes.swift").path)[.modificationDate] as? Date
        let t = Agentes.Tarea(agente: a, pedido: "Agregale un comentario arriba a Sources/Dixity/Agentes.swift que diga hola.", seleccion: "", carpeta: carpeta)
        let r = try await Agentes.correr(t, hacer: false)
        print("\(a.nombre): \(r.texto.prefix(300)) · sesión: \(r.sesion ?? "-")")
        #expect(!r.texto.isEmpty)
        let despues = try FileManager.default.attributesOfItem(atPath: carpeta.appendingPathComponent("Sources/Dixity/Agentes.swift").path)[.modificationDate] as? Date
        #expect(antes == despues)
        if a == .claude { #expect(r.sesion != nil) }
    }

    @Test func leeElUsoDeVerdad() {
        for a in [Agente.claude, .codex] { print("USO", Agentes.uso(a)) ; #expect(!Agentes.uso(a).hasPrefix("No encontré")) }
    }
}
