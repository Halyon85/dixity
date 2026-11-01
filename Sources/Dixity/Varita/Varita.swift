import AppKit
import OSLog
import SwiftUI

// El modo Varita (lo de Magic Pointer, a nuestra manera): se prende al sacudir el mouse o con el atajo, la flecha del
// sistema se vuelve la Varita, lo que está debajo del puntero se marca con un borde y una cajita con sugerencias va
// abajo a la derecha del cursor. Clic elige (no llega a la app de abajo, salvo en una caja de texto, que así queda
// activa); arrastrar selecciona texto como siempre; ⇧ + clic suma más cosas, que quedan copiadas juntas. ⌥ + rueda
// (o ⌥↑/⌥↓) agranda lo marcado a lo que lo contiene: una tarjeta, una sección, la ventana. ⌥ + arrastrar (o «Modo
// captura») recorta un recuadro. 1…5 eligen una sugerencia; Esc suelta lo elegido o apaga. Lo que se pide lo hace el Motor (`alPedir`), que después la apaga.
//
// Prendida: un reloj de 60 por segundo mueve el borde y la cajita con resortes; cada 4 vueltas pregunta a
// Accesibilidad qué hay debajo, fuera del hilo principal (así no traba el audio). Apagada no queda nada andando: las
// ventanitas y el escucha de clics se destruyen.
final class Varita {
    enum Pedido: Equatable {
        case copiarImagen, sacarTexto, leerQR, preguntar, describir, sacarPrompt
        case recrearLogo, recrearBanner, maqueta, colores
        case traducir(String), resumir, reformular, corregir, copiarTexto, leerEnVozAlta
        case adonde, copiarLink, copiarTabla, queHace, dictarAca
        case sumarPalabra                    // una palabra o un nombre seleccionado, al diccionario (como ⌃⌥D)
        case captura
        case copiarTodas, collage, preguntarTodas
        case mandar(Agente), arreglar        // pegarlo en la ventana de Claude Code o Codex; "Arreglalo con Claude"
    }

    // Qué hay disponible: sin IA configurada no se ofrece lo que la usa, y Claude o Codex solo si están en la Mac.
    struct Disponible: Equatable {
        var ia = true
        var claude = false            // se le puede mandar (la terminal o su app)
        var codex = false
        var claudeResponde = false    // Claude Code en la terminal: puede mirar imágenes y responder en la tarjeta
        var veImagenes = false        // tu IA mira imágenes: Describir, Sacar prompt y Preguntar van a ella, al instante
    }

    static let registro = Logger(subsystem: "team.halyon.dixity", category: "varita")

    var alPedir: (Pedido, [Senalador.Cosa], CGPoint) -> Void = { _, _, _ in }
    var alApagar: () -> Void = {}
    // Terminaste de seleccionar texto arrastrando con la Varita prendida: el Motor lee la selección y la pasa con
    // `usarSeleccion` (leerla puede mandar ⌘C, por eso no lo hace la Varita).
    var alSeleccionar: () -> Void = {}
    // Hiciste clic en una caja de texto: lo que escribas va a la caja (el Motor deja de tomar 1…9 y ↩ para la cajita).
    var alEntrarEnCaja: () -> Void = {}
    private(set) var prendida = false
    private(set) var elegidos: [Senalador.Cosa] = []
    private(set) var miniaturas: [NSImage] = []
    // El texto que tenías seleccionado al prenderla (o que seleccionaste arrastrando): mientras no elijas otra cosa, la
    // cajita ofrece qué hacer con él. `seleccionEditable`: está en una caja donde se escribe, así que se cambia ahí.
    private var seleccion = ""
    private var seleccionEditable = false
    var disponible = Disponible()
    // De la página Varita del panel (los pone el Motor antes de prenderla).
    var apagado: TimeInterval = 30            // 0: no se apaga sola
    var cambiarFlecha = true
    var buscarQR = true
    private var pusoFlecha = false            // esta vez se cambió la flecha: al apagar se devuelve

    private let modeloBorde = ModeloBorde()
    private let modeloCajita = ModeloCajita()
    private var ventanaBorde: VentanaFlotante?
    private var ventanaCajita: VentanaFlotante?
    private var marcas: [(VentanaFlotante, ModeloBorde, Senalador.Cosa)] = []
    private var reloj: Timer?
    private var tap: CFMachPort?
    private var fuenteTap: CFRunLoopSource?
    private var debajo: Senalador.Cosa?
    private var candidato: (Senalador.Cosa?, Date)?
    private var borde: ResorteRect?
    private var cajita: (x: Resorte, y: Resorte)?
    private var puntoClic: CGPoint?
    private var vuelta = 0
    private var buscando = false
    private var puntoBuscado: CGPoint?       // dónde se preguntó la última vez (con el mouse quieto se pregunta menos)
    private var tamCajita = CGSize(width: 272, height: 240)
    private var medirCajita = 3              // vueltas en que se vuelve a medir la cajita (cambió lo que muestra)
    private var ultimoUso = Date()
    // El clic que todavía no se sabe si es un clic (elegir) o el principio de un arrastre (seleccionar texto).
    private var apretado: (evento: CGEvent, punto: CGPoint, suma: Bool)?
    private var arrastrando = false
    private var apretadoEnCaja: CGPoint?     // un clic que pasó a una caja de texto: si arrastrás, seleccionaste ahí
    private var dobleClic = false            // un doble clic pasó a la app (selecciona una palabra): al soltar, se lee
    private var revisados: [(marco: CGRect, tiene: Bool)] = []   // las imágenes donde ya se buscó un QR (una vez por imagen)
    // Agrandar (01/11/2026): los escalones desde la cosa hasta la ventana, en cuál estás y dónde estaba el mouse.
    // Moverlo más de 12 puntos (sin nada elegido) vuelve a la cosa de abajo.
    private var niveles: [Senalador.Cosa] = []
    private var nivel = 0
    private var puntoNivel: CGPoint?
    private var calculandoNiveles = false
    private var ruedaAcumulada: CGFloat = 0
    private var ultimoPasoRueda = Date.distantPast
    // Recortar un recuadro (⌥ + arrastrar o «Modo captura»): en vez de la captura de macOS, que solo copiaba.
    private(set) var recortando = false
    private var inicioRecorte: CGPoint?
    private let cola = DispatchQueue(label: "dixity.varita", qos: .userInteractive)

    // MARK: Prender y apagar

    func prender(seleccion: String = "", editable: Bool = false) {
        guard !prendida else { return }
        prendida = true
        ultimoUso = Date()
        self.seleccion = seleccion.trimmingCharacters(in: .whitespacesAndNewlines)
        seleccionEditable = editable && !self.seleccion.isEmpty
        pusoFlecha = cambiarFlecha
        let flecha = cambiarFlecha && FlechaVarita.poner()
        Varita.registro.notice("prendida · flecha \(flecha ? "puesta" : "sin cambiar", privacy: .public) · selección \(self.seleccion.count) letras")
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        let borde = VentanaFlotante(VistaBorde(modelo: modeloBorde))
        let cajita = VentanaFlotante(VistaCajita(modelo: modeloCajita), tocable: true)
        cajita.ignoresMouseEvents = true
        ventanaBorde = borde
        ventanaCajita = cajita
        modeloCajita.alElegir = { [weak self] s in self?.elegir(s.id) }
        let p = NSEvent.mouseLocation
        self.cajita = (Resorte(valor: p.x + 16), Resorte(valor: p.y - 22))
        // Con algo seleccionado, la cajita se queda quieta junto al mouse para que puedas tocar una opción.
        if !self.seleccion.isEmpty { puntoClic = p }
        actualizarCajita()
        borde.orderFrontRegardless()
        cajita.orderFrontRegardless()
        modeloCajita.visible = true
        escucharClics()
        reloj = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tic() }
        RunLoop.main.add(reloj!, forMode: .common)
    }

    /// La selección llegó después de prender (en un navegador se lee copiando, que tarda un poco) o la hiciste
    /// arrastrando con la Varita prendida (`nueva`): en ese caso reemplaza lo que hubieras elegido con clic.
    func usarSeleccion(_ texto: String, editable: Bool, nueva: Bool = false) {
        guard prendida, nueva || elegidos.isEmpty else { return }
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || !nueva else { return }
        if nueva && !elegidos.isEmpty { elegidos = []; miniaturas = []; dibujarMarcas() }
        seleccion = t
        seleccionEditable = editable && !t.isEmpty
        if nueva { modeloBorde.visible = false; ultimoUso = Date() }
        if nueva || (puntoClic == nil && !t.isEmpty) { puntoClic = NSEvent.mouseLocation }
        actualizarCajita()
    }

    func apagar(_ motivo: String = "") {
        guard prendida else { return }
        Varita.registro.notice("apagada \(motivo, privacy: .public)")
        prendida = false
        reloj?.invalidate(); reloj = nil
        dejarDeEscucharClics()
        if pusoFlecha { FlechaVarita.devolver(); pusoFlecha = false }
        modeloCajita.visible = false
        modeloBorde.visible = false
        let ventanas = [ventanaBorde, ventanaCajita].compactMap { $0 } + marcas.map(\.0)
        ventanaBorde = nil; ventanaCajita = nil; marcas = []
        elegidos = []; miniaturas = []; debajo = nil; borde = nil; puntoClic = nil; seleccion = ""; seleccionEditable = false
        apretado = nil; arrastrando = false; apretadoEnCaja = nil; dobleClic = false; revisados = []; puntoBuscado = nil
        niveles = []; nivel = 0; puntoNivel = nil; calculandoNiveles = false; recortando = false; inicioRecorte = nil
        modeloCajita.miniaturas = []; modeloCajita.elegida = false
        // Se van con un fundido y después se destruyen (no quedan escondidas ocupando memoria).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ventanas.forEach { $0.orderOut(nil); $0.contentView = nil } }
        alApagar()
    }

    // Esc: primero deja de recortar o suelta lo elegido; si no había nada, apaga.
    func escape() {
        if recortando { terminarRecorte(nil) } else if !elegidos.isEmpty { soltar() } else { apagar("con Esc") }
    }

    // MARK: El reloj

    private func tic() {
        guard prendida else { return }
        let p = NSEvent.mouseLocation
        let dt: CGFloat = 1.0 / 60
        vuelta += 1
        // Pregunta a Accesibilidad 15 veces por segundo si el mouse se movió; quieto, 2 veces por segundo (por si
        // cambió lo de abajo, como al hacer scroll).
        // Agrandado y sin nada elegido: si el mouse se va de ahí, vuelve a marcar lo que tenga abajo.
        if nivel > 0, elegidos.isEmpty, let q = puntoNivel, hypot(p.x - q.x, p.y - q.y) > 12 { niveles = []; nivel = 0; puntoNivel = nil }
        if vuelta % 4 == 0 && elegidos.isEmpty && nivel == 0 && !recortando && !buscando && (p != puntoBuscado || vuelta % 32 == 0) {
            puntoBuscado = p
            buscar(en: p)
        }
        // El borde salta con resorte a lo que está debajo.
        if let d = debajo, elegidos.isEmpty, let v = ventanaBorde {
            let meta = d.marco.insetBy(dx: -6 - VistaBorde.margen, dy: -6 - VistaBorde.margen)
            if borde == nil { borde = ResorteRect(meta) }
            borde!.mover(a: meta, dt: dt, rigidez: 520)
            let marco = Varita.alPixel(borde!.rect, escala: v.backingScaleFactor)
            if marco != v.frame { v.setFrame(marco, display: true) }   // quieta, no se redibuja
        }
        moverCajita(p, dt: dt)
        if apagado > 0 && Date().timeIntervalSince(ultimoUso) > apagado { apagar("sola, \(Int(apagado)) s sin usar") }
    }

    private func buscar(en p: CGPoint) {
        buscando = true
        cola.async { [weak self] in
            let cosa = Senalador.cosa(en: p)
            DispatchQueue.main.async { self?.encontrado(cosa) }
        }
    }

    // Para no titilar entre dos cosas vecinas, el cambio se confirma si sigue igual 60 ms (entrar desde la nada es ya).
    private func encontrado(_ cosa: Senalador.Cosa?) {
        buscando = false
        guard prendida, elegidos.isEmpty, nivel == 0, !recortando else { return }
        if cosa != candidato?.0 { candidato = (cosa, Date()) }
        let firme = debajo == nil || Date().timeIntervalSince(candidato?.1 ?? Date()) > 0.06
        guard cosa != debajo, firme else { return }
        if debajo == nil, let c = cosa { borde = ResorteRect(c.marco.insetBy(dx: -6 - VistaBorde.margen, dy: -6 - VistaBorde.margen)) }
        debajo = cosa
        if cosa != nil { ultimoUso = Date() }
        modeloBorde.etiqueta = cosa?.tipo.nombre ?? ""
        modeloBorde.visible = cosa != nil
        actualizarCajita()
        if let c = cosa, [.imagen, .logo, .banner].contains(c.tipo), buscarQR { revisarCodigo(c) }
    }

    // «Leer el QR» se ofrece solo si la imagen tiene uno: se mira una vez por imagen, recién cuando el mouse se queda
    // un momento encima (no en cada imagen por la que pasás), con una foto chica (hasta 900 px) leída en la Mac
    // (Vision), y se suelta enseguida. Sin permiso de Grabación de pantalla no se ofrece.
    private func revisarCodigo(_ c: Senalador.Cosa) {
        if let ya = revisados.first(where: { $0.marco == c.marco }) {
            if ya.tiene { marcarCodigo(c) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.prendida, self.debajo == c || self.elegidos.contains(c),
                  !self.revisados.contains(where: { $0.marco == c.marco }) else { return }
            self.buscarCodigo(c)
        }
    }

    private func buscarCodigo(_ c: Senalador.Cosa) {
        revisados.append((c.marco, false))
        if revisados.count > 30 { revisados.removeFirst() }
        Task { @MainActor [weak self] in
            guard let img = await Pantalla.recorte(c.marco, maxPixeles: 900) else { return }
            // Vision fuera del hilo principal: ahí también se escuchan los clics, y la primera vez carga su modelo.
            let tiene = await Task.detached(priority: .utility) { !autoreleasepool(invoking: { EnLaMac.codigos(en: img) }).isEmpty }.value
            guard tiene, let self, self.prendida else { return }
            if let i = self.revisados.firstIndex(where: { $0.marco == c.marco }) { self.revisados[i].tiene = true }
            self.marcarCodigo(c)
        }
    }

    private func marcarCodigo(_ c: Senalador.Cosa) {
        if debajo == c { debajo?.tieneCodigo = true }
        if let i = elegidos.firstIndex(of: c) { elegidos[i].tieneCodigo = true }
        actualizarCajita()
    }

    // La cajita va abajo a la derecha del cursor (o de donde hiciste clic). Si no entra, del lado donde hay lugar.
    private func moverCajita(_ p: CGPoint, dt: CGFloat) {
        guard let v = ventanaCajita, var c = cajita else { return }
        // Se mide solo cuando cambió lo que muestra (medir la vista en cada vuelta gastaba CPU).
        if medirCajita > 0, let t = v.contentView?.fittingSize { tamCajita = t; medirCajita -= 1 }
        let tam = tamCajita
        let meta = Varita.lugarCajita(cursor: puntoClic ?? p, tam: tam,
                                      pantalla: NSScreen.screens.first { $0.frame.contains(p) }?.visibleFrame ?? .zero)
        c.x.mover(a: meta.x, dt: dt, rigidez: 1100, amortiguado: 1)
        c.y.mover(a: meta.y, dt: dt, rigidez: 1100, amortiguado: 1)
        cajita = c
        let marco = Varita.alPixel(CGRect(x: c.x.valor, y: c.y.valor, width: tam.width, height: tam.height), escala: v.backingScaleFactor)
        if marco != v.frame { v.setFrame(marco, display: true) }
    }

    /// Un marco con los bordes justo en píxeles de la pantalla: los resortes dan medios puntos y la ventanita se
    /// dibujaba entre dos píxeles, con los costados borrosos (la "rebaba").
    static func alPixel(_ r: CGRect, escala: CGFloat) -> CGRect {
        let e = max(1, escala)
        return CGRect(x: (r.minX * e).rounded() / e, y: (r.minY * e).rounded() / e,
                      width: (r.width * e).rounded() / e, height: (r.height * e).rounded() / e)
    }

    /// Dónde va la esquina de abajo a la izquierda de la cajita (coordenadas de AppKit) para que quede abajo a la
    /// derecha del cursor; si no entra a la derecha va a la izquierda, y si no entra abajo va arriba.
    static func lugarCajita(cursor p: CGPoint, tam: CGSize, pantalla: CGRect) -> CGPoint {
        let sombra: CGFloat = 18   // la vista tiene un margen alrededor para la sombra
        guard pantalla.width > 0 else { return CGPoint(x: p.x - sombra + 16, y: p.y + sombra - 22 - tam.height) }
        let derecha = p.x + 16 + tam.width - 2 * sombra <= pantalla.maxX - 8
        let abajo = p.y - 22 - tam.height + 2 * sombra >= pantalla.minY + 8
        var x = derecha ? p.x + 16 - sombra : p.x - 12 - tam.width + sombra
        var y = abajo ? p.y - 22 - tam.height + sombra : p.y + 10 - sombra
        x = min(max(x, pantalla.minX - sombra), pantalla.maxX - tam.width + sombra)
        y = min(max(y, pantalla.minY - sombra), pantalla.maxY - tam.height + sombra)
        return CGPoint(x: x, y: y)
    }

    // MARK: Sugerencias

    // Sobre qué trabaja ahora: lo elegido con clic; si no, lo seleccionado; si no, lo que está debajo del puntero.
    private var actuales: [Senalador.Cosa] {
        if !elegidos.isEmpty { return elegidos }
        if !seleccion.isEmpty { return [Senalador.Cosa(tipo: .texto, marco: .zero, texto: seleccion, editable: seleccionEditable)] }
        return [debajo].compactMap { $0 }
    }

    private func actualizarCajita() {
        let cosas = actuales
        let s = Varita.sugerencias(para: cosas, disponible: disponible, idiomaPersona: T("es", "en"))
        modeloCajita.sugerencias = s.map(\.0)
        modeloCajita.marcada = min(modeloCajita.marcada, max(0, s.count - 1))
        if cosas.count > 1 {
            modeloCajita.titulo = T("\(cosas.count) cosas juntas · copiadas", "\(cosas.count) items together · copied")
            modeloCajita.icono = "square.on.square"
        } else if let c = cosas.first, Varita.esSeleccion(c) {
            let n = Respuestas.palabras(c.texto)
            modeloCajita.titulo = n == 1 ? T("1 palabra seleccionada", "1 word selected") : T("\(n) palabras seleccionadas", "\(n) words selected")
            modeloCajita.icono = "text.cursor"
        } else if let c = cosas.first {
            modeloCajita.titulo = c.tipo == .campo && c.texto.isEmpty ? T("Caja de texto vacía", "Empty text box")
                : c.tipo == .campo ? T("Caja de texto", "Text box") : c.tipo.nombre
            modeloCajita.icono = Varita.icono(c.tipo)
        } else if recortando {
            modeloCajita.titulo = T("Recortar", "Snip")
            modeloCajita.icono = "crop"
        } else {
            modeloCajita.titulo = T("Varita", "Wonder")
            modeloCajita.icono = "wand.and.stars"
        }
        let editable = cosas.count == 1 && cosas[0].editable && !cosas[0].texto.isEmpty
        modeloCajita.pie = editable ? T("Lo cambia ahí mismo · ⌘Z deshace", "Changes it in place · ⌘Z undoes")
            : recortando ? T("Arrastrá un recuadro · Esc cancela", "Drag a box · Esc cancels")
            : elegidos.isEmpty ? T("Clic elige · ⌥ + rueda agranda", "Click picks · ⌥ + scroll grows")
            : elegidos.count == 1 ? T("⌥ + rueda agranda · ⇧ + clic suma otra", "⌥ + scroll grows · ⇧ + click adds another")
            : T("Mantené ⇧ y tocá otra para sumarla", "Hold ⇧ and click another to add it")
        modeloCajita.miniaturas = miniaturas
        modeloCajita.elegida = !elegidos.isEmpty
        medirCajita = 3   // SwiftUI la redibuja en la vuelta que sigue: se mide un par de veces
        // Se puede tocar cuando se queda quieta (elegiste algo o hay texto seleccionado); mientras sigue al mouse, no.
        ventanaCajita?.ignoresMouseEvents = puntoClic == nil
    }

    static func icono(_ t: Senalador.Tipo) -> String {
        switch t {
        case .imagen: "photo"
        case .texto: "text.alignleft"
        case .link: "link"
        case .tabla: "tablecells"
        case .campo: "character.cursor.ibeam"
        case .control: "cursorarrow.click"
        case .seccion: "rectangle.dashed"
        case .ventana: "macwindow"
        case .recorte: "crop"
        case .video: "play.rectangle"
        case .logo: "seal"
        case .banner: "rectangle.inset.filled"
        }
    }

    /// Lo seleccionado se representa como un texto sin lugar en pantalla.
    static func esSeleccion(_ c: Senalador.Cosa) -> Bool { c.tipo == .texto && c.marco == .zero }

    /// Qué ofrece la cajita según lo que hay: lo más útil primero, hasta 5, y siempre el modo captura al final.
    /// - Donde se puede escribir (una caja o un texto seleccionado en ella), lo que cambia el texto va primero y lo cambia
    ///   ahí mismo; en un texto que solo se lee, se muestra en una tarjeta.
    /// - Pasar de idioma, solo hacia el otro (un texto en inglés ofrece español). «Leer el QR», solo si la imagen tiene
    ///   uno. «Arreglalo con Claude», solo si lo seleccionado parece un error.
    /// - Lo que necesita IA no se ofrece sin IA; Claude y Codex, solo si están en la Mac.
    static func sugerencias(para cosas: [Senalador.Cosa], disponible: Disponible = Disponible(),
                            idiomaPersona: String) -> [(SugerenciaVarita, Pedido)] {
        func s(_ id: String, _ nombre: String, _ icono: String, _ color: UInt32, _ p: Pedido) -> (SugerenciaVarita, Pedido) {
            (SugerenciaVarita(id: id, nombre: nombre, icono: icono, color: Color(hex: color)), p)
        }
        let hayImagen = cosas.contains { $0.esVisual }
        // Con imágenes la pregunta va a tu IA si las ve (responde al instante); si no, a Claude Code si está.
        let aClaude = hayImagen && !disponible.veImagenes && disponible.claudeResponde
        let preguntar = aClaude
            ? s("preguntar", T("Preguntale a Claude", "Ask Claude"), "mic.fill", 0xF56138, .preguntar)
            : s("preguntar", T("Preguntá sobre esto", "Ask about this"), "mic.fill", 0xF56138, .preguntar)
        let captura = s("captura", T("Modo captura", "Capture"), "camera.viewfinder", 0xF59E0B, .captura)
        let leer = s("leer", T("Leer en voz alta", "Read aloud"), "speaker.wave.2.fill", 0x0EA5E9, .leerEnVozAlta)
        func traducir(_ texto: String) -> (SugerenciaVarita, Pedido) {
            let idioma = Respuestas.idioma(de: texto) ?? idiomaPersona
            let otro = idioma == "es" ? "en" : idioma == "en" ? "es" : idiomaPersona
            return s("traducir", T("Pasar a \(Respuestas.nombreIdioma(otro))", "To \(Respuestas.nombreIdioma(otro))"), "globe", 0x3B82F6, .traducir(otro))
        }
        let resumir = s("resumir", T("Resumir", "Summarize"), "text.line.first.and.arrowtriangle.forward", 0x8B5CF6, .resumir)
        let reformular = s("reformular", T("Reformular", "Rephrase"), "arrow.triangle.2.circlepath", 0x8B5CF6, .reformular)
        let corregir = s("corregir", T("Corregir", "Fix spelling"), "checkmark.seal.fill", 0x00B489, .corregir)
        let dictar = s("dictarAca", T("Dictá acá", "Dictate here"), "waveform", 0xF56138, .dictarAca)
        let claude = s("mandarClaude", T("Mandar a Claude", "Send to Claude"), "paperplane.fill", 0xD97757, .mandar(.claude))
        let codex = s("mandarCodex", T("Mandar a Codex", "Send to Codex"), "paperplane.fill", 0x10A37F, .mandar(.codex))
        let sumar = s("sumarPalabra", T("Sumar al diccionario", "Add to dictionary"), "character.book.closed.fill", 0xF56138, .sumarPalabra)
        // Para texto alcanza con uno: Claude si está; si no, Codex.
        let unAgente = disponible.claude ? [claude] : disponible.codex ? [codex] : []
        var lista: [(SugerenciaVarita, Pedido)]
        if cosas.count > 1 {
            lista = [s("copiarTodas", T("Copiar todas juntas", "Copy all together"), "doc.on.doc.fill", 0x14B8A6, .copiarTodas)]
                + (disponible.claude ? [claude] : []) + (disponible.codex ? [codex] : [])
                + [s("collage", T("Armar un collage", "Make a collage"), "square.grid.2x2.fill", 0xFF4F9A, .collage),
                   aClaude ? s("preguntarTodas", T("Preguntale a Claude", "Ask Claude"), "mic.fill", 0xF56138, .preguntarTodas)
                       : s("preguntarTodas", T("Preguntá sobre todas", "Ask about all"), "mic.fill", 0xF56138, .preguntarTodas)]
        } else if let c = cosas.first {
            let conTexto = !c.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            switch c.tipo {
            case .imagen, .seccion, .ventana, .recorte, .video, .logo, .banner:
                // Todo lo visual se trabaja con su foto. Describir va primero en una imagen: con tu IA la mira y responde
                // al instante; sin ella, la Mac dice lo que reconoce. Lo demás (Sacar prompt, Recrear, Maqueta) necesita
                // una IA que vea imágenes (01/11/2026). Cada clase pone primero lo suyo.
                let ve = disponible.veImagenes
                let describir = s("describir", T("Describir", "Describe"), "eye.fill", 0x6366F1, .describir)
                let prompt = s("sacarPrompt", T("Sacar prompt", "Get a prompt"), "wand.and.stars", 0x8B5CF6, .sacarPrompt)
                let qr = c.tieneCodigo ? [s("leerQR", T("Leer el QR", "Read the QR"), "qrcode", 0x6366F1, .leerQR)] : []
                let copiar = s("copiarImagen", T("Copiar imagen", "Copy image"), "doc.on.doc.fill", 0x14B8A6, .copiarImagen)
                let sacarTexto = s("sacarTexto", T("Sacar el texto", "Grab the text"), "text.viewfinder", 0x3B82F6, .sacarTexto)
                let colores = s("colores", T("Sacar colores", "Get colors"), "paintpalette.fill", 0xF59E0B, .colores)
                switch c.tipo {
                case .video:
                    let cuadro = s("copiarImagen", T("Copiar este cuadro", "Copy this frame"), "camera.fill", 0x14B8A6, .copiarImagen)
                    lista = [describir] + (ve ? [prompt] : []) + [cuadro, sacarTexto] + unAgente
                case .logo:
                    let logo = s("recrearLogo", T("Recrear logo", "Recreate logo"), "seal.fill", 0x8B5CF6, .recrearLogo)
                    lista = (ve ? [logo] : []) + [colores, describir] + qr + [copiar] + unAgente
                case .banner:
                    let banner = s("recrearBanner", T("Recrear banner", "Recreate banner"), "wand.and.stars", 0x8B5CF6, .recrearBanner)
                    lista = (ve ? [banner] : []) + [describir] + qr + [colores, sacarTexto, copiar]
                case .seccion, .ventana, .recorte:
                    let maqueta = s("maqueta", T("Hacer maqueta", "Make a mockup"), "rectangle.3.group.fill", 0xEC4899, .maqueta)
                    lista = (ve ? [maqueta] : []) + [describir] + qr + (ve ? [prompt] : []) + [colores, copiar, sacarTexto] + unAgente
                default:
                    lista = [describir] + (ve ? [prompt] : []) + qr + [copiar, sacarTexto] + unAgente + [preguntar]
                }
            // Seleccionaste una palabra o un nombre: se ofrece sumarlo al diccionario, en el lugar de Reformular o
            // Resumir, que con dos palabras no sirven (01/11/2026).
            case .texto where esSeleccion(c) && c.editable && Diccionario.esCorto(Diccionario.deSeleccion(c.texto)):
                lista = [traducir(c.texto), corregir, sumar, leer] + unAgente
            case .texto where esSeleccion(c) && c.editable, .campo where conTexto:
                lista = [traducir(c.texto), reformular, corregir, leer] + unAgente
            case .campo:
                lista = [dictar, s("queHace", T("¿Qué es esto?", "What is this?"), "questionmark.circle.fill", 0x6366F1, .queHace)]
            case .texto where esSeleccion(c) && pareceError(c.texto) && disponible.claude:
                lista = [s("arreglar", T("Arreglalo con Claude", "Fix it with Claude"), "wrench.and.screwdriver.fill", 0xD97757, .arreglar),
                         s("preguntar", T("Explicame este error", "Explain this error"), "mic.fill", 0xF56138, .preguntar), leer]
            case .texto where esSeleccion(c) && Diccionario.esCorto(Diccionario.deSeleccion(c.texto)):
                lista = [leer, traducir(c.texto), sumar, preguntar] + unAgente
            case .texto where esSeleccion(c):
                lista = [leer, traducir(c.texto), resumir, preguntar] + unAgente
            case .texto:
                lista = [traducir(c.texto), leer, resumir] + unAgente
                    + [s("copiarTexto", T("Copiar texto", "Copy text"), "doc.on.doc.fill", 0x14B8A6, .copiarTexto)]
            case .link:
                lista = [s("adonde", T("¿A dónde lleva?", "Where does it go?"), "magnifyingglass", 0x6366F1, .adonde),
                         s("copiarLink", T("Copiar link", "Copy link"), "link", 0x14B8A6, .copiarLink)] + unAgente
            case .tabla:
                lista = [s("copiarTabla", T("Copiar como planilla", "Copy as spreadsheet"), "tablecells.fill", 0x00B489, .copiarTabla)]
                    + unAgente + [preguntar]
            case .control:
                lista = [s("queHace", T("¿Qué es esto?", "What is this?"), "questionmark.circle.fill", 0x6366F1, .queHace), preguntar]
            }
        } else {
            // Sin nada debajo, solo el modo captura. (¿Cuánto me queda? se sacó el 31/10: Claude y Codex ya lo
            // muestran, y en la Varita aparecía o no según dónde estaba el mouse.)
            lista = []
        }
        // Preguntarle a Claude por una imagen usa Claude, no tu IA: se ofrece aunque no haya IA configurada.
        let usaIA: Set<String> = aClaude ? ["resumir", "reformular", "corregir", "queHace"]
            : ["preguntar", "preguntarTodas", "resumir", "reformular", "corregir", "queHace"]
        lista = lista.filter { disponible.ia || !usaIA.contains($0.0.id) }
        return Array(lista.prefix(5)) + [captura]
    }

    /// Lo seleccionado parece un error de un programa (de la Terminal, del navegador): se ofrece arreglarlo con Claude.
    static func pareceError(_ texto: String) -> Bool {
        let t = texto.lowercased()
        let pistas = ["error", "exception", "traceback", "failed", "fatal", "panic", "undefined is not", "cannot find",
                      "not found", "no such file", "segmentation fault", "uncaught", "warning:", "falló", "excepción"]
        return t.count >= 12 && pistas.contains { t.contains($0) }
    }

    /// 1…5 del teclado o clic en la cajita.
    func elegir(numero n: Int) {
        let s = modeloCajita.sugerencias
        guard n >= 1, n <= s.count else { return }
        elegir(s[n - 1].id)
    }

    func mover(_ paso: Int) {
        let n = modeloCajita.sugerencias.count
        guard n > 0 else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) { modeloCajita.marcada = (modeloCajita.marcada + paso + n) % n }
    }

    func elegirMarcada() {
        let s = modeloCajita.sugerencias
        if s.indices.contains(modeloCajita.marcada) { elegir(s[modeloCajita.marcada].id) }
    }

    private func elegir(_ id: String) {
        ultimoUso = Date()
        if id == "captura" { return empezarRecorte() }   // se recorta acá, con la Varita, y después se elige qué hacer
        let cosas = actuales
        guard let pedido = Varita.sugerencias(para: cosas, disponible: disponible, idiomaPersona: T("es", "en"))
            .first(where: { $0.0.id == id })?.1 else { return }
        let punto = puntoClic ?? NSEvent.mouseLocation
        alPedir(pedido, cosas, punto)
    }

    // MARK: Clics

    // Mientras está prendida, los clics fuera de la cajita no llegan a la app de abajo: eligen lo que hay debajo. Si
    // apretás y arrastrás, es para seleccionar texto: el clic se le devuelve a la app y la selección sigue como siempre.
    private func escucharClics() {
        let mascara = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.scrollWheel.rawValue)
        let yo = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mascara),
                                        callback: { _, tipo, evento, ref in
                                            let v = Unmanaged<Varita>.fromOpaque(ref!).takeUnretainedValue()
                                            return v.clic(tipo, evento)
                                        }, userInfo: yo) else { return }
        tap = t
        fuenteTap = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), fuenteTap, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func dejarDeEscucharClics() {
        if let f = fuenteTap { CFRunLoopRemoveSource(CFRunLoopGetMain(), f, .commonModes) }
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        tap = nil; fuenteTap = nil
    }

    private func clic(_ tipo: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        // El clic que la Varita le devuelve a la app (al empezar a arrastrar) pasa sin tocarlo.
        guard prendida, e.getIntegerValueField(.eventSourceUserData) != Motor.marcaPropia else { return Unmanaged.passUnretained(e) }
        let p = NSEvent.mouseLocation
        if tipo == .scrollWheel { return rueda(e) }
        if recorte(tipo, p) { return nil }
        switch tipo {
        case .leftMouseDown:
            // Clic en la cajita (cuando ya hay algo elegido): es para ella.
            if let v = ventanaCajita, !v.ignoresMouseEvents, v.frame.insetBy(dx: 18, dy: 18).contains(p) { return Unmanaged.passUnretained(e) }
            // ⌥ + arrastrar: recortar un recuadro sin pasar por la cajita.
            if e.flags.contains(.maskAlternate) && !e.flags.contains(.maskCommand) && !e.flags.contains(.maskControl) {
                recortando = true
                inicioRecorte = p
                DispatchQueue.main.async { [weak self] in self?.prepararRecorte() }
                return nil
            }
            let suma = e.flags.contains(.maskShift) || e.flags.contains(.maskCommand)
            // Doble (o triple) clic: es para seleccionar una palabra (o un párrafo). Pasa a la app, que lo cuenta igual
            // aunque el primer clic se lo haya quedado la Varita, y al soltar se lee lo seleccionado.
            if !suma, e.getIntegerValueField(.mouseEventClickState) >= 2 {
                dobleClic = true
                apretado = nil
                return Unmanaged.passUnretained(e)
            }
            // En una caja de texto el clic llega a la app (así queda activa y lo que escribas va ahí) y además la elige.
            if !suma, let d = debajo, d.editable, d.marco.contains(p) {
                apretadoEnCaja = p
                DispatchQueue.main.async { [weak self] in self?.alEntrarEnCaja() }
                DispatchQueue.main.async { [weak self] in self?.clicEn(p, suma: false) }
                return Unmanaged.passUnretained(e)
            }
            guard let copia = e.copy() else { return nil }
            apretado = (copia, p, suma)
            arrastrando = false
            return nil
        case .leftMouseDragged:
            if arrastrando { return Unmanaged.passUnretained(e) }
            guard let a = apretado else { return Unmanaged.passUnretained(e) }
            guard hypot(p.x - a.punto.x, p.y - a.punto.y) > 5 else { return nil }
            // Es un arrastre: la app recibe el clic de antes (marcado, para que la Varita lo deje pasar) y desde ahí el
            // arrastre sigue normal, así se selecciona texto con la Varita prendida.
            arrastrando = true
            a.evento.setIntegerValueField(.eventSourceUserData, value: Motor.marcaPropia)
            a.evento.post(tap: .cghidEventTap)
            ultimoUso = Date()
            return nil
        case .leftMouseUp:
            if dobleClic {
                dobleClic = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self, self.prendida else { return }
                    self.alSeleccionar()
                }
                return Unmanaged.passUnretained(e)
            }
            if let q = apretadoEnCaja {
                apretadoEnCaja = nil
                if hypot(p.x - q.x, p.y - q.y) > 5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                        guard let self, self.prendida else { return }
                        self.alSeleccionar()
                    }
                }
                return Unmanaged.passUnretained(e)
            }
            if arrastrando {
                arrastrando = false
                apretado = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self, self.prendida else { return }
                    self.alSeleccionar()
                }
                return Unmanaged.passUnretained(e)
            }
            guard let a = apretado else { return Unmanaged.passUnretained(e) }
            apretado = nil
            DispatchQueue.main.async { [weak self] in self?.clicEn(a.punto, suma: a.suma) }
            return nil
        default:
            return Unmanaged.passUnretained(e)
        }
    }

    private func clicEn(_ p: CGPoint, suma: Bool) {
        ultimoUso = Date()
        // Agrandado: se elige lo marcado (la sección o la ventana), no la cosa chica que está debajo del clic.
        if nivel > 0, elegidos.isEmpty, let d = debajo { return elegirCosa(d, en: p, suma: suma) }
        cola.async { [weak self] in
            let cosa = Senalador.cosa(en: p, conPagina: true)
            DispatchQueue.main.async { self?.elegirCosa(cosa, en: p, suma: suma) }
        }
    }

    private func elegirCosa(_ cosa: Senalador.Cosa?, en p: CGPoint, suma: Bool) {
        guard prendida else { return }
        guard var cosa else { soltar(); return }    // clic en la nada: suelta lo elegido
        if cosa.tipo == .imagen, let ya = revisados.first(where: { $0.marco == cosa.marco }) { cosa.tieneCodigo = ya.tiene }
        if !suma { seleccion = ""; seleccionEditable = false }   // elegiste otra cosa: deja de ofrecer lo seleccionado
        if suma && !elegidos.isEmpty {
            guard !elegidos.contains(cosa) else { return }
            elegidos.append(cosa)
            sumarMiniatura(cosa)
        } else {
            elegidos = [cosa]
            miniaturas = []
            if suma { sumarMiniatura(cosa) }
        }
        puntoClic = p
        modeloBorde.visible = false
        dibujarMarcas()
        actualizarCajita()
    }

    func soltar() {
        elegidos = []; miniaturas = []
        niveles = []; nivel = 0; puntoNivel = nil
        puntoClic = seleccion.isEmpty ? nil : NSEvent.mouseLocation   // con texto seleccionado, la cajita sigue quieta
        dibujarMarcas()
        debajo = nil
        actualizarCajita()
    }

    // Lo sumado con ⇧ se fotografía (tal como se ve), va a la cajita como miniatura y todo queda copiado junto.
    private func sumarMiniatura(_ c: Senalador.Cosa) {
        Task { @MainActor [weak self] in
            guard let img = await Pantalla.recorte(c.marco) else { return }
            guard let self, self.prendida else { return }
            self.miniaturas.append(NSImage(cgImage: img, size: c.marco.size))
            self.modeloCajita.miniaturas = self.miniaturas
            Cursor.copiarImagenes(self.miniaturas)
        }
    }

    private func dibujarMarcas() {
        for (v, _, _) in marcas { v.orderOut(nil); v.contentView = nil }
        marcas = elegidos.map { c in
            let m = ModeloBorde()
            m.elegido = true
            m.visible = true
            let v = VentanaFlotante(VistaBorde(modelo: m))
            v.setFrame(c.marco.insetBy(dx: -6 - VistaBorde.margen, dy: -6 - VistaBorde.margen), display: true)
            v.orderFrontRegardless()
            return (v, m, c)
        }
        ventanaCajita?.orderFrontRegardless()
    }

    // MARK: Agrandar

    /// ⌥ + rueda o ⌥↑/⌥↓: lo marcado (lo que está debajo o lo elegido) crece a lo que lo contiene —una tarjeta, una
    /// sección, la ventana— o vuelve a achicarse. Los escalones se calculan una vez (Accesibilidad, fuera del hilo
    /// principal) y se recorren al instante. Con varias cosas juntas no se agranda.
    func agrandar(_ paso: Int) {
        guard prendida, !recortando, elegidos.count <= 1, !calculandoNiveles else { return }
        ultimoUso = Date()
        if !niveles.isEmpty { return irANivel(nivel + paso) }
        guard paso > 0 else { return }
        let p = elegidos.isEmpty ? NSEvent.mouseLocation : (puntoClic ?? NSEvent.mouseLocation)
        calculandoNiveles = true
        cola.async { [weak self] in
            let lista = Senalador.niveles(en: p)
            DispatchQueue.main.async {
                guard let self, self.prendida else { return }
                self.calculandoNiveles = false
                guard lista.count > 1 else { return }
                self.niveles = lista
                self.puntoNivel = p
                self.nivel = 0
                self.irANivel(1)
            }
        }
    }

    private func irANivel(_ i: Int) {
        guard !niveles.isEmpty else { return }
        nivel = min(max(i, 0), niveles.count - 1)
        let c = niveles[nivel]
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        if elegidos.count == 1 {
            elegidos = [c]
            miniaturas = []
            dibujarMarcas()
        } else {
            debajo = c
            modeloBorde.etiqueta = c.tipo.nombre + (niveles.count > 2 ? " · \(nivel + 1)/\(niveles.count)" : "")
            modeloBorde.visible = true
        }
        if nivel == 0 && elegidos.isEmpty { niveles = []; puntoNivel = nil }   // volvió a la cosa: el mouse manda otra vez
        actualizarCajita()
    }

    // La rueda con ⌥ (también el trackpad): un paso cada 24 puntos, y no más de uno cada 0,15 s (la inercia del
    // trackpad seguiría agrandando). Sin ⌥, la rueda pasa a la app y la página se mueve como siempre.
    private func rueda(_ e: CGEvent) -> Unmanaged<CGEvent>? {
        let f = e.flags
        guard f.contains(.maskAlternate), !f.contains(.maskCommand), !f.contains(.maskControl), !recortando else {
            return Unmanaged.passUnretained(e)
        }
        var d = CGFloat(e.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        if d == 0 { d = CGFloat(e.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * 12 }
        ruedaAcumulada += d
        if abs(ruedaAcumulada) >= 24, Date().timeIntervalSince(ultimoPasoRueda) > 0.15 {
            let paso = ruedaAcumulada > 0 ? 1 : -1
            ruedaAcumulada = 0
            ultimoPasoRueda = Date()
            DispatchQueue.main.async { [weak self] in self?.agrandar(paso) }
        }
        return nil
    }

    // MARK: Recortar

    /// «Modo captura»: el próximo arrastre dibuja un recuadro y lo recortado queda elegido, con las mismas opciones que
    /// una imagen (Describir, Sacar prompt, Copiar…). Esc cancela.
    func empezarRecorte() {
        guard prendida else { return }
        recortando = true
        inicioRecorte = nil
        prepararRecorte()
    }

    private func prepararRecorte() {
        elegidos = []; miniaturas = []; niveles = []; nivel = 0
        dibujarMarcas()
        debajo = nil
        puntoClic = nil
        modeloBorde.visible = false
        ventanaCajita?.ignoresMouseEvents = true
        actualizarCajita()
    }

    // Los clics mientras se recorta son para el recuadro y no llegan a la app. False: no se está recortando.
    private func recorte(_ tipo: CGEventType, _ p: CGPoint) -> Bool {
        guard recortando else { return false }
        switch tipo {
        case .leftMouseDown:
            inicioRecorte = p
        case .leftMouseDragged:
            if let a = inicioRecorte {
                let r = Varita.recuadro(a, p)
                DispatchQueue.main.async { [weak self] in self?.mostrarRecorte(r) }
            }
        case .leftMouseUp:
            let r = inicioRecorte.map { Varita.recuadro($0, p) }
            DispatchQueue.main.async { [weak self] in self?.terminarRecorte(r) }
        default: return false
        }
        return true
    }

    /// El recuadro entre dos puntos (arrastrar para cualquier lado), en puntos enteros.
    static func recuadro(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).integral
    }

    private func mostrarRecorte(_ r: CGRect) {
        guard prendida, recortando, let v = ventanaBorde else { return }
        borde = nil
        modeloBorde.etiqueta = "\(Int(r.width)) × \(Int(r.height))"   // el borde de siempre, con la medida
        modeloBorde.visible = r.width > 2 && r.height > 2
        v.setFrame(Varita.alPixel(r.insetBy(dx: -VistaBorde.margen, dy: -VistaBorde.margen), escala: v.backingScaleFactor), display: true)
    }

    // Soltaste (o Esc, con nil): un recuadro de al menos 12 × 12 queda elegido como una imagen.
    private func terminarRecorte(_ r: CGRect?) {
        guard prendida else { return }
        recortando = false
        inicioRecorte = nil
        modeloBorde.visible = false
        guard let r, r.width >= 12, r.height >= 12 else { return actualizarCajita() }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        elegirCosa(Senalador.Cosa(tipo: .recorte, marco: r, pid: pid), en: CGPoint(x: r.maxX, y: r.minY), suma: false)
        if buscarQR, let c = elegidos.first { revisarCodigo(c) }
    }

    /// Varias imágenes en una sola: grilla de hasta 3 columnas, cada una de 480 px de ancho, con 12 px entre medio.
    static func collage(_ imagenes: [NSImage]) -> NSImage? {
        guard !imagenes.isEmpty else { return nil }
        let columnas = min(3, imagenes.count), ancho: CGFloat = 480, separacion: CGFloat = 12
        let altos = imagenes.map { ancho * $0.size.height / max(1, $0.size.width) }
        let filas = stride(from: 0, to: imagenes.count, by: columnas).map { Array($0..<min($0 + columnas, imagenes.count)) }
        let altoFila = filas.map { f in f.map { altos[$0] }.max() ?? 0 }
        let total = CGSize(width: CGFloat(columnas) * ancho + CGFloat(columnas - 1) * separacion,
                           height: altoFila.reduce(0, +) + CGFloat(filas.count - 1) * separacion)
        return NSImage(size: total, flipped: true) { _ in
            var y: CGFloat = 0
            for (i, fila) in filas.enumerated() {
                for (j, k) in fila.enumerated() {
                    let x = CGFloat(j) * (ancho + separacion)
                    imagenes[k].draw(in: CGRect(x: x, y: y, width: ancho, height: altos[k]))
                }
                y += altoFila[i] + separacion
            }
            return true
        }
    }

    /// Mientras el Motor trabaja en lo pedido, lo elegido brilla con una luz que lo recorre.
    func pensando(_ si: Bool) {
        marcas.forEach { $0.1.pensando = si }
        modeloBorde.pensando = si
    }
}
