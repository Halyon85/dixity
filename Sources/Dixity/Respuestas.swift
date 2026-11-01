import Foundation
import NaturalLanguage

// Las tarjetas de respuesta (Preguntar, el menú del mouse, Claude y Codex): qué forma tiene cada una y qué botones
// ofrece para seguir trabajando. Todo se decide en la Mac y sin IA: por quién respondió y por la forma del texto.
// Cómo se dibujan está en TarjetaRespuesta.swift.
enum Respuestas {
    enum Clase: Equatable {
        case texto
        case traduccion(de: String, a: String, original: String)   // códigos de idioma ("es", "en")
        case textoLeido                                            // de la ventana o de una imagen
        case codigos                                               // QR o códigos de barras
        case uso([Agentes.Uso])
        case agente
        case posteo(marca: String)                                 // una pestaña por red (Posteos)
        case imagen                                                // tu IA mirando una imagen de la Varita
        case prompt                                                // un prompt para recrear una imagen
        case video                                                 // un prompt para animar esa imagen (15 s)
        case maqueta                                               // el resumen de diseño de una sección
        case colores                                               // los colores de lo elegido ("#1E1B3A · 42 %")
    }

    // MARK: Formato del texto

    // La respuesta partida en piezas para dibujarla con formato: títulos, listas y bloques de código (con su Copiar).
    // Lo de adentro de cada pieza puede traer **negritas** o `código`: eso lo resuelve la vista.
    enum Bloque: Equatable {
        case parrafo(String)
        case titulo(String)
        case item(marca: String, texto: String)   // "•" o "1."
        case codigo(String)
    }

    static func bloques(_ texto: String) -> [Bloque] {
        var salida: [Bloque] = []
        var parrafo: [String] = []
        var codigo: [String]?
        func cerrarParrafo() {
            if !parrafo.isEmpty { salida.append(.parrafo(parrafo.joined(separator: "\n"))) }
            parrafo = []
        }
        for linea in texto.components(separatedBy: "\n") {
            let l = linea.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("```") {
                if let c = codigo { salida.append(.codigo(c.joined(separator: "\n"))); codigo = nil }
                else { cerrarParrafo(); codigo = [] }
                continue
            }
            if codigo != nil { codigo?.append(linea); continue }
            if l.isEmpty { cerrarParrafo(); continue }
            if let r = l.range(of: #"^#{1,4}\s+"#, options: .regularExpression) {
                cerrarParrafo(); salida.append(.titulo(String(l[r.upperBound...]))); continue
            }
            if let r = l.range(of: #"^[-*•]\s+"#, options: .regularExpression) {
                cerrarParrafo(); salida.append(.item(marca: "•", texto: String(l[r.upperBound...]))); continue
            }
            if let r = l.range(of: #"^\d{1,2}[.)]\s+"#, options: .regularExpression) {
                let numero = l[r].trimmingCharacters(in: .whitespaces).dropLast()
                cerrarParrafo(); salida.append(.item(marca: "\(numero).", texto: String(l[r.upperBound...]))); continue
            }
            parrafo.append(l)
        }
        if let c = codigo { salida.append(.codigo(c.joined(separator: "\n"))) }   // un bloque sin cerrar se muestra igual
        cerrarParrafo()
        return salida
    }

    // MARK: Idioma

    static func idioma(de texto: String) -> String? {
        let r = NLLanguageRecognizer()
        r.processString(String(texto.prefix(2000)))
        return r.dominantLanguage.map { String($0.rawValue.prefix(2)) }
    }

    static func nombreIdioma(_ codigo: String) -> String {
        let nombres: [String: (String, String)] = [
            "es": ("español", "Spanish"), "en": ("inglés", "English"), "pt": ("portugués", "Portuguese"),
            "fr": ("francés", "French"), "it": ("italiano", "Italian"), "de": ("alemán", "German"),
            "ja": ("japonés", "Japanese"), "zh": ("chino", "Chinese"), "ko": ("coreano", "Korean"), "ru": ("ruso", "Russian"),
        ]
        guard let n = nombres[codigo] else { return codigo.uppercased() }
        return T(n.0, n.1)
    }

    static func palabras(_ texto: String) -> Int { texto.split(whereSeparator: \.isWhitespace).count }

    // MARK: Botones para seguir trabajando

    enum Opcion: Hashable {
        case traducir(String)   // al idioma de ese código
        case reformular, masCorto, masFormal, masCasual, resumir, corregir
        case masDetallado       // el prompt de una imagen, con más detalle
        case cambiarAlgo        // el prompt de una imagen, cambiado por voz («que sea de noche»)
        case animar             // pregunta el formato del video (animarEn) y arma el prompt para animarla
        case animarEn(String)   // "9:16" o "16:9"
        case volver             // deja de preguntar el formato y vuelven los botones de antes
        case copiarImagen       // la imagen de la tarjeta, para pegarla como referencia en la app de video
        case mandarClaude       // la maqueta (resumen e imagen) a la ventana de Claude, para que la arme
        case promptImagen       // la maqueta pasada a un prompt de imagen

        var nombre: String {
            switch self {
            case .traducir(let a): T("Pasar a \(Respuestas.nombreIdioma(a))", "To \(Respuestas.nombreIdioma(a))")
            case .reformular: T("Reformular", "Rephrase")
            case .masCorto: T("Más corto", "Shorter")
            case .masFormal: T("Más formal", "More formal")
            case .masCasual: T("Más casual", "More casual")
            case .resumir: T("Resumir", "Summarize")
            case .corregir: T("Corregir", "Fix")
            case .masDetallado: T("Más detallado", "More detail")
            case .cambiarAlgo: T("Cambiar algo", "Change something")
            case .animar: T("Animarla", "Animate it")
            case .animarEn(let f): f == "9:16" ? T("Vertical 9:16", "Vertical 9:16") : T("Horizontal 16:9", "Horizontal 16:9")
            case .volver: T("Volver", "Back")
            case .copiarImagen: T("Copiar imagen", "Copy image")
            case .mandarClaude: T("Mandar a Claude", "Send to Claude")
            case .promptImagen: T("Prompt de imagen", "Image prompt")
            }
        }

        var trabajando: String {
            switch self {
            case .traducir(let a): T("Pasando a \(Respuestas.nombreIdioma(a))…", "Translating to \(Respuestas.nombreIdioma(a))…")
            case .resumir: T("Resumiendo…", "Summarizing…")
            case .corregir: T("Corrigiendo…", "Fixing…")
            case .animarEn: T("Armando el prompt del video…", "Writing the video prompt…")
            case .promptImagen: T("Armando el prompt…", "Writing the prompt…")
            default: T("Reescribiendo…", "Rewriting…")
            }
        }

        var icono: String {
            switch self {
            case .traducir: "globe"
            case .reformular: "arrow.triangle.2.circlepath"
            case .masCorto: "arrow.down.right.and.arrow.up.left"
            case .masFormal: "briefcase"
            case .masCasual: "face.smiling"
            case .resumir: "text.line.first.and.arrowtriangle.forward"
            case .corregir: "checkmark.seal"
            case .masDetallado: "plus.magnifyingglass"
            case .cambiarAlgo: "mic.fill"
            case .animar: "film"
            case .animarEn(let f): f == "9:16" ? "rectangle.portrait" : "rectangle"
            case .volver: "chevron.left"
            case .copiarImagen: "photo.on.rectangle"
            case .mandarClaude: "paperplane.fill"
            case .promptImagen: "wand.and.stars"
            }
        }

        // Pasar de idioma se intenta primero con el traductor de Apple (gratis); lo demás va a tu IA. Volver y
        // Copiar imagen no usan nada (no llevan la marquita de gratis: no hay nada que cobrar).
        var enLaMac: Bool { if case .traducir = self { true } else { false } }
        var sinIA: Bool { enLaMac || [.volver, .copiarImagen, .animar, .mandarClaude].contains(self) }

        // El pedido para la IA (también para traducir, si el idioma no está bajado en la Mac).
        var instruccion: String {
            switch self {
            case .traducir(let a): "Traducilo al \(Respuestas.nombreIdioma(a)). Devolvé solo la traducción, completa."
            case .reformular: "Reformulalo con otras palabras: mismo sentido, mismo idioma y largo parecido."
            case .masCorto: "Hacelo bastante más corto, sin perder lo importante. Mismo idioma."
            case .masFormal: "Hacelo más formal y profesional. Mismo idioma."
            case .masCasual: "Hacelo más casual y cercano. Mismo idioma."
            case .resumir: "Resumilo en pocas líneas, con lo importante. Mismo idioma."
            case .corregir: "Corregí ortografía, gramática y puntuación sin cambiar nada más. Mismo idioma."
            case .masDetallado: "Es un prompt para generar una imagen: hacelo más detallado (composición, luz, texturas, "
                + "materiales, estilo), sin cambiar lo que muestra. Mismo idioma, un solo párrafo."
            // Estos los resuelve el Motor aparte (no son una reescritura del texto).
            case .cambiarAlgo, .animar, .animarEn, .volver, .copiarImagen, .mandarClaude, .promptImagen: ""
            }
        }
    }

    // Qué botones ofrece la tarjeta según el texto: el otro idioma primero (es lo más pedido), después reescribir.
    // `idiomaPersona`: el de la interfaz ("es" o "en"). Hasta 5 botones.
    static func opciones(para texto: String, clase: Clase, idiomaPersona: String) -> [Opcion] {
        let n = palabras(texto)
        guard n > 0 else { return [] }
        let idioma = idioma(de: texto) ?? idiomaPersona
        let otro = idioma == "es" ? "en" : idioma == "en" ? "es" : idiomaPersona
        switch clase {
        case .uso, .codigos, .posteo, .colores:
            return []
        case .maqueta:
            return [.mandarClaude, .promptImagen, .traducir(otro)]
        case .traduccion(let de, _, _):
            return [.traducir(de), .reformular, .masCorto].filter { n > 3 || $0.enLaMac }
        case .textoLeido:
            return [.traducir(otro), .corregir] + (n > 120 ? [.resumir] : [])
        case .agente:
            return [.traducir(otro)] + (n > 120 ? [.resumir] : [])
        case .imagen:
            return [.traducir(otro), .masCorto] + (n > 120 ? [.resumir] : [])
        case .prompt:
            // Cambiar algo y Animarla primero: son lo que sigue después de sacar el prompt (01/11/2026).
            return [.cambiarAlgo, .animar, .traducir(otro), .masDetallado]
        case .video:
            return [.copiarImagen, .traducir(otro), .masCorto]
        case .texto:
            guard n > 3 else { return [.traducir(otro)] }
            var lista: [Opcion] = [.traducir(otro), .reformular, .masCorto, idioma == "en" ? .masCasual : .masFormal]
            if n > 120 { lista.insert(.resumir, at: 1) }
            return Array(lista.prefix(5))
        }
    }

    // MARK: Formato de una imagen

    // Para qué es la imagen: cambia el final del prompt (proporción y tamaño). Siempre en alta resolución.
    enum Formato: String, CaseIterable, Hashable {
        case original, cuadrado, post, historia, horizontal

        var nombre: String {
            switch self {
            case .original: T("Original", "Original")
            case .cuadrado: T("Cuadrado 1:1", "Square 1:1")
            case .post: T("Post 4:5", "Post 4:5")
            case .historia: T("Historia 9:16", "Story 9:16")
            case .horizontal: T("Horizontal 16:9", "Landscape 16:9")
            }
        }

        // Lo que dice el botón: corto, para que entren los cinco en la tarjeta (el nombre entero va en la ayuda).
        var corto: String {
            switch self {
            case .original: T("Original", "Original")
            case .cuadrado: "1:1"
            case .post: T("Post 4:5", "Post 4:5")
            case .historia: T("Historia 9:16", "Story 9:16")
            case .horizontal: "16:9"
            }
        }

        var ayuda: String {
            switch self {
            case .original: T("La forma de la imagen elegida.", "The shape of the picked image.")
            case .cuadrado: T("Cuadrado 1:1 (1080×1080): post de Instagram.", "Square 1:1 (1080×1080): Instagram post.")
            case .post: T("Vertical 4:5 (1080×1350): el post de Instagram que más ocupa.", "Portrait 4:5 (1080×1350): the biggest Instagram post.")
            case .historia: T("Vertical 9:16 (1080×1920): historias y reels.", "Vertical 9:16 (1080×1920): stories and reels.")
            case .horizontal: T("Horizontal 16:9 (1920×1080): YouTube y pantallas.", "Landscape 16:9 (1920×1080): YouTube and screens.")
            }
        }

        // Proporción y tamaño de Instagram y YouTube (original: los de la imagen elegida).
        var medida: (proporcion: String, pixeles: String)? {
            switch self {
            case .original: nil
            case .cuadrado: ("1:1", "1080×1080")
            case .post: ("4:5", "1080×1350")
            case .historia: ("9:16", "1080×1920")
            case .horizontal: ("16:9", "1920×1080")
            }
        }
    }

    /// El prompt con el final de `formato`: saca el que tenía («High resolution… Aspect ratio …», también en español
    /// si lo pasaste) y pone el nuevo. `original`: la proporción de la imagen elegida ("16:9").
    static func conFormato(_ texto: String, _ formato: Formato, original: String) -> String {
        let patron = #"(?i)[ \t]*(high resolution[^.\n]*\.\s*|alta resolución[^.\n]*\.\s*)?(aspect ratio|relación de aspecto|proporción)[^\n]*\s*$"#
        let cuerpo = texto.replacingOccurrences(of: patron, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let final = formato.medida.map { "High resolution, sharp detail, \($0.pixeles) px. Aspect ratio \($0.proporcion)." }
            ?? "High resolution, sharp detail. Aspect ratio \(original)."
        return cuerpo + " " + final
    }

    // MARK: Uso

    // "renueva en 42 min" / "renueva en 2 h 10 min" / "renueva el jueves", para la tarjeta de uso.
    static func cuentaRegresiva(hasta: Date, desde: Date) -> String {
        let s = Int(hasta.timeIntervalSince(desde))
        guard s > 60 else { return T("se renueva ahora", "resets now") }
        let h = s / 3600, m = (s % 3600) / 60
        if h == 0 { return T("renueva en \(m) min", "resets in \(m) min") }
        if h < 24 { return m == 0 ? T("renueva en \(h) h", "resets in \(h) h") : T("renueva en \(h) h \(m) min", "resets in \(h) h \(m) min") }
        let f = DateFormatter()
        f.locale = Locale(identifier: T("es_AR", "en_US"))
        f.dateFormat = "EEEE"
        return T("renueva el \(f.string(from: hasta))", "resets \(f.string(from: hasta))")
    }

    // MARK: Links

    // Los links del texto (un QR suele ser uno solo). Solo http y https: nada de abrir esquemas raros de un QR.
    static func links(_ texto: String) -> [URL] {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return d.matches(in: texto, range: NSRange(texto.startIndex..., in: texto)).compactMap(\.url)
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }
}
