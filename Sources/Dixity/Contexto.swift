import AppKit
import ApplicationServices

// Lo que hay alrededor del cursor en la app donde estás escribiendo.
struct ContextoCursor {
    var app = ""
    var bundle = ""
    var ventana = ""
    var antes = ""
    var despues = ""
    var seleccion = ""
    var hayCampo = false
    var editable = false
    var secreto = false        // el foco está en un campo de contraseña: no se guarda ni se manda nada de este dictado
    // seguro: hay un campo de texto · noHay: el foco está en algo que no es texto · desconocido: la app no lo cuenta
    enum Campo { case seguro, noHay, desconocido }
    var campo = Campo.desconocido
}

enum Cursor {
    // Terminales: lo que se pega ahí puede ejecutarse (Motor.entregar no pega reescrituras de varias líneas en ellas).
    static let terminales: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "dev.warp.Warp", "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty",
        "co.zeit.hyper", "com.github.wez.wezterm", "com.raphaelamorim.rio", "dev.commandline.waveterm"]

    // Cambios del portapapeles hechos por Dicta (el historial del portapapeles no los anota).
    static var cambiosPropios = Set<Int>()

    private static func anotarPropio() {
        cambiosPropios.insert(NSPasteboard.general.changeCount)
        if cambiosPropios.count > 200 { cambiosPropios.removeFirst() }
    }

    static func pegarPortapapeles() { teclear(9, cmd: true) }
    static var accesibilidadPermitida: Bool { AXIsProcessTrusted() }

    static func pedirAccesibilidad() {
        let opciones = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opciones)
    }

    private static func atributo(_ el: AXUIElement, _ nombre: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, nombre as CFString, &v) == .success ? v : nil
    }

    // Chrome y las apps Electron (Claude, Slack, VS Code…) no cuentan dónde está el cursor hasta que se les pide.
    private static var activadas = Set<pid_t>()
    private static let candadoActivadas = NSLock()   // la usan el hilo principal y la cola de la Varita a la vez
    private static let chromium: Set<String> = ["com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
        "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "company.thebrowser.Browser",
        "com.operasoftware.Opera", "org.chromium.Chromium", "ai.perplexity.comet", "com.openai.atlas",
        "company.thebrowser.dia", "com.operasoftware.OperaGX", "com.microsoft.edgemac.Beta", "com.brave.Browser.beta"]
    private static let rolesSinTexto: Set<String> = ["AXButton", "AXCheckBox", "AXRadioButton", "AXImage", "AXList",
        "AXOutline", "AXTable", "AXRow", "AXCell", "AXMenu", "AXMenuItem", "AXMenuBar", "AXSlider", "AXPopUpButton",
        "AXToolbar", "AXTabGroup", "AXDisclosureTriangle", "AXIncrementor", "AXColorWell", "AXLink"]

    static func activarAccesibilidad(_ app: NSRunningApplication, _ axApp: AXUIElement) {
        let pid = app.processIdentifier
        candadoActivadas.lock()
        let nueva = activadas.insert(pid).inserted
        candadoActivadas.unlock()
        guard nueva else { return }
        let esElectron = app.bundleURL.map {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        } ?? false
        if esElectron { AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue) }
        if chromium.contains(app.bundleIdentifier ?? "") {
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    // Título de la ventana de adelante de una app (para reconocer pestañas de gestores de contraseñas).
    static func tituloVentana(pid: pid_t) -> String {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let ventana = atributo(axApp, kAXFocusedWindowAttribute) else { return "" }
        return atributo(ventana as! AXUIElement, kAXTitleAttribute) as? String ?? ""
    }

    // El campo enfocado y su texto completo, para volver a leerlo después (Correcciones). Nada si es de contraseña.
    struct CampoLeido { let elemento: AXUIElement; let valor: String }
    static func campoEnfocado() -> CampoLeido? {
        let sistema = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sistema, 0.25)
        guard let f = atributo(sistema, kAXFocusedUIElementAttribute) else { return nil }
        let el = f as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 0.25)
        guard !Secretos.campoSeguro(subrol: atributo(el, kAXSubroleAttribute) as? String ?? ""),
              let v = atributo(el, kAXValueAttribute) as? String else { return nil }
        return CampoLeido(elemento: el, valor: v)
    }

    static func valor(de el: AXUIElement) -> String? { atributo(el, kAXValueAttribute) as? String }

    /// La selección que se leyó copiando (⌘C) está dentro de la caja de texto que tiene el foco. Si no, no se puede dar
    /// por hecho que se puede escribir ahí: en una página web, el foco puede estar en el buscador mientras seleccionás
    /// un párrafo, y reemplazar «lo seleccionado» pegaba en el buscador (revisión del 31/10).
    static func seleccionEstaEnElCampo(_ texto: String) -> Bool {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let campo = campoEnfocado() else { return false }
        return campo.valor.contains(t)
    }

    static func capturar(conTexto: Bool) -> ContextoCursor {
        var c = ContextoCursor()
        var enfocadoApp: AnyObject?
        if let app = NSWorkspace.shared.frontmostApplication {
            c.app = app.localizedName ?? ""
            c.bundle = app.bundleIdentifier ?? ""
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            activarAccesibilidad(app, axApp)
            if let ventana = atributo(axApp, kAXFocusedWindowAttribute) {
                c.ventana = atributo(ventana as! AXUIElement, kAXTitleAttribute) as? String ?? ""
            }
            enfocadoApp = atributo(axApp, kAXFocusedUIElementAttribute)
        }
        let sistema = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sistema, 0.25)
        guard let enfocado = enfocadoApp ?? atributo(sistema, kAXFocusedUIElementAttribute) else { return c }
        let el = enfocado as! AXUIElement
        c.hayCampo = true
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success { c.editable = settable.boolValue }
        let rol = atributo(el, kAXRoleAttribute) as? String ?? ""
        // Campo de contraseña: no se lee nada de él (Motor no guarda ni manda nada de este dictado).
        c.secreto = Secretos.campoSeguro(subrol: atributo(el, kAXSubroleAttribute) as? String ?? "")
        if ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(rol) { c.editable = true }
        // Campos web y de apps Electron: si tienen cursor de texto (rango seleccionado), se puede escribir.
        if !c.editable, atributo(el, kAXSelectedTextRangeAttribute) != nil,
           atributo(el, "AXEditableAncestor") != nil { c.editable = true }
        c.campo = c.editable ? .seguro : (rolesSinTexto.contains(rol) ? .noHay : .desconocido)
        guard !c.secreto else { return c }
        c.seleccion = atributo(el, kAXSelectedTextAttribute) as? String ?? ""
        guard conTexto, let valor = atributo(el, kAXValueAttribute) as? String else { return c }
        if let rangoAX = atributo(el, kAXSelectedTextRangeAttribute) {
            var rango = CFRange()
            if AXValueGetValue(rangoAX as! AXValue, .cfRange, &rango) {
                let u = valor.utf16
                let ini = min(max(0, rango.location), u.count)
                let fin = min(ini + max(0, rango.length), u.count)
                let i0 = u.index(u.startIndex, offsetBy: ini), i1 = u.index(u.startIndex, offsetBy: fin)
                c.antes = String(String(u[u.startIndex..<i0]) ?? "").suffix(600).description
                c.despues = String(String(u[i1..<u.endIndex]) ?? "").prefix(300).description
            }
        } else {
            c.antes = String(valor.suffix(600))
        }
        // Lo que parece una clave (un .env abierto, un token en la terminal) no va a la IA.
        c.antes = Secretos.tapar(c.antes)
        c.despues = Secretos.tapar(c.despues)
        return c
    }

    // Si la app no expone la selección por accesibilidad, la copiamos con ⌘C.
    static func seleccionPorCopia() -> String {
        let pb = NSPasteboard.general
        let respaldo = guardarPortapapeles()
        let antes = pb.changeCount
        teclear(8, cmd: true)
        let limite = Date().addingTimeInterval(0.35)
        while pb.changeCount == antes && Date() < limite { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        // Si el ⌘C no copió nada, el portapapeles queda como estaba: reescribirlo igual le cambiaba el número de
        // versión a una contraseña copiada y el gestor ya no la borraba (auditoría del 23/10/2026).
        guard pb.changeCount != antes else { return "" }
        anotarPropio()
        let texto = pb.string(forType: .string) ?? ""
        restaurarPortapapeles(respaldo)
        return texto
    }

    enum ResultadoPegado { case entro, noEntro, sinSaber }

    // Huella del campo enfocado (largo del texto y dónde está el cursor): si cambia después del ⌘V, el pegado entró.
    private static func huellaFoco() -> [Int]? {
        let sistema = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sistema, 0.2)
        guard let f = atributo(sistema, kAXFocusedUIElementAttribute) else { return nil }
        let el = f as! AXUIElement
        var largo = -1, cursor = -1
        if let n = atributo(el, kAXNumberOfCharactersAttribute) as? Int { largo = n }
        else if let v = atributo(el, kAXValueAttribute) as? String { largo = v.utf16.count }
        if let r = atributo(el, kAXSelectedTextRangeAttribute) {
            var rango = CFRange()
            if AXValueGetValue(r as! AXValue, .cfRange, &rango) { cursor = rango.location }
        }
        return largo < 0 && cursor < 0 ? nil : [largo, cursor]
    }

    // Pega el texto donde está el cursor y comprueba que haya entrado; si no entró, lo deja copiado.
    // Entró: a los 0,5 s vuelve lo que tenías en el portapapeles. No entró o no se puede saber: el dictado queda copiado,
    // así ⌘V trae lo último y no algo viejo. Antes se devolvía el portapapeles viejo a los 0,6 s pasara lo que pasara.
    // `secreto`: va a un campo de contraseña. Se marca como oculto y pasajero (los gestores del portapapeles no lo
    // guardan) y el portapapeles vuelve a como estaba pase lo que pase, para que la contraseña no quede copiada.
    static func pegar(_ texto: String, secreto: Bool = false, alTerminar: @escaping (ResultadoPegado) -> Void) {
        let pb = NSPasteboard.general
        let respaldo = guardarPortapapeles()
        let antes = huellaFoco()
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(texto, forType: .string)
        if secreto {
            for marca in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"] {
                item.setData(Data(), forType: NSPasteboard.PasteboardType(marca))
            }
        }
        pb.writeObjects([item])
        anotarPropio()
        let nuestro = pb.changeCount
        teclear(9, cmd: true)
        func devolver() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if pb.changeCount == nuestro { restaurarPortapapeles(respaldo) }
            }
        }
        guard let antes else { if secreto { devolver() }; alTerminar(.sinSaber); return }
        var vueltas = 0
        func mirar() {
            vueltas += 1
            if let ahora = huellaFoco(), ahora != antes {
                devolver()
                alTerminar(.entro)
            } else if vueltas >= 9 {
                if secreto { devolver() }
                alTerminar(.noEntro)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { mirar() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { mirar() }
    }

    static func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        anotarPropio()
    }

    // Lo que copia la Varita (imágenes juntas, un collage): a propósito no se marca como propio, así queda también en
    // el Portapapeles de 24 h, como cualquier cosa que copiás vos.
    static func copiarImagenes(_ imagenes: [NSImage]) {
        guard !imagenes.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(imagenes)
    }

    static func enviar(_ t: TeclaEnviar) {
        switch t {
        case .ninguna: return
        case .enter: teclear(36, cmd: false)
        case .shiftEnter: teclear(36, cmd: false, banderas: .maskShift)
        case .cmdEnter: teclear(36, cmd: true)
        }
    }

    private static func teclear(_ codigo: CGKeyCode, cmd: Bool, banderas extra: CGEventFlags = []) {
        let fuente = CGEventSource(stateID: .combinedSessionState)
        let abajo = CGEvent(keyboardEventSource: fuente, virtualKey: codigo, keyDown: true)
        let arriba = CGEvent(keyboardEventSource: fuente, virtualKey: codigo, keyDown: false)
        let banderas = extra.union(cmd ? .maskCommand : [])
        if !banderas.isEmpty { abajo?.flags = banderas; arriba?.flags = banderas }
        abajo?.setIntegerValueField(.eventSourceUserData, value: Motor.marcaPropia)
        arriba?.setIntegerValueField(.eventSourceUserData, value: Motor.marcaPropia)
        abajo?.post(tap: .cghidEventTap)
        arriba?.post(tap: .cghidEventTap)
    }

    private static func guardarPortapapeles() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        }
    }

    // Vuelve a poner lo que había. Una contraseña copiada de un gestor (marcada como oculta o pasajera) no se vuelve a
    // escribir: quedaría con otro número de versión y el gestor ya no la borraría a los segundos, como prometió.
    static func restaurable(_ items: [[NSPasteboard.PasteboardType: Data]]) -> Bool {
        !items.contains { $0.keys.contains { Secretos.marcasPrivadas.contains($0.rawValue) } }
    }

    private static func restaurarPortapapeles(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        anotarPropio()
        guard !items.isEmpty, restaurable(items) else { return }
        pb.writeObjects(items.map { d in
            let item = NSPasteboardItem()
            for (t, v) in d { item.setData(v, forType: t) }
            return item
        })
        anotarPropio()
    }
}
