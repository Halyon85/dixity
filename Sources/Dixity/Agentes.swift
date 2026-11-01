import Foundation

// Claude Code y Codex por voz, con el atajo de Preguntar (⌃⌥P). "Claude, …" o "Codex, …" le pasa el pedido al agente en
// la carpeta del proyecto, sin ventana y con tu suscripción (los programas de la Mac, no la API). Primero solo mira y
// responde: Claude en modo plan y Codex en solo lectura. Editar archivos es solo con el botón Hacelo de la ventanita.
// "¿Cuánto me queda de Claude?" se responde con lo que cada herramienta guarda en la Mac, sin IA ni internet.
enum Agente: String {
    case claude, codex
    var nombre: String { self == .claude ? "Claude" : "Codex" }

    // Cómo suele escribir la voz a texto cada nombre ("cloud" es lo más común para Claude).
    private static let nombres: [String: Agente] = ["claude": .claude, "cloud": .claude, "clod": .claude, "clode": .claude,
        "claud": .claude, "cloude": .claude, "codex": .codex, "kodex": .codex, "codec": .codex, "codecs": .codex]
    static func de(_ palabra: String) -> Agente? { nombres[Diccionario.normalizar(palabra)] }

    // "Claude, ¿qué hace Motor?" → (.claude, "¿qué hace Motor?"). Solo si el nombre va primero ("che"/"hey" antes vale).
    static func detectar(_ pedido: String) -> (agente: Agente, resto: String)? {
        var palabras = pedido.split(whereSeparator: \.isWhitespace).map(String.init)
        if let p = palabras.first, ["che", "hey", "ey", "oye"].contains(Diccionario.normalizar(p)) { palabras.removeFirst() }
        guard let primera = palabras.first, let a = de(primera) else { return nil }
        let resto = palabras.dropFirst().joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.:;-—").union(.whitespaces))
        guard resto.split(whereSeparator: \.isWhitespace).count >= 2 else { return nil }
        return (a, resto)
    }

    // "¿Cuánto me queda de Claude?", "Codex, ¿cuánto límite me queda?". Si el pedido arranca con el nombre y es largo,
    // es una tarea ("Claude, arreglá el límite de caracteres del login"), no una consulta.
    static func consulta(_ pedido: String) -> Agente? {
        let p = Diccionario.normalizar(pedido).split(separator: " ").map(String.init)
        let claves: Set = ["queda", "quedan", "limite", "limites", "consumi", "consumo", "gaste", "usaste", "left", "remaining", "usage"]
        guard p.count <= 12, p.contains(where: claves.contains), let i = p.firstIndex(where: { de($0) != nil }) else { return nil }
        guard i > 0 || p.count <= 6 else { return nil }
        return de(p[i])
    }

    // Para la tarjeta de uso: los dos si nombrás a los dos ("¿cuánto me queda de Claude y Codex?") o si preguntás por
    // tus límites en general ("¿cuánto uso me queda?"); si no, el que nombraste. nil: no es una consulta de uso.
    static func consultaUso(_ pedido: String) -> [Agente]? {
        let p = Diccionario.normalizar(pedido)
        let palabras = p.split(separator: " ").map(String.init)
        let nombrados = Set(palabras.compactMap { de($0) })
        let general = ["cuanto uso me queda", "cuanto me queda de uso", "mis limites", "how much usage", "my limits"]
        if palabras.count <= 12, general.contains(where: { p.contains($0) }) && nombrados.isEmpty { return [.claude, .codex] }
        guard let uno = consulta(pedido) else { return nil }
        return nombrados.count == 2 ? [.claude, .codex] : [uno]
    }
}

enum Agentes {
    // Un pedido para Claude o Codex. `sesion`: la conversación de Claude a la que vuelve Hacelo (ya revisó el proyecto).
    struct Tarea {
        var agente: Agente
        var pedido: String
        var seleccion: String
        var carpeta: URL
        var sesion: String? = nil
        var extras: [URL] = []                              // otras carpetas que puede leer (el producto, en un posteo)
        var guiaPropia: (leer: String, hacer: String)? = nil  // en vez de la guía de siempre (Posteos)
        var clase = Respuestas.Clase.agente                 // la forma de la tarjeta de su respuesta
        var imagenes: [URL] = []                            // lo que le mostrás con la Varita (PNG en la carpeta de Mandar)
    }

    struct ErrorAgente: LocalizedError {
        let mensaje: String
        var errorDescription: String? { mensaje }
    }

    static let topeLectura: TimeInterval = 5 * 60
    static let topeHacer: TimeInterval = 15 * 60

    // MARK: Cuánto te queda

    // Lo que informó cada herramienta: un tope por barra (la sesión de 5 horas, la semana…). La tarjeta de uso lo
    // dibuja y la frase del historial sale de lo mismo, así nunca dicen cosas distintas.
    struct Uso: Equatable {
        struct Tope: Equatable {
            var nombre: String      // "Sesión de 5 h", "Semana": el rótulo de la barra
            var cual: String        // "de la sesión de 5 horas": para la frase
            var usado: Int          // porcentaje usado
            var renueva: Date?
        }
        struct Sesiones: Equatable {
            var proyecto: String
            var cantidad: Int
        }
        var agente: Agente
        var topes: [Tope] = []
        var leido: Date?
        var hoy: [Sesiones] = []    // solo Claude: las conversaciones de hoy por proyecto
    }

    static func uso(_ a: Agente, ahora: Date = Date()) -> String {
        datos(a).map { frase($0, ahora: ahora) } ?? sinDato(a)
    }

    // Los datos de cada uno, leídos de la Mac (sin IA ni internet). nil si la herramienta no dejó nada.
    static func datos(_ a: Agente, ahora: Date = Date()) -> Uso? {
        let casa = FileManager.default.homeDirectoryForCurrentUser
        guard a == .claude else { return datosCodex(casa.appendingPathComponent(".codex/sessions")) }
        var u = datosClaude(casa.appendingPathComponent(".claude.json"))
        u?.hoy = sesionesDeHoy(casa.appendingPathComponent(".claude/projects"), ahora: ahora)
        return u
    }

    static func usoClaude(_ archivo: URL, ahora: Date) -> String {
        datosClaude(archivo).map { frase($0, ahora: ahora) } ?? sinDato(.claude)
    }

    static func usoCodex(_ carpeta: URL, ahora: Date) -> String {
        datosCodex(carpeta).map { frase($0, ahora: ahora) } ?? sinDato(.codex)
    }

    static func sinDato(_ a: Agente) -> String {
        a == .claude ? T("No encontré cuánto usaste de Claude: abrí Claude Code un momento y volvé a preguntar.",
                         "Couldn't find your Claude usage: open Claude Code for a moment and ask again.")
                     : T("No encontré cuánto usaste de Codex: usalo una vez y volvé a preguntar.",
                         "Couldn't find your Codex usage: use it once and ask again.")
    }

    // "Claude: usaste 4 % de la sesión de 5 horas (se renueva hoy a las 03:09) y 12 % de la semana (…). Dato de hace…"
    static func frase(_ u: Uso, ahora: Date) -> String {
        guard !u.topes.isEmpty else { return T("\(u.agente.nombre) no informó cuánto usaste.", "\(u.agente.nombre) didn't report your usage.") }
        let partes = u.topes.map { "\($0.usado) % \($0.cual)" + renueva($0.renueva, ahora: ahora) }
        return T("\(u.agente.nombre): usaste ", "\(u.agente.nombre): you've used ") + partes.joined(separator: T(" y ", " and ")) + "."
            + hace(u.leido, ahora: ahora)
    }

    // Claude Code guarda en ~/.claude.json lo último que le informó el servidor (no es un formato oficial: si cambia,
    // se avisa que no se encontró). Se lee solo esa parte.
    static func datosClaude(_ archivo: URL) -> Uso? {
        guard let d = try? Data(contentsOf: archivo),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let c = j["cachedUsageUtilization"] as? [String: Any], let u = c["utilization"] as? [String: Any] else { return nil }
        var uso = Uso(agente: .claude, leido: (c["fetchedAtMs"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) })
        let topes = [("five_hour", T("Sesión de 5 h", "5-hour session"), T("de la sesión de 5 horas", "of the 5-hour session")),
                     ("seven_day", T("Semana", "Week"), T("de la semana", "of the week")),
                     ("seven_day_opus", T("Semana · Opus", "Week · Opus"), T("de la semana de Opus", "of the Opus week"))]
        for (clave, nombre, cual) in topes {
            guard let s = u[clave] as? [String: Any], let pct = (s["utilization"] as? NSNumber)?.intValue else { continue }
            uso.topes.append(.init(nombre: nombre, cual: cual, usado: pct, renueva: fechaISO(s["resets_at"] as? String)))
        }
        return uso
    }

    // Codex anota su límite en sus sesiones (~/.codex/sessions/AAAA/MM/DD/*.jsonl). Vale el de la última que lo tenga:
    // las sesiones cortas o internas a veces no lo traen (pasó el 30/10/2026).
    static func datosCodex(_ carpeta: URL) -> Uso? {
        for archivo in sesionesRecientes(carpeta) {
            guard let j = ultimoLimite(archivo), let r = (j["payload"] as? [String: Any])?["rate_limits"] as? [String: Any] else { continue }
            var uso = Uso(agente: .codex, leido: fechaISO(j["timestamp"] as? String))
            for clave in ["primary", "secondary"] {
                guard let s = r[clave] as? [String: Any], let pct = (s["used_percent"] as? NSNumber)?.intValue else { continue }
                let minutos = (s["window_minutes"] as? NSNumber)?.intValue ?? 0
                let horas = max(1, minutos / 60)
                let semana = minutos >= 10_080
                uso.topes.append(.init(nombre: semana ? T("Semana", "Week") : T("Sesión de \(horas) h", "\(horas)-hour session"),
                                       cual: semana ? T("de la semana", "of the week") : T("de las \(horas) horas", "of the \(horas)-hour window"),
                                       usado: pct,
                                       renueva: (s["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }))
            }
            guard !uso.topes.isEmpty else { continue }
            return uso
        }
        return nil
    }

    // Las conversaciones de Claude Code de hoy, por proyecto (~/.claude/projects/<carpeta>/<sesión>.jsonl). Se mira
    // solo la fecha de cada archivo y, para el nombre, el "cwd" del principio de uno: nunca lo que se habló.
    static func sesionesDeHoy(_ carpeta: URL, ahora: Date) -> [Uso.Sesiones] {
        let fm = FileManager.default
        let claves: [URLResourceKey] = [.contentModificationDateKey]
        var lista: [Uso.Sesiones] = []
        for dir in (try? fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil)) ?? [] {
            let deHoy = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: claves)) ?? []).filter {
                guard $0.pathExtension == "jsonl",
                      let f = try? $0.resourceValues(forKeys: Set(claves)).contentModificationDate else { return false }
                return Calendar.current.isDate(f, inSameDayAs: ahora)
            }
            guard let uno = deHoy.first else { continue }
            lista.append(.init(proyecto: nombreProyecto(uno) ?? String(dir.lastPathComponent.split(separator: "-").last ?? ""),
                               cantidad: deHoy.count))
        }
        return Array(lista.sorted { $0.cantidad > $1.cantidad }.prefix(4))
    }

    // El nombre de la carpeta donde se abrió la sesión ("cwd" en las primeras líneas; se leen hasta 64 KB).
    private static func nombreProyecto(_ archivo: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: archivo) else { return nil }
        defer { try? h.close() }
        let inicio = String(decoding: (try? h.read(upToCount: 65_536)) ?? Data(), as: UTF8.self)
        guard let r = inicio.range(of: #""cwd":"([^"]+)""#, options: .regularExpression) else { return nil }
        let ruta = inicio[r].dropFirst(7).dropLast()
        return URL(fileURLWithPath: String(ruta)).lastPathComponent
    }

    // Las sesiones de los últimos 3 días, de la que se tocó más recién a la más vieja (hasta 12).
    private static func sesionesRecientes(_ carpeta: URL) -> [URL] {
        let fm = FileManager.default
        func hijos(_ u: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var dias: [URL] = []
        for anio in hijos(carpeta) where dias.count < 3 {
            for mes in hijos(anio) where dias.count < 3 { dias += hijos(mes).prefix(3 - dias.count) }
        }
        func fecha(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        return Array(dias.flatMap { hijos($0).filter { $0.pathExtension == "jsonl" } }.sorted { fecha($0) > fecha($1) }.prefix(12))
    }

    // La última línea de un archivo de sesión que trae el límite (se lee la cola: hasta 8 MB).
    private static func ultimoLimite(_ archivo: URL) -> [String: Any]? {
        guard let h = try? FileHandle(forReadingFrom: archivo) else { return nil }
        defer { try? h.close() }
        let largo = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: largo > 8_000_000 ? largo - 8_000_000 : 0)
        let cola = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
        guard let linea = cola.split(separator: "\n").last(where: { $0.contains("\"rate_limits\"") }) else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(linea.utf8)) as? [String: Any]
    }

    private static func fechaISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // " (se renueva hoy a las 03:09)" / "mañana a las…" / "el vie 6 a las…".
    static func renueva(_ fecha: Date?, ahora: Date) -> String {
        guard let fecha else { return "" }
        let cal = Calendar.current
        let hora = DateFormatter()
        hora.locale = Locale(identifier: T("es_AR", "en_US"))
        hora.dateFormat = "HH:mm"
        let dia: String
        if cal.isDate(fecha, inSameDayAs: ahora) { dia = T("hoy", "today") }
        else if let m = cal.date(byAdding: .day, value: 1, to: ahora), cal.isDate(fecha, inSameDayAs: m) { dia = T("mañana", "tomorrow") }
        else {
            let f = DateFormatter()
            f.locale = hora.locale
            f.dateFormat = T("'el' EEE d", "EEE d")
            dia = f.string(from: fecha)
        }
        return T(" (se renueva \(dia) a las \(hora.string(from: fecha)))", " (resets \(dia) at \(hora.string(from: fecha)))")
    }

    private static func hace(_ fecha: Date?, ahora: Date) -> String {
        guard let fecha else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: T("es_AR", "en_US"))
        return T(" Dato de \(f.localizedString(for: fecha, relativeTo: ahora)).", " As of \(f.localizedString(for: fecha, relativeTo: ahora)).")
    }

    // MARK: Pedirle algo

    static func programa(_ a: Agente) -> URL? {
        let casa = FileManager.default.homeDirectoryForCurrentUser.path
        let rutas = a == .claude
            ? ["\(casa)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(casa)/.claude/local/claude"]
            : ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex", "/opt/homebrew/bin/codex",
               "/usr/local/bin/codex", "\(casa)/.local/bin/codex"]
        return rutas.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    // Lo que se le dice al agente sobre cómo responder (va aparte del pedido).
    static func guia(hacer: Bool) -> String {
        hacer
            ? T("Te habla una persona por voz desde Dixity, una app de dictado. Hacé el cambio que pidió. Al terminar, contá en pocas líneas qué cambiaste y en qué archivos, en español rioplatense.",
                "A person is talking to you by voice from Dixity, a dictation app. Make the change they asked for. When done, say in a few lines what you changed and in which files.")
            : T("Te habla una persona por voz desde Dixity, una app de dictado. Tu respuesta se muestra en una ventanita chica: respondé en español rioplatense, corto (hasta unas 10 líneas), sin títulos ni tablas. Si pide un cambio, no lo hagas: contá en pocas líneas qué harías y en qué archivos.",
                "A person is talking to you by voice from Dixity, a dictation app. Your answer shows in a small window: reply briefly (about 10 lines at most), with no headings or tables. If they ask for a change, don't make it: say in a few lines what you would do and in which files.")
    }

    // Solo lo que dijiste y, si había, lo que seleccionaste y las imágenes que elegiste con la Varita: nada de la
    // pantalla ni de la memoria. A Claude se le dicen las rutas (las abre con Read); Codex las recibe con -i.
    static func pedido(_ t: Tarea) -> String {
        let sel = t.seleccion.trimmingCharacters(in: .whitespacesAndNewlines)
        var texto = sel.isEmpty ? t.pedido : t.pedido + T("\n\nTexto seleccionado:\n", "\n\nSelected text:\n") + String(sel.prefix(4000))
        if t.agente == .claude, !t.imagenes.isEmpty {
            texto += T("\n\nImágenes que te muestro (abrilas con Read antes de responder):\n",
                       "\n\nImages I'm showing you (open them with Read before answering):\n") + t.imagenes.map(\.path).joined(separator: "\n")
        }
        return texto
    }

    // Los argumentos de cada programa. A propósito nunca lleva permisos totales ni salir del sandbox: leer es modo plan
    // (Claude) o solo lectura (Codex); Hacelo deja editar archivos del proyecto, y Claude sigue sin poder correr
    // comandos que no tengas permitidos.
    static func argumentos(_ t: Tarea, hacer: Bool, plan: String = "", salida: URL? = nil) -> [String] {
        switch t.agente {
        case .claude:
            // A propósito en este orden: --disallowedTools junta todas las palabras que le siguen, así que después va
            // otra opción y nunca el pedido (si no, Claude no lo recibía; 30/10/2026).
            var a = ["-p"]
            a += hacer ? ["--permission-mode", "acceptEdits"] : ["--permission-mode", "plan", "--disallowedTools", "Edit Write NotebookEdit"]
            if hacer, let s = t.sesion { a += ["--resume", s] }
            // --add-dir junta varias carpetas: después va otra opción, nunca el pedido.
            for e in t.extras { a += ["--add-dir", e.path] }
            a += ["--output-format", "json", "--append-system-prompt", t.guiaPropia.map { hacer ? $0.hacer : $0.leer } ?? guia(hacer: hacer)]
            let texto = hacer && t.sesion != nil ? T("Hacelo.", "Go ahead and do it.")
                : hacer ? pedido(t) + T("\n\nPlan que propusiste:\n", "\n\nYour plan:\n") + plan : pedido(t)
            return a + [texto]
        case .codex:
            var a = ["exec", "-s", hacer ? "workspace-write" : "read-only", "--skip-git-repo-check", "-C", t.carpeta.path]
            if !hacer { a.append("--ephemeral") }
            for i in t.imagenes { a += ["-i", i.path] }
            if let salida { a += ["-o", salida.path] }
            let extra = hacer && !plan.isEmpty ? T("\n\nPlan que propusiste antes:\n", "\n\nYour earlier plan:\n") + plan : ""
            return a + [guia(hacer: hacer) + "\n\n" + pedido(t) + extra]
        }
    }

    // Corre el agente y devuelve su respuesta (y, en Claude, la conversación para Hacelo). Lo llama Motor fuera del hilo
    // principal. Si tarda más del tope, se corta.
    static func correr(_ t: Tarea, hacer: Bool, plan: String = "") async throws -> (texto: String, sesion: String?) {
        guard let prog = programa(t.agente) else {
            throw ErrorAgente(mensaje: T("No encontré \(t.agente.nombre) en esta Mac.", "Couldn't find \(t.agente.nombre) on this Mac."))
        }
        let salida = t.agente == .codex ? FileManager.default.temporaryDirectory.appendingPathComponent("dixity-codex-\(UUID().uuidString).txt") : nil
        defer { if let salida { try? FileManager.default.removeItem(at: salida) } }
        let tope = hacer ? topeHacer : topeLectura
        let r = try await ejecutar(prog, argumentos(t, hacer: hacer, plan: plan, salida: salida), carpeta: t.carpeta, tope: tope)
        if r.cortado {
            throw ErrorAgente(mensaje: T("\(t.agente.nombre) tardó más de \(Int(tope / 60)) minutos y lo corté.",
                                         "\(t.agente.nombre) took more than \(Int(tope / 60)) minutes, so I stopped it."))
        }
        if t.agente == .claude, let j = respuestaJSON(r.salida) {
            let texto = (j["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if j["is_error"] as? Bool != true, !texto.isEmpty { return (texto, j["session_id"] as? String) }
            throw ErrorAgente(mensaje: texto.isEmpty ? T("Claude no respondió.", "Claude didn't answer.") : String(texto.prefix(200)))
        }
        let texto = (salida.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if r.codigo == 0, !texto.isEmpty { return (texto, nil) }
        throw ErrorAgente(mensaje: motivo(r.salida, agente: t.agente))
    }

    // La salida JSON de Claude es la última línea que empieza con "{" (antes puede haber avisos).
    static func respuestaJSON(_ s: String) -> [String: Any]? {
        guard let l = s.split(separator: "\n").last(where: { $0.hasPrefix("{") }) else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any]
    }

    // Por qué falló, en simple. "Workspace not trusted" y "Not logged in" son los que se ven en la práctica.
    static func motivo(_ salida: String, agente: Agente) -> String {
        if salida.contains("Not logged in") || salida.contains("/login") || salida.contains("codex login") {
            return T("\(agente.nombre) no tiene la sesión iniciada: abrilo una vez en la terminal.", "\(agente.nombre) isn't signed in: open it once in Terminal.")
        }
        let ultima = salida.split(separator: "\n").last { !$0.contains("SEP-2352") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return ultima.map { String($0.prefix(200)) } ?? T("\(agente.nombre) no respondió.", "\(agente.nombre) didn't answer.")
    }

    private static func ejecutar(_ programa: URL, _ args: [String], carpeta: URL, tope: TimeInterval) async throws
        -> (salida: String, codigo: Int32, cortado: Bool) {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = programa
            p.arguments = args
            p.currentDirectoryURL = carpeta
            // Una app abierta desde el Finder tiene un PATH mínimo: se suman donde suelen estar estas herramientas.
            var env = ProcessInfo.processInfo.environment
            let casa = FileManager.default.homeDirectoryForCurrentUser.path
            env["PATH"] = (["\(casa)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"] + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
            p.environment = env
            let tubo = Pipe()
            p.standardOutput = tubo
            p.standardError = tubo
            p.standardInput = FileHandle.nullDevice
            DispatchQueue.global(qos: .utility).async {
                do { try p.run() } catch { cont.resume(throwing: error); return }
                // Pasado el tope se corta: termina por señal y así se sabe que fue por tiempo.
                DispatchQueue.global().asyncAfter(deadline: .now() + tope) { if p.isRunning { p.terminate() } }
                let datos = tubo.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (String(decoding: datos, as: UTF8.self), p.terminationStatus, p.terminationReason == .uncaughtSignal))
            }
        }
    }
}
