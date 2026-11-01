import CoreGraphics
import Foundation
import Testing
@testable import Dixity

// Tanda 2 del 31/10/2026: tarjetas que cambian según lo que muestran, botones para seguir trabajando, la tarjeta de uso
// de Claude y Codex, y el menú que aparece al sacudir el mouse.
@Suite(.serialized) struct TarjetasYMenu {
    init() { Ayudas.preparar() }

    // MARK: Formato

    @Test func parteLaRespuestaEnTitulosListasYCodigo() {
        let b = Respuestas.bloques("# Pasos\nPrimero esto,\nen dos líneas.\n\n1. Uno\n2) Dos\n- Suelto\n```\nls -la\n```\nFin")
        #expect(b == [.titulo("Pasos"), .parrafo("Primero esto,\nen dos líneas."), .item(marca: "1.", texto: "Uno"),
                      .item(marca: "2.", texto: "Dos"), .item(marca: "•", texto: "Suelto"), .codigo("ls -la"), .parrafo("Fin")])
        // Un bloque de código sin cerrar se muestra igual.
        #expect(Respuestas.bloques("```\necho hola") == [.codigo("echo hola")])
    }

    // MARK: Botones para seguir

    @Test func ofreceElOtroIdiomaPrimero() {
        let es = Respuestas.opciones(para: "¡Hola Caro! Sí, el jueves puedo. ¿Te queda bien a las diez en la oficina?", clase: .texto, idiomaPersona: "es")
        #expect(es.first == .traducir("en"))
        #expect(es.contains(.masFormal) && es.contains(.reformular) && es.contains(.masCorto))
        let en = Respuestas.opciones(para: "Hi Caro! Thursday works for me. Does ten at the office suit you?", clase: .texto, idiomaPersona: "es")
        #expect(en.first == .traducir("es"))
        #expect(en.contains(.masCasual))
        // Una traducción ofrece volver al idioma de antes.
        let vuelta = Respuestas.opciones(para: "Thanks for waiting, I'll send it tomorrow.",
                                         clase: .traduccion(de: "es", a: "en", original: "Gracias por esperar, mañana lo mando."), idiomaPersona: "es")
        #expect(vuelta.first == .traducir("es"))
        // Largo: se suma Resumir. Uso y QR no tienen botones.
        let largo = String(repeating: "Esto es una frase bastante larga para la prueba. ", count: 20)
        #expect(Respuestas.opciones(para: largo, clase: .texto, idiomaPersona: "es").contains(.resumir))
        #expect(Respuestas.opciones(para: "https://halyon.team", clase: .codigos, idiomaPersona: "es").isEmpty)
        #expect(Respuestas.opciones(para: "x", clase: .uso([]), idiomaPersona: "es").isEmpty)
        #expect(Respuestas.opciones(para: largo, clase: .texto, idiomaPersona: "es").count <= 5)
    }

    @Test func soloOfreceAbrirLinksWeb() {
        #expect(Respuestas.links("https://halyon.team/dixity").map(\.host) == ["halyon.team"])
        #expect(Respuestas.links("Mirá http://ejemplo.com y ftp://raro.com").count == 1)
        #expect(Respuestas.links("WIFI:S:Casa;T:WPA;P:clave;;").isEmpty)
    }

    // MARK: Uso

    @Test func laCuentaRegresivaSeLeeFacil() {
        let ahora = Date(timeIntervalSince1970: 1_793_400_000)
        #expect(Respuestas.cuentaRegresiva(hasta: ahora.addingTimeInterval(42 * 60 + 5), desde: ahora) == "renueva en 42 min")
        #expect(Respuestas.cuentaRegresiva(hasta: ahora.addingTimeInterval(2 * 3600 + 10 * 60 + 5), desde: ahora) == "renueva en 2 h 10 min")
        #expect(Respuestas.cuentaRegresiva(hasta: ahora.addingTimeInterval(30), desde: ahora) == "se renueva ahora")
        #expect(Respuestas.cuentaRegresiva(hasta: ahora.addingTimeInterval(3 * 86400), desde: ahora).hasPrefix("renueva el "))
    }

    @Test func entiendeQueAgentesPedis() {
        #expect(Agente.consultaUso("¿Cuánto me queda de Claude?") == [.claude])
        #expect(Agente.consultaUso("¿Cuánto me queda de Claude y de Codex?") == [.claude, .codex])
        #expect(Agente.consultaUso("¿Cuánto uso me queda?") == [.claude, .codex])
        #expect(Agente.consultaUso("¿Cuánto me queda para terminar?") == nil)
        #expect(Agente.consultaUso("Claude, arreglá el límite de caracteres del formulario de login") == nil)
    }

    @Test func losDatosDeUsoTraenCadaTope() throws {
        let archivo = Ayudas.carpeta.appendingPathComponent("claude-\(UUID().uuidString).json")
        let json: [String: Any] = ["cachedUsageUtilization": ["fetchedAtMs": 1_793_400_000_000.0,
            "utilization": ["five_hour": ["utilization": 62, "resets_at": "2026-10-31T06:09:59Z"],
                            "seven_day": ["utilization": 31, "resets_at": "2026-11-06T14:59:59Z"]]]]
        try JSONSerialization.data(withJSONObject: json).write(to: archivo)
        let u = try #require(Agentes.datosClaude(archivo))
        #expect(u.topes.map(\.usado) == [62, 31])
        #expect(u.topes.map(\.nombre) == ["Sesión de 5 h", "Semana"])
        #expect(u.topes.allSatisfy { $0.renueva != nil })
    }

    @Test func cuentaLasSesionesDeHoyPorProyecto() throws {
        let base = Ayudas.carpeta.appendingPathComponent("proyectos-\(UUID().uuidString)")
        let fm = FileManager.default
        let dicta = base.appendingPathComponent("-tmp-proyectos-Dicta")
        let viejo = base.appendingPathComponent("-Users-ana-viejo")
        try fm.createDirectory(at: dicta, withIntermediateDirectories: true)
        try fm.createDirectory(at: viejo, withIntermediateDirectories: true)
        for i in 0..<3 {
            try #"{"type":"user","cwd":"/tmp/proyectos/Dicta","message":"secreto"}"#
                .write(to: dicta.appendingPathComponent("s\(i).jsonl"), atomically: true, encoding: .utf8)
        }
        let antiguo = viejo.appendingPathComponent("a.jsonl")
        try "{}".write(to: antiguo, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 86400)], ofItemAtPath: antiguo.path)
        let hoy = Agentes.sesionesDeHoy(base, ahora: Date())
        #expect(hoy == [Agentes.Uso.Sesiones(proyecto: "Dicta", cantidad: 3)])
    }

    // MARK: Sacudir el mouse

    // Movimientos inventados: (x, y) cada 16 ms (60 por segundo).
    private func recorrer(_ puntos: [CGPoint], _ d: inout DetectorSacudida, desde t0: TimeInterval = 100) -> Int {
        var veces = 0
        for (i, p) in puntos.enumerated() where d.mover(a: p, hora: t0 + Double(i) * 0.016) { veces += 1 }
        return veces
    }

    private func vaivenes(_ n: Int, ancho: CGFloat, pasos: Int = 6, vertical: Bool = false) -> [CGPoint] {
        var puntos: [CGPoint] = []
        for v in 0..<n {
            for k in 0...pasos {
                let x = (v % 2 == 0 ? CGFloat(k) : CGFloat(pasos - k)) * ancho / CGFloat(pasos)
                puntos.append(vertical ? CGPoint(x: 500, y: 300 + x) : CGPoint(x: 500 + x, y: 300 + CGFloat(k % 2)))
            }
        }
        return puntos
    }

    @Test func unaSacudidaAbreElMenuUnaSolaVez() {
        var d = DetectorSacudida()
        #expect(recorrer(vaivenes(6, ancho: 120), &d) == 1)
        // Enseguida otra, sin quedarse quieto: no cuenta.
        #expect(recorrer(vaivenes(6, ancho: 120), &d, desde: 100.5) == 0)
    }

    // El error del 31/10: una sacudida larga (más de 2 s) la prendía y enseguida la apagaba.
    @Test func seguirSacudiendoNoLaVuelveAApagar() {
        var d = DetectorSacudida()
        #expect(recorrer(vaivenes(20, ancho: 120), &d) == 1)
        // Después de quedarse quieto, otra sacudida sí cuenta (para apagarla).
        #expect(recorrer(vaivenes(6, ancho: 120), &d, desde: 110) == 1)
    }

    @Test func moverNormalNoEsSacudir() {
        var d = DetectorSacudida()
        // Una recta larga, ir y volver una vez, vaivenes chiquitos (apuntar) y arriba-abajo: nada.
        #expect(recorrer((0..<60).map { CGPoint(x: 100 + CGFloat($0) * 12, y: 300) }, &d) == 0)
        #expect(recorrer(vaivenes(2, ancho: 300), &d, desde: 200) == 0)
        #expect(recorrer(vaivenes(8, ancho: 12, pasos: 3), &d, desde: 300) == 0)
        #expect(recorrer(vaivenes(8, ancho: 120, vertical: true), &d, desde: 400) == 0)
    }

    @Test func lentoNoCuenta() {
        var d = DetectorSacudida()
        var veces = 0
        // Las mismas idas y vueltas, con pausas de 0,3 s entre una y otra.
        for (i, p) in vaivenes(8, ancho: 120).enumerated() where d.mover(a: p, hora: 100 + Double(i) * 0.016 + Double(i / 7) * 0.3) {
            veces += 1
        }
        #expect(veces == 0)
    }

    @Test func laSensibilidadCambiaCuantoHayQueSacudir() {
        var alta = DetectorSacudida(.alta)
        var media = DetectorSacudida(.media)
        var baja = DetectorSacudida(.baja)
        #expect(recorrer(vaivenes(4, ancho: 40), &alta) == 1)
        #expect(recorrer(vaivenes(4, ancho: 40), &media) == 0)
        #expect(recorrer(vaivenes(4, ancho: 40), &baja) == 0)
        // Media (la de siempre, desde el 31/10 más dura): con 3 idas y vueltas ya no alcanza; con 6 bien largas, sí.
        var media2 = DetectorSacudida(.media)
        #expect(recorrer(vaivenes(4, ancho: 120), &media2) == 0)
        #expect(recorrer(vaivenes(6, ancho: 120), &media2, desde: 200) == 1)
    }

    // MARK: El menú

    @Test func losPedidosDeLaVaritaSeResuelvenEnLaMacCuandoSePuede() {
        #expect(EnLaMac.entender(PedidoEscrito.traducir("en").instruccion) == .traducir(destino: "en"))
        #expect(EnLaMac.entender(PedidoEscrito.traducir("es").instruccion) == .traducir(destino: "es"))
        #expect(EnLaMac.entender(PedidoEscrito.resumir.instruccion) == nil)   // resumir lo hace la IA
    }

    @Test func conElMenuAbiertoLasTeclasLoManejan() {
        let m = MonitorAtajos()
        var vistos: [String] = []
        m.alEvento = { vistos.append("\($0)") }
        func tecla(_ c: CGKeyCode) -> CGEvent { CGEvent(keyboardEventSource: nil, virtualKey: c, keyDown: true)! }
        #expect(m.procesar(.keyDown, tecla(19)) != nil)   // cerrado: el 2 es de la app
        m.capturaMenu = true
        #expect(m.procesar(.keyDown, tecla(19)) == nil)
        #expect(m.procesar(.keyDown, tecla(125)) == nil)
        #expect(m.procesar(.keyDown, tecla(36)) == nil)
        #expect(m.procesar(.keyDown, tecla(0)) != nil)    // una "a": llega a la app y cierra el menú
        #expect(vistos == ["menu(Dixity.MonitorAtajos.TeclaMenu.numero(2))", "menu(Dixity.MonitorAtajos.TeclaMenu.abajo)",
                           "menu(Dixity.MonitorAtajos.TeclaMenu.elegir)", "menu(Dixity.MonitorAtajos.TeclaMenu.otra)"])
    }

    // MARK: Posteos

    @Test func reconoceUnPedidoDePosteo() {
        #expect(Posteos.esPedido("Armame un post para LinkedIn sobre Dixity"))
        #expect(Posteos.esPedido("Haceme el plan de contenidos de la semana para Café Luna"))
        #expect(Posteos.esPedido("un carrusel para Instagram del lanzamiento"))
        #expect(!Posteos.esPedido("Respondele que el jueves puedo"))
        #expect(!Posteos.esPedido("¿Qué dice acá?"))
    }

    @Test func encuentraLaMarcaYElProducto() throws {
        let fm = FileManager.default
        let base = Ayudas.carpeta.appendingPathComponent("mkt-\(UUID().uuidString)")
        for m in ["halyon", "cafeluna"] { try fm.createDirectory(at: base.appendingPathComponent("marcas/\(m)"), withIntermediateDirectories: true) }
        let marcas = Posteos.marcas(en: [base.path])
        #expect(Set(marcas.map(\.nombre)) == ["halyon", "cafeluna"])
        #expect(marcas.allSatisfy { $0.raiz.path == base.path })
        #expect(Posteos.elegir("un post para Instagram de cafeluna", marcas: marcas)?.nombre == "cafeluna")
        #expect(Posteos.elegir("un post para Instagram", marcas: marcas) == nil)     // hay dos: se pregunta
        // Una carpeta sin "marcas/" es la marca.
        let suelta = Ayudas.carpeta.appendingPathComponent("Cafe-\(UUID().uuidString)")
        try fm.createDirectory(at: suelta, withIntermediateDirectories: true)
        #expect(Posteos.elegir("un post", marcas: Posteos.marcas(en: [suelta.path]))?.carpeta.path == suelta.path)
        // El producto se encuentra por el título del README aunque la carpeta se llame distinto.
        let proyectos = Ayudas.carpeta.appendingPathComponent("apps-\(UUID().uuidString)")
        let dicta = proyectos.appendingPathComponent("Dicta")
        try fm.createDirectory(at: dicta, withIntermediateDirectories: true)
        try "# Dixity\n\nDictado para Mac.".write(to: dicta.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        #expect(Posteos.producto("Armame un post para LinkedIn sobre Dixity", carpetas: [proyectos.path])?.lastPathComponent == "Dicta")
    }

    @Test func partePorRedConSuLimite() {
        let s = Posteos.secciones("## LinkedIn\nLanzamos Dixity.\n#mac\n\n## X\nLanzamos Dixity 🚀\n## Imagen\nUna Mac con la píldora.")
        #expect(s.map(\.titulo) == ["LinkedIn", "X", "Imagen"])
        #expect(s[0].texto == "Lanzamos Dixity.\n#mac")
        #expect(s[1].limite == 280 && s[0].limite == 3000 && s[2].limite == nil)
        #expect(Posteos.secciones("Ojo con esto.\n## Instagram\nHola").first?.titulo == "Nota")
    }

    @Test func elPosteoSoloLeeYPuedeMirarElProducto() {
        let marca = Posteos.Marca(nombre: "halyon", carpeta: URL(fileURLWithPath: "/tmp/mkt/marcas/halyon"), raiz: URL(fileURLWithPath: "/tmp/mkt"))
        let producto = URL(fileURLWithPath: "/tmp/apps/Dicta")
        let t = Agentes.Tarea(agente: .claude, pedido: "un post", seleccion: "", carpeta: marca.raiz, extras: [producto],
                              guiaPropia: Posteos.guia(marca, producto: producto), clase: .posteo(marca: "halyon"))
        let a = Agentes.argumentos(t, hacer: false)
        #expect(a.contains("plan") && a.contains("Edit Write NotebookEdit"))
        let i = a.firstIndex(of: "--add-dir")!
        #expect(a[i + 1] == producto.path && a[i + 2].hasPrefix("--"))   // después de la carpeta va otra opción, no el pedido
        #expect(a.last == "un post")
        #expect(a.contains { $0.contains("## LinkedIn") && $0.contains("No publiques") })
        let h = Agentes.argumentos(t, hacer: true, plan: "## X\nHola")
        #expect(h.contains { $0.contains("/tmp/mkt/marcas/halyon/organico") })
        #expect(!h.contains("bypassPermissions") && !h.contains("--dangerously-skip-permissions"))
    }

    @Test func alPreguntarDiceSobreQueVaATrabajar() {
        #expect(Motor.sobreQue(seleccion: "uno dos tres", ajustando: false, app: "Mail") == "Sobre 3 palabras")
        #expect(Motor.sobreQue(seleccion: "", ajustando: false, app: "Safari") == "Sin selección · Safari")
        #expect(Motor.sobreQue(seleccion: "hola", ajustando: true, app: "Mail") == "Ajustando la respuesta")
    }
}
