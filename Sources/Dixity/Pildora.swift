import AppKit
import SwiftUI

// La píldora flotante: grabando → procesando → listo. Se puede arrastrar y recuerda dónde la dejaste.
final class ModeloPildora: ObservableObject {
    enum Estado: Equatable {
        case oculto, grabando, procesando, listo(String), aviso(String), sinCampo(String), modo(String), fallo(String)
        case respuesta(String)   // Preguntar: la respuesta, antes de pegarla
        var esRespuesta: Bool { if case .respuesta = self { true } else { false } }
    }
    enum Modo { case dictado, reescritura, pregunta }

    @Published var estado: Estado = .oculto
    @Published var modo: Modo = .dictado
    @Published var niveles: [CGFloat] = Array(repeating: 0, count: 11)
    @Published var manosLibres = false
    @Published var trabajo = false
    @Published var etiqueta: String?      // modo de este dictado (Correo, Mensaje, Formal, → Inglés)
    @Published var colorModo = Tema.acento   // color del modo de este dictado (se elige en Modos)
    @Published var cambioModo = 0          // sube cada vez que elegís un modo: la etiqueta salta para que se note
    @Published var frase = 0
    @Published var copiado = false
    @Published var hover = false
    @Published var sinSonido = false     // a los 2 s de grabar sin que llegue voz: "No te escucho"
    @Published var puedePegar = true     // la respuesta tiene un campo donde pegarse (si no, solo Copiar)
    @Published var tituloRespuesta = ""  // "Respuesta", o "Claude"/"Codex" si respondió un agente
    @Published var hacelo: String?       // "Hacelo con Claude": solo en respuestas de un agente
    @Published var atajoPreguntar = ""   // para la ayuda de la ventanita ("⌃⌥P y hablá para ajustarla")
    // La tarjeta de la respuesta (ver Respuestas y TarjetaRespuesta): su forma, los botones para seguir y si está
    // trabajando en uno. Los botones llaman al motor por `alOpcion` / `alDeshacer`.
    @Published var clase = Respuestas.Clase.texto
    @Published var miniaturas: [NSImage] = []   // la imagen que miró la IA (Varita), arriba de la respuesta
    @Published var opciones: [Respuestas.Opcion] = []
    @Published var trabajando: Respuestas.Opcion?
    @Published var puedeDeshacer = false
    @Published var enLaMac = false          // la resolvió la Mac, sin IA: la tarjeta lo marca
    @Published var avisoTarjeta: String?    // un botón no pudo (sin IA, idioma sin bajar…)
    @Published var avisoBueno = false       // el aviso es que salió bien ("Imagen copiada"): va con ✓ y no con !
    @Published var formato: Respuestas.Formato?   // la tarjeta de un prompt de imagen: su formato (nil: sin la fila)
    @Published var preguntaOpciones: String?      // los botones están preguntando algo ("¿En qué formato va el video?")
    @Published var sobre: String?           // mientras preguntás: sobre qué va a trabajar ("34 palabras seleccionadas")
    @Published var arriba = false           // la tarjeta va arriba de la ventanita (al lado del mouse, por la Varita)
    var alOpcion: (Respuestas.Opcion) -> Void = { _ in }
    var alDeshacer: () -> Void = {}
    var alFormato: (Respuestas.Formato) -> Void = { _ in }
    private var huboSonido = false
    var marcoPildora: CGRect = .zero      // dónde está la píldora dentro de la ventanita (para el hover)

    static var frases: [String] {
        [T("Pensando…", "Thinking…"), T("Puliendo…", "Polishing…"), T("Desenredando…", "Untangling…"),
         T("Eligiendo palabras…", "Choosing words…"), T("Dándole forma…", "Shaping it…"), T("Casi listo…", "Almost done…")]
    }

    func nivel(_ v: Float) {
        if v > 0.08 && !huboSonido {
            huboSonido = true
            if sinSonido { withAnimation(Tema.expo) { sinSonido = false } }
        }
        var n = niveles
        n.removeFirst()
        n.append(CGFloat(v))
        niveles = n
    }

    func empezarEscucha() {
        huboSonido = false
        sinSonido = false
    }

    // Si a los 2 s no llegó voz, avisa (micrófono equivocado o muteado).
    func revisarSonido() {
        guard estado == .grabando, !huboSonido else { return }
        withAnimation(Tema.expo) { sinSonido = true }
    }
}

final class PanelPildora: NSObject, NSWindowDelegate {
    let modelo = ModeloPildora()
    private let panel: NSPanel
    private var ocultar: DispatchWorkItem?
    private var rotar: Timer?
    private var ubicando = false
    var alCancelar: (() -> Void)?
    var alTerminar: (() -> Void)?
    var alReintentar: (() -> Void)?
    var alPegar: (() -> Void)?
    var alHacelo: (() -> Void)?
    var alDejarRespuesta: (() -> Void)?   // la ventanita dejó de mostrar la respuesta (cualquier cambio de estado)

    override init() {
        // Alta para que entre la respuesta de Preguntar; lo transparente deja pasar los clics.
        // 520 x 560: entra la tarjeta más alta (uso de Claude y Codex, o texto largo con botones).
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        // Sin fijar ignoresMouseEvents: las zonas transparentes dejan pasar los clics y la píldora se puede arrastrar.
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.delegate = self
        let vista = VistaClicable(rootView: VistaPildora(modelo: modelo, ajustes: .shared,
                                                         copiar: { [weak self] in self?.copiarTexto() },
                                                         cerrar: { [weak self] in self?.esconder() },
                                                         arrastrar: { [weak self] fin in self?.arrastrar(fin: fin) },
                                                         cancelarAhora: { [weak self] in self?.alCancelar?() },
                                                         terminarAhora: { [weak self] in self?.alTerminar?() },
                                                         reintentar: { [weak self] in self?.alReintentar?() },
                                                         pegar: { [weak self] in self?.alPegar?() },
                                                         hacelo: { [weak self] in self?.alHacelo?() }))
        // Arrastre nativo de macOS (anda aunque la ventanita no tenga foco); los botones siguen respondiendo.
        vista.debeArrastrar = { [weak self] punto in
            guard let m = self?.modelo, m.marcoPildora.contains(punto) else { return false }
            if case .sinCampo = m.estado { return punto.y < m.marcoPildora.minY + 34 && punto.x < m.marcoPildora.maxX - 40 }
            if m.estado.esRespuesta { return punto.y < m.marcoPildora.minY + 34 && punto.x < m.marcoPildora.maxX - 40 }
            if case .fallo = m.estado { return punto.x < m.marcoPildora.maxX - 140 }   // a la derecha, los botones
            if m.hover && m.estado == .grabando { return punto.x > m.marcoPildora.minX + 44 && punto.x < m.marcoPildora.maxX - 44 }
            return true
        }
        vista.alMover = { [weak self] punto in
            guard let m = self?.modelo else { return }
            let dentro = punto.map { m.marcoPildora.insetBy(dx: -6, dy: -6).contains($0) } ?? false
            if dentro != m.hover { withAnimation(.easeOut(duration: 0.15)) { m.hover = dentro } }
        }
        vista.frame = panel.contentView!.bounds
        vista.autoresizingMask = [.width, .height]
        panel.contentView = vista
    }

    // La Varita pide que lo próximo aparezca abajo a la derecha de donde estaba el mouse, no en el lugar de siempre.
    // Vale hasta que la ventanita se esconde.
    private var cerca: NSPoint?
    func mostrarCerca(de punto: NSPoint) {
        cerca = punto
        modelo.arriba = true
        ubicar()
    }

    private func ubicar() {
        ubicando = true
        defer { ubicando = false }
        if let c = cerca {
            // La tarjeta mide unos 468 de ancho y va centrada en la ventanita de 520: 26 de margen a cada lado.
            let area = (NSScreen.screens.first { NSMouseInRect(c, $0.frame, false) } ?? NSScreen.main)?.visibleFrame ?? .zero
            var origen = NSPoint(x: c.x + 16 - 26, y: c.y - 8 - panel.frame.height)
            origen.x = min(max(origen.x, area.minX - 26), area.maxX - panel.frame.width + 26)
            origen.y = max(origen.y, area.minY)
            panel.setFrameOrigin(origen)
            return
        }
        if let p = Ajustes.shared.datos.posicionPildora, p.count == 2 {
            let origen = NSPoint(x: p[0], y: p[1])
            let marco = NSRect(origin: origen, size: panel.frame.size)
            if NSScreen.screens.contains(where: { $0.frame.intersects(marco.insetBy(dx: 200, dy: 60)) }) {
                panel.setFrameOrigin(origen)
                return
            }
        }
        let mouse = NSEvent.mouseLocation
        let pantalla = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = pantalla?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.minY + 6))
    }

    func windowDidMove(_ n: Notification) {
        guard !ubicando, cerca == nil else { return }   // mover una tarjeta de la Varita no cambia el lugar de la píldora
        Ajustes.shared.datos.posicionPildora = [Double(panel.frame.origin.x), Double(panel.frame.origin.y)]
    }

    // Arrastre: sigue al mouse y, al soltar, guarda el lugar.
    private var desfase: NSPoint?
    private func arrastrar(fin: Bool) {
        let mouse = NSEvent.mouseLocation
        if fin {
            desfase = nil
            if cerca == nil { Ajustes.shared.datos.posicionPildora = [Double(panel.frame.origin.x), Double(panel.frame.origin.y)] }
            return
        }
        ocultar?.cancel()   // mientras la movés no se esconde
        if desfase == nil { desfase = NSPoint(x: mouse.x - panel.frame.origin.x, y: mouse.y - panel.frame.origin.y) }
        if let d = desfase { panel.setFrameOrigin(NSPoint(x: mouse.x - d.x, y: mouse.y - d.y)) }
    }

    func volverAlCentro() {
        Ajustes.shared.datos.posicionPildora = nil
        if panel.isVisible { ubicar() }
    }

    // Muestra la píldora un rato para poder acomodarla.
    func mostrarParaMover() {
        mostrar(.listo(T("Arrastrame a donde quieras", "Drag me anywhere")), durante: 10)
    }

    func mostrar(_ estado: ModeloPildora.Estado, modo: ModeloPildora.Modo? = nil, durante: TimeInterval? = nil) {
        ocultar?.cancel()
        if !panel.isVisible { ubicar(); panel.orderFrontRegardless() }
        if let m = modo { modelo.modo = m }
        rotar?.invalidate()
        if estado == .procesando {
            modelo.frase = 0
            rotar = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] _ in
                guard let m = self?.modelo else { return }
                withAnimation(Tema.expo) { m.frase = (m.frase + 1) % ModeloPildora.frases.count }
            }
        }
        if estado == .grabando {
            modelo.niveles = Array(repeating: 0, count: 11)
            modelo.empezarEscucha()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.modelo.revisarSonido() }
        }
        modelo.copiado = false
        let dejaRespuesta = modelo.estado.esRespuesta && !estado.esRespuesta
        withAnimation(Tema.expo) { modelo.estado = estado }
        if dejaRespuesta { alDejarRespuesta?() }
        if let t = durante {
            let w = DispatchWorkItem { [weak self] in self?.esconder() }
            ocultar = w
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: w)
        }
    }

    func esconder() {
        rotar?.invalidate()
        ocultar?.cancel()
        modelo.hover = false
        let dejaRespuesta = modelo.estado.esRespuesta
        withAnimation(.easeOut(duration: 0.22)) { modelo.estado = .oculto }
        if dejaRespuesta { alDejarRespuesta?() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.modelo.estado == .oculto else { return }
            self.panel.orderOut(nil)
            self.cerca = nil
            self.modelo.arriba = false
        }
    }

    private func copiarTexto() {
        let texto: String
        switch modelo.estado {
        case .sinCampo(let t), .respuesta(let t): texto = t
        default: return
        }
        Cursor.copiar(Prompts.sinControles(texto))
        withAnimation(Tema.expo) { modelo.copiado = true }
        let w = DispatchWorkItem { [weak self] in self?.esconder() }
        ocultar?.cancel()
        ocultar = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
    }
}

struct VistaPildora: View {
    @ObservedObject var modelo: ModeloPildora
    @ObservedObject var ajustes: Ajustes
    let copiar: () -> Void
    let cerrar: () -> Void
    var arrastrar: (Bool) -> Void = { _ in }
    var cancelarAhora: () -> Void = {}
    var terminarAhora: () -> Void = {}
    var reintentar: () -> Void = {}
    var pegar: () -> Void = {}
    var hacelo: () -> Void = {}
    @Environment(\.colorScheme) private var esquemaSistema

    private var estilo: EstiloPildora { ajustes.datos.estiloPildora }
    private var tarjeta: Bool {
        switch modelo.estado {
        case .sinCampo, .respuesta: true
        default: false
        }
    }
    private var radio: CGFloat { tarjeta ? 16 : 18 }

    var body: some View {
        VStack {
            if !modelo.arriba { Spacer(minLength: 0) }
            if modelo.estado != .oculto {
                contenido
                    .padding(.horizontal, 14)
                    .padding(.vertical, tarjeta ? 12 : 0)
                    .frame(minHeight: 36)
                    .background(fondo)
                    .overlay(borde)
                    .foregroundStyle(colorTexto)
                    .environment(\.colorScheme, esquemaPildora)
                    .background(GeometryReader { g in
                        Color.clear.onAppear { modelo.marcoPildora = g.frame(in: .global) }
                            .onChange(of: g.frame(in: .global)) { _, f in modelo.marcoPildora = f }
                    })
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                    .scaleEffect(ajustes.datos.tamanoPildora.escala, anchor: modelo.arriba ? .top : .bottom)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .offset(y: 5)).combined(with: .opacity),
                                            removal: .scale(scale: 0.94).combined(with: .offset(y: 8)).combined(with: .opacity)))
            }
            if modelo.arriba { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(modelo.arriba ? .top : .bottom, 14)
    }

    // "Automática": contrasta con el sistema (clara en modo oscuro y al revés).
    private var esquemaPildora: ColorScheme {
        switch estilo {
        case .automatica: esquemaSistema == .dark ? .light : .dark
        case .clara: .light
        case .oscura: .dark
        case .vidrio, .cristal: esquemaSistema
        }
    }
    private var colorTexto: Color { esquemaPildora == .dark ? .white : Color(hex: 0x0A0A0A) }

    @ViewBuilder private var fondo: some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        if estilo == .cristal {
            FondoCristal(forma: forma, opacidad: ajustes.datos.opacidadPildora)
        } else if estilo == .vidrio {
            forma.fill(.ultraThinMaterial).opacity(max(0.35, ajustes.datos.opacidadPildora))
        } else {
            forma.fill(esquemaPildora == .dark ? Color(hex: 0x1D1D1C) : Color(hex: 0xF8F6F4))
                .opacity(ajustes.datos.opacidadPildora)
        }
    }

    @ViewBuilder private var borde: some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        if modelo.modo != .dictado && modelo.estado == .grabando {
            forma.strokeBorder(Tema.arcoiris, lineWidth: 1.5)
        } else if modelo.estado == .procesando {
            BordeGirando(forma: forma, color: modelo.modo == .dictado ? modelo.colorModo : Tema.acento)
        } else {
            forma.strokeBorder(esquemaPildora == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder private var contenido: some View {
        switch modelo.estado {
        case .grabando:
            HStack(spacing: 12) {
                // Con el mouse encima: ✕ cancela y ✓ termina.
                if modelo.hover {
                    BotonRedondo(icono: "xmark", relleno: colorTexto.opacity(0.12), tinta: colorTexto, accion: cancelarAhora)
                        .help(T("Cancelar", "Cancel"))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    // Coral: Común. Violeta: modo Trabajo (prompt para Claude).
                    PuntoGrabando(color: modelo.modo == .dictado ? modelo.colorModo : Tema.acento)
                        .transition(.scale.combined(with: .opacity))
                }
                if modelo.sinSonido && !modelo.hover {
                    // En el color de aviso y con ícono: antes era texto gris y pasaba de largo (30/10/2026).
                    HStack(spacing: 5) {
                        Image(systemName: "mic.slash.fill").font(.system(size: 12, weight: .semibold))
                        Text(T("No te escucho", "Can't hear you")).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Tema.acento)
                    .transition(.opacity)
                } else {
                    Puntos(niveles: modelo.niveles)
                }
                if let e = modelo.etiqueta, !modelo.hover {
                    Text(e).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Capsule().fill(modelo.colorModo.opacity(0.18)))
                        .foregroundStyle(modelo.colorModo)
                        .id("\(e)-\(modelo.cambioModo)")
                        .transition(.asymmetric(insertion: .scale(scale: 1.35).combined(with: .opacity), removal: .opacity))
                }
                // Preguntar: sobre qué va a trabajar ("Sobre 34 palabras", "Sin selección · Safari").
                if modelo.modo == .pregunta, let s = modelo.sobre, !modelo.hover, !modelo.sinSonido {
                    HStack(spacing: 4) {
                        Image(systemName: s.hasPrefix(T("Sobre", "About")) ? "text.cursor" : "eye").font(.system(size: 10, weight: .semibold))
                        Text(s).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                    }
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(Tema.acento.opacity(0.16)))
                    .foregroundStyle(Tema.acento)
                    .frame(maxWidth: 200)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                if modelo.hover {
                    BotonRedondo(icono: "checkmark", relleno: colorTexto, tinta: esquemaPildora == .dark ? .black : .white, accion: terminarAhora)
                        .help(T("Terminar y escribir", "Finish and type"))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: modelo.modo == .reescritura ? "wand.and.stars" : modelo.modo == .pregunta ? "sparkles" : "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        case .procesando:
            Brillo(texto: ModeloPildora.frases[modelo.frase], color: colorTexto)
                .id(modelo.frase)
                .transition(.opacity.combined(with: .offset(y: 3)))
                .padding(.horizontal, 4)
        case .listo(let texto):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.exito).font(.system(size: 16))
                    .symbolEffect(.bounce, value: texto)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                Text(texto).font(.system(size: 14))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        case .modo(let nombre):
            // Aviso de modo elegido con el atajo: solo confirma, no graba.
            HStack(spacing: 8) {
                Circle().fill(modelo.colorModo).frame(width: 9, height: 9)
                Text(T("Modo", "Mode")).font(.system(size: 13)).opacity(0.6)
                Text(nombre).font(.system(size: 14, weight: .semibold)).foregroundStyle(modelo.colorModo)
            }
            .id(nombre)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .fallo(let texto):
            // Un dictado que falló: queda a la vista hasta que lo reintentes o lo cierres (antes era un aviso de 3,5 s
            // y se perdía si no estabas mirando; 30/10/2026). El audio ya está guardado.
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tema.acento).font(.system(size: 14))
                Text(texto).font(.system(size: 13)).lineLimit(2).frame(maxWidth: 300, alignment: .leading)
                Button(action: reintentar) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                        Text(T("Reintentar", "Retry")).font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(Capsule().fill(Tema.acento))
                    .foregroundStyle(.white)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(action: cerrar) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).opacity(0.6)
                        .frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
        case .aviso(let texto):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tema.acento).font(.system(size: 14))
                Text(texto).font(.system(size: 13)).lineLimit(2).frame(maxWidth: 420, alignment: .leading)
            }
        case .sinCampo(let texto):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tema.acento).font(.system(size: 13))
                    Text(T("No se pudo pegar. Quedó copiado:", "Couldn't paste. Copied to clipboard:")).font(.system(size: 12, weight: .medium)).opacity(0.75)
                    Spacer(minLength: 12)
                    Button(action: cerrar) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).opacity(0.6)
                            .frame(width: 18, height: 18).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text(texto).font(.system(size: 13)).lineLimit(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer()
                    Button(action: copiar) {
                        HStack(spacing: 5) {
                            Image(systemName: modelo.copiado ? "checkmark" : "doc.on.doc").font(.system(size: 11, weight: .semibold))
                            Text(modelo.copiado ? T("Copiado", "Copied") : T("Copiar", "Copy")).font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule().fill(Tema.acento))
                        .foregroundStyle(.white)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 400)
        case .respuesta(let texto):
            TarjetaRespuesta(modelo: modelo, texto: texto, tinta: colorTexto, copiar: copiar, pegar: pegar, hacer: hacelo, cerrar: cerrar)
        case .oculto:
            EmptyView()
        }
    }
}

private struct PuntoGrabando: View {
    let color: Color
    @Estado private var latido = false
    var body: some View {
        Circle().fill(color).frame(width: 9, height: 9)
            .opacity(latido ? 0.45 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { latido = true } }
    }
}

// Onda: sale del centro hacia los costados; en las puntas quedan puntitos.
private struct Puntos: View {
    let niveles: [CGFloat]
    private let cantidad = 13
    var body: some View {
        let centro = cantidad / 2
        HStack(spacing: 2.6) {
            ForEach(0..<cantidad, id: \.self) { i in
                let distancia = abs(i - centro)
                let nivel = niveles[max(0, niveles.count - 1 - distancia)]           // lo más reciente, en el medio
                let forma = max(0.12, 1 - pow(CGFloat(distancia) / CGFloat(centro + 1), 1.6))   // campana
                Capsule()
                    .frame(width: 2.6, height: max(2.6, 18 * min(1, nivel * 1.4) * forma))
                    .animation(.easeOut(duration: 0.1), value: nivel)
            }
        }
        .frame(height: 20)
    }
}

// Cristal 3D: Liquid Glass de Apple (macOS 26+) con un brillo arriba y sombra abajo para darle volumen.
struct FondoCristal<F: InsettableShape>: View {
    let forma: F
    let opacidad: Double
    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: forma)
            } else {
                forma.fill(.regularMaterial)
            }
            forma.fill(LinearGradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.08)],
                                      startPoint: .top, endPoint: .bottom))
            forma.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05), .black.opacity(0.15)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .opacity(max(0.5, opacidad))
        .shadow(color: .black.opacity(0.22), radius: 1, y: 1)
    }
}

private struct BotonRedondo: View {
    let icono: String
    let relleno: Color
    let tinta: Color
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            Image(systemName: icono).font(.system(size: 10, weight: .bold))
                .foregroundStyle(tinta)
                .frame(width: 22, height: 22)
                .background(Circle().fill(relleno))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// Mientras mejora el texto: un brillo de color que gira por el borde.
struct BordeGirando<F: InsettableShape>: View {
    let forma: F
    let color: Color
    var body: some View {
        TimelineView(.animation) { ctx in
            let angulo = Angle.degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 * 360)
            forma.strokeBorder(AngularGradient(colors: [color.opacity(0), color.opacity(0.9), color.opacity(0)],
                                               center: .center, angle: angulo), lineWidth: 1.5)
        }
    }
}

// Texto con un brillo que lo recorre mientras la IA trabaja.
struct Brillo: View {
    let texto: String
    let color: Color
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let fase = CGFloat((t.truncatingRemainder(dividingBy: 1.4)) / 1.4) * 1.6 - 0.3
            Text(texto).font(.system(size: 14))
                .foregroundStyle(color.opacity(0.5))
                .overlay(
                    Text(texto).font(.system(size: 14)).foregroundStyle(color)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: min(1, max(0, fase - 0.25))),
                                                     .init(color: .white, location: min(1, max(0, fase))),
                                                     .init(color: .clear, location: min(1, max(0, fase + 0.25)))],
                                             startPoint: .leading, endPoint: .trailing))
                )
        }
    }
}

// Acepta el primer clic aunque Dicta no sea la app activa (para arrastrar o tocar "Copiar"),
// y avisa dónde está el mouse aunque la ventanita no tenga el foco (para mostrar ✕ y ✓).
final class VistaClicable<C: View>: NSHostingView<C> {
    var alMover: ((CGPoint?) -> Void)?
    var debeArrastrar: ((CGPoint) -> Bool)?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        if debeArrastrar?(punto(e)) == true { window?.performDrag(with: e) } else { super.mouseDown(with: e) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = area { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseMoved(with e: NSEvent) { super.mouseMoved(with: e); alMover?(punto(e)) }
    override func mouseEntered(with e: NSEvent) { super.mouseEntered(with: e); alMover?(punto(e)) }
    override func mouseExited(with e: NSEvent) { super.mouseExited(with: e); alMover?(nil) }

    // Coordenadas de arriba hacia abajo, como las de SwiftUI.
    private func punto(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return isFlipped ? p : CGPoint(x: p.x, y: bounds.height - p.y)
    }
}
