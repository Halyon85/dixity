import AppKit

// "Mandar a Claude" y "Mandar a Codex" desde la Varita: lo que elegiste (imágenes, un texto, la página de donde viene)
// se pega en la ventana de Claude Code o Codex que tengas abierta, listo para que le digas qué querés. Nunca aprieta
// Enter: lo mandás vos. Lo llama el Motor.
//
// Las imágenes se guardan como PNG en una carpeta temporal propia (se borran al día, también al abrir la app). En una terminal se pegan sus
// rutas, que Claude Code y Codex abren como imágenes; en sus apps (Claude, ChatGPT/Codex) se pegan las imágenes mismas.
// "Preguntale a Claude" usa los mismos archivos para que Claude los vea y responda en la tarjeta.
//
// Cuidados (revisión del 31/10): a una terminal nunca se le pega más de un renglón (si Claude ya no corría ahí, cada
// renglón se ejecutaría como un comando): un texto de varios renglones va como archivo y se pega su ruta. Solo se
// pega si la ventana de Claude o Codex quedó de verdad adelante; si no, queda copiado. Los editores (VS Code, Cursor…)
// no se usan: su título es el del archivo abierto y un CLAUDE.md abierto los hacía pasar por Claude.
enum Mandar {
    struct Ventana {
        let app: NSRunningApplication
        let titulo: String
        let terminal: Bool     // una terminal con Claude Code / Codex adentro (se pegan rutas, en un solo renglón)
    }

    static let apps: [Agente: String] = [.claude: "com.anthropic.claudefordesktop", .codex: "com.openai.codex"]

    /// Está en la Mac (el programa de la terminal o su app): solo así la Varita lo ofrece.
    static func instalado(_ a: Agente) -> Bool {
        Agentes.programa(a) != nil || apps[a].flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } != nil
    }

    /// Es una ventana de `a`, por su título. Claude Code pone "✳" (o una ruedita de puntos mientras trabaja) y su
    /// nombre; Codex, su nombre. Sin permiso de Grabación de pantalla macOS no cuenta los títulos.
    static func esDe(_ a: Agente, titulo: String) -> Bool {
        let t = titulo.lowercased()
        switch a {
        case .claude: return t.contains("claude") || titulo.hasPrefix("✳") || titulo.unicodeScalars.first.map { (0x2800...0x28FF).contains($0.value) } == true
        case .codex: return t.contains("codex")
        }
    }

    /// La ventana de `a` que está más adelante: primero en el escritorio que estás mirando, después en los otros.
    static func ventana(de a: Agente) -> Ventana? {
        for opciones in [CGWindowListOption.optionOnScreenOnly, .optionAll] {
            let lista = CGWindowListCopyWindowInfo([opciones, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            for w in lista {
                guard (w[kCGWindowLayer as String] as? Int) == 0, let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                      let app = NSRunningApplication(processIdentifier: pid), let b = app.bundleIdentifier else { continue }
                let titulo = w[kCGWindowName as String] as? String ?? ""
                if b == apps[a] { return Ventana(app: app, titulo: titulo, terminal: false) }
                if Cursor.terminales.contains(b), esDe(a, titulo: titulo) {
                    return Ventana(app: app, titulo: titulo, terminal: true)
                }
            }
        }
        return nil
    }

    // MARK: Las imágenes como archivos

    static var carpeta: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Dixity-para-agentes", isDirectory: true) }

    /// Borra de la carpeta lo que tiene más de un día. Lo llaman `guardar`, `guardarTexto` y la app al abrir: antes
    /// solo se limpiaba al volver a mandar imágenes, y si no mandabas más, lo último quedaba ahí (01/11/2026).
    static func borrarViejas(en carpeta: URL = Mandar.carpeta, ahora: Date = Date()) {
        let fm = FileManager.default
        let archivos = (try? fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for a in archivos {
            let fecha = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if ahora.timeIntervalSince(fecha) > 86_400 { try? fm.removeItem(at: a) }
        }
    }

    /// Guarda las imágenes como PNG (y borra lo de más de un día). Devuelve sus rutas, sin espacios.
    static func guardar(_ imagenes: [NSImage]) -> [URL] {
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        borrarViejas()
        let tanda = UUID().uuidString.prefix(8)   // dos envíos seguidos no se pisan los archivos
        return imagenes.enumerated().compactMap { i, img in
            guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return nil }
            let url = carpeta.appendingPathComponent("varita-\(tanda)-\(i + 1).png")
            return (try? png.write(to: url)) != nil ? url : nil
        }
    }

    /// Un texto de varios renglones, como archivo (para pegar su ruta en una terminal en un solo renglón).
    static func guardarTexto(_ texto: String) -> URL? {
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        borrarViejas()
        let url = carpeta.appendingPathComponent("varita-\(UUID().uuidString.prefix(8)).txt")
        return (try? texto.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    /// Lo que se pega en una terminal, siempre en un solo renglón: de qué página viene, las rutas de las imágenes y el
    /// texto. Un texto de varios renglones va como archivo (`guardar` le da la ruta). Termina en espacio para que lo que
    /// dictes después quede a continuación.
    static func textoParaTerminal(prefijo: String?, pagina: URL?, rutas: [URL], textos: [String],
                                  guardar: (String) -> URL? = guardarTexto) -> String {
        var partes: [String] = []
        if let prefijo, !prefijo.isEmpty { partes.append(prefijo) }
        if let pagina { partes.append(T("De la página \(pagina.absoluteString)", "From the page \(pagina.absoluteString)")) }
        if !rutas.isEmpty { partes.append(rutas.map(\.path).joined(separator: " ")) }
        for t in textos.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !t.isEmpty {
            if t.contains(where: \.isNewline) { if let u = guardar(t) { partes.append(T("(el texto está en \(u.path))", "(the text is in \(u.path))")) } }
            else { partes.append(t) }
        }
        return partes.joined(separator: " ").replacingOccurrences(of: "\n", with: " ") + " "
    }

    /// Lo que se pega en sus apps (Claude, ChatGPT/Codex): ahí sí van los renglones tal cual.
    static func textoParaApp(prefijo: String?, pagina: URL?, textos: [String]) -> String {
        var partes: [String] = []
        if let prefijo, !prefijo.isEmpty { partes.append(prefijo) }
        if let pagina { partes.append(T("De la página \(pagina.absoluteString)", "From the page \(pagina.absoluteString)")) }
        partes += textos.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return partes.joined(separator: "\n") + " "
    }

    // MARK: Mandar

    /// Trae adelante la ventana de `a` y pega ahí lo elegido. `listo(ventana)`: ya está pegado (nil: no había ninguna
    /// ventana abierta, así que quedó copiado para pegarlo a mano).
    static func mandar(a: Agente, imagenes: [NSImage], textos: [String], pagina: URL?, prefijo: String? = nil,
                       listo: @escaping (Ventana?) -> Void) {
        let textos = textos.map { Secretos.tapar($0) }   // lo que parece una clave no viaja
        let rutas = guardar(imagenes)
        func dejarCopiado() {
            if !imagenes.isEmpty && textos.isEmpty { Cursor.copiarImagenes(imagenes) }
            else { Cursor.copiar(textoParaApp(prefijo: prefijo, pagina: pagina, textos: textos + rutas.map(\.path))) }
            listo(nil)
        }
        guard let v = ventana(de: a) else { return dejarCopiado() }
        traerAdelante(v)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // Solo si quedó adelante de verdad (macOS a veces no deja que otra app la active): si no, iría a otra app.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == v.app.processIdentifier else { return dejarCopiado() }
            if v.terminal {
                Cursor.pegar(textoParaTerminal(prefijo: prefijo, pagina: pagina, rutas: rutas, textos: textos)) { _ in listo(v) }
                return
            }
            // En sus apps: primero las imágenes (⌘V), después el texto.
            let texto = textoParaApp(prefijo: prefijo, pagina: pagina, textos: textos)
            if !imagenes.isEmpty {
                Cursor.copiarImagenes(imagenes)
                Cursor.pegarPortapapeles()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (imagenes.isEmpty ? 0 : 0.4)) {
                guard texto.trimmingCharacters(in: .whitespaces).isEmpty == false else { listo(v); return }
                Cursor.pegar(texto) { _ in listo(v) }
            }
        }
    }

    // Activa la app y sube la ventana con ese título (si hay varias terminales, la de Claude y no otra).
    private static func traerAdelante(_ v: Ventana) {
        v.app.activate()
        let ax = AXUIElementCreateApplication(v.app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.3)
        var valor: AnyObject?
        guard !v.titulo.isEmpty, AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &valor) == .success,
              let ventanas = valor as? [AXUIElement] else { return }
        for w in ventanas {
            var t: AnyObject?
            guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success, t as? String == v.titulo else { continue }
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)   // si estaba minimizada
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            return
        }
    }
}
