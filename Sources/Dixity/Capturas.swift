import AppKit
import SwiftUI

// Modo de prueba: `Dixity --capturas <carpeta>` dibuja cada pantalla y la píldora en PNG y sale.
// Sirve para revisar el diseño sin abrir ventanas ni tocar la pantalla.
enum Capturas {
    static func hacer(en carpeta: String) {
        let url = URL(fileURLWithPath: carpeta, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let motor = Motor()
        let nav = Navegacion()
        for (nombre, apariencia) in [("claro", NSAppearance(named: .aqua)!), ("oscuro", NSAppearance(named: .darkAqua)!)] {
            NSApp.appearance = apariencia
            for p in Pagina.allCases {
                nav.pagina = p
                let vista = VistaPanel(motor: motor, ajustes: .shared, navegacion: nav, pedirTeclado: {})
                guardar(vista, tam: NSSize(width: 940, height: 1800), apariencia: apariencia, en: url.appendingPathComponent("panel-\(p.rawValue)-\(nombre).png"))
            }
            for paso in 1...6 {
                guardar(Bienvenida(ajustes: .shared, motor: motor, pedirTeclado: {}, cerrar: {}, paso: paso), tam: NSSize(width: 640, height: 560),
                        apariencia: apariencia, en: url.appendingPathComponent("bienvenida-\(paso)-\(nombre).png"))
            }
            guardar(VistaPortapapeles(portapapeles: .shared, estado: EstadoPortapapeles(), elegir: { _ in }),
                    tam: NSSize(width: 620, height: 470), apariencia: apariencia, en: url.appendingPathComponent("portapapeles-\(nombre).png"))
            let modelo = ModeloPildora()
            modelo.atajoPreguntar = Ajustes.shared.datos.atajoPreguntar.descripcion
            modelo.niveles = [0, 0, 0.2, 0.5, 0.8, 0.6, 0.9, 0.4, 0.7, 0.3, 0.1]
            let estados: [(String, ModeloPildora.Estado, ModeloPildora.Modo)] = [
                ("grabando", .grabando, .dictado), ("procesando", .procesando, .dictado), ("listo", .listo(T("Listo", "Done")), .dictado),
                ("aviso", .aviso(T("No había dónde escribir: quedó copiado.", "Nowhere to type: copied to clipboard.")), .dictado),
                ("fallo", .fallo(T("No se pudo conectar con OpenAI.", "Couldn't reach OpenAI.")), .dictado), ("reescribir", .grabando, .reescritura),
                ("trabajo", .grabando, .dictado), ("sinsonido", .grabando, .dictado), ("modo", .grabando, .dictado), ("modoelegido", .modo("Correo"), .dictado),
                ("sincampo", .sinCampo(T("Quiero que en el panel de historial agregues un botón para exportar los dictados del día como .txt.",
                                         "Add a button to the history panel that exports today's dictations as a .txt file.")), .dictado),
                ("preguntar", .grabando, .pregunta),
                ("agente", .respuesta(T("Motor.swift une todo: escucha el atajo, graba, pasa la voz a texto, la limpia con la IA y la pega. Para que Preguntar le hable a Claude, sumaría un paso en `procesar` que detecte «Claude, …» y le pase el pedido a `Agentes.correr`.",
                                        "Motor.swift ties it all together: it listens for the shortcut, records, transcribes, cleans up with AI and pastes. To let Ask talk to Claude, I'd add a step in `procesar` that detects “Claude, …” and hands the request to `Agentes.correr`.")), .pregunta),
                ("respuesta", .respuesta(T("¡Hola Caro! Sí, el jueves puedo. ¿Te queda bien a las 10 en la oficina? Si preferís por videollamada, avisame y te paso el link.",
                                           "Hi Caro! Yes, Thursday works for me. Does 10am at the office suit you? If you'd rather do a video call, let me know and I'll send the link.")), .pregunta),
            ]
            tarjetas(en: url, apariencia: apariencia, nombre: nombre)
            for (n, e, m) in estados {
                modelo.hacelo = n == "agente" ? T("Hacelo con Claude", "Have Claude do it") : nil
                modelo.tituloRespuesta = n == "agente" ? "Claude" : ""
                modelo.estado = e; modelo.modo = m; modelo.trabajo = n == "trabajo"; modelo.sinSonido = n == "sinsonido"; modelo.etiqueta = n == "modo" ? Estilo.correo.etiqueta : nil; modelo.colorModo = n == "trabajo" ? Color(hex: 0x8B5CF6) : (n == "modo" || n == "modoelegido") ? Color(hex: 0x3B82F6) : Tema.acento
                guardar(VistaPildora(modelo: modelo, ajustes: .shared, copiar: {}, cerrar: {}).background(Color.gray.opacity(0.25)), tam: NSSize(width: 520, height: n == "respuesta" || n == "agente" ? 300 : 190),
                        apariencia: apariencia, en: url.appendingPathComponent("pildora-\(n)-\(nombre).png"))
            }
        }
    }

    // Cada forma de la tarjeta de respuesta (TarjetaRespuesta), con datos de ejemplo.
    private static func tarjetas(en url: URL, apariencia: NSAppearance, nombre: String) {
        TarjetaRespuesta.sinAnimar = true
        let ahora = Date()
        let uso = [
            Agentes.Uso(agente: .claude, topes: [.init(nombre: T("Sesión de 5 h", "5-hour session"), cual: "", usado: 62, renueva: ahora.addingTimeInterval(7800)),
                                                 .init(nombre: T("Semana", "Week"), cual: "", usado: 31, renueva: ahora.addingTimeInterval(4 * 86400))],
                        leido: ahora.addingTimeInterval(-240), hoy: [.init(proyecto: "Dicta", cantidad: 3), .init(proyecto: "halyon", cantidad: 2)]),
            Agentes.Uso(agente: .codex, topes: [.init(nombre: T("Sesión de 5 h", "5-hour session"), cual: "", usado: 15, renueva: ahora.addingTimeInterval(3000)),
                                                .init(nombre: T("Semana", "Week"), cual: "", usado: 93, renueva: ahora.addingTimeInterval(2 * 86400))],
                        leido: ahora.addingTimeInterval(-3600)),
        ]
        let lista = T("Para publicar la app:\n\n1. Revisá que el **README** esté al día.\n2. Corré `./probar.sh` y fijate que pase todo.\n3. Armá la copia pública:\n\n```\ntools/exportar-publico.sh ../dixity-publico\n```\n\nDespués la subís a GitHub.",
                      "To publish the app:\n\n1. Check the **README** is up to date.\n2. Run `./probar.sh` and make sure everything passes.\n3. Build the public copy:\n\n```\ntools/exportar-publico.sh ../dixity-public\n```\n\nThen push it to GitHub.")
        let casos: [(String, String, Respuestas.Clase, String, Bool, Respuestas.Opcion?, String?)] = [
            ("texto", lista, .texto, "", false, nil, nil),
            ("traduccion", "I'll send you the report early tomorrow morning.\n\nThanks for waiting.",
             .traduccion(de: "es", a: "en", original: "Mañana a primera hora te mando el informe.\n\nGracias por esperar."),
             T("Traductor de Apple · en la Mac", "Apple Translate · on your Mac"), true, nil, nil),
            ("leido", "Factura B 0001-00004521\nFecha: 28/10/2026\nTotal: $ 48.300", .textoLeido, T("Texto leído · en la Mac", "Text read · on your Mac"), true, nil, nil),
            ("qr", "https://halyon.team/dixity\nhttp://promo.ejemplo.com/2x1", .codigos, T("Código leído · en la Mac", "Code read · on your Mac"), true, nil, nil),
            ("uso", "", .uso(uso), T("Uso · en la Mac", "Usage · on your Mac"), true, nil, nil),
            ("posteo", T("## LinkedIn\nHoy lanzamos Dixity: dictás en cualquier app de tu Mac y el texto sale prolijo. Gratis y de código abierto.\n\n#productividad #mac\n\n## Instagram\nHablás, Dixity escribe ✍️\n\n## X\nLanzamos Dixity: dictado prolijo en cualquier app de la Mac. Gratis.\n\n## Imagen\nLa píldora flotando sobre un mail a medio escribir.",
                         "## LinkedIn\nToday we're launching Dixity: dictate in any Mac app and get clean text. Free and open source.\n\n#productivity #mac\n\n## Instagram\nYou talk, Dixity writes ✍️\n\n## X\nDixity is out: clean dictation in any Mac app. Free.\n\n## Image\nThe pill floating over a half-written email."),
             .posteo(marca: "halyon"), T("Posteo · halyon", "Post · halyon"), false, nil, nil),
            ("imagen", T("Una cabaña de madera en un bosque nevado, al atardecer. Las ventanas tienen luz cálida y sale humo de la chimenea; atrás hay montañas y un cielo naranja y violeta. No tiene texto.",
                          "A wooden cabin in a snowy forest at dusk. The windows glow warm and smoke rises from the chimney; mountains and an orange-violet sky behind. No text."),
             .imagen, PedidoImagen.describir.titulo, false, nil, nil),
            ("prompt", "A cozy wooden cabin nestled in a snowy pine forest at dusk, warm golden light glowing from small windows, thin smoke rising from a stone chimney, snow-capped mountains behind under a gradient sky of orange and violet. Wide shot, eye level, 35mm lens, soft low-key lighting, cinematic color grading, fine snow texture, calm and nostalgic mood, photorealistic. Aspect ratio 16:9.",
             .prompt, PedidoImagen.prompt.titulo, false, nil, nil),
            ("prompt-post", Respuestas.conFormato("A cozy wooden cabin nestled in a snowy pine forest at dusk, warm golden light glowing from small windows, thin smoke rising from a stone chimney, snow-capped mountains behind under a gradient sky of orange and violet. Wide shot, eye level, 35mm lens, cinematic color grading, calm and nostalgic mood, photorealistic.", .post, original: "16:9"),
             .prompt, PedidoImagen.prompt.titulo, false, nil, nil),
            ("animar", "A cozy wooden cabin nestled in a snowy pine forest at dusk, warm golden light glowing from small windows. High resolution, sharp detail. Aspect ratio 16:9.",
             .prompt, PedidoImagen.prompt.titulo, false, nil, nil),
            ("video", "Animate the reference image of a cozy wooden cabin in a snowy pine forest at dusk, keeping the warm window light, violet-orange sky and soft snow exactly as shown. Reframe to vertical, centered on the cabin.\nCamera: a slow, steady push-in toward the cabin.\n0–5 s: snow drifts down gently; smoke curls from the chimney.\n5–10 s: a window light flickers warmer; pine branches sway slightly.\n10–15 s: the sky deepens to violet as the camera settles close on the glowing door.\nSound: soft wind, crackling fire, a calm piano melody.\n15 seconds, 9:16 vertical, 1080×1920, 24 fps, smooth natural motion, no cuts, no text overlays.",
             .video, PedidoImagen.tituloVideo, false, nil, nil),
            ("colores", "#1E1B3A · 42 %\n#C2569B · 23 %\n#F59E0B · 15 %\n#F8FAFC · 12 %\n#7C4A2D · 8 %", .colores,
             T("Colores · en la Mac", "Colors · on your Mac"), true, nil, nil),
            ("maqueta", T("**Qué es:** el encabezado de una landing de una app de dictado.\n\n**Estructura**\n- Barra arriba: logo a la izquierda, tres links y un botón a la derecha.\n- Título grande centrado, una frase abajo y dos botones.\n- Una captura de la app en una tarjeta con sombra suave.\n\n**Textos**\n- Título: «Hablás, Dixity escribe»\n- Botón: «Descargar gratis»\n\n**Colores:** #1E1B3A (fondo), #F59E0B (botón), #F8FAFC (texto).\n\n**Tipografía:** sans geométrica, título 56 px bold, texto 18 px.",
                          "**What it is:** the header of a dictation app landing page.\n\n**Structure**\n- Top bar: logo left, three links and a button right.\n- Big centered heading, a line below and two buttons.\n- A screenshot of the app in a softly shadowed card.\n\n**Texts**\n- Heading: “You talk, Dixity writes”\n- Button: “Download free”\n\n**Colors:** #1E1B3A (background), #F59E0B (button), #F8FAFC (text).\n\n**Typography:** geometric sans, 56 px bold heading, 18 px body."),
             .maqueta, PedidoImagen.maqueta.titulo, false, nil, nil),
            ("trabajando", T("¡Hola Caro! Sí, el jueves puedo. ¿Te queda bien a las 10 en la oficina?", "Hi Caro! Thursday works. Does 10am at the office suit you?"),
             .texto, "", false, .traducir(T("en", "es")), nil),
            ("aviso", T("¡Hola Caro! Sí, el jueves puedo.", "Hi Caro! Thursday works."), .texto, "", false, nil,
             T("Para traducir a ese idioma falta bajarlo en Ajustes del Sistema › Idioma y región, o configurar una IA.",
               "To translate to that language, download it in System Settings › Language & Region, or set up an AI.")),
        ]
        for (n, texto, clase, titulo, enLaMac, trabajando, aviso) in casos {
            let m = ModeloPildora()
            m.atajoPreguntar = Ajustes.shared.datos.atajoPreguntar.descripcion
            m.tituloRespuesta = titulo
            m.clase = clase
            m.enLaMac = enLaMac
            m.opciones = Respuestas.opciones(para: texto, clase: clase, idiomaPersona: T("es", "en"))
            m.puedeDeshacer = n == "traduccion"
            m.trabajando = trabajando
            m.avisoTarjeta = aviso
            if [.imagen, .prompt, .video, .colores, .maqueta].contains(clase) { m.miniaturas = [fotoDeMuestra()] }
            if clase == .prompt { m.formato = n == "prompt-post" ? .post : .original }
            if n == "animar" {
                m.opciones = [.animarEn("9:16"), .animarEn("16:9"), .volver]
                m.preguntaOpciones = T("¿En qué formato va el video?", "Which format for the video?")
            }
            if n == "video" {
                m.puedeDeshacer = true
                m.avisoBueno = true
                m.avisoTarjeta = T("Imagen copiada: pegala como referencia en la app de video.", "Image copied: paste it as the reference in your video app.")
            }
            m.estado = .respuesta(texto)
            m.modo = .pregunta
            guardar(VistaPildora(modelo: m, ajustes: .shared, copiar: {}, cerrar: {}).background(Color.gray.opacity(0.25)),
                    tam: NSSize(width: 520, height: 560), apariencia: apariencia, en: url.appendingPathComponent("tarjeta-\(n)-\(nombre).png"))
        }
        // La cajita de la Varita: sobre una imagen, sobre un texto, en una caja de texto y con tres cosas juntas (con
        // Claude y Codex en la Mac). Sobre blanco puro (o casi negro), que es donde se notaba el halo del 31/10.
        let foto = Senalador.Cosa(tipo: .imagen, marco: CGRect(x: 0, y: 0, width: 300, height: 200))
        let parrafo = Senalador.Cosa(tipo: .texto, marco: CGRect(x: 0, y: 0, width: 300, height: 60),
                                     texto: "Armala una hora antes y sacá los quesos de la heladera con tiempo.")
        let caja = Senalador.Cosa(tipo: .campo, marco: CGRect(x: 0, y: 0, width: 300, height: 40),
                                  texto: "Mañana te paso el presupuesto", editable: true)
        let todos = Varita.Disponible(ia: true, claude: true, codex: true, claudeResponde: true, veImagenes: true)
        let seccion = Senalador.Cosa(tipo: .seccion, marco: CGRect(x: 0, y: 0, width: 900, height: 420))
        for (n, cosas) in [("imagen", [foto]), ("texto", [parrafo]), ("caja", [caja]), ("varias", [foto, foto, foto]), ("seccion", [seccion]),
                            ("logo", [Senalador.Cosa(tipo: .logo, marco: CGRect(x: 0, y: 0, width: 160, height: 48))]),
                            ("video", [Senalador.Cosa(tipo: .video, marco: CGRect(x: 0, y: 0, width: 640, height: 360))])] {
            let m = ModeloCajita()
            m.sugerencias = Varita.sugerencias(para: cosas, disponible: todos, idiomaPersona: T("es", "en")).map(\.0)
            m.titulo = cosas.count > 1 ? T("3 cosas juntas · copiadas", "3 items together · copied")
                : cosas[0].tipo == .campo ? T("Caja de texto", "Text box") : cosas[0].tipo.nombre
            m.icono = cosas.count > 1 ? "square.on.square" : Varita.icono(cosas[0].tipo)
            m.pie = cosas.count > 1 ? T("Mantené ⇧ y tocá otra para sumarla", "Hold ⇧ and click another to add it")
                : cosas[0].editable ? T("Lo cambia ahí mismo · ⌘Z deshace", "Changes it in place · ⌘Z undoes")
                : T("Clic elige · ⌥ + rueda agranda", "Click picks · ⌥ + scroll grows")
            m.visible = true
            m.marcada = 0
            if cosas.count > 1, let f = FlechaVarita.Dibujo.varita(escala: 1) {
                m.miniaturas = Array(repeating: NSImage(cgImage: f, size: NSSize(width: 48, height: 48)), count: 3)
            }
            guardar(VistaCajita(modelo: m).padding(20).background(Tema.dinamico(0xFFFFFF, 0x111111)), tam: NSSize(width: 330, height: 420),
                    apariencia: apariencia, en: url.appendingPathComponent("varita-\(n)-\(nombre).png"))
        }
        // El borde al agrandar (una sección, escalón 2 de 4) y al recortar un recuadro (con su medida).
        for (n, etiqueta, elegido) in [("borde-seccion", T("Sección · 2/4", "Section · 2/4"), false), ("borde-recorte", "640 × 360", false)] {
            let m = ModeloBorde()
            m.etiqueta = etiqueta
            m.elegido = elegido
            m.visible = true
            let fondo = Image(nsImage: fotoDeMuestra()).resizable().aspectRatio(contentMode: .fill).frame(width: 420, height: 240).clipped()
            guardar(fondo.overlay(VistaBorde(modelo: m).padding(30)), tam: NSSize(width: 420, height: 240),
                    apariencia: apariencia, en: url.appendingPathComponent("varita-\(n)-\(nombre).png"))
        }
        // La flecha que vuelve al apagar la Varita mientras no haya copia de la de verdad.
        if let f = FlechaVarita.Dibujo.clasica()?.imagenes.last {
            try? NSBitmapImageRep(cgImage: f).representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("flecha-clasica.png"))
        }
        TarjetaRespuesta.sinAnimar = false
    }

    // Una foto de muestra para las tarjetas de imagen (una cabaña al atardecer, dibujada: no hay fotos en el repo).
    private static func fotoDeMuestra() -> NSImage {
        NSImage(size: NSSize(width: 320, height: 180), flipped: false) { r in
            NSGradient(colors: [NSColor(hex: 0x3B2A6B), NSColor(hex: 0xC2569B), NSColor(hex: 0xF59E0B)])?.draw(in: r, angle: -90)
            NSColor(hex: 0xFDE68A).setFill()
            NSBezierPath(ovalIn: NSRect(x: 210, y: 70, width: 44, height: 44)).fill()
            let montes = NSBezierPath()
            montes.move(to: .zero); montes.line(to: NSPoint(x: 90, y: 110)); montes.line(to: NSPoint(x: 170, y: 50))
            montes.line(to: NSPoint(x: 250, y: 120)); montes.line(to: NSPoint(x: 320, y: 40)); montes.line(to: NSPoint(x: 320, y: 0))
            NSColor(hex: 0x1E1B3A).setFill(); montes.fill()
            NSColor(hex: 0xF8FAFC).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 320, height: 26)).fill()
            NSColor(hex: 0x7C4A2D).setFill()
            NSBezierPath(rect: NSRect(x: 120, y: 22, width: 60, height: 34)).fill()
            NSColor(hex: 0xFCD34D).setFill()
            NSBezierPath(rect: NSRect(x: 134, y: 32, width: 12, height: 12)).fill()
            NSBezierPath(rect: NSRect(x: 156, y: 32, width: 12, height: 12)).fill()
            return true
        }
    }

    private static func guardar<V: View>(_ vista: V, tam: NSSize, apariencia: NSAppearance, en destino: URL) {
        let host = NSHostingView(rootView: vista)
        host.appearance = apariencia
        let ventana = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: tam),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        ventana.appearance = apariencia
        ventana.contentView = host
        ventana.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: destino)
        ventana.orderOut(nil)
    }
}
