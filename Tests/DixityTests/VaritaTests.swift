import AppKit
import Testing
@testable import Dixity

// La Varita (31/10/2026): dónde va la cajita, qué sugiere según lo que hay debajo, el collage, los resortes y la
// flecha. Ninguna prueba cambia la flecha de la Mac (eso solo lo hace la Varita prendida, en la app).
@Suite(.serialized) struct VaritaPruebas {
    init() { Ayudas.preparar() }

    private let pantalla = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let tam = CGSize(width: 272, height: 240)   // incluye 18 de margen para la sombra a cada lado

    // La cajita visible (sin el margen de la sombra).
    private func visible(_ origen: CGPoint) -> CGRect { CGRect(origin: origen, size: tam).insetBy(dx: 18, dy: 18) }

    @Test func laCajitaVaAbajoALaDerechaDelCursor() {
        let p = CGPoint(x: 400, y: 600)
        let c = visible(Varita.lugarCajita(cursor: p, tam: tam, pantalla: pantalla))
        #expect(c.minX == p.x + 16)
        #expect(c.maxY == p.y - 22)
    }

    @Test func enLosBordesSeDaVueltaHaciaDondeHayLugar() {
        // Borde derecho: a la izquierda del cursor.
        let derecha = visible(Varita.lugarCajita(cursor: CGPoint(x: 1400, y: 600), tam: tam, pantalla: pantalla))
        #expect(derecha.maxX <= 1400 - 12 + 0.5)
        // Abajo: arriba del cursor.
        let abajo = visible(Varita.lugarCajita(cursor: CGPoint(x: 400, y: 60), tam: tam, pantalla: pantalla))
        #expect(abajo.minY >= 60 + 10 - 0.5)
        // Esquina de abajo a la derecha: arriba a la izquierda, y siempre adentro de la pantalla.
        let esquina = visible(Varita.lugarCajita(cursor: CGPoint(x: 1430, y: 10), tam: tam, pantalla: pantalla))
        #expect(pantalla.contains(esquina))
        #expect(esquina.maxX < 1430 && esquina.minY > 10)
    }

    @Test func sugiereSegunLoQueHayDebajo() {
        let ids = { (cosas: [Senalador.Cosa]) in Varita.sugerencias(para: cosas, idiomaPersona: "es").map(\.0.id) }
        let foto = Senalador.Cosa(tipo: .imagen, marco: CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(ids([foto]).first == "describir")
        let parrafo = Senalador.Cosa(tipo: .texto, marco: CGRect(x: 0, y: 0, width: 300, height: 60),
                                     texto: "Armala una hora antes y sacá los quesos de la heladera.")
        #expect(Varita.sugerencias(para: [parrafo], idiomaPersona: "es").first?.1 == .traducir("en"))
        let ingles = Senalador.Cosa(tipo: .texto, marco: CGRect(x: 0, y: 0, width: 300, height: 60), texto: "Put it together an hour ahead of time, please.")
        #expect(Varita.sugerencias(para: [ingles], idiomaPersona: "es").first?.1 == .traducir("es"))
        #expect(ids([Senalador.Cosa(tipo: .link, marco: .zero)]).first == "adonde")
        #expect(ids([foto, foto]) == ["copiarTodas", "collage", "preguntarTodas", "captura"])
        // El modo captura siempre está, al final, y nunca hay más de 6.
        for cosas in [[foto], [parrafo], [], [foto, foto]] {
            #expect(ids(cosas).last == "captura")
            #expect(ids(cosas).count <= 6)
        }
    }

    @Test func conTextoSeleccionadoOfreceLeerlo() {
        let seleccion = Senalador.Cosa(tipo: .texto, marco: .zero, texto: "Mañana a primera hora te mando el informe.")
        #expect(Varita.esSeleccion(seleccion))
        let ids = Varita.sugerencias(para: [seleccion], idiomaPersona: "es").map(\.0.id)
        #expect(ids.prefix(2) == ["leer", "traducir"])
    }

    @Test func noOfreceLoQueNoHay() {
        let parrafo = Senalador.Cosa(tipo: .texto, marco: CGRect(x: 0, y: 0, width: 300, height: 60), texto: "Hola, ¿cómo andás?")
        let sinIA = Varita.sugerencias(para: [parrafo], disponible: .init(ia: false), idiomaPersona: "es").map(\.0.id)
        #expect(!sinIA.contains("resumir") && !sinIA.contains("reformular") && sinIA.contains("traducir"))
        // Sin nada debajo, solo el modo captura.
        #expect(Varita.sugerencias(para: [], idiomaPersona: "es").map(\.0.id) == ["captura"])
    }

    @Test func reconoceLoQueSeSenala() {
        #expect(Senalador.tipo(rol: "AXImage", subrol: "") == .imagen)
        #expect(Senalador.tipo(rol: "AXStaticText", subrol: "") == .texto)
        #expect(Senalador.tipo(rol: "AXLink", subrol: "") == .link)
        #expect(Senalador.tipo(rol: "AXTextField", subrol: "AXSecureTextField") == nil)   // contraseñas: nunca
        #expect(Senalador.tipo(rol: "AXWindow", subrol: "") == nil)
    }

    @Test func elCollageJuntaLasImagenesEnUnaGrilla() throws {
        let cuadrado = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        let c = try #require(Varita.collage([cuadrado, cuadrado, cuadrado, cuadrado]))
        #expect(c.size == NSSize(width: 1464, height: 972))   // 3 columnas de 480 y 2 filas, con 12 entre medio
        #expect(Varita.collage([]) == nil)
    }

    @Test func elResorteLlegaSinPasarseAunqueLaPantallaSeTrabe() {
        for dt in [1.0 / 120, 1.0 / 60, 1.0 / 20] as [CGFloat] {
            var r = Resorte(valor: 0)
            var maximo: CGFloat = 0
            for _ in 0..<Int(1 / dt) { r.mover(a: 100, dt: dt, rigidez: 1100, amortiguado: 1); maximo = max(maximo, r.valor) }
            #expect(abs(r.valor - 100) < 0.5)
            #expect(maximo <= 100.01)
        }
    }

    @Test func laFlechaSeDibujaYSeReconoceComoPropia() throws {
        let tira = try #require(FlechaVarita.Dibujo.varita(escala: 2))
        #expect(tira.width == 96 && tira.height == 96 * FlechaVarita.Dibujo.cuadros)
        let nuestra = FlechaVarita.Registrada(tam: FlechaVarita.Dibujo.tam, punta: FlechaVarita.Dibujo.punta, cuadros: 12, duracion: 0.09, imagenes: [tira])
        #expect(FlechaVarita.esNuestra(nuestra))
        // La rearmada del dibujo del menú contextual (el triangulito) no es nuestra, pero tampoco la de verdad: nunca se
        // guarda como original (pasó el 31/10: se perdió la flecha original).
        if let rearmada = FlechaVarita.Dibujo.originalDelSistema("com.apple.coregraphics.Arrow") {
            #expect(rearmada.tam == CGSize(width: 28, height: 40))
            #expect(!FlechaVarita.esNuestra(rearmada))
            #expect(!FlechaVarita.esDeVerdad(rearmada, nombre: "com.apple.coregraphics.Arrow"))
            #expect(rearmada.imagenes.count == 2)
        }
        // La clásica que vuelve mientras no haya copia de la de verdad, tampoco.
        let clasica = try #require(FlechaVarita.Dibujo.clasica())
        #expect(clasica.imagenes.map(\.width) == [28, 56])
        #expect(FlechaVarita.esClasica(clasica))
        #expect(!FlechaVarita.esDeVerdad(clasica, nombre: "com.apple.coregraphics.Arrow"))
        #expect(!FlechaVarita.esDeVerdad(nuestra, nombre: "com.apple.coregraphics.Arrow"))
        // La grande del primer intento se sigue reconociendo, y no se parece a la de ahora.
        let grande = try #require(FlechaVarita.Dibujo.clasica(k: 1))
        #expect(FlechaVarita.esClasica(grande) && !FlechaVarita.seParecen(grande, clasica))
    }

    // MARK: 31/10 (noche): cajas de texto, Claude y Codex, QR y la voz

    @Test func enUnaCajaConTextoLoCambiaAhiMismo() {
        let caja = Senalador.Cosa(tipo: .campo, marco: CGRect(x: 0, y: 0, width: 300, height: 40),
                                  texto: "Mañana te paso el presupuesto", editable: true)
        let s = Varita.sugerencias(para: [caja], idiomaPersona: "es")
        #expect(s.first?.1 == .traducir("en"))
        #expect(s.map(\.0.id).prefix(3) == ["traducir", "reformular", "corregir"])
        // Lo seleccionado dentro de una caja, igual.
        let seleccion = Senalador.Cosa(tipo: .texto, marco: .zero, texto: "Hello, how are you doing today?", editable: true)
        #expect(Varita.sugerencias(para: [seleccion], idiomaPersona: "es").first?.1 == .traducir("es"))
        // Una caja vacía ofrece dictar ahí.
        let vacia = Senalador.Cosa(tipo: .campo, marco: CGRect(x: 0, y: 0, width: 300, height: 40), editable: true)
        #expect(Varita.sugerencias(para: [vacia], idiomaPersona: "es").first?.1 == .dictarAca)
    }

    @Test func elQRSoloSiLaImagenTieneUno() {
        var foto = Senalador.Cosa(tipo: .imagen, marco: CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(!Varita.sugerencias(para: [foto], idiomaPersona: "es").map(\.0.id).contains("leerQR"))
        foto.tieneCodigo = true
        #expect(Varita.sugerencias(para: [foto], idiomaPersona: "es").map(\.0.id).prefix(2) == ["describir", "leerQR"])
    }

    @Test func claudeYCodexSoloSiEstan() {
        let foto = Senalador.Cosa(tipo: .imagen, marco: CGRect(x: 0, y: 0, width: 300, height: 200))
        let todos = Varita.Disponible(ia: true, claude: true, codex: true, claudeResponde: true)
        let ids = { (cosas: [Senalador.Cosa], d: Varita.Disponible) in Varita.sugerencias(para: cosas, disponible: d, idiomaPersona: "es").map(\.0.id) }
        // Para una imagen alcanza con uno (Claude si está); con varias, los dos.
        #expect(ids([foto], todos).contains("mandarClaude") && !ids([foto], todos).contains("mandarCodex"))
        #expect(ids([foto, foto], todos).prefix(3) == ["copiarTodas", "mandarClaude", "mandarCodex"])
        #expect(!ids([foto], Varita.Disponible()).contains("mandarClaude"))
        // Con Claude Code, preguntar por una imagen se lo pregunta a Claude (aunque no haya IA configurada).
        let sinIA = Varita.Disponible(ia: false, claude: true, codex: false, claudeResponde: true)
        let preguntar = Varita.sugerencias(para: [foto], disponible: sinIA, idiomaPersona: "es").first { $0.0.id == "preguntar" }
        #expect(preguntar?.0.nombre == "Preguntale a Claude")
        // Un error seleccionado: arreglarlo con Claude, primero.
        let error = Senalador.Cosa(tipo: .texto, marco: .zero, texto: "TypeError: undefined is not a function at login.ts:42")
        #expect(Varita.sugerencias(para: [error], disponible: todos, idiomaPersona: "es").first?.1 == .arreglar)
        #expect(!Varita.pareceError("Mañana a primera hora te mando el informe."))
    }

    // Con una IA que ve imágenes (01/11/2026): Describir y Sacar prompt primero, y preguntar va a tu IA aunque esté
    // Claude Code (responde al instante en la tarjeta). Sin ella, Describir igual (lo hace la Mac), sin Sacar prompt.
    @Test func conUnaIAQueVeImagenesDescribeYSacaElPrompt() {
        let foto = Senalador.Cosa(tipo: .imagen, marco: CGRect(x: 0, y: 0, width: 300, height: 200))
        let conVision = Varita.Disponible(ia: true, claude: true, codex: true, claudeResponde: true, veImagenes: true)
        let lista = Varita.sugerencias(para: [foto], disponible: conVision, idiomaPersona: "es")
        #expect(lista.map(\.0.id).prefix(3) == ["describir", "sacarPrompt", "copiarImagen"])
        let sinVision = Varita.sugerencias(para: [foto], disponible: Varita.Disponible(ia: true), idiomaPersona: "es").map(\.0.id)
        #expect(sinVision.first == "describir" && !sinVision.contains("sacarPrompt"))
        let todas = Varita.sugerencias(para: [foto, foto], disponible: conVision, idiomaPersona: "es")
        #expect(todas.first { $0.0.id == "preguntarTodas" }?.0.nombre == "Preguntá sobre todas")
    }

    // Agrandar (01/11/2026): de la cosa a lo que la contiene, salteando los grupos casi iguales de una web, recortado a
    // la ventana, hasta 5 escalones y la ventana al final.
    @Test func agrandarSubeDeAEscalonesQueCrecenDeVerdad() {
        let ventana = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let foto = CGRect(x: 100, y: 500, width: 200, height: 150)
        let padres = [CGRect(x: 98, y: 498, width: 204, height: 154),      // casi igual: se saltea
                      CGRect(x: 80, y: 420, width: 400, height: 300),      // la tarjeta
                      CGRect(x: 60, y: 400, width: 420, height: 320),      // casi igual a la tarjeta: se saltea
                      CGRect(x: 0, y: 300, width: 1400, height: 520),      // la sección
                      CGRect(x: 0, y: -2000, width: 1400, height: 4000)]  // la página entera: más que la ventana
        let e = Senalador.escalones(desde: foto, padres: padres, ventana: ventana)
        #expect(e == [CGRect(x: 80, y: 420, width: 400, height: 300), CGRect(x: 0, y: 300, width: 1400, height: 520), ventana])
        // Sin padres útiles, igual llega a la ventana; y nunca más de 5 escalones antes de ella.
        #expect(Senalador.escalones(desde: foto, padres: [], ventana: ventana) == [ventana])
        let muchos = (1...10).map { i in CGRect(x: 0, y: 0, width: 30 * pow(1.7, Double(i)), height: 30 * pow(1.7, Double(i))) }
        #expect(Senalador.escalones(desde: CGRect(x: 0, y: 0, width: 30, height: 30), padres: muchos, ventana: nil).count == 5)
    }

    // Tanda 3 (01/11/2026): un logo o un banner se reconocen sin mirarlos, y cada uno pone primero lo suyo.
    @Test func reconoceLogosYBannersYOfreceLoSuyo() {
        let chica = CGRect(x: 0, y: 0, width: 160, height: 48)
        #expect(Senalador.clase(deImagen: chica, alt: "Halyon Team logo", llevaAlInicio: false) == .logo)
        #expect(Senalador.clase(deImagen: chica, alt: "", llevaAlInicio: true) == .logo)
        #expect(Senalador.clase(deImagen: CGRect(x: 0, y: 0, width: 1200, height: 300), alt: "Ofertas", llevaAlInicio: false) == .banner)
        #expect(Senalador.clase(deImagen: CGRect(x: 0, y: 0, width: 600, height: 400), alt: "Una playa", llevaAlInicio: false) == .imagen)
        let ve = Varita.Disponible(ia: true, claude: true, veImagenes: true)
        func primera(_ t: Senalador.Tipo) -> String? {
            Varita.sugerencias(para: [Senalador.Cosa(tipo: t, marco: CGRect(x: 0, y: 0, width: 800, height: 300))], disponible: ve,
                               idiomaPersona: "es").first?.0.id
        }
        #expect(primera(.logo) == "recrearLogo" && primera(.banner) == "recrearBanner" && primera(.seccion) == "maqueta")
        let video = Varita.sugerencias(para: [Senalador.Cosa(tipo: .video, marco: CGRect(x: 0, y: 0, width: 640, height: 360))],
                                       disponible: ve, idiomaPersona: "es")
        #expect(video.contains { $0.0.nombre == "Copiar este cuadro" })
        // Sin una IA que vea imágenes no se ofrece recrear ni la maqueta, pero sí los colores (en la Mac).
        let sinVision = Varita.sugerencias(para: [Senalador.Cosa(tipo: .logo, marco: chica)], idiomaPersona: "es").map(\.0.id)
        #expect(!sinVision.contains("recrearLogo") && sinVision.first == "colores")
        #expect(PedidoImagen.maqueta.clase == .maqueta && PedidoImagen.logo.clase == .prompt)
        #expect(Respuestas.opciones(para: "Qué es: el encabezado de una landing.", clase: .maqueta, idiomaPersona: "es").prefix(2)
                == [.mandarClaude, .promptImagen])
    }

    // Sacar colores: el que más ocupa primero, con cuánto ocupa, y los casi iguales juntos.
    @Test func sacaLosColoresPrincipales() throws {
        let ctx = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 75, height: 100))
        ctx.setFillColor(CGColor(srgbRed: 0.99, green: 0.02, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 5, height: 100))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 75, y: 0, width: 25, height: 100))
        let imagen = try #require(ctx.makeImage())
        let c = Pantalla.colores(de: imagen)
        #expect(c.count == 2)
        #expect(c.first?.hex.hasPrefix("#F") == true && c.last?.hex == "#0000FF")
        #expect(abs((c.first?.parte ?? 0) - 0.75) < 0.05)
    }

    @Test func elRecuadroSaleParaCualquierLado() {
        #expect(Varita.recuadro(CGPoint(x: 300, y: 200), CGPoint(x: 100.4, y: 500.6)) == CGRect(x: 100, y: 200, width: 200, height: 301))
        // Una sección o un recorte se trabajan como una imagen: Describir primero.
        let seccion = Senalador.Cosa(tipo: .seccion, marco: CGRect(x: 0, y: 0, width: 800, height: 400))
        #expect(seccion.esVisual && !Senalador.Cosa(tipo: .texto, marco: .zero).esVisual)
        #expect(Varita.sugerencias(para: [seccion], idiomaPersona: "es").first?.0.id == "describir")
    }

    @Test func elPromptDiceLaProporcion() {
        #expect(PedidoImagen.proporcion(CGSize(width: 1920, height: 1080)) == "16:9")
        #expect(PedidoImagen.proporcion(CGSize(width: 500, height: 500)) == "1:1")
        #expect(PedidoImagen.proporcion(CGSize(width: 600, height: 800)) == "3:4")
        #expect(PedidoImagen.proporcion(CGSize(width: 1000, height: 300)) == "3.33:1")
        #expect(PedidoImagen.prompt.instruccion(tam: CGSize(width: 1920, height: 1080)).contains("Aspect ratio 16:9."))
        #expect(PedidoImagen.prompt.clase == .prompt && PedidoImagen.describir.clase == .imagen)
        // La tarjeta del prompt ofrece cambiarlo por voz, animarla, pasarlo de idioma y hacerlo más detallado.
        let opciones = Respuestas.opciones(para: "A cozy cabin in a snowy forest at dusk, warm light in the windows", clase: .prompt, idiomaPersona: "es")
        #expect(opciones == [.cambiarAlgo, .animar, .traducir("es"), .masDetallado])
        #expect(Respuestas.opciones(para: "A slow push-in on the cabin as snow falls", clase: .video, idiomaPersona: "es").first == .copiarImagen)
    }

    // El formato cambia solo el final del prompt (proporción y tamaño, siempre en alta resolución), sin repetirlo.
    @Test func elFormatoCambiaElFinalDelPrompt() {
        let prompt = "A cozy cabin at dusk, photorealistic. High resolution, sharp detail. Aspect ratio 16:9."
        let post = Respuestas.conFormato(prompt, .post, original: "16:9")
        #expect(post == "A cozy cabin at dusk, photorealistic. High resolution, sharp detail, 1080×1350 px. Aspect ratio 4:5.")
        #expect(Respuestas.conFormato(post, .original, original: "16:9") == prompt)
        #expect(Respuestas.conFormato(post, .historia, original: "16:9").hasSuffix("1080×1920 px. Aspect ratio 9:16."))
        // Sin final (la IA lo sacó al reescribir) se agrega; pasado a español, se reemplaza igual.
        #expect(Respuestas.conFormato("A cozy cabin at dusk.", .cuadrado, original: "3:2")
                == "A cozy cabin at dusk. High resolution, sharp detail, 1080×1080 px. Aspect ratio 1:1.")
        let espanol = "Una cabaña al atardecer. Alta resolución, mucho detalle. Relación de aspecto 16:9."
        #expect(Respuestas.conFormato(espanol, .post, original: "16:9")
                == "Una cabaña al atardecer. High resolution, sharp detail, 1080×1350 px. Aspect ratio 4:5.")
    }

    @Test func elPromptDelVideoEsDe15Segundos() {
        let vertical = PedidoImagen.instruccionVideo(formato: "9:16", promptImagen: "A cozy cabin at dusk.")
        #expect(vertical.contains("15-second") && vertical.contains("1080×1920") && vertical.contains("A cozy cabin at dusk."))
        #expect(PedidoImagen.instruccionVideo(formato: "16:9", promptImagen: "x").contains("1920×1080"))
    }

    // Lo que va a la IA: JPEG de hasta 1280 px del lado largo, con la forma de la original.
    @Test func laImagenParaLaIAVaChica() throws {
        let ctx = try #require(CGContext(data: nil, width: 3000, height: 2000, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        let imagen = try #require(ctx.makeImage())
        let datos = try #require(Pantalla.paraIA(imagen))
        let rep = try #require(NSBitmapImageRep(data: datos))
        #expect(rep.pixelsWide == 1280 && rep.pixelsHigh == 853)
        #expect(datos.prefix(2) == Data([0xFF, 0xD8]))   // es un JPEG
    }

    @Test func losPedidosEscritosDicenQueHicieron() {
        #expect(PedidoEscrito(.traducir("en")) == .traducir("en"))
        #expect(PedidoEscrito(.corregir) == .corregir)
        #expect(PedidoEscrito(.copiarImagen) == nil)
        #expect(PedidoEscrito.traducir("en").hecho == "Pasado a inglés")
    }

    @Test func loQueSePegaEnLaTerminalDeClaude() {
        let rutas = [URL(fileURLWithPath: "/tmp/varita-1.png"), URL(fileURLWithPath: "/tmp/varita-2.png")]
        let t = Mandar.textoParaTerminal(prefijo: nil, pagina: URL(string: "https://halyon.team/precios"), rutas: rutas,
                                         textos: ["  quiero este botón  "])
        #expect(t == "De la página https://halyon.team/precios /tmp/varita-1.png /tmp/varita-2.png quiero este botón ")
        // A una terminal nunca va más de un renglón: un error de varios renglones va como archivo (si no, se ejecutaría).
        let error = Mandar.textoParaTerminal(prefijo: "Arreglalo:", pagina: nil, rutas: [], textos: ["rm -rf algo\nTypeError: x"],
                                             guardar: { _ in URL(fileURLWithPath: "/tmp/varita-ab.txt") })
        #expect(!error.contains("\n") && error.contains("/tmp/varita-ab.txt") && !error.contains("rm -rf"))
    }

    // Lo que se le pasó a Claude o Codex se borra al día aunque no se vuelva a mandar nada (01/11/2026).
    @Test func lasImagenesParaLosAgentesSeBorranAlDia() throws {
        let fm = FileManager.default
        let carpeta = fm.temporaryDirectory.appendingPathComponent("dixity-prueba-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: carpeta) }
        let vieja = carpeta.appendingPathComponent("varita-vieja.png"), nueva = carpeta.appendingPathComponent("varita-nueva.png")
        try Data([1]).write(to: vieja)
        try Data([1]).write(to: nueva)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-90_000)], ofItemAtPath: vieja.path)
        Mandar.borrarViejas(en: carpeta)
        #expect(!fm.fileExists(atPath: vieja.path))
        #expect(fm.fileExists(atPath: nueva.path))
    }

    @Test func reconoceLasVentanasDeLosAgentes() {
        #expect(Mandar.esDe(.claude, titulo: "✳ Arreglar el login"))
        #expect(Mandar.esDe(.claude, titulo: "dixity — claude — 120×40"))
        #expect(Mandar.esDe(.codex, titulo: "codex — Dicta"))
        #expect(!Mandar.esDe(.claude, titulo: "zsh — 80×24"))
    }

    @Test func lasVentanitasQuedanJustoEnLosPixeles() {
        let r = Varita.alPixel(CGRect(x: 10.3, y: 20.76, width: 100.2, height: 50.49), escala: 2)
        #expect(r == CGRect(x: 10.5, y: 21, width: 100, height: 50.5))
    }

    @Test func elTextoLargoSeLeeEnPartesSinCortarOraciones() {
        let oracion = "Esta es una oración de prueba para leer en voz alta. "
        let largo = String(repeating: oracion, count: 200)   // ~10.600 letras
        let partes = Lector.partes(largo)
        #expect(partes.count == 4)
        #expect(partes.allSatisfy { $0.count <= 3500 && $0.hasSuffix(".") })
        #expect(Lector.partes("Hola.") == ["Hola."])
        // Lo que colgaba la app (revisión del 31/10): un texto largo sin puntos ni espacios después del primer corte.
        for raro in ["Mirá esto. " + String(repeating: "A", count: 5000), "Hola. " + String(repeating: "中", count: 4000)] {
            let p = Lector.partes(raro)
            #expect(p.allSatisfy { !$0.isEmpty && $0.count <= 3500 })
            #expect(p.joined().filter { !$0.isWhitespace }.count == raro.filter { !$0.isWhitespace }.count)
        }
    }

    // MARK: 01/11 (tarde): sumar al diccionario

    @Test func unaPalabraSeleccionadaSeOfreceParaElDiccionario() {
        let ids = { (c: Senalador.Cosa) in Varita.sugerencias(para: [c], idiomaPersona: "es").map(\.0.id) }
        // Una palabra o un nombre corto: Sumar al diccionario, en vez de Resumir (en un texto) o Reformular (en una caja).
        let palabra = Senalador.Cosa(tipo: .texto, marco: .zero, texto: " Halyon, ")
        #expect(ids(palabra).contains("sumarPalabra") && !ids(palabra).contains("resumir"))
        let enCaja = Senalador.Cosa(tipo: .texto, marco: .zero, texto: "Club Nahuel", editable: true)
        #expect(ids(enCaja).prefix(3) == ["traducir", "corregir", "sumarPalabra"])
        // Una oración o una caja entera, no.
        #expect(!ids(Senalador.Cosa(tipo: .texto, marco: .zero, texto: "Mañana a primera hora te mando el informe.")).contains("sumarPalabra"))
        #expect(!ids(Senalador.Cosa(tipo: .campo, marco: CGRect(x: 0, y: 0, width: 300, height: 40), texto: "Hola", editable: true)).contains("sumarPalabra"))
        // Lo mismo que acepta ⌃⌥D.
        #expect(Diccionario.deSeleccion("«Dixity».") == "Dixity")
        #expect(Diccionario.esCorto("Halyon Team") && !Diccionario.esCorto("") && !Diccionario.esCorto("uno\ndos"))
        #expect(!Diccionario.esCorto("una frase con más de cuatro palabras"))
    }
}
