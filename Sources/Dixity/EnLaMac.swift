import AppKit
import NaturalLanguage
import Translation
import Vision

// Preguntar resuelve en la Mac, sin IA ni gasto, lo que no necesita pensar (31/10/2026): traducir con el traductor de
// Apple, sacar el texto de la ventana o de una imagen copiada y leer códigos QR o de barras (Vision). Lo demás
// ("¿qué dice acá?", "resumime esto") sigue a tu IA. Nunca abre links: solo muestra lo que leyó.
enum EnLaMac {
    enum Herramienta: Equatable {
        case traducir(destino: String?)     // código de idioma ("en", "pt"…) o nil: el contrario del de la persona
        case leerTexto(deCopiada: Bool)
        case escanear(deCopiada: Bool)
    }

    // Qué herramienta pide, o nil si es para la IA. Solo pedidos cortos y directos: "traducilo al inglés y hacelo
    // más formal" tiene que pensar, así que va a la IA.
    static func entender(_ pedido: String) -> Herramienta? {
        let p = Diccionario.normalizar(pedido)
        let palabras = p.split(separator: " ").map(String.init)
        guard !palabras.isEmpty, palabras.count <= 10 else { return nil }
        let copiada = palabras.contains { ["copie", "copiada", "copiado", "copiaste", "portapapeles", "clipboard"].contains($0) }
        if palabras.contains("qr") || p.contains("codigo de barra") || p.contains("barcode")
            || palabras.contains { $0.hasPrefix("escane") || $0 == "scan" } {
            return .escanear(deCopiada: copiada)
        }
        if palabras.contains(where: { $0.hasPrefix("traduc") || $0 == "translate" }) {
            // "y" suma otro pedido ("…y resumilo"): eso lo hace la IA.
            guard !palabras.contains("y"), !palabras.contains("and") else { return nil }
            return .traducir(destino: idioma(en: palabras))
        }
        let pideSacar = palabras.contains { ["saca", "sacame", "sacale", "copia", "copiame", "extrae", "extraeme", "extract",
                                             "pasame", "dame", "get", "copy"].contains($0) }
        if palabras.contains("ocr") || (pideSacar && palabras.contains { $0 == "texto" || $0 == "text" }) {
            return .leerTexto(deCopiada: copiada)
        }
        return nil
    }

    private static func idioma(en palabras: [String]) -> String? {
        let nombres: [(String, String)] = [
            ("ingles", "en"), ("english", "en"), ("espanol", "es"), ("castellano", "es"), ("spanish", "es"),
            ("portugues", "pt"), ("portuguese", "pt"), ("frances", "fr"), ("french", "fr"), ("italiano", "it"),
            ("italian", "it"), ("aleman", "de"), ("german", "de"), ("japones", "ja"), ("japanese", "ja"),
            ("chino", "zh"), ("chinese", "zh"), ("coreano", "ko"), ("korean", "ko"), ("ruso", "ru"), ("russian", "ru"),
        ]
        return nombres.first { palabras.contains($0.0) }?.1
    }

    // Traduce con los idiomas bajados en la Mac (Ajustes del Sistema › General › Idioma y región › Idiomas de
    // traducción). nil si no se puede acá (macOS viejo, idioma sin bajar o ya está en ese idioma): entonces va a la IA.
    static func traducir(_ texto: String, a destino: String?, idiomaPersona: String) async -> String? {
        await traducirConIdiomas(texto, a: destino, idiomaPersona: idiomaPersona)?.texto
    }

    // Lo mismo, con los idiomas de ida y vuelta (la tarjeta de traducción muestra «ES → EN»).
    static func traducirConIdiomas(_ texto: String, a destino: String?, idiomaPersona: String) async
        -> (texto: String, de: String, a: String)? {
        guard #available(macOS 26, *) else { return nil }
        let reconocedor = NLLanguageRecognizer()
        reconocedor.processString(texto)
        guard let origen = reconocedor.dominantLanguage?.rawValue else { return nil }
        // Sin idioma pedido: si está en el tuyo, al inglés (o al español si usás la app en inglés); si no, al tuyo.
        let otro = idiomaPersona == "es" ? "en" : "es"
        let meta = destino ?? (origen.hasPrefix(idiomaPersona) ? otro : idiomaPersona)
        guard !origen.hasPrefix(meta) else { return nil }
        let de = Locale.Language(identifier: origen), a = Locale.Language(identifier: meta)
        guard await LanguageAvailability().status(from: de, to: a) == .installed else { return nil }
        let sesion = TranslationSession(installedSource: de, target: a)
        // Línea por línea, así quedan los párrafos y las listas como estaban.
        var salida: [String] = []
        for linea in texto.components(separatedBy: "\n") {
            if linea.trimmingCharacters(in: .whitespaces).isEmpty { salida.append(linea); continue }
            guard let t = try? await sesion.translate(linea).targetText else { return nil }
            salida.append(t)
        }
        return (salida.joined(separator: "\n"), String(origen.prefix(2)), String(meta.prefix(2)))
    }

    // Los códigos QR o de barras de la imagen, sin repetir y en el orden en que aparecen.
    static func codigos(en imagen: CGImage) -> [String] {
        let pedido = VNDetectBarcodesRequest()
        do { try VNImageRequestHandler(cgImage: imagen).perform([pedido]) } catch { return [] }
        var vistos: [String] = []
        for r in pedido.results ?? [] {
            if let s = r.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, !vistos.contains(s) {
                vistos.append(s)
            }
        }
        return vistos
    }

    // La imagen que copiaste (una captura, una foto del navegador), si la hay.
    static func imagenCopiada() -> CGImage? {
        guard let img = NSImage(pasteboard: .general) else { return nil }
        var rect = CGRect(origin: .zero, size: img.size)
        return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

extension EnLaMac {
    // Sin selección, ¿habla de lo que tiene adelante? ("¿qué dice acá?", "resumime esta página", "explicame este error").
    // Entonces Preguntar le pasa a la IA el texto de la ventana.
    static func hablaDeLoVisible(_ pedido: String) -> Bool {
        let p = " " + Diccionario.normalizar(pedido) + " "
        let sueltas = ["aca", "aqui", "esto", "pantalla", "pagina", "ventana", "here", "this", "screen", "page"]
        let frases = ["este mail", "este correo", "este mensaje", "este error", "este documento", "este articulo",
                      "esta nota", "esta imagen", "este texto", "esta conversacion", "este chat"]
        return sueltas.contains { p.contains(" \($0) ") } || frases.contains { p.contains(" \($0) ") }
    }
}

extension Motor {
    // Resuelve en la Mac lo que pide Preguntar. nil = esto no se puede acá (traducir sin selección o sin el idioma
    // bajado) y sigue a la IA. Si hay que avisar algo (falta el permiso, no hay ningún QR), tira el error para la píldora.
    static func resolverEnLaMac(_ h: EnLaMac.Herramienta, _ p: Pedido) async throws
        -> (texto: String, quien: String, clase: Respuestas.Clase)? {
        let enLaMac = T("en la Mac", "on your Mac")
        switch h {
        case .traducir(let destino):
            guard !p.seleccion.isEmpty,
                  let t = await EnLaMac.traducirConIdiomas(p.seleccion, a: destino, idiomaPersona: T("es", "en")) else { return nil }
            return (t.texto, T("Traductor de Apple", "Apple Translate") + " · " + enLaMac,
                    .traduccion(de: t.de, a: t.a, original: p.seleccion))
        case .leerTexto(let deCopiada):
            let imagen = try await imagenPara(deCopiada: deCopiada, p)
            let texto = Pantalla.texto(de: imagen, tope: 20_000)
            guard !texto.isEmpty else { throw ErrorPaso(mensaje: T("No encontré texto para leer.", "Couldn't find any text to read.")) }
            return (texto, T("Texto leído", "Text read") + " · " + enLaMac, .textoLeido)
        case .escanear(let deCopiada):
            var codigos = EnLaMac.codigos(en: try await imagenPara(deCopiada: deCopiada, p))
            // En la ventana no había: puede estar en la imagen que copiaste.
            if codigos.isEmpty, !deCopiada, let copiada = EnLaMac.imagenCopiada() { codigos = EnLaMac.codigos(en: copiada) }
            guard !codigos.isEmpty else {
                throw ErrorPaso(mensaje: T("No encontré ningún código QR ni de barras.", "Couldn't find any QR code or barcode."))
            }
            return (codigos.joined(separator: "\n"), T("Código leído", "Code read") + " · " + enLaMac, .codigos)
        }
    }

    // La imagen copiada, o la foto de la ventana donde preguntaste (que pide Grabación de pantalla).
    private static func imagenPara(deCopiada: Bool, _ p: Pedido) async throws -> CGImage {
        if deCopiada {
            guard let i = EnLaMac.imagenCopiada() else {
                throw ErrorPaso(mensaje: T("No hay ninguna imagen copiada.", "There's no copied image."))
            }
            return i
        }
        guard Pantalla.permitido else {
            throw ErrorPaso(mensaje: T("Para mirar la ventana falta el permiso de Grabación de pantalla (General › Permisos).",
                                       "To look at the window, allow Screen Recording (General › Permissions)."))
        }
        guard let pid = p.pid, let i = await Pantalla.foto(pid: pid) else {
            throw ErrorPaso(mensaje: T("No pude mirar esa ventana.", "Couldn't look at that window."))
        }
        return i
    }
}
