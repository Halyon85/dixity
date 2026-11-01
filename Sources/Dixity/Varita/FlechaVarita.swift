import AppKit
import ImageIO
import OSLog
import UniformTypeIdentifiers

// La flecha de la Varita: mientras está prendida, la flecha del sistema (en todas las apps) pasa a ser la de Dixity
// —relleno celeste, azul y lavanda que gira por dentro y un aura azul fija—. Es la flecha de verdad, así que no tiene
// demora. Al apagarla vuelve la original.
//
// A propósito usa funciones internas de macOS (las mismas que la app Mousecape): Apple no ofrece otra forma de cambiar
// la flecha en otras apps. Si un macOS futuro no las trae, la Varita anda igual, solo que sin flecha propia.
// Probado el 31/10/2026 en macOS 27.2: `CoreCursorUnregisterAll` NO devuelve la original, por eso antes de cambiarla se
// copian las originales (`CGSCopyRegisteredCursorImages`) y al apagar se vuelven a registrar.
//
// La copia se guarda en disco (carpeta de Dixity › flecha-original), no solo en memoria: hasta el 31/10 vivía en
// memoria y, cada vez que Dixity se reinstalaba, tomaba como "original" la flecha que había quedado de antes. Así la de
// verdad se perdió y quedó un triangulito (la puntita del dibujo del menú contextual). Ahora solo se guarda una flecha
// que no es nuestra ni una rearmada por Dixity; si todavía no hay copia de la de verdad, al apagar vuelve la flecha
// clásica de macOS, dibujada acá. La de verdad vuelve sola al cerrar sesión y, desde ahí, Dixity la guarda.
enum FlechaVarita {
    private typealias FnConexion = @convention(c) () -> Int32
    private typealias FnRegistrar = @convention(c) (Int32, UnsafePointer<CChar>, Bool, Bool, CGSize, CGPoint, UInt, CGFloat,
                                                    CFArray, UnsafeMutablePointer<Int32>) -> Int32
    private typealias FnCopiar = @convention(c) (Int32, UnsafePointer<CChar>, UnsafeMutablePointer<CGSize>, UnsafeMutablePointer<CGPoint>,
                                                 UnsafeMutablePointer<UInt>, UnsafeMutablePointer<CGFloat>,
                                                 UnsafeMutablePointer<Unmanaged<CFArray>?>) -> Int32

    private static func funcion<T>(_ nombre: String, _: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), nombre).map { unsafeBitCast($0, to: T.self) }   // RTLD_DEFAULT
    }
    private static let conexion = funcion("CGSMainConnectionID", FnConexion.self)
    private static let registrar = funcion("CGSRegisterCursorWithImages", FnRegistrar.self)
    private typealias FnSacar = @convention(c) (Int32, UnsafePointer<CChar>, UnsafeMutablePointer<Int32>) -> Int32
    private static let sacar = funcion("CGSRemoveRegisteredCursor", FnSacar.self)
    private typealias FnLeerEscala = @convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32
    private typealias FnPonerEscala = @convention(c) (Int32, Float) -> Int32
    private static let leerEscala = funcion("CGSGetCursorScale", FnLeerEscala.self)
    private static let ponerEscala = funcion("CGSSetCursorScale", FnPonerEscala.self)
    private static let copiar = funcion("CGSCopyRegisteredCursorImages", FnCopiar.self)

    /// Las flechas que se cambian: la común, su variante de macOS 26+ y la del menú contextual (⌃ + clic).
    static let nombres = ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowS", "com.apple.coregraphics.ArrowCtx"]
    static var disponible: Bool { conexion != nil && registrar != nil && copiar != nil }

    // Una flecha tal como la tiene registrada el sistema.
    struct Registrada {
        var tam: CGSize
        var punta: CGPoint
        var cuadros: UInt
        var duracion: CGFloat
        var imagenes: [CGImage]
    }

    // MARK: Prender y apagar

    private(set) static var puesta = false
    private static var originales: [String: Registrada] = [:]
    private static let registro = Logger(subsystem: "team.halyon.dixity", category: "varita")

    /// Pone la flecha de la Varita. Antes guarda las originales (solo las de verdad, en memoria y en disco). false si
    /// no se pudo.
    @discardableResult
    static func poner() -> Bool {
        guard let conexion, let registrar, !puesta else { return puesta }
        let cid = conexion()
        for n in nombres where originales[n] == nil {
            if let r = leer(n), esDeVerdad(r, nombre: n) {
                originales[n] = r
                guardarEnDisco(r, nombre: n)
            } else if let r = leerDeDisco(n) {
                originales[n] = r
            }
        }
        guard let x1 = Dibujo.varita(escala: 1), let x2 = Dibujo.varita(escala: 2) else { return false }
        let varita = Registrada(tam: Dibujo.tam, punta: Dibujo.punta, cuadros: UInt(Dibujo.cuadros), duracion: Dibujo.duracion, imagenes: [x1, x2])
        var bien = true
        for n in nombres { bien = poner(varita, en: n, cid: cid, registrar: registrar) && bien }
        // macOS a veces responde que sí y no la cambia (31/10, después de devolver la clásica): se comprueba leyéndola.
        if bien, let actual = leer(nombres[0]), !esNuestra(actual) {
            registro.notice("la Varita no quedó puesta (sigue una de \(Int(actual.tam.width))×\(Int(actual.tam.height))): la saco y la vuelvo a poner")
            for n in nombres {
                var semilla: Int32 = 0
                if let sacar { _ = n.withCString { sacar(cid, $0, &semilla) } }
                bien = poner(varita, en: n, cid: cid, registrar: registrar) && bien
            }
            let ahora = leer(nombres[0])
            bien = bien && ahora.map(esNuestra) == true
            registro.notice("segundo intento: \(bien ? "puesta" : "macOS no la cambió", privacy: .public)")
        }
        puesta = bien
        refrescar()
        // Marca en disco: si Dixity se cierra de golpe con la Varita puesta, al abrir la devuelve.
        if bien { FileManager.default.createFile(atPath: marca.path, contents: Data()) }
        return bien
    }

    private static func poner(_ r: Registrada, en n: String, cid: Int32, registrar: FnRegistrar) -> Bool {
        var semilla: Int32 = 0
        return n.withCString { registrar(cid, $0, true, true, r.tam, r.punta, r.cuadros, r.duracion, r.imagenes as CFArray, &semilla) } == 0
    }

    /// Devuelve las flechas originales. Lo llaman: apagar la Varita, cerrar Dixity y abrirla si quedó puesta.
    static func devolver() {
        defer {
            puesta = false
            try? FileManager.default.removeItem(at: marca)
        }
        guard let conexion, let registrar else { return }
        let cid = conexion()
        for n in nombres {
            // La copia de verdad (de esta vez o guardada en disco); si no hay, la clásica (y el menú contextual del
            // sistema para ⌃ + clic).
            let copia = originales[n] ?? leerDeDisco(n)
            guard let o = copia ?? (n.hasSuffix("ArrowCtx") ? Dibujo.rearmada(n) : Dibujo.clasicaNormal) else { continue }
            if n == nombres[0] { registro.notice("flecha devuelta: \(copia != nil ? "la de verdad" : "la clásica", privacy: .public)") }
            var semilla: Int32 = 0
            _ = n.withCString {
                registrar(cid, $0, true, true, o.tam, o.punta, o.cuadros, o.duracion, o.imagenes as CFArray, &semilla)
            }
        }
        refrescar()
    }

    /// Hace que la pantalla redibuje la flecha ya. Cambiarla no alcanza: macOS la vuelve a dibujar recién cuando una app
    /// pide la flecha otra vez (al pasar de un texto a un botón, por ejemplo), y si ninguna la pedía se seguía viendo
    /// la de antes: por eso la Varita a veces cambiaba la flecha y a veces no (31/10). Se le cambia el tamaño al
    /// puntero un instante (y se le devuelve el de siempre, el de Accesibilidad) y se manda un movimiento del mouse en
    /// el mismo lugar, marcado como propio.
    /// El tamaño que se devuelve es el elegido en Accesibilidad, no el que hay en ese momento: al sacudir, macOS puede
    /// estar agrandando el puntero («Agitar para localizarlo») y quedaba fijo así (revisión del 31/10).
    private static func refrescar() {
        if let conexion, let leerEscala, let ponerEscala {
            let cid = conexion()
            var ahora: Float = 1
            let elegido = (CFPreferencesCopyAppValue("mouseDriverCursorSize" as CFString, "com.apple.universalaccess" as CFString) as? NSNumber)?.floatValue ?? 1
            if leerEscala(cid, &ahora) == 0, elegido >= 1 {
                _ = ponerEscala(cid, elegido + 0.01)
                _ = ponerEscala(cid, elegido)
            }
        }
        let alto = NSScreen.screens.first?.frame.height ?? 0
        let p = NSEvent.mouseLocation
        if let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x, y: alto - p.y), mouseButton: .left) {
            e.setIntegerValueField(.eventSourceUserData, value: Motor.marcaPropia)
            e.post(tap: .cghidEventTap)
        }
    }

    /// Al abrir Dixity: si la última vez quedó la Varita puesta (se cortó la luz, se colgó), devuelve la original.
    static func revisarAlAbrir() {
        let quedoPuesta = FileManager.default.fileExists(atPath: marca.path)
        let actual = leer(nombres[0])
        // Se devuelve también si quedó la clásica grande del primer intento: así vuelve la del tamaño normal.
        let alDia = actual.map { r in Dibujo.clasicaNormal.map { seParecen(r, $0) } ?? false } ?? false
        if quedoPuesta || actual.map({ !esDeVerdad($0, nombre: nombres[0]) && !alDia }) == true { devolver() }
    }

    private static var marca: URL { Almacen.carpeta.appendingPathComponent("varita-puesta") }

    // MARK: La copia en disco

    private static var carpetaCopia: URL { Almacen.carpeta.appendingPathComponent("flecha-original", isDirectory: true) }

    // Cada flecha: un PNG por tamaño (1x, 2x…) y un archivo con su tamaño, punta, cuadros y duración.
    private static func guardarEnDisco(_ r: Registrada, nombre: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: carpetaCopia, withIntermediateDirectories: true)
        for (i, img) in r.imagenes.enumerated() {
            let url = carpetaCopia.appendingPathComponent("\(nombre)-\(i).png") as CFURL
            guard let d = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(d, img, nil)
            guard CGImageDestinationFinalize(d) else { return }
        }
        let datos: [String: Any] = ["ancho": r.tam.width, "alto": r.tam.height, "x": r.punta.x, "y": r.punta.y,
                                    "cuadros": r.cuadros, "duracion": r.duracion, "imagenes": r.imagenes.count]
        (datos as NSDictionary).write(to: carpetaCopia.appendingPathComponent("\(nombre).plist"), atomically: true)
    }

    private static func leerDeDisco(_ nombre: String) -> Registrada? {
        guard let d = NSDictionary(contentsOf: carpetaCopia.appendingPathComponent("\(nombre).plist")) as? [String: Any],
              let n = d["imagenes"] as? Int, n > 0 else { return nil }
        let imagenes = (0..<n).compactMap { i -> CGImage? in
            let url = carpetaCopia.appendingPathComponent("\(nombre)-\(i).png") as CFURL
            return CGImageSourceCreateWithURL(url, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }
        guard imagenes.count == n else { return nil }
        func num(_ k: String) -> CGFloat { CGFloat((d[k] as? NSNumber)?.doubleValue ?? 0) }
        let r = Registrada(tam: CGSize(width: num("ancho"), height: num("alto")), punta: CGPoint(x: num("x"), y: num("y")),
                           cuadros: UInt(num("cuadros")), duracion: num("duracion"), imagenes: imagenes)
        return esDeVerdad(r, nombre: nombre) ? r : nil
    }

    // MARK: Leer

    static func leer(_ nombre: String) -> Registrada? {
        guard let conexion, let copiar else { return nil }
        var tam = CGSize.zero, punta = CGPoint.zero, cuadros: UInt = 0, duracion: CGFloat = 0
        var imagenes: Unmanaged<CFArray>?
        let r = nombre.withCString { copiar(conexion(), $0, &tam, &punta, &cuadros, &duracion, &imagenes) }
        guard r == 0, let lista = imagenes?.takeRetainedValue() as? [CGImage], !lista.isEmpty else { return nil }
        return Registrada(tam: tam, punta: punta, cuadros: cuadros, duracion: duracion, imagenes: lista)
    }

    /// ¿Es una flecha que puso Dixity (o una de las pruebas del 31/10)? Se reconocen por la punta, que es propia.
    /// Así nunca se guarda como «original» una flecha de la Varita.
    static func esNuestra(_ r: Registrada) -> Bool {
        let puntas = [CGPoint(x: 6.4, y: 5.2), CGPoint(x: 11.34, y: 9.56), CGPoint(x: 15.34, y: 13.56), Dibujo.punta]
        return puntas.contains { abs($0.x - r.punta.x) < 0.05 && abs($0.y - r.punta.y) < 0.05 }
    }

    /// ¿Es la flecha de verdad del sistema? No lo es una de la Varita, ni una que rearmó Dixity al devolverla (la del
    /// dibujo del menú contextual, el triangulito, o la clásica): esas se reconocen por cómo se ven.
    static func esDeVerdad(_ r: Registrada, nombre: String) -> Bool {
        guard !esNuestra(r), !esClasica(r) else { return false }
        guard let rearmada = Dibujo.rearmada(nombre) else { return true }
        return !seParecen(r, rearmada)
    }

    /// La clásica de ahora o la grande del primer intento (nunca son la de verdad).
    static func esClasica(_ r: Registrada) -> Bool {
        [Dibujo.clasicaNormal, Dibujo.clasicaGrande].contains { $0.map { seParecen(r, $0) } ?? false }
    }

    /// Dos flechas se ven igual: mismo tamaño y punta, y el dibujo de 1x casi idéntico (se comparan dibujadas en el
    /// mismo formato, porque el sistema puede devolver los píxeles en otro).
    static func seParecen(_ a: Registrada, _ b: Registrada) -> Bool {
        guard a.tam == b.tam, abs(a.punta.x - b.punta.x) < 0.05, abs(a.punta.y - b.punta.y) < 0.05,
              let ia = a.imagenes.first, let ib = b.imagenes.first,
              let pa = pixeles(ia, tam: a.tam), let pb = pixeles(ib, tam: b.tam) else { return false }
        let diferencia = zip(pa, pb).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(diferencia) / Double(max(1, pa.count)) < 3
    }

    private static func pixeles(_ img: CGImage, tam: CGSize) -> [UInt8]? {
        let w = Int(tam.width), h = Int(tam.height)
        guard w > 0, h > 0, let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.interpolationQuality = .medium
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let datos = c.data else { return nil }
        return Array(UnsafeBufferPointer(start: datos.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
    }
}

// MARK: - Dibujo

extension FlechaVarita {
    enum Dibujo {
        static let lado: CGFloat = 48            // lugar para el aura
        static let tam = CGSize(width: lado, height: lado)
        static let cuadros = 12
        static let duracion: CGFloat = 0.09     // una vuelta del brillo de adentro cada ~1,1 s
        private static let k: CGFloat = 0.78, dx: CGFloat = 13, dy: CGFloat = 12
        static let punta = CGPoint(x: 3 * k + dx, y: 2 * k + dy)

        private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
        }

        // La flecha clásica (punta en 3, 2 en una grilla de 34 × 40), dentro del cuadro de 48 pt.
        private static func camino(_ escala: CGFloat) -> CGPath {
            let alto = lado * escala
            let p = CGMutablePath()
            let pts: [(CGFloat, CGFloat)] = [(3, 2), (3, 26), (9, 20.2), (13.2, 29.6), (17.2, 27.9), (13.1, 18.7), (21.3, 18.7)]
            for (i, (x, y)) in pts.enumerated() {
                let q = CGPoint(x: (x * k + dx) * escala, y: alto - (y * k + dy) * escala)   // CoreGraphics cuenta desde abajo
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
            return p
        }

        /// La tira de cuadros (uno debajo del otro, el primero arriba) a 1x o 2x. Diseño elegido el 31/10: aura fija
        /// que no late (dos capas: un velo ancho y suave y el aura más cerca) y el relleno que gira por dentro.
        static func varita(escala: CGFloat) -> CGImage? {
            let alto = lado * escala
            guard let c = CGContext(data: nil, width: Int(alto), height: Int(alto) * cuadros, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            let degradado = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       colors: [color(0.62, 0.92, 1), color(0.3, 0.55, 0.97), color(0.7, 0.68, 1)] as CFArray,
                                       locations: [0, 0.45, 1])!
            let flecha = camino(escala)
            for i in 0..<cuadros {
                c.saveGState()
                c.translateBy(x: 0, y: CGFloat(cuadros - 1 - i) * alto)
                for (desenfoque, sombra, relleno) in [(16.0, color(0.33, 0.55, 1, 0.9), color(0.4, 0.65, 1, 0.6)),
                                                      (10.0, color(0.4, 0.68, 1, 1), color(0.4, 0.65, 1, 0.85)),
                                                      (3.5, color(0.55, 0.85, 1, 0.9), color(0.45, 0.75, 1, 1))] {
                    c.saveGState()
                    c.setShadow(offset: .zero, blur: desenfoque * escala, color: sombra)
                    c.addPath(flecha); c.setFillColor(relleno); c.fillPath()
                    c.restoreGState()
                }
                c.saveGState()
                c.addPath(flecha); c.clip()
                let a = CGFloat(i) / CGFloat(cuadros) * 2 * .pi
                let centro = CGPoint(x: alto * 0.467, y: alto * 0.49), r = alto * 0.2
                c.drawLinearGradient(degradado, start: CGPoint(x: centro.x - cos(a) * r, y: centro.y - sin(a) * r),
                                     end: CGPoint(x: centro.x + cos(a) * r, y: centro.y + sin(a) * r),
                                     options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                c.restoreGState()
                c.addPath(flecha); c.setStrokeColor(.white); c.setLineWidth(1.4 * escala); c.setLineJoin(.round); c.strokePath()
                c.restoreGState()
            }
            return c.makeImage()
        }

        // La flecha de macOS 27 sale del dibujo del menú contextual del sistema (la misma flecha con un menucito abajo,
        // en un lienzo de 28 × 40 y la punta en 5, 5): la común es la parte de arriba. Solo se usa si no hay copia
        // guardada. En otros macOS el archivo puede no estar: entonces no se toca nada (vuelve al cerrar sesión).
        private static let menuContextual = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors/contextualmenu/cursor.pdf"

        /// La flecha clásica de macOS (negra, con borde blanco y su sombra), en el mismo lienzo de 28 × 40 con la punta
        /// en 5, 5. Es la que vuelve al apagar la Varita mientras no haya copia de la flecha de verdad. `k` es el tamaño:
        /// 0,62 da la flecha normal de la Mac (unos 14 × 20 pt con el borde). La primera versión (31/10) usó 1, el
        /// tamaño de la flecha de la Varita, y quedó enorme; esa se sigue reconociendo para no guardarla nunca como
        /// la de verdad.
        static let tamClasica: CGFloat = 0.62
        // Se dibujan una vez y se reusan: prender la Varita las compara cada vez con la flecha que hay (antes se volvían
        // a dibujar en cada prendida, en el hilo principal).
        static let clasicaNormal = clasica()
        static let clasicaGrande = clasica(k: 1)
        private static var rearmadas: [String: Registrada?] = [:]
        static func rearmada(_ nombre: String) -> Registrada? {
            if let r = rearmadas[nombre] { return r }
            let r = originalDelSistema(nombre)
            rearmadas[nombre] = r
            return r
        }
        static func clasica(k: CGFloat = tamClasica) -> Registrada? {
            let tam = CGSize(width: 28, height: 40)
            let imagenes = [1.0, 2.0].compactMap { (escala: CGFloat) -> CGImage? in
                guard let c = CGContext(data: nil, width: Int(tam.width * escala), height: Int(tam.height * escala), bitsPerComponent: 8,
                                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                let p = CGMutablePath()
                let pts: [(CGFloat, CGFloat)] = [(3, 2), (3, 26), (9, 20.2), (13.2, 29.6), (17.2, 27.9), (13.1, 18.7), (21.3, 18.7)]
                for (i, (x, y)) in pts.enumerated() {
                    let q = CGPoint(x: (x * k + 5 - 3 * k) * escala, y: (tam.height - (y * k + 5 - 2 * k)) * escala)   // punta en 5, 5
                    if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
                p.closeSubpath()
                c.setLineJoin(.round)
                // Borde blanco con la sombra de macOS (la de su info.plist) y adentro, negra.
                c.saveGState()
                c.setShadow(offset: CGSize(width: 0, height: -1 * escala), blur: 2 * escala, color: NSColor(white: 0, alpha: 0.45).cgColor)
                c.addPath(p); c.setStrokeColor(.white); c.setLineWidth((k < 1 ? 2.5 : 3) * escala); c.strokePath()
                c.restoreGState()
                c.addPath(p); c.setFillColor(.black); c.fillPath()   // tapa la mitad de adentro del borde: queda 1,5 pt blanco
                return c.makeImage()
            }
            guard imagenes.count == 2 else { return nil }
            return Registrada(tam: tam, punta: CGPoint(x: 5, y: 5), cuadros: 1, duracion: 0, imagenes: imagenes)
        }

        static func originalDelSistema(_ nombre: String) -> Registrada? {
            guard let pdf = NSImage(contentsOfFile: menuContextual), pdf.size == NSSize(width: 28, height: 40) else { return nil }
            let completo = nombre.hasSuffix("ArrowCtx")
            let imagenes = [1.0, 2.0].compactMap { imagen(pdf, escala: $0, completo: completo) }
            guard imagenes.count == 2 else { return nil }
            return Registrada(tam: pdf.size, punta: CGPoint(x: 5, y: 5), cuadros: 1, duracion: 0, imagenes: imagenes)
        }

        private static func imagen(_ pdf: NSImage, escala: CGFloat, completo: Bool) -> CGImage? {
            let tam = pdf.size
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(tam.width * escala), pixelsHigh: Int(tam.height * escala),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
            rep.size = tam
            // Primero la flecha sola (sin el menucito) y después con la sombra de macOS (info.plist del cursor).
            let sola = NSImage(size: tam, flipped: false) { _ in
                if !completo {
                    let recorte = NSBezierPath()
                    for (i, (x, y)) in [(0.0, 0.0), (28.0, 0.0), (28.0, 16.8), (8.0, 16.8), (8.0, 24.0), (0.0, 24.0)].enumerated() {
                        let p = NSPoint(x: x, y: tam.height - y)
                        if i == 0 { recorte.move(to: p) } else { recorte.line(to: p) }
                    }
                    recorte.close()
                    recorte.addClip()
                }
                pdf.draw(in: NSRect(origin: .zero, size: tam))
                return true
            }
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let sombra = NSShadow()
            sombra.shadowBlurRadius = 2
            sombra.shadowOffset = NSSize(width: 0, height: -1)
            sombra.shadowColor = NSColor(white: 0, alpha: 0.45)
            sombra.set()
            sola.draw(in: NSRect(origin: .zero, size: tam))
            return rep.cgImage
        }
    }
}
