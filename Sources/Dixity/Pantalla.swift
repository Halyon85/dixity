import AppKit
import Carbon
import ScreenCaptureKit
import Vision

// "Leer la pantalla": al empezar a dictar saca una foto de la ventana de adelante, lee su texto en la Mac (Vision)
// y la suelta enseguida. La imagen nunca se guarda ni se manda: a la IA le llega solo el texto, con tope.
// Aparte, la Varita: recorta lo que elegiste y, para Describir, Sacar prompt o Preguntar sobre una imagen, se la
// manda a tu IA (`paraIA`) solo cuando vos lo pedís.
enum Pantalla {
    static var permitido: Bool { CGPreflightScreenCaptureAccess() }
    static func pedirPermiso() { _ = CGRequestScreenCaptureAccess() }

    // El texto visible de la ventana de adelante de `pid`, o "" si no se puede o no conviene.
    static func leer(pid: pid_t, tope: Int = 1500) async -> String {
        guard let imagen = await foto(pid: pid) else { return "" }
        // El pool suelta la imagen al terminar. Medido 21/10: leer tarda 0,2–0,6 s y sube la memoria a ~85 MB;
        // a los 2 s queda en ~55 MB porque Vision se guarda su modelo (la 1.ª lectura después de instalar tardó 29 s).
        return texto(de: imagen, tope: tope)
    }

    // La foto de la ventana de adelante de `pid` (también para Preguntar: QR y "sacame el texto"). Sin permiso no se
    // pide nada (no aparecen carteles en medio de un dictado); con una contraseña activa o un gestor de contraseñas
    // adelante, tampoco.
    static func foto(pid: pid_t) async -> CGImage? {
        guard permitido, !IsSecureEventInputEnabled() else { return nil }
        if Secretos.esGestor(NSRunningApplication(processIdentifier: pid)) { return nil }
        return await capturar(pid: pid)
    }

    // El texto de una imagen, leído en la Mac. Lo que parece una clave o va después de "contraseña:" se tapa antes de
    // mandarlo o mostrarlo (auditoría del 23/10/2026).
    static func texto(de imagen: CGImage, tope: Int) -> String {
        Secretos.tapar(autoreleasepool { reconocer(imagen, tope: tope) })
    }

    /// Una foto de un rectángulo de la pantalla (coordenadas de AppKit), tal como se ve, sin las ventanitas de Dixity.
    /// La usa la Varita para copiar o leer lo que elegiste. Nil sin permiso de Grabación de pantalla o con una
    /// contraseña activa. `maxPixeles`: el lado más largo, como mucho (para buscar un QR alcanza una foto chica, y una
    /// a tamaño completo de una imagen grande ocupaba decenas de MB).
    static func recorte(_ marco: CGRect, maxPixeles: CGFloat? = nil) async -> CGImage? {
        guard permitido, !IsSecureEventInputEnabled(), marco.width >= 2, marco.height >= 2,
              let pantalla = pantalla(de: marco, en: NSScreen.screens.map(\.frame)).map({ NSScreen.screens[$0] }),
              let numero = pantalla.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let contenido = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = contenido.displays.first(where: { $0.displayID == numero }) else { return nil }
        let propias = contenido.applications.filter { $0.processID == getpid() }
        let filtro = SCContentFilter(display: display, excludingApplications: propias, exceptingWindows: [])
        let conf = SCStreamConfiguration()
        let recorte = marco.intersection(pantalla.frame)
        // ScreenCaptureKit cuenta desde arriba a la izquierda de esa pantalla.
        conf.sourceRect = CGRect(x: recorte.minX - pantalla.frame.minX, y: pantalla.frame.maxY - recorte.maxY,
                                 width: recorte.width, height: recorte.height)
        var escala = pantalla.backingScaleFactor
        if let tope = maxPixeles { escala = min(escala, tope / max(recorte.width, recorte.height)) }
        conf.width = Int(recorte.width * escala)
        conf.height = Int(recorte.height * escala)
        conf.showsCursor = false
        conf.capturesAudio = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filtro, configuration: conf)
    }

    /// La pantalla donde queda la mayor parte de `marco` (con dos pantallas, un recuadro que toca las dos se saca de
    /// la que tiene más; antes, de la primera de la lista). Nil si no toca ninguna.
    static func pantalla(de marco: CGRect, en pantallas: [CGRect]) -> Int? {
        let areas = pantallas.map { p -> CGFloat in let i = marco.intersection(p); return i.isNull ? 0 : i.width * i.height }
        guard let mayor = areas.max(), mayor > 0 else { return nil }
        return areas.firstIndex(of: mayor)
    }

    /// Por qué `recorte` no sacó la foto, para el aviso («Para copiar imágenes…»). Con una contraseña activa en otra
    /// app (un campo de contraseña, la Terminal con «Entrada de teclado segura») macOS no deja sacar fotos de la
    /// pantalla: antes el aviso decía que faltaba el permiso aunque estuviera dado (01/11/2026).
    static var hayContrasena: Bool { IsSecureEventInputEnabled() }

    static func porQueNo(_ es: String, _ en: String, contrasena: Bool = hayContrasena) -> String {
        if permitido && contrasena {
            return T("Hay una contraseña activa en otra app y macOS no deja sacar fotos de la pantalla mientras tanto. Cerrá ese campo y probá de nuevo.",
                     "A password field is active in another app, and macOS blocks screen pictures until it closes. Close it and try again.")
        }
        return T("Para \(es) falta el permiso de Grabación de pantalla (General › Permisos).", "To \(en), allow Screen Recording (General › Permissions).")
    }

    /// Una imagen lista para mandar a la IA: JPEG de hasta 1280 px del lado largo (más grande no la ve mejor y tarda
    /// más en subir). Nil si no se pudo armar.
    static func paraIA(_ imagen: CGImage, lado: CGFloat = 1280) -> Data? {
        let factor = min(1, lado / CGFloat(max(imagen.width, imagen.height)))
        let ancho = max(1, Int(CGFloat(imagen.width) * factor)), alto = max(1, Int(CGFloat(imagen.height) * factor))
        guard let espacio = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: 0, space: espacio,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(.white)   // lo transparente queda blanco y no negro
        ctx.fill(CGRect(x: 0, y: 0, width: ancho, height: alto))
        ctx.interpolationQuality = .high
        ctx.draw(imagen, in: CGRect(x: 0, y: 0, width: ancho, height: alto))
        guard let chica = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: chica).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    /// Lo mismo desde un archivo (las imágenes de la Varita guardadas para seguir preguntando sobre ellas).
    static func paraIA(archivo: URL) -> Data? {
        guard let fuente = CGImageSourceCreateWithURL(archivo as CFURL, nil),
              let imagen = CGImageSourceCreateImageAtIndex(fuente, 0, nil) else { return nil }
        return paraIA(imagen)
    }

    /// Qué reconoce la Mac en una foto («dog», «beach»…), lo más seguro primero. Para Describir sin una IA que vea
    /// imágenes. Vienen en inglés: el Motor las pasa al idioma de la persona si puede.
    static func etiquetas(de imagen: CGImage, cuantas: Int = 6) -> [String] {
        autoreleasepool {
            let pedido = VNClassifyImageRequest()
            do { try VNImageRequestHandler(cgImage: imagen).perform([pedido]) } catch { return [] }
            return (pedido.results ?? []).filter { $0.confidence >= 0.3 }.sorted { $0.confidence > $1.confidence }.prefix(cuantas)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }
    }

    /// Los colores principales de una imagen, del que más ocupa al que menos, con cuánto ocupa (0…1). En la Mac:
    /// se achica a 64 × 64, se agrupan los parecidos y se saltean los casi iguales a uno ya elegido. Para «Sacar
    /// colores» de la Varita (un logo, un banner, una sección).
    static func colores(de imagen: CGImage, cuantos: Int = 6) -> [(hex: String, parte: Double)] {
        let lado = 64
        guard let espacio = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: lado * 4, space: espacio,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let datos = ctx.data else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(imagen, in: CGRect(x: 0, y: 0, width: lado, height: lado))
        let px = datos.bindMemory(to: UInt8.self, capacity: lado * lado * 4)
        // Grupos de 4 bits por canal: suma de cada canal y cuántos píxeles cayeron ahí.
        var grupos: [Int: (r: Int, g: Int, b: Int, n: Int)] = [:]
        var total = 0
        for i in 0..<(lado * lado) {
            let a = Int(px[i * 4 + 3])
            guard a > 200 else { continue }   // lo transparente no es un color del logo
            let r = Int(px[i * 4]), g = Int(px[i * 4 + 1]), b = Int(px[i * 4 + 2])
            let clave = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let v = grupos[clave] ?? (0, 0, 0, 0)
            grupos[clave] = (v.r + r, v.g + g, v.b + b, v.n + 1)
            total += 1
        }
        guard total > 0 else { return [] }
        var elegidos: [(r: Int, g: Int, b: Int, n: Int)] = []
        for v in grupos.values.sorted(by: { $0.n > $1.n }) {
            let c = (r: v.r / v.n, g: v.g / v.n, b: v.b / v.n, n: v.n)
            if let i = elegidos.firstIndex(where: { abs($0.r - c.r) + abs($0.g - c.g) + abs($0.b - c.b) < 60 }) {
                elegidos[i].n += c.n   // casi igual a uno que ya está: suma a ese
            } else if elegidos.count < cuantos {
                elegidos.append(c)
            }
        }
        return elegidos.sorted { $0.n > $1.n }.map {
            (String(format: "#%02X%02X%02X", $0.r, $0.g, $0.b), Double($0.n) / Double(total))
        }
    }

    private static func capturar(pid: pid_t) async -> CGImage? {
        guard let contenido = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              // Vienen de adelante hacia atrás: la primera ventana normal de la app es la que estás usando.
              let ventana = contenido.windows.first(where: {
                  $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 120 && $0.frame.height > 80
              }) else { return nil }
        let conf = SCStreamConfiguration()
        // Hasta 1800 px del lado largo: alcanza para leer letra chica y no gasta memoria de más.
        let factor = min(2, 1800 / max(ventana.frame.width, ventana.frame.height))
        conf.width = Int(ventana.frame.width * factor)
        conf.height = Int(ventana.frame.height * factor)
        conf.showsCursor = false
        conf.capturesAudio = false
        return try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: ventana),
                                                           configuration: conf)
    }

    private static func reconocer(_ imagen: CGImage, tope: Int) -> String {
        let pedido = VNRecognizeTextRequest()
        pedido.recognitionLevel = .accurate
        pedido.recognitionLanguages = ["es-ES", "en-US"]
        pedido.usesLanguageCorrection = true
        do { try VNImageRequestHandler(cgImage: imagen).perform([pedido]) } catch { return "" }
        var lineas: [String] = []
        for r in pedido.results ?? [] {
            guard let l = r.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces), l.count > 1 else { continue }
            if lineas.last != l { lineas.append(l) }
        }
        let texto = lineas.joined(separator: "\n")
        // Si sobra, queda la parte de abajo: en chats y editores es donde está lo último y el campo donde escribís.
        return texto.count > tope ? String(texto.suffix(tope)) : texto
    }
}
