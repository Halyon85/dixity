import AppKit
import ServiceManagement
import SwiftUI

@main
enum Principal {
    // Modos de prueba que usan permisos de macOS o claves de API (los demás solo dibujan o calculan).
    static let modosConPermisos: Set<String> = ["--importar-claves", "--diagnostico-campo", "--probar-dictado",
        "--probar-reescritura", "--probar-estilo", "--probar-trabajo", "--medir", "--probar-pegado", "--probar-pantalla",
        "--actualizar-memoria", "--probar-microfono", "--diagnostico-permisos", "--descargar-modelo"]

    static func modoConPermisos(_ argumentos: [String]) -> String? {
        argumentos.dropFirst().first { modosConPermisos.contains($0) }
    }

    // Ventanita "¿Permitir?" antes de un modo de prueba con permisos. Devuelve si la persona tocó Permitir.
    static func confirmar(_ modo: String) -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)
        let alerta = NSAlert()
        alerta.messageText = T("¿Permitir el modo de prueba \(modo)?", "Allow the test mode \(modo)?")
        alerta.informativeText = T("Algo pidió abrir Dixity en un modo de prueba que usa tus permisos (pantalla, accesibilidad o micrófono) o tus claves de API. Si no lo abriste vos desde la Terminal, tocá Cancelar.",
                                   "Something asked to open Dixity in a test mode that uses your permissions (screen, accessibility or microphone) or your API keys. If you didn't start it yourself from Terminal, click Cancel.")
        alerta.addButton(withTitle: T("Permitir", "Allow"))
        alerta.addButton(withTitle: T("Cancelar", "Cancel"))
        return alerta.runModal() == .alertFirstButtonReturn
    }

    static func main() {
        let app = NSApplication.shared
        Ajustes.soloLectura = CommandLine.arguments.dropFirst().contains { $0.hasPrefix("--") }
        // Los modos de prueba que usan tus permisos (pantalla, accesibilidad, micrófono) o tus claves preguntan antes:
        // cualquier programa podía abrir Dixity con ellos y leer tu pantalla, pegar texto o gastar tus claves sin que
        // te enteraras (auditoría de seguridad del 23/10/2026). Un programa no puede tocar el botón por vos.
        if let modo = Principal.modoConPermisos(CommandLine.arguments), !Principal.confirmar(modo) {
            print(T("Cancelado: no se permitió \(modo).", "Canceled: \(modo) was not allowed."))
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--capturas"), i + 1 < CommandLine.arguments.count {
            app.setActivationPolicy(.accessory)
            Capturas.hacer(en: CommandLine.arguments[i + 1])
            return
        }
        // `Dixity --importar-claves <archivo .env>`: guarda en el llavero (como dueña) las claves que encuentre.
        if let i = CommandLine.arguments.firstIndex(of: "--importar-claves"), i + 1 < CommandLine.arguments.count {
            let mapa = ["OPENAI_API_KEY": "openai", "XAI_API_KEY": "xai", "ANTHROPIC_API_KEY": "anthropic",
                        "GROQ_API_KEY": "groq", "OPENROUTER_API_KEY": "openrouter"]
            let texto = (try? String(contentsOfFile: CommandLine.arguments[i + 1], encoding: .utf8)) ?? ""
            for linea in texto.split(separator: "\n") {
                let partes = linea.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard partes.count == 2, let cuenta = mapa[partes[0]] else { continue }
                let valor = partes[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                Llavero.guardar(cuenta, valor)
                print("\(cuenta): \(Llavero.leer(cuenta).isEmpty ? "error" : "guardada")")
            }
            return
        }
        // `Dixity --demo-pildora`: muestra la píldora grabando 40 s con una onda simulada (sin micrófono) para revisarla.
        if CommandLine.arguments.contains("--demo-pildora") {
            app.setActivationPolicy(.accessory)
            let p = PanelPildora()
            p.modelo.trabajo = CommandLine.arguments.contains("--trabajo")
            p.alCancelar = { print("✕ cancelar"); p.mostrar(.aviso(T("Cancelado", "Canceled")), durante: 1.5) }
            p.alTerminar = { print("✓ terminar"); p.mostrar(.procesando); DispatchQueue.main.asyncAfter(deadline: .now() + 3) { p.mostrar(.listo(T("Listo", "Done")), durante: 2) } }
            p.mostrar(.grabando, modo: .dictado)
            var t = 0.0
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                t += 0.05
                let habla = sin(t * 1.3) > -0.3
                p.modelo.nivel(Float(habla ? 0.35 + 0.45 * abs(sin(t * 9)) * abs(sin(t * 2.3)) : 0.02))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 40) { exit(0) }
            app.run()
            return
        }
        // `Dixity --diagnostico-campo`: dice qué ve Dicta en la app de adelante (útil para apps que no pegan).
        if CommandLine.arguments.contains("--diagnostico-campo") {
            for vuelta in 1...2 {
                let c = Cursor.capturar(conTexto: true)
                print("vuelta \(vuelta): app=\(c.app) campo=\(c.campo) editable=\(c.editable) hayCampo=\(c.hayCampo) antes=\(c.antes.suffix(40).debugDescription)")
                Thread.sleep(forTimeInterval: 1.5)
            }
            return
        }
        // `Dixity --probar-trabajo "<transcripción>"`: muestra cómo queda el prompt del modo Trabajo.
        // `--probar-dictado audio.wav [estilo]`: el camino completo de un dictado (voz → limpieza → barrera) con los ajustes actuales.
        if let i = CommandLine.arguments.firstIndex(of: "--probar-dictado"), i + 1 < CommandLine.arguments.count,
           let wav = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1])) {
            let estilo = (i + 2 < CommandLine.arguments.count ? Estilo(rawValue: CommandLine.arguments[i + 2]) : nil) ?? .comun
            let d = Ajustes.shared.datos
            print("voz: \(d.proveedorVoz.nombre) · IA: \(d.proveedorIA.nombre) \(d.modeloIA) · modo: \(estilo.corto)")
            Task {
                let p = Motor.Pedido(wav: wav, segundos: Double(wav.count - 44) / 32_000, accion: .dictar, contexto: nil,
                                     seleccion: "", estilo: estilo, audio: nil)
                do {
                    let r = try await Motor.procesar(p)
                    print("voz \(r.registro.msVoz) ms · IA \(r.registro.msIA) ms · usó IA: \(r.registro.usoIA)\(r.registro.barrera.map { " · barrera: \($0)" } ?? "")")
                    print(r.texto)
                } catch { print("error: \(error.localizedDescription)") }
                exit(0)
            }
            RunLoop.main.run()
        }
        // `--probar-reescritura "selección" "instrucción"`: lo mismo que seleccionar texto y usar Reescribir.
        if let i = CommandLine.arguments.firstIndex(of: "--probar-reescritura"), i + 2 < CommandLine.arguments.count {
            let sel = CommandLine.arguments[i + 1], instr = CommandLine.arguments[i + 2]
            Task {
                let u = Prompts.usuarioReescritura(seleccion: sel, instruccion: instr, contexto: nil, terminos: [])
                do { print(Prompts.limpiarSalida(try await Proveedores.completar(sistema: Prompts.sistemaReescritura, usuario: u, ajustes: .shared))) }
                catch { print("error: \(error.localizedDescription)") }
                exit(0)
            }
            RunLoop.main.run()
        }
        // `--probar-limpieza "texto" …`: la limpieza básica sin IA (muletillas y marcas), una línea por texto.
        if let i = CommandLine.arguments.firstIndex(of: "--probar-limpieza") {
            for texto in CommandLine.arguments.dropFirst(i + 1) { print("«\(texto)» → «\(Prompts.arreglarCorto(Prompts.limpiezaBasica(texto)))»") }
            return
        }
        // `--probar-estilo <comun|correo|mensaje|formal|traducir> "texto"`: pasa el texto por ese modo (o por el que diga la frase).
        if let i = CommandLine.arguments.firstIndex(of: "--probar-estilo"), i + 2 < CommandLine.arguments.count,
           let elegido = Estilo(rawValue: CommandLine.arguments[i + 1]) {
            var texto = CommandLine.arguments[i + 2]
            var estilo = elegido
            var idioma = Ajustes.shared.idiomaDestino
            if let d = Prompts.estiloDicho(texto) {
                print("frase detectada → \(d.estilo.corto)\(d.idioma.map { " (\($0))" } ?? "") · queda: \(d.texto)")
                texto = d.texto; estilo = d.estilo; idioma = d.idioma ?? idioma
            }
            Task {
                let u = Prompts.usuarioDictado(transcripcion: texto, contexto: nil, estilo: estilo, idioma: idioma, terminos: [], extra: Ajustes.shared.datos.instruccionesExtra)
                do {
                    let r = Prompts.limpiarSalida(try await Proveedores.completar(sistema: Prompts.sistemaDictado, usuario: u, ajustes: .shared))
                    print(r)
                    print("barrera: \(Prompts.barrera(transcripcion: texto, salida: r, estilo: estilo) ?? "pasa")")
                } catch { print("error: \(error.localizedDescription)") }
                exit(0)
            }
            RunLoop.main.run()
        }
        if let i = CommandLine.arguments.firstIndex(of: "--probar-trabajo"), i + 1 < CommandLine.arguments.count {
            // DIXITY_PANTALLA=<archivo> simula el texto de la pantalla; DIXITY_RECIENTES=1 suma los dictados recientes.
            let texto = CommandLine.arguments[i + 1]
            let entorno = ProcessInfo.processInfo.environment
            let pantalla = entorno["DIXITY_PANTALLA"].flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
            // Los recientes son de una app (como al dictar): la del último dictado del historial.
            let ultimaApp = Historial.shared.registros.first?.app ?? ""
            let recientes = entorno["DIXITY_RECIENTES"] == "1" ? Historial.shared.recientes(4, app: ultimaApp, minutos: 100_000) : []
            Task {
                let u = Prompts.usuarioTrabajo(transcripcion: texto, contexto: nil, pantalla: pantalla, proyecto: nil, recientes: recientes,
                                               terminos: Diccionario.shared.paraPrompt(transcripcion: texto), extra: "")
                do {
                    let r = Prompts.limpiarSalida(try await Proveedores.completar(sistema: Prompts.sistemaTrabajo, usuario: u, ajustes: .shared))
                    print(r)
                    let ajeno = ([pantalla] + recientes.map(\.final)).joined(separator: "\n")
                    print("barrera: \(Prompts.barrera(transcripcion: texto, salida: r, trabajo: true, ajeno: ajeno) ?? "pasa")")
                }
                catch { print("error: \(error.localizedDescription)") }
                exit(0)
            }
            RunLoop.main.run()
        }
        // `--probar-barrera`: pasa los dictados del historial que usaron IA por la barrera de hoy y muestra los que frena.
        if CommandLine.arguments.contains("--probar-barrera") {
            var frena = 0, total = 0
            for r in Historial.shared.registros where r.usoIA && r.modo == .dictado && r.reprocesoDe == nil {
                total += 1
                let e = Estilo.desde(corto: r.estilo) ?? .comun
                guard let motivo = Prompts.barrera(transcripcion: r.transcripcion, salida: r.final, trabajo: e == .trabajo, estilo: e) else { continue }
                frena += 1
                print("[\(r.estilo ?? "")] \(motivo)\n  dijo: \(r.transcripcion.prefix(160))\n  salió: \(r.final.prefix(160))\n")
            }
            print("frena \(frena) de \(total)")
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--medir"), i + 1 < CommandLine.arguments.count {
            let ruta = CommandLine.arguments[i + 1]
            Task {
                await Medir.correr(ruta)
                // DICTA_ESPERAR=1: queda viva 30 s al final para revisar fugas con `leaks`.
                if ProcessInfo.processInfo.environment["DICTA_ESPERAR"] != nil {
                    print("LISTO_PARA_REVISAR"); fflush(stdout)
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                }
                exit(0)
            }
            RunLoop.main.run()
        }
        // `--probar-pegado "texto"`: a los 3 s pega el texto donde esté el cursor y dice si entró (para revisar el pegado).
        if let i = CommandLine.arguments.firstIndex(of: "--probar-pegado"), i + 1 < CommandLine.arguments.count {
            let texto = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
                Cursor.pegar(texto) { r in
                    print("\(app): \(r) · portapapeles ahora: \(NSPasteboard.general.string(forType: .string) ?? "(nada)")")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        print("después: \(NSPasteboard.general.string(forType: .string) ?? "(nada)")"); exit(0)
                    }
                }
            }
            RunLoop.main.run()
        }
        // `--probar-pantalla`: a los 3 s lee la ventana de adelante y dice cuánto tardó, qué leyó y la memoria usada.
        if CommandLine.arguments.contains("--probar-pantalla") {
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let app = NSWorkspace.shared.frontmostApplication else { exit(1) }
                print("Permiso de grabación de pantalla: \(Pantalla.permitido ? "sí" : "no") · app: \(app.localizedName ?? "?")")
                for vuelta in 1...2 {
                    let t = Date()
                    let texto = await Pantalla.leer(pid: app.processIdentifier)
                    print("vuelta \(vuelta): \(Int(Date().timeIntervalSince(t) * 1000)) ms, \(texto.count) caracteres, memoria \(Medir.memoriaMB()) MB")
                    if vuelta == 1 { print(texto.prefix(400)) }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                print("2 s después: memoria \(Medir.memoriaMB()) MB")
                exit(0)
            }
            RunLoop.main.run()
        }
        // `--actualizar-memoria`: arma la memoria propia con los últimos dictados y la muestra.
        if CommandLine.arguments.contains("--actualizar-memoria") {
            Memoria.shared.actualizar { error in
                print(error.map { "error: \($0)" } ?? Memoria.shared.texto)
                exit(0)
            }
            RunLoop.main.run()
        }
        // `--probar-microfono <archivo> [identificador…]`: graba 1,5 s con cada micrófono ("" = el de la Mac) y anota
        // con cuál grabó y cuánto audio llegó; el audio se descarta. Abrirla con `open -n` para usar el permiso de Dixity.
        if let i = CommandLine.arguments.firstIndex(of: "--probar-microfono"), i + 1 < CommandLine.arguments.count {
            var l: [String] = []
            for uid in [""] + CommandLine.arguments.dropFirst(i + 2) {
                let g = Grabador()
                var pico: Float = 0
                g.alNivel = { pico = max(pico, $0) }
                do {
                    try g.empezar(microfono: uid)
                    let usado = Microfonos.nombre(g.dispositivo)
                    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
                    let r = g.terminar()
                    l.append("pedido «\(uid)» → grabó con \(usado) · \(String(format: "%.2f", r.segundos)) s · nivel máx. \(String(format: "%.2f", pico))")
                } catch { l.append("pedido «\(uid)» → error: \(error.localizedDescription)") }
            }
            try? l.joined(separator: "\n").write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
            return
        }
        // `--diagnostico-permisos <archivo>`: anota los permisos que macOS le da a esta app (abrirla con `open -n`
        // para que cuenten los suyos y no los de la terminal) y si llegan teclas comunes durante 8 s.
        if let i = CommandLine.arguments.firstIndex(of: "--diagnostico-permisos"), i + 1 < CommandLine.arguments.count {
            let destino = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            var l = ["Accesibilidad: \(AXIsProcessTrusted())", "Monitoreo de entrada: \(CGPreflightListenEventAccess())",
                     "Enviar teclas: \(CGPreflightPostEventAccess())", "Pantalla: \(CGPreflightScreenCaptureAccess())"]
            var teclas = 0, modificadores = 0
            let mascara = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            let cuenta = UnsafeMutablePointer<(Int, Int)>.allocate(capacity: 1); cuenta.pointee = (0, 0)
            let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                        eventsOfInterest: CGEventMask(mascara), callback: { _, tipo, e, ref in
                let c = ref!.assumingMemoryBound(to: (Int, Int).self)
                if tipo == .keyDown { c.pointee.0 += 1 } else if tipo == .flagsChanged { c.pointee.1 += 1 }
                return Unmanaged.passUnretained(e)
            }, userInfo: cuenta)
            l.append("Escucha del teclado creada: \(tap != nil)")
            if let tap {
                CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                teclas = cuenta.pointee.0; modificadores = cuenta.pointee.1
                l.append("En 8 s llegaron: \(teclas) teclas comunes y \(modificadores) cambios de modificadores")
                try? l.joined(separator: "\n").write(to: destino, atomically: true, encoding: .utf8)
                exit(0)
            }
            RunLoop.main.run()
        }
        // `--probar-teclas`: pasa por el detector de atajos las mismas teclas que manda el teclado y muestra qué entiende.
        if CommandLine.arguments.contains("--probar-teclas") {
            let m = MonitorAtajos()
            let d = Ajustes.shared.datos
            m.atajos = [.dictar: d.atajoDictar, .reescribir: d.atajoReescribir, .portapapeles: d.atajoPortapapeles,
                        .reprocesar: d.atajoReprocesar, .sumarPalabra: d.atajoSumarPalabra, .preguntar: d.atajoPreguntar]
            m.atajosNumero = d.atajosNumero
            m.familiasModos = d.teclaModos.familias
            var vistos: [String] = []
            m.alEvento = { vistos.append("\($0)") }
            func mod(_ x: Modificador, _ abajo: Bool, _ resto: Set<Modificador>) {
                let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(x.codigo), keyDown: abajo)!
                e.type = .flagsChanged
                var f: UInt64 = 0
                for r in resto.union(abajo ? [x] : []) { f |= r.mascara | (r.familia == "ctrl" ? 0x40000 : r.familia == "opcion" ? 0x80000 : r.familia == "shift" ? 0x20000 : r.familia == "cmd" ? 0x100000 : 0x800000) }
                e.flags = CGEventFlags(rawValue: f)
                _ = m.procesar(.flagsChanged, e)
            }
            func tecla(_ c: CGKeyCode) {
                for abajo in [true, false] {
                    let e = CGEvent(keyboardEventSource: nil, virtualKey: c, keyDown: abajo)!
                    _ = m.procesar(abajo ? .keyDown : .keyUp, e)
                }
            }
            func caso(_ nombre: String, _ hacer: () -> Void) { vistos = []; hacer(); print("\(nombre): \(vistos.isEmpty ? "nada" : vistos.joined(separator: ", "))") }
            caso("⌃⌥ izq + 3") { mod(.ctrlIzq, true, []); mod(.opcionIzq, true, [.ctrlIzq]); tecla(20); mod(.opcionIzq, false, [.ctrlIzq]); mod(.ctrlIzq, false, []) }
            caso("⌃ izq + ⌥ der + 2") { mod(.ctrlIzq, true, []); mod(.opcionDer, true, [.ctrlIzq]); tecla(19); mod(.opcionDer, false, [.ctrlIzq]); mod(.ctrlIzq, false, []) }
            caso("⌥ der (dictar)") { mod(.opcionDer, true, []); mod(.opcionDer, false, []) }
            caso("⇧ der + ⌃ der (reescribir)") { mod(.shiftDer, true, []); mod(.ctrlDer, true, [.shiftDer]); mod(.ctrlDer, false, [.shiftDer]); mod(.shiftDer, false, []) }
            caso("⌃ izq + C (portapapeles)") { mod(.ctrlIzq, true, []); tecla(8); mod(.ctrlIzq, false, []) }
            caso("⌃⌥ izq + R (volver a procesar)") { mod(.ctrlIzq, true, []); mod(.opcionIzq, true, [.ctrlIzq]); tecla(15); mod(.opcionIzq, false, [.ctrlIzq]); mod(.ctrlIzq, false, []) }
            caso("⌃⌥ izq + D (sumar al diccionario)") { mod(.ctrlIzq, true, []); mod(.opcionIzq, true, [.ctrlIzq]); tecla(2); mod(.opcionIzq, false, [.ctrlIzq]); mod(.ctrlIzq, false, []) }
            exit(0)
        }
        // `--descargar-modelo ultra|v3`: baja ese Parakeet a la carpeta de Dicta (lo mismo que el botón de Proveedores).
        if let i = CommandLine.arguments.firstIndex(of: "--descargar-modelo"), i + 1 < CommandLine.arguments.count,
           let m = ModeloLocal(rawValue: CommandLine.arguments[i + 1]) {
            Task {
                let t = Date()
                do { try await Parakeet.descargar(m); print("Listo: \(m.nombre) en \(Int(Date().timeIntervalSince(t))) s") }
                catch { print("error: \(error.localizedDescription)") }
                exit(0)
            }
            RunLoop.main.run()
        }
        let delegado = Delegado()
        app.delegate = delegado
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class Delegado: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let motor = Motor()
    let navegacion = Navegacion()
    let ventanaPortapapeles = VentanaPortapapeles()
    private var item: NSStatusItem!
    private var ventana: NSWindow?
    private var reintento: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        FlechaVarita.revisarAlAbrir()     // si la última vez quedó la flecha de la Varita puesta, vuelve la original
        DispatchQueue.global(qos: .utility).async { Mandar.borrarViejas() }   // lo de más de un día que se pasó a Claude o Codex
        Llavero.mudarDelServicioViejo()     // antes de mirar si faltan claves
        crearMenu()
        aplicarApariencia()
        Actualizaciones.arrancar()      // solo las versiones publicadas buscan, una vez por día (ver Actualizaciones)
        motor.alternarPortapapeles = { [weak self] in self?.ventanaPortapapeles.alternar() }
        aplicarPortapapeles()
        Ajustes.shared.alCambiar = { [weak self] in
            self?.aplicarPortapapeles()
            self?.motor.actualizarAtajos()
            self?.aplicarApariencia()
            self?.actualizarMenu()
        }
        motor.abrirPanel = { [weak self] pagina in self?.abrirPanel(pagina) }
        arrancarTeclado()
        let centro = NSWorkspace.shared.notificationCenter
        centro.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.motor.antesDeDormir()
            self?.ventanaPortapapeles.cerrar()
            Portapapeles.shared.detener()
        }
        centro.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.motor.alBloquear()
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.motor.alBloquear()
        }
        centro.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Un respiro para que vuelvan el audio y la sesión antes de rearmar todo.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let self else { return }
                self.motor.alDespertar()
                self.aplicarPortapapeles()
                self.actualizarMenu()
            }
        }
        // Primera vez: la bienvenida guía permisos y proveedores. Si falta algo después, se abre el panel.
        if !Ajustes.shared.datos.bienvenidaVista {
            abrirPanel(nil)
            navegacion.bienvenida = true
        } else if Ajustes.shared.faltanClaves || !Cursor.accesibilidadPermitida || !Grabador.permitido {
            abrirPanel(Ajustes.shared.faltanClaves ? "proveedores" : "general")
        }
    }

    private func aplicarPortapapeles() {
        if Ajustes.shared.datos.portapapelesActivo { Portapapeles.shared.arrancar() } else { Portapapeles.shared.detener() }
    }

    // Sin permiso de Accesibilidad no se puede escuchar el teclado; reintenta hasta que lo den.
    private func arrancarTeclado() {
        if motor.arrancarTeclado() { reintento?.invalidate(); actualizarMenu(); return }
        guard reintento == nil else { return }
        reintento = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Cursor.accesibilidadPermitida, self.motor.arrancarTeclado() {
                self.reintento?.invalidate(); self.reintento = nil
                self.actualizarMenu()
            }
        }
    }

    private func crearMenu() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            // El logo (la "d" que termina en onda) en versión plantilla: macOS lo pinta claro u oscuro según la barra.
            let img = NSImage(named: "BarraMenu") ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "Dixity")
            if let img, img.name() == "BarraMenu" {
                let alto: CGFloat = 17
                img.size = NSSize(width: (img.size.width / img.size.height * alto).rounded(), height: alto)
            }
            img?.isTemplate = true
            img?.accessibilityDescription = "Dixity"
            b.image = img
        }
        actualizarMenu()
    }

    private func actualizarMenu() {
        let m = NSMenu()
        let estado = NSMenuItem(title: motor.monitor.activo ? T("Dixity · Lista", "Dixity · Ready") : T("Dixity · Falta permiso de Accesibilidad", "Dixity · Accessibility access needed"),
                                action: nil, keyEquivalent: "")
        estado.isEnabled = false
        m.addItem(estado)
        let d = Ajustes.shared.datos
        let info = NSMenuItem(title: T("Dictar: \(d.atajoDictar.descripcion)   ·   Reescribir: \(d.atajoReescribir.descripcion)",
                                    "Dictate: \(d.atajoDictar.descripcion)   ·   Rewrite: \(d.atajoReescribir.descripcion)"), action: nil, keyEquivalent: "")
        info.isEnabled = false
        m.addItem(info)
        m.addItem(.separator())
        m.addItem(withTitle: T("Abrir Dixity…", "Open Dixity…"), action: #selector(abrirInicio), keyEquivalent: ",").target = self
        m.addItem(withTitle: T("Copiar el último resultado", "Copy last result"), action: #selector(copiarUltimo), keyEquivalent: "").target = self
        m.addItem(withTitle: T("Volver a procesar el último dictado (\(d.atajoReprocesar.descripcion))", "Process last dictation again (\(d.atajoReprocesar.descripcion))"),
                  action: #selector(reprocesarUltimo), keyEquivalent: "").target = self
        if d.portapapelesActivo {
            m.addItem(withTitle: T("Portapapeles (\(d.atajoPortapapeles.descripcion))", "Clipboard (\(d.atajoPortapapeles.descripcion))"), action: #selector(abrirPortapapeles), keyEquivalent: "").target = self
        }
        let estilo = NSMenuItem(title: T("Estilo", "Style"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        // Automático y los modos visibles en tu orden (más el elegido, si lo ocultaste).
        let visibles = [Estilo.automatico] + Ajustes.shared.modosActivos
        for e in visibles + (visibles.contains(d.estilo) ? [] : [d.estilo]) {
            let n = Ajustes.shared.modosActivos.firstIndex(of: e).map { "   \(d.teclaModos.simbolo)\($0 + 1)" } ?? ""
            let it = NSMenuItem(title: e.nombre + (d.atajosNumero ? n : ""), action: #selector(elegirEstilo(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = e.rawValue
            it.state = d.estilo == e ? .on : .off
            sub.addItem(it)
        }
        estilo.submenu = sub
        m.addItem(estilo)
        m.addItem(withTitle: T("Historial", "History"), action: #selector(abrirHistorial), keyEquivalent: "").target = self
        if Actualizaciones.disponibles {
            m.addItem(withTitle: T("Buscar actualizaciones…", "Check for Updates…"), action: #selector(buscarActualizaciones), keyEquivalent: "").target = self
        }
        m.addItem(.separator())
        m.addItem(withTitle: T("Salir de Dixity", "Quit Dixity"), action: #selector(salir), keyEquivalent: "q").target = self
        item.menu = m
    }

    @objc private func abrirInicio() { abrirPanel(nil) }
    @objc private func abrirHistorial() { abrirPanel("historial") }
    @objc private func copiarUltimo() { motor.copiarUltimo() }
    @objc private func reprocesarUltimo() { motor.reprocesarUltimo() }
    @objc private func abrirPortapapeles() { ventanaPortapapeles.abrir() }
    @objc private func buscarActualizaciones() { Actualizaciones.buscar() }
    @objc private func elegirEstilo(_ it: NSMenuItem) {
        if let r = it.representedObject as? String, let e = Estilo(rawValue: r) { Ajustes.shared.datos.estilo = e }
    }
    @objc private func salir() { NSApp.terminate(nil) }

    func abrirPanel(_ pagina: String?) {
        if let p = pagina, let destino = Pagina(rawValue: p) { navegacion.pagina = destino }
        if ventana == nil {
            let raiz = VistaPanel(motor: motor, ajustes: .shared, navegacion: navegacion,
                                  pedirTeclado: { [weak self] in self?.arrancarTeclado() })
            let v = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            v.titlebarAppearsTransparent = true
            v.titleVisibility = .hidden
            v.isMovableByWindowBackground = true
            v.minSize = NSSize(width: 760, height: 520)
            v.contentView = NSHostingView(rootView: raiz)
            v.isReleasedWhenClosed = false
            v.delegate = self
            v.center()
            v.setFrameAutosaveName("PanelDicta")
            ventana = v
        }
        NSApp.setActivationPolicy(.regular)
        ventana?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Al cerrar el panel se libera entero (vistas, superficies de dibujo y relojes): no queda nada en memoria.
    func windowWillClose(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async { [weak self] in
            self?.ventana?.contentView = nil
            self?.ventana?.delegate = nil
            self?.ventana = nil
        }
    }

    // Al cerrar Dixity, la flecha vuelve a la de macOS (si la Varita estaba prendida).
    func applicationWillTerminate(_ n: Notification) {
        motor.varita.apagar()
    }

        func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        abrirPanel(nil)
        return true
    }

    private func aplicarApariencia() {
        switch Ajustes.shared.datos.apariencia {
        case .sistema: NSApp.appearance = nil
        case .claro: NSApp.appearance = NSAppearance(named: .aqua)
        case .oscuro: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum InicioSesion {
    static var activo: Bool { SMAppService.mainApp.status == .enabled }
    static var esperaAprobacion: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func cambiar(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Dixity: no pude cambiar el inicio de sesión: \(error)")
        }
    }
}
