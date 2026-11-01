import AppKit
import Carbon

// Un elemento de Accesibilidad para pasarlo a otro hilo (leer los textos de una sección para la maqueta): solo se lee,
// nunca se cambia, así que no hay carreras.
struct ElementoAX: @unchecked Sendable {
    let el: AXUIElement
    init(_ el: AXUIElement) { self.el = el }
}

// Qué hay debajo del puntero (para la Varita): una imagen, un texto, un link, una tabla… con su marco en pantalla.
// Lo pregunta a Accesibilidad (el permiso que Dixity ya tiene): no saca fotos ni manda nada. Lo llama la Varita unas
// 15 veces por segundo mientras está prendida, nunca cuando está apagada.
enum Senalador {
    enum Tipo: String, Equatable {
        case imagen, texto, link, tabla, campo, control
        case seccion, ventana, recorte   // más grande que una cosa (⌥ + rueda) o un recuadro que arrastraste
        case video, logo, banner         // imágenes que se reconocen aparte (01/11/2026): tienen sus propias opciones
        var nombre: String {
            switch self {
            case .video: T("Video", "Video")
            case .logo: T("Logo", "Logo")
            case .banner: T("Banner", "Banner")
            case .seccion: T("Sección", "Section")
            case .ventana: T("Ventana", "Window")
            case .recorte: T("Recorte", "Snip")
            case .imagen: T("Imagen", "Image")
            case .texto: T("Texto", "Text")
            case .link: T("Link", "Link")
            case .tabla: T("Tabla", "Table")
            case .campo: T("Caja de texto", "Text box")
            case .control: T("Botón", "Button")
            }
        }
    }

    // Una cosa señalada. `marco` en coordenadas de AppKit (origen abajo a la izquierda de la pantalla principal).
    struct Cosa: Equatable {
        var tipo: Tipo
        var marco: CGRect
        var texto: String = ""        // lo que dice (párrafo, link, campo), si lo cuenta
        var url: URL? = nil           // links
        var pid: pid_t = 0
        // Se puede escribir ahí (una caja de texto, un mail que estás escribiendo): traducir o reformular lo cambia en
        // su lugar en vez de mostrarlo en una tarjeta. `elemento` es esa caja, para escribir en ella y no en otra.
        var editable = false
        var elemento: AXUIElement? = nil
        var pagina: URL? = nil        // la página web donde está (solo al elegir con clic), para mandársela a Claude
        var tieneCodigo = false       // una imagen con un QR o código de barras (lo revisa la Varita al pasar por encima)
        static func == (a: Cosa, b: Cosa) -> Bool { a.tipo == b.tipo && a.marco == b.marco && a.pid == b.pid }
        /// Se trabaja con su foto (una imagen, una sección, la ventana o un recorte): Describir, Sacar prompt…
        var esVisual: Bool { [.imagen, .seccion, .ventana, .recorte, .video, .logo, .banner].contains(tipo) }
    }

    // Roles de Accesibilidad que se reconocen y qué son. Lo demás se sube al padre (hasta 6 niveles) buscando uno.
    static func tipo(rol: String, subrol: String) -> Tipo? {
        switch rol {
        case "AXImage": .imagen
        case "AXLink": .link
        case "AXStaticText", "AXHeading", "AXTextArea", "AXParagraph": .texto
        case "AXTable", "AXGrid", "AXOutline": .tabla
        case "AXTextField", "AXComboBox", "AXSearchField": subrol == "AXSecureTextField" ? nil : .campo
        case "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton": .control
        default: nil
        }
    }

    private static let sistema: AXUIElement = {
        let s = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(s, 0.08)   // si una app tarda, se saltea esa vuelta (no se traba el mouse)
        return s
    }()

    /// La cosa debajo de `punto` (coordenadas de AppKit), o nil si no hay nada útil (escritorio, una ventana entera,
    /// Dixity misma, un campo de contraseña o un gestor de contraseñas). `conPagina`: busca también la dirección de la
    /// página web (sube hasta la web entera, así que solo se pide al elegir con clic, no al pasar por encima).
    static func cosa(en punto: CGPoint, propio: pid_t = getpid(), conPagina: Bool = false) -> Cosa? {
        guard let alto = NSScreen.screens.first?.frame.height else { return nil }
        var el: AXUIElement?
        // Accesibilidad cuenta desde arriba a la izquierda.
        guard AXUIElementCopyElementAtPosition(sistema, Float(punto.x), Float(alto - punto.y), &el) == .success, var actual = el else {
            return nil
        }
        var pid: pid_t = 0
        AXUIElementGetPid(actual, &pid)
        guard pid != propio else { return nil }
        if let app = NSRunningApplication(processIdentifier: pid) {
            if Secretos.esGestor(app) || IsSecureEventInputEnabled() { return nil }
            Cursor.activarAccesibilidad(app, AXUIElementCreateApplication(pid))   // Chrome y Electron cuentan su web
        }
        let pantalla = NSScreen.screens.first { $0.frame.contains(punto) }?.frame ?? NSScreen.main?.frame ?? .zero
        for _ in 0..<7 {
            let rol = texto(actual, kAXRoleAttribute) ?? ""
            let subrol = texto(actual, kAXSubroleAttribute) ?? ""
            if let t = tipo(rol: rol, subrol: subrol) ?? (esVideo(actual, rol: rol, subrol: subrol) ? .video : nil),
               let m = marco(actual, alto: alto),
               m.width >= 6, m.height >= 6, m.width * m.height < pantalla.width * pantalla.height * 0.55 {
                var cosa = Cosa(tipo: t, marco: m, pid: pid)
                cosa.texto = String(contenido(actual, tipo: t).prefix(8000))
                if t == .imagen { cosa.tipo = clase(deImagen: m, alt: cosa.texto, llevaAlInicio: llevaAlInicio(actual)) }
                if t == .link { cosa.url = valor(actual, kAXURLAttribute) as? URL }
                // Una caja donde se escribe (también un renglón dentro de un mail que estás escribiendo en la web) es un
                // campo: se marca la caja entera y se ofrece cambiar su texto ahí mismo.
                if t == .texto || t == .campo, let caja = cajaEditable(actual) {
                    cosa.tipo = .campo
                    cosa.editable = true
                    cosa.elemento = caja
                    if !CFEqual(caja, actual), let mc = marco(caja, alto: alto), mc.width * mc.height < pantalla.width * pantalla.height * 0.55 {
                        cosa.marco = mc
                        cosa.texto = String(contenido(caja, tipo: .texto).prefix(8000))
                    }
                }
                if conPagina { cosa.pagina = pagina(desde: actual) }
                return cosa.editable ? cosa : ajustarTexto(cosa, elemento: actual, alto: alto)
            }
            guard let padre = valor(actual, kAXParentAttribute) else { break }
            actual = padre as! AXUIElement   // swiftlint:disable:this force_cast — AXParent siempre es un AXUIElement
        }
        return nil
    }

    // Un video de una página: Safari y Chrome lo cuentan como un grupo que dice «video» (o con rol AXVideo). Solo se
    // pregunta en grupos y elementos de video, no en cada cosa.
    private static func esVideo(_ el: AXUIElement, rol: String, subrol: String) -> Bool {
        if rol == "AXVideo" || subrol.contains("Video") { return true }
        guard rol == "AXGroup", let d = texto(el, kAXRoleDescriptionAttribute)?.lowercased() else { return false }
        return d == "video" || d == "vídeo" || d.hasPrefix("video ") || d.hasPrefix("vídeo ")
    }

    /// Qué clase de imagen es, por lo que se sabe sin mirarla: un logo (su texto alternativo lo dice, o es chica y
    /// lleva al inicio de la página), un banner (ancha y grande) o una imagen común. Aparte para probarlo.
    static func clase(deImagen m: CGRect, alt: String, llevaAlInicio: Bool) -> Tipo {
        let t = alt.lowercased()
        if ["logo", "logotipo", "isotipo", "isologo"].contains(where: t.contains) { return .logo }
        if llevaAlInicio && m.width <= 360 && m.height <= 180 { return .logo }
        if m.width >= 480 && m.width / max(m.height, 1) >= 2.4 { return .banner }
        return .imagen
    }

    // La imagen está dentro de un link al inicio del sitio ("/"): así suelen estar los logos de arriba.
    private static func llevaAlInicio(_ el: AXUIElement) -> Bool {
        var actual = el
        for _ in 0..<3 {
            guard let padre = valor(actual, kAXParentAttribute), CFGetTypeID(padre) == AXUIElementGetTypeID() else { return false }
            actual = padre as! AXUIElement   // swiftlint:disable:this force_cast
            if texto(actual, kAXRoleAttribute) == "AXLink", let u = valor(actual, kAXURLAttribute) as? URL {
                return u.path.isEmpty || u.path == "/"
            }
        }
        return false
    }

    /// Los textos de una sección (títulos, botones, links, textos, campos), en orden y sin repetir, hasta `tope`
    /// letras. Para la maqueta: así la IA copia los textos tal cual en vez de leerlos de la foto. Recorre hasta 600
    /// elementos. Lo llama el Motor fuera del hilo principal.
    static func textos(de el: AXUIElement, tope: Int = 4000) -> String {
        var lineas: [String] = []
        var largo = 0
        var vistos = 0
        func recorrer(_ e: AXUIElement, _ hondo: Int) {
            guard vistos < 600, largo < tope, hondo < 30 else { return }
            vistos += 1
            let rol = texto(e, kAXRoleAttribute) ?? ""
            let dicho = contenido(e, tipo: .control).trimmingCharacters(in: .whitespacesAndNewlines)
            let etiqueta: String? = switch rol {
            case "AXHeading": T("Título", "Heading")
            case "AXButton", "AXMenuButton", "AXPopUpButton": T("Botón", "Button")
            case "AXLink": "Link"
            case "AXTextField", "AXSearchField", "AXComboBox": T("Campo", "Field")
            case "AXImage": T("Imagen", "Image")
            case "AXStaticText": ""
            default: nil
            }
            if let etiqueta, !dicho.isEmpty, dicho.count < 400, lineas.last?.hasSuffix(dicho) != true {
                let l = etiqueta.isEmpty ? dicho : "\(etiqueta): \(dicho)"
                lineas.append(l)
                largo += l.count + 1
                // Un título, botón o link ya dijo su texto: no se repiten los textos de adentro.
                if !etiqueta.isEmpty { return }
            }
            guard let hijos = valor(e, kAXChildrenAttribute) as? [AXUIElement] else { return }
            for h in hijos.prefix(80) { recorrer(h, hondo + 1) }
        }
        recorrer(el, 0)
        return String(lineas.joined(separator: "\n").prefix(tope))
    }

    /// Los escalones para agrandar lo marcado (⌥ + rueda o ⌥↑): la cosa de `punto`, después lo que la contiene
    /// (una tarjeta, una sección de la página…) y al final la ventana. Lo llama la Varita al empezar a agrandar, fuera
    /// del hilo principal. Vacío si no hay nada (escritorio, Dixity, contraseñas).
    static func niveles(en punto: CGPoint, propio: pid_t = getpid()) -> [Cosa] {
        guard let alto = NSScreen.screens.first?.frame.height, let base = cosa(en: punto, propio: propio, conPagina: true) else { return [] }
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sistema, Float(punto.x), Float(alto - punto.y), &el) == .success, var actual = el else {
            return [base]
        }
        var marcos: [(marco: CGRect, el: AXUIElement)] = []
        var ventana: (marco: CGRect, el: AXUIElement)?
        for _ in 0..<40 {
            guard let padre = valor(actual, kAXParentAttribute), CFGetTypeID(padre) == AXUIElementGetTypeID() else { break }
            actual = padre as! AXUIElement   // swiftlint:disable:this force_cast
            let rol = texto(actual, kAXRoleAttribute) ?? ""
            if rol == "AXApplication" { break }
            guard let m = marco(actual, alto: alto) else { continue }
            if rol == "AXWindow" { ventana = (m, actual); break }
            marcos.append((m, actual))
        }
        let escalones = Senalador.escalones(desde: base.marco, padres: marcos.map(\.marco), ventana: ventana?.marco)
        return [base] + escalones.enumerated().map { i, m in
            let esVentana = i == escalones.count - 1 && ventana != nil
            var c = Cosa(tipo: esVentana ? .ventana : .seccion, marco: m, pid: base.pid)
            c.pagina = base.pagina
            // Su elemento, para leer sus textos al hacer la maqueta (el escalón puede estar recortado a la ventana).
            c.elemento = esVentana ? ventana?.el : marcos.first { $0.marco.intersection(ventana?.marco ?? $0.marco) == m }?.el
            return c
        }
    }

    /// De los marcos que contienen a la cosa (de adentro hacia afuera), los que crecen de verdad (al menos 1,6 veces
    /// el lugar del anterior: en una web hay decenas de grupos casi iguales), recortados a la ventana, hasta 5, y al
    /// final la ventana. Aparte para probarlo sin pantalla.
    static func escalones(desde base: CGRect, padres: [CGRect], ventana: CGRect?) -> [CGRect] {
        func area(_ r: CGRect) -> CGFloat { r.width * r.height }
        var lista: [CGRect] = []
        var ultimo = base
        for m in padres {
            let visible = ventana.map { m.intersection($0) } ?? m
            guard !visible.isNull, visible.width >= 24, visible.height >= 24,
                  visible.contains(ultimo.insetBy(dx: 2, dy: 2)) || ultimo == base,
                  area(visible) >= area(ultimo) * 1.6 else { continue }
            if let v = ventana, area(visible) >= area(v) * 0.85 { break }   // ya es casi la ventana entera
            lista.append(visible)
            ultimo = visible
        }
        lista = Array(lista.prefix(5))
        if let v = ventana, area(v) > area(lista.last ?? base) * 1.05 { lista.append(v) }
        return lista
    }

    // Un renglón suelto de una web (AXStaticText chiquito) se agranda al párrafo que lo contiene, si el padre es un
    // grupo de texto razonable: así se marca el párrafo entero, como en Magic Pointer.
    private static func ajustarTexto(_ c: Cosa, elemento: AXUIElement, alto: CGFloat) -> Cosa {
        guard c.tipo == .texto, c.marco.height < 40, let p = valor(elemento, kAXParentAttribute) else { return c }
        let padre = p as! AXUIElement   // swiftlint:disable:this force_cast
        let rol = texto(padre, kAXRoleAttribute) ?? ""
        guard ["AXGroup", "AXParagraph"].contains(rol), let m = marco(padre, alto: alto),
              m.height < 600, m.width < 1400, m.contains(c.marco.insetBy(dx: 1, dy: 1)) else { return c }
        var r = c
        r.marco = m
        let completo = hijosTexto(padre)
        if !completo.isEmpty { r.texto = String(completo.prefix(8000)) }
        return r
    }

    // La caja donde se puede escribir que contiene a `el` (o `el` mismo), o nil si es texto que solo se lee. Las cajas
    // de la Mac lo dicen con su rol; las de la web y Electron, con "AXEditableAncestor" (la caja editable de afuera).
    private static func cajaEditable(_ el: AXUIElement) -> AXUIElement? {
        let rol = texto(el, kAXRoleAttribute) ?? ""
        if ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(rol) {
            var editable: DarwinBoolean = false
            let puede = AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &editable) == .success && editable.boolValue
            // Un AXTextArea de solo lectura (el texto de una terminal, un visor) no es una caja.
            if rol != "AXTextArea" || puede { return el }
        }
        // Se comprueba el tipo: esto corre 15 veces por segundo sobre cualquier app, y una que devolviera otra cosa
        // cerraba Dixity.
        if let caja = valor(el, "AXEditableAncestor"), CFGetTypeID(caja) == AXUIElementGetTypeID() { return (caja as! AXUIElement) }   // swiftlint:disable:this force_cast
        return nil
    }

    // La dirección de la página web que contiene a `el` (la "AXWebArea" de Safari, Chrome y compañía), subiendo hasta 40
    // niveles. Nil fuera de un navegador.
    private static func pagina(desde el: AXUIElement) -> URL? {
        var actual = el
        for _ in 0..<40 {
            if texto(actual, kAXRoleAttribute) == "AXWebArea" { return valor(actual, kAXURLAttribute) as? URL }
            guard let padre = valor(actual, kAXParentAttribute) else { return nil }
            actual = padre as! AXUIElement   // swiftlint:disable:this force_cast
        }
        return nil
    }

    /// Le pasa el foco a una caja (la que señalaste), así lo que se escriba va ahí y no a la que estaba activa.
    static func enfocar(_ el: AXUIElement) {
        AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    /// Le pasa el foco a la caja y selecciona todo su texto, para reemplazarlo. Solo dice que sí si lo pudo comprobar:
    /// la caja quedó con el foco y con todo su texto seleccionado (así nunca se pega encima de otra cosa).
    static func seleccionarTodo(_ el: AXUIElement) -> Bool {
        enfocar(el)
        let largo = (valor(el, kAXNumberOfCharactersAttribute) as? Int) ?? texto(el, kAXValueAttribute)?.utf16.count ?? 0
        guard largo > 0 else { return false }
        var rango = CFRange(location: 0, length: largo)
        if let v = AXValueCreate(.cfRange, &rango) { AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, v) }
        guard let r = valor(el, kAXSelectedTextRangeAttribute), CFGetTypeID(r) == AXValueGetTypeID() else { return false }
        var leido = CFRange()
        guard AXValueGetValue(r as! AXValue, .cfRange, &leido), leido.location == 0, leido.length == largo else { return false }   // swiftlint:disable:this force_cast
        // Y que el foco sea esa caja.
        let sistema = AXUIElementCreateSystemWide()
        guard let f = valor(sistema, kAXFocusedUIElementAttribute) else { return false }
        return CFEqual(f, el)
    }

    private static func hijosTexto(_ el: AXUIElement) -> String {
        guard let hijos = valor(el, kAXChildrenAttribute) as? [AXUIElement] else { return "" }
        return hijos.prefix(60).compactMap { texto($0, kAXValueAttribute) }.joined()
    }

    private static func contenido(_ el: AXUIElement, tipo: Tipo) -> String {
        for a in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let s = texto(el, a), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        }
        return tipo == .texto || tipo == .link ? hijosTexto(el) : ""
    }

    private static func marco(_ el: AXUIElement, alto: CGFloat) -> CGRect? {
        guard let p = valor(el, kAXPositionAttribute), let s = valor(el, kAXSizeAttribute) else { return nil }
        var punto = CGPoint.zero, tam = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &punto), AXValueGetValue(s as! AXValue, .cgSize, &tam) else { return nil }   // swiftlint:disable:this force_cast
        return CGRect(x: punto.x, y: alto - punto.y - tam.height, width: tam.width, height: tam.height)
    }

    private static func valor(_ el: AXUIElement, _ nombre: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, nombre as CFString, &v) == .success ? v : nil
    }
    private static func texto(_ el: AXUIElement, _ nombre: String) -> String? { valor(el, nombre) as? String }
}
