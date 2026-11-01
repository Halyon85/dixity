import AppKit
import SwiftUI

// Une todo: atajo → grabar → voz a texto → pasar en limpio → pegar.
final class Motor {
    static let marcaPropia: Int64 = 0x4449_4354   // marca los eventos de teclado que manda Dicta

    let pildora = PanelPildora()
    let grabador = Grabador()
    let monitor = MonitorAtajos()
    let varita = Varita()
    let sacudida = Sacudida()
    // Lo que eligió la Varita para preguntar por voz: pasa a ser "lo seleccionado" de ese Preguntar. Las imágenes
    // elegidas van como archivos a Claude (o Codex), que las mira y responde en la tarjeta.
    private var seleccionVarita: String?
    private var imagenesVarita: [URL] = []
    private var imagenesPregunta: [URL] = []
    var abrirPanel: ((String?) -> Void)?
    var alternarPortapapeles: (() -> Void)?
    private(set) var ultimoResultado = ""
    // El último dictado, para volver a procesarlo con el atajo (⌃⌥R). Si falló, su audio queda acá (el historial
    // borra los audios sin dictado); si salió, se lee del historial.
    private var ultimoDictado: (audio: String?, wav: Data?, segundos: Double, estilo: Estilo, id: UUID?)?

    private enum Estado { case libre, grabando, procesando }
    private var estado = Estado.libre
    private var accion = MonitorAtajos.Accion.dictar
    private var manosLibres = false
    private var contexto: ContextoCursor?
    private var seleccion = ""
    private var pidAdelante: pid_t?   // Preguntar: la app de adelante al empezar (para leer su ventana)
    private var estilo = Estilo.comun        // el de este dictado (por app, por fn + número o dicho en voz alta)
    private var trabajo: Bool { estilo == .trabajo }
    private var lecturaPantalla: Task<String, Never>?   // el texto de la ventana, leído mientras hablás
    // Preguntar: lo que está en la ventanita (para pegarlo con ↩) y, al volver a hablar, lo que se ajusta.
    private var respuesta: Respuesta?
    private var seguimiento: Respuesta?
    struct Respuesta {
        var pedido: String
        var texto: String
        var contexto: ContextoCursor?
        var tarea: Agentes.Tarea? = nil   // respuesta de Claude o Codex: con ella, el botón Hacelo
        var titulo: String? = nil         // lo resolvió la Mac sin IA ("Traductor de Apple · en la Mac")
        var clase = Respuestas.Clase.texto
        var versiones: [(texto: String, clase: Respuestas.Clase)] = []   // lo de antes de cada botón, para Deshacer
        var imagenes: [URL] = []          // las de la Varita que miró la IA: seguir preguntando las vuelve a mandar
        var miniaturas: [NSImage] = []    // las mismas, chiquitas arriba de la respuesta
        var formato = Respuestas.Formato.original   // un prompt de imagen: para qué es (Post 4:5, Historia 9:16…)

        /// La proporción de la imagen elegida ("16:9"), para el formato Original.
        var proporcionOriginal: String { miniaturas.first.map { PedidoImagen.proporcion($0.size) } ?? "1:1" }
    }
    private var agenteTrabajando: Agente?   // uno a la vez: el pedido sigue mientras dictás
    private var ajustes: Ajustes { .shared }

    init() {
        grabador.alNivel = { [weak self] v in self?.pildora.modelo.nivel(v) }
        monitor.alEvento = { [weak self] e in self?.atender(e) }
        pildora.alCancelar = { [weak self] in if self?.estado == .grabando { self?.cancelar(aviso: T("Cancelado", "Canceled")) } }
        pildora.alTerminar = { [weak self] in if self?.estado == .grabando { self?.terminar() } }
        pildora.alPausar = { [weak self] in self?.alternarPausa() }
        pildora.alReintentar = { [weak self] in self?.reprocesarUltimo() }
        pildora.alPegar = { [weak self] in self?.pegarRespuesta() }
        pildora.alDejarRespuesta = { [weak self] in self?.soltarRespuesta() }
        pildora.alHacelo = { [weak self] in self?.hacerTarea() }
        pildora.modelo.alOpcion = { [weak self] o in self?.aplicarOpcion(o) }
        pildora.modelo.alDeshacer = { [weak self] in self?.deshacerOpcion() }
        pildora.modelo.alFormato = { [weak self] f in self?.elegirFormato(f) }
        sacudida.alSacudir = { [weak self] _ in self?.alternarVarita() }
        varita.alPedir = { [weak self] p, cosas, punto in self?.pedidoVarita(p, cosas, en: punto) }
        varita.alSeleccionar = { [weak self] in self?.leerSeleccionVarita() }
        varita.alEntrarEnCaja = { [weak self] in self?.monitor.menuEscribiendo = true }
        varita.alApagar = { [weak self] in
            guard let self else { return }
            self.programarDevolucionDeMemoria()   // las fotos de lo que señalaste y lo que usó Vision vuelven a la Mac
            self.monitor.capturaMenu = false
            self.monitor.menuEscribiendo = false
            if self.estado != .grabando && self.respuesta == nil { self.monitor.capturaEsc = false }
        }
        actualizarAtajos()
    }

    func actualizarAtajos() {
        var a: [MonitorAtajos.Accion: Atajo] = [.dictar: ajustes.datos.atajoDictar, .reescribir: ajustes.datos.atajoReescribir]
        if ajustes.datos.portapapelesActivo { a[.portapapeles] = ajustes.datos.atajoPortapapeles }
        a[.reprocesar] = ajustes.datos.atajoReprocesar
        a[.sumarPalabra] = ajustes.datos.atajoSumarPalabra
        a[.preguntar] = ajustes.datos.atajoPreguntar
        monitor.atajos = a
        monitor.atajosNumero = ajustes.datos.atajosNumero
        monitor.familiasModos = ajustes.datos.teclaModos.familias
        var propios = Dictionary(uniqueKeysWithValues: ajustes.datos.modos.compactMap { m in m.atajo.map { (m.estilo, $0) } })
        if let a = ajustes.datos.atajoAutomatico { propios[.automatico] = a }
        monitor.atajosModo = propios
        monitor.atajosAccion = Dictionary(uniqueKeysWithValues: ajustes.datos.acciones.compactMap { a in a.atajo.map { (a.id, $0) } })
        if ajustes.datos.sacudirMouse { sacudida.prender(ajustes.datos.sensibilidadSacudida) } else { sacudida.apagar() }
    }

    @discardableResult
    func arrancarTeclado() -> Bool { monitor.arrancar() }

    // `defaults write team.halyon.dixity depurarTeclas -bool YES` anota en el registro del sistema cada atajo que llega.
    static let depurar = UserDefaults.standard.bool(forKey: "depurarTeclas")

    private func atender(_ e: MonitorAtajos.Evento) {
        if Motor.depurar { NSLog("Dixity atajo: \(e) · estado \(estado)") }
        switch e {
        case .apretar(.portapapeles):
            DispatchQueue.main.async { [weak self] in self?.alternarPortapapeles?() }
        case .apretar(.reprocesar):
            DispatchQueue.main.async { [weak self] in self?.reprocesarUltimo() }
        case .apretar(.sumarPalabra):
            DispatchQueue.main.async { [weak self] in self?.sumarSeleccion() }
        case .apretar(let a):
            // En modo toques, cada toque alterna, dure lo que dure. En "apretar y soltar", vale el segundo toque del modo manos libres.
            if estado == .grabando && accion == a && (manosLibres || ajustes.datos.modoTecla == .alternar) { terminar() }
            else if estado == .libre {
                // Fuera del callback del teclado: leer la selección puede mandar ⌘C.
                DispatchQueue.main.async { [weak self] in
                    if self?.estado == .libre { self?.empezar(a) }
                }
            }
        case .soltar(.portapapeles, _), .anular(.portapapeles), .soltar(.reprocesar, _), .anular(.reprocesar),
             .soltar(.sumarPalabra, _), .anular(.sumarPalabra):
            break
        case .soltar(let a, let sostenido):
            guard estado == .grabando, accion == a, !manosLibres else { return }
            // "Apretar y soltar": al soltar, termina y pega. "Toques": soltar no corta; corta el próximo toque.
            // "Las dos": un toque corto sigue grabando (como "Toques"); si mantuviste, al soltar termina.
            let modo = ajustes.datos.modoTecla
            if modo == .alternar || (modo == .ambos && sostenido < ModoTecla.toqueMaximo) {
                manosLibres = true          // fue un toque: sigue grabando hasta el próximo toque
                pildora.modelo.manosLibres = true
            } else {
                terminar()
            }
        case .anular(let a):
            if estado == .grabando && accion == a && !manosLibres { cancelar(aviso: nil) }
        case .modo(let n):
            // 0 = automático según la app; 1…n = los modos visibles en tu orden.
            let lista = ajustes.modosActivos
            guard n == 0 || n <= lista.count else { return }
            let e = n == 0 ? Estilo.automatico : lista[n - 1]
            DispatchQueue.main.async { [weak self] in self?.elegirModo(e) }
        case .modoPropio(let e):
            DispatchQueue.main.async { [weak self] in self?.elegirModo(e) }
        case .accionRapida(let id):
            // Fuera del callback del teclado: leer la selección puede mandar ⌘C.
            DispatchQueue.main.async { [weak self] in self?.ejecutarAccion(id) }
        case .escape:
            if lector.leyendo { DispatchQueue.main.async { [weak self] in self?.lector.parar() } }
            else if varita.prendida { DispatchQueue.main.async { [weak self] in self?.varita.escape() } }
            else if estado == .grabando { cancelar(aviso: T("Cancelado", "Canceled")) }
            else if respuesta != nil { DispatchQueue.main.async { [weak self] in self?.pildora.esconder() } }
        case .confirmar:
            DispatchQueue.main.async { [weak self] in self?.pegarRespuesta() }
        case .menu(let t):
            DispatchQueue.main.async { [weak self] in
                guard let self, self.varita.prendida else { return }
                switch t {
                case .numero(let n): self.varita.elegir(numero: n)
                case .arriba: self.varita.mover(-1)
                case .abajo: self.varita.mover(1)
                case .elegir: self.varita.elegirMarcada()
                case .agrandar: self.varita.agrandar(1)
                case .achicar: self.varita.agrandar(-1)
                case .otra: self.varita.apagar("al escribir")   // la tecla llega a la app
                }
            }
        case .teclaSuelta:
            // Escribís en otro lado: la ventanita se cierra (la respuesta queda en el historial) y ↩ vuelve a ser tuyo.
            DispatchQueue.main.async { [weak self] in if self?.respuesta != nil { self?.pildora.esconder() } }
        }
    }

    private func empezar(_ a: MonitorAtajos.Accion, estilo forzado: Estilo? = nil) {
        guard Grabador.permitido else {
            Grabador.pedirPermiso { [weak self] ok in
                self?.pildora.mostrar(.aviso(ok ? T("Micrófono permitido. Apretá el atajo de nuevo.", "Microphone allowed. Press the shortcut again.")
                                                 : T("Falta permiso de micrófono (Ajustes › Privacidad › Micrófono).", "Microphone access needed (Settings › Privacy › Microphone).")), durante: 3)
            }
            return
        }
        let d = ajustes.datos
        // Preguntarle a Claude por imágenes de la Varita no usa tu IA (lo responde Claude Code).
        if a == .preguntar && !ajustes.iaLista && imagenesVarita.isEmpty {
            pildora.mostrar(.aviso(T("Preguntar usa la IA: configurala en Proveedores.", "Ask uses AI: set it up in Providers.")), durante: 3)
            return
        }
        if !d.proveedorVoz.local && ajustes.claveVoz.isEmpty {
            pildora.mostrar(.aviso(T("Falta la clave de voz a texto. Cargala en Proveedores.", "Speech-to-text key missing. Add it in Providers.")), durante: 3)
            abrirPanel?("proveedores")
            return
        }
        accion = a
        manosLibres = false
        pildora.modelo.manosLibres = false
        // Con la ventanita abierta, volver a preguntar ajusta esa respuesta (en la misma app y el mismo campo).
        seguimiento = a == .preguntar ? respuesta : nil
        // El texto alrededor del cursor se lee solo con "Mirar la ventana" prendido, también al reescribir: la selección
        // se lee igual, aparte (antes reescribir lo mandaba a la IA aunque estuviera apagado; auditoría del 23/10/2026).
        contexto = seguimiento?.contexto ?? Cursor.capturar(conTexto: d.mirarVentana)
        let conSeleccion = a == .reescribir || (a == .preguntar && seguimiento == nil)
        seleccion = conSeleccion ? (contexto?.seleccion ?? "") : ""
        if a == .preguntar, let elegido = seleccionVarita, !elegido.isEmpty { seleccion = elegido }
        // Seguir preguntando sobre la respuesta de una imagen vuelve a mandar esa imagen.
        imagenesPregunta = a == .preguntar ? (seguimiento?.imagenes ?? imagenesVarita) : []
        pidAdelante = a == .preguntar ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
        if conSeleccion && seleccion.isEmpty && contexto?.hayCampo == true {
            seleccion = Cursor.seleccionPorCopia()
        }
        estilo = a == .dictar ? (forzado ?? ajustes.estiloPara(contexto)) : .comun
        lecturaPantalla?.cancel()
        lecturaPantalla = nil
        // Solo si la IA lo va a usar: sin IA no sirve y la de Apple tiene poco lugar (y así no se gasta Vision).
        let iaUsaPantalla = ajustes.iaLista && d.proveedorIA != .apple && (d.limpiarConIA || estilo != .comun) && contexto?.secreto != true
        if a == .dictar && d.leerPantalla && d.mirarVentana && iaUsaPantalla, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            lecturaPantalla = Task.detached(priority: .utility) { await Pantalla.leer(pid: pid) }
        }
        do { try grabador.empezar(microfono: d.microfono) }
        catch {
            pildora.mostrar(.aviso(T("No pude empezar a grabar: \(error.localizedDescription)", "Couldn't start recording: \(error.localizedDescription)")), durante: 3)
            return
        }
        estado = .grabando
        monitor.capturaEsc = true
        monitor.capturaNumeros = a == .dictar && d.numerosGrabando
        if d.sonidoAlEmpezar { Motor.sonido("Tink") }
        if d.pausarMusica { Musica.pausar() }
        mostrarModo()
        pildora.modelo.sobre = a == .preguntar ? Motor.sobreQue(seleccion: seleccion, ajustando: seguimiento != nil, app: contexto?.app ?? "") : nil
        pildora.mostrar(.grabando, modo: a == .reescribir ? .reescritura : a == .preguntar ? .pregunta : .dictado)
        precalentar(d)
    }

    // Mientras hablás: carga Parakeet o abre la conexión con los servicios, así al soltar no se espera.
    private func precalentar(_ d: DatosAjustes) {
        if d.proveedorVoz == .parakeet { Task.detached { _ = try? await Parakeet.shared.cargar() } }
        else { Proveedores.precalentar(ajustes.urlVoz) }
        if d.proveedorIA != .ninguno && d.proveedorIA.urlBase != d.proveedorVoz.urlBase { Proveedores.precalentar(ajustes.urlIA) }
    }

    // Atajo de modo: nunca empieza a grabar. Sin dictado, deja elegido ese modo para los próximos (como el menú) y lo
    // muestra en la píldora un momento; grabando, cambia el modo de ese dictado.
    private func elegirModo(_ e: Estilo) {
        if estado == .grabando && accion == .dictar {
            estilo = e == .automatico ? ajustes.estiloPara(contexto) : e
            mostrarModo(elegido: true)
        } else if estado == .libre {
            ajustes.datos.estilo = e
            pildora.modelo.colorModo = e == .automatico ? Tema.acento : ajustes.color(de: e)
            pildora.mostrar(.modo(e == .automatico ? T("Automático", "Automatic") : e.etiqueta), durante: 1.3)
        }
    }

    // Punto violeta en Trabajo; el nombre del modo en la píldora para Correo, Mensaje, Formal y Traducir, y para
    // cualquiera que elijas con la combinación (así se ve a qué modo pasaste, aunque sea Común).
    private func mostrarModo(elegido: Bool = false) {
        withAnimation(Tema.expo) {
            pildora.modelo.trabajo = trabajo
            pildora.modelo.colorModo = ajustes.color(de: estilo)
            pildora.modelo.etiqueta = switch estilo {
            case .traducir: "→ " + ajustes.idiomaDestino.capitalized
            case .comun, .trabajo, .automatico: elegido ? estilo.etiqueta : nil
            default: estilo.etiqueta
            }
            if elegido { pildora.modelo.cambioModo += 1 }
        }
    }

    // ⏸ / ▶ de la píldora (la llama alPausar): pausa el dictado o lo sigue. Al pausar pasa a manos libres, así
    // soltar la tecla no lo termina; después el atajo o el ✓ terminan con todo lo grabado y Esc cancela.
    // Si el micrófono no vuelve (lo desconectaste en la pausa), termina con lo que ya había.
    private func alternarPausa() {
        guard estado == .grabando else { return }
        let m = pildora.modelo
        if grabador.enPausa {
            do { try grabador.seguir() } catch { terminar(); return }
            if ajustes.datos.sonidoAlEmpezar { Motor.sonido("Tink") }
            withAnimation(Tema.expo) { m.enPausa = false }
        } else {
            grabador.pausar()
            manosLibres = true
            m.manosLibres = true
            m.niveles = Array(repeating: 0, count: m.niveles.count)
            withAnimation(Tema.expo) { m.enPausa = true; m.sinSonido = false }
        }
    }

    private func cancelar(aviso: String?) {
        grabador.cancelar()
        if ajustes.datos.pausarMusica { Musica.reanudar() }
        monitor.capturaNumeros = false
        lecturaPantalla?.cancel()
        lecturaPantalla = nil
        estado = .libre
        monitor.capturaEsc = false
        // Cancelaste un ajuste: vuelve la respuesta que estaba.
        if let s = seguimiento { seguimiento = nil; mostrarRespuesta(s); return }
        if let aviso { pildora.mostrar(.aviso(aviso), durante: 1.2) } else { pildora.esconder() }
    }

    // Los sonidos se cargan una vez y se reusan (antes se creaba uno nuevo en cada dictado).
    private static var sonidos: [String: NSSound] = [:]
    static func sonido(_ nombre: String) {
        let s = sonidos[nombre] ?? {
            let n = NSSound(named: nombre)
            n?.volume = 0.6
            sonidos[nombre] = n
            return n
        }()
        s?.stop()
        s?.play()
    }

    private func terminar() {
        let (wav, segundos) = grabador.terminar()
        if ajustes.datos.pausarMusica { Musica.reanudar() }
        monitor.capturaEsc = false
        monitor.capturaNumeros = false
        if ajustes.datos.sonidoAlEmpezar { Motor.sonido("Pop") }
        guard segundos >= 0.35 else {
            estado = .libre
            if let s = seguimiento { seguimiento = nil; mostrarRespuesta(s); return }   // un toque sin hablar: vuelve la respuesta
            pildora.mostrar(.aviso(T("Muy corto: mantené apretado mientras hablás.", "Too short: hold the key while you talk.")), durante: 2)
            return
        }
        estado = .procesando
        pildora.mostrar(.procesando)
        // En un campo de contraseña no se guarda el audio ni queda para volver a procesar.
        let secreto = contexto?.secreto == true
        var pedido = Pedido(wav: wav, segundos: segundos, accion: accion, contexto: contexto, seleccion: seleccion, pantalla: lecturaPantalla,
                            estilo: estilo, audio: secreto ? nil : Historial.shared.guardarAudio(wav))
        pedido.anterior = seguimiento.map { ($0.pedido, $0.texto) }
        pedido.pid = pidAdelante
        pedido.imagenes = imagenesPregunta
        imagenesPregunta = []
        // Ajustar un prompt o una maqueta sigue siendo eso (con sus botones).
        if let c = seguimiento?.clase, c == .prompt || c == .maqueta { pedido.claseImagen = c }
        if accion == .dictar && !secreto { ultimoDictado = (pedido.audio, nil, segundos, estilo, nil) }
        lanzar(pedido, wavSiFalla: accion == .dictar && !secreto ? wav : nil)
    }

    // Un rato después del último pedido, le devuelve a macOS la memoria que quedó libre (leer la pantalla con Vision,
    // la voz y la IA dejan decenas de MB ya liberados que macOS se llevaba de a poco: 73 MB en reposo; 30/10/2026).
    // Sin pérdidas según `leaks`. Si llega otro pedido antes, se corre la cuenta.
    private var devolucion: DispatchWorkItem?
    private func programarDevolucionDeMemoria() {
        devolucion?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard self?.estado == .libre else { return }
            DispatchQueue.global(qos: .utility).async { malloc_zone_pressure_relief(nil, 0) }
        }
        devolucion = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: w)
    }

    // Procesa y pega; si falla, el audio queda a mano para volver a intentarlo con el atajo.
    private func lanzar(_ pedido: Pedido, wavSiFalla: Data?) {
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let r = try await Motor.procesar(pedido)
                await MainActor.run {
                    self.programarDevolucionDeMemoria()
                    if wavSiFalla != nil { self.ultimoDictado = (r.registro.audio, nil, pedido.segundos, pedido.estilo, r.registro.reprocesoDe ?? r.registro.id) }
                    if let tarea = r.tarea {
                        self.estado = .libre
                        self.seguimiento = nil
                        self.arrancarAgente(tarea, contexto: pedido.contexto)
                    } else if pedido.accion == .preguntar {
                        let previa = self.seguimiento
                        self.estado = .libre
                        self.seguimiento = nil
                        Motor.guardarRastro(r.registro, texto: r.texto, contexto: pedido.contexto)
                        // El pedido acumulado ("mail al equipo → más corto"), así el próximo ajuste sabe de dónde viene.
                        let pedidoTexto = [pedido.anterior?.pedido, r.registro.instruccion].compactMap { $0 }.joined(separator: " → ")
                        let titulo = r.registro.usoIA ? nil : r.registro.proveedorIA
                        var nueva = Respuesta(pedido: pedidoTexto, texto: r.texto, contexto: pedido.contexto, titulo: titulo,
                                              clase: r.clase, imagenes: pedido.imagenes,
                                              miniaturas: pedido.imagenes.compactMap { NSImage(contentsOf: $0) })
                        // Un prompt cambiado por voz («que sea de noche») sigue con el formato que habías elegido.
                        if nueva.clase == .prompt {
                            nueva.formato = previa?.formato ?? .original
                            nueva.texto = Respuestas.conFormato(nueva.texto, nueva.formato, original: nueva.proporcionOriginal)
                        }
                        self.mostrarRespuesta(nueva)
                    } else {
                        self.entregar(r.texto, contexto: pedido.contexto, registro: r.registro)
                    }
                }
            } catch {
                await MainActor.run {
                    self.estado = .libre
                    self.seguimiento = nil
                    self.programarDevolucionDeMemoria()
                    if self.ajustes.datos.sonidoAlEmpezar { Motor.sonido("Basso") }   // para notarlo aunque no mires
                    if let wav = wavSiFalla, self.ultimoDictado != nil {
                        self.ultimoDictado?.wav = wav
                        self.pildora.mostrar(.fallo(error.localizedDescription))      // queda hasta reintentar o cerrar
                    } else {
                        self.pildora.mostrar(.aviso(error.localizedDescription), durante: 3.5)
                    }
                }
            }
        }
    }

    // ⌃⌥R: vuelve a procesar el último dictado (con los ajustes de ahora) y lo pega donde está el cursor.
    // Si lo que pegó antes está seleccionado, lo reemplaza.
    func reprocesarUltimo() {
        guard estado == .libre else { return }
        guard let u = ultimoDictado, let wav = u.wav ?? u.audio.flatMap({ Historial.shared.audio(nombre: $0) }) else {
            pildora.mostrar(.aviso(T("No hay un dictado para volver a procesar.", "There's no dictation to process again.")), durante: 2)
            return
        }
        estado = .procesando
        pildora.mostrar(.procesando)
        let ctx = Cursor.capturar(conTexto: ajustes.datos.mirarVentana)
        let pedido = Pedido(wav: wav, segundos: u.segundos, accion: .dictar, contexto: ctx, seleccion: "",
                            estilo: u.estilo, audio: u.audio ?? Historial.shared.guardarAudio(wav), reprocesoDe: u.id)
        ultimoDictado?.audio = pedido.audio
        lanzar(pedido, wavSiFalla: wav)
    }

    // Acción rápida (Modos › Acciones rápidas): reescribe el texto seleccionado con su instrucción, sin hablar, y lo
    // pega en su lugar como Reescribir. Sin selección o sin IA, avisa y no hace nada.
    func ejecutarAccion(_ id: UUID) {
        guard estado == .libre, let accion = ajustes.datos.acciones.first(where: { $0.id == id }) else { return }
        guard ajustes.iaLista else {
            pildora.mostrar(.aviso(T("Las acciones rápidas usan la IA: configurala en Proveedores.", "Quick actions use AI: set it up in Providers.")), durante: 3)
            return
        }
        let ctx = Cursor.capturar(conTexto: ajustes.datos.mirarVentana)
        guard !ctx.secreto else { return }
        var seleccion = ctx.seleccion
        if seleccion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { seleccion = Cursor.seleccionPorCopia() }
        guard !seleccion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pildora.mostrar(.aviso(T("Seleccioná un texto y apretá el atajo de «\(accion.nombre)».", "Select some text and press the “\(accion.nombre)” shortcut.")), durante: 2.5)
            return
        }
        estado = .procesando
        pildora.mostrar(.procesando, modo: .reescritura)
        let pedido = Pedido(wav: Data(), segundos: 0, accion: .reescribir, contexto: ctx, seleccion: seleccion,
                            estilo: .comun, audio: nil, instruccion: accion.instruccion)
        lanzar(pedido, wavSiFalla: nil)
    }

    // Preguntar: la respuesta queda a la vista hasta que la pegás (↩ o el botón), la cerrás (Esc, ✕ o escribiendo en
    // otro lado) o la ajustás volviendo a mantener el atajo. Nada se pega sin que la veas.
    private func mostrarRespuesta(_ r: Respuesta) {
        respuesta = r
        let c = r.contexto
        pildora.modelo.puedePegar = c != nil && c?.campo != .noHay && c?.secreto != true
        if case .posteo(let marca) = r.clase { pildora.modelo.tituloRespuesta = T("Posteo · \(marca)", "Post · \(marca)") }
        else if r.titulo == nil && r.tarea == nil && r.clase == .imagen { pildora.modelo.tituloRespuesta = PedidoImagen.describir.titulo }
        else if r.titulo == nil && r.tarea == nil && r.clase == .prompt { pildora.modelo.tituloRespuesta = PedidoImagen.prompt.titulo }
        else if r.tarea == nil && r.clase == .video { pildora.modelo.tituloRespuesta = PedidoImagen.tituloVideo }
        else if r.titulo == nil && r.tarea == nil && r.clase == .maqueta { pildora.modelo.tituloRespuesta = PedidoImagen.maqueta.titulo }
        else { pildora.modelo.tituloRespuesta = r.tarea?.agente.nombre ?? r.titulo ?? T("Respuesta", "Answer") }
        pildora.modelo.hacelo = r.tarea.map { t in
            if case .posteo = t.clase { return T("Guardar borrador", "Save draft") }
            return T("Hacelo con \(t.agente.nombre)", "Have \(t.agente.nombre) do it")
        }
        pildora.modelo.atajoPreguntar = ajustes.datos.atajoPreguntar.descripcion
        pildora.modelo.clase = r.clase
        pildora.modelo.enLaMac = r.titulo != nil && r.tarea == nil && r.clase != .agente
        pildora.modelo.opciones = Respuestas.opciones(para: r.texto, clase: r.clase, idiomaPersona: T("es", "en"))
        pildora.modelo.puedeDeshacer = !r.versiones.isEmpty
        pildora.modelo.miniaturas = r.miniaturas
        pildora.modelo.formato = r.clase == .prompt ? r.formato : nil
        pildora.modelo.preguntaOpciones = nil
        pildora.modelo.avisoBueno = false
        pildora.modelo.trabajando = nil
        pildora.modelo.avisoTarjeta = nil
        pildora.mostrar(.respuesta(r.texto))
        monitor.capturaEsc = true
        monitor.capturaRespuesta = true
    }

    // La ventanita dejó de mostrar la respuesta (la llama la píldora al cambiar de estado o esconderse).
    private func soltarRespuesta() {
        respuesta = nil
        monitor.capturaRespuesta = false
        if estado != .grabando { monitor.capturaEsc = false }
    }

    // ↩ o el botón Pegar: va al campo donde preguntaste, si seguís en esa app; si no, queda copiada.
    func pegarRespuesta() {
        guard let r = respuesta, estado == .libre else { return }
        let texto = Prompts.sinControles(r.texto)
        pildora.esconder()
        let mismaApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == r.contexto?.bundle
        guard mismaApp, let c = r.contexto, c.campo != .noHay, !c.secreto else {
            Cursor.copiar(texto)
            pildora.mostrar(.listo(T("Copiado", "Copied")), durante: 1.2)
            return
        }
        // Igual que una reescritura: varias líneas en una terminal se dejan copiadas (cada línea podría ejecutarse).
        if Motor.copiarEnVezDePegar(texto, modo: .reescritura, bundle: c.bundle) {
            Cursor.copiar(texto)
            pildora.mostrar(.sinCampo(texto), durante: 30)
            return
        }
        Cursor.pegar(texto) { [weak self] res in
            if res == .noEntro { self?.pildora.mostrar(.sinCampo(texto), durante: 30) }
            else { self?.pildora.mostrar(.listo(T("Pegado", "Pasted")), durante: 0.9) }
        }
    }

    // MARK: Varita

    // Sacudiste el mouse: prende o apaga la Varita (no mientras grabás o procesás). Si tenías un texto seleccionado,
    // la cajita ofrece qué hacer con él (leerlo, traducirlo…). En los navegadores la selección a veces solo se lee
    // copiando: se intenta después de prender, para que la Varita aparezca al instante.
    func alternarVarita() {
        guard estado == .libre || varita.prendida else { return }
        if varita.prendida { varita.apagar("al sacudir de nuevo"); return }
        if respuesta != nil { pildora.esconder() }
        lector.parar()
        let ctx = Cursor.capturar(conTexto: false)
        guard !ctx.secreto else { return }
        let d = ajustes.datos
        varita.disponible = Varita.Disponible(ia: ajustes.iaLista, claude: d.varitaAgentes && Mandar.instalado(.claude),
                                              codex: d.varitaAgentes && Mandar.instalado(.codex),
                                              claudeResponde: d.varitaAgentes && Agentes.programa(.claude) != nil,
                                              veImagenes: ajustes.iaVeImagenes)
        varita.apagado = TimeInterval(d.varitaApagado.rawValue)
        varita.cambiarFlecha = d.varitaFlecha
        varita.buscarQR = d.varitaQR
        let editable = ctx.editable && ctx.campo == .seguro
        varita.prender(seleccion: ctx.seleccion, editable: editable)
        monitor.capturaEsc = true
        monitor.capturaMenu = true
        monitor.menuEscribiendo = false
        if ctx.seleccion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, Ajustes.navegadores.contains(ctx.bundle) {
            DispatchQueue.main.async { [weak self] in
                let copiada = Cursor.seleccionPorCopia()
                if !copiada.isEmpty { self?.varita.usarSeleccion(copiada, editable: editable && Cursor.seleccionEstaEnElCampo(copiada)) }
            }
        }
    }

    // Seleccionaste texto arrastrando con la Varita prendida: se lee (copiando, si la app no lo cuenta) y la cajita
    // ofrece qué hacer con eso. Si está en una caja donde se escribe, lo que lo cambia lo cambia ahí.
    private func leerSeleccionVarita() {
        let ctx = Cursor.capturar(conTexto: false)
        guard !ctx.secreto else { return }
        var texto = ctx.seleccion
        var editable = ctx.editable && ctx.campo == .seguro
        if texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texto = Cursor.seleccionPorCopia()
            editable = editable && Cursor.seleccionEstaEnElCampo(texto)   // copiada: solo si está en la caja activa
        }
        varita.usarSeleccion(texto, editable: editable, nueva: true)
    }

    // Lo que pidió la Varita. Lo que se resuelve en la Mac va directo; lo demás pasa por Preguntar con lo elegido
    // como "lo seleccionado". La respuesta aparece abajo a la derecha de donde estaba el mouse. La Varita se apaga.
    private func pedidoVarita(_ p: Varita.Pedido, _ cosas: [Senalador.Cosa], en punto: CGPoint) {
        let c = cosas.first
        let miniaturas = varita.miniaturas
        varita.apagar("al pedir algo")
        guard estado == .libre else { return }
        let ctx = Cursor.capturar(conTexto: false)
        let pid = c?.pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        switch p {
        case .copiarTexto, .copiarTabla:
            guard let t = c?.texto, !t.isEmpty else { return leerYMostrar(cosas, en: punto, copiar: true) }
            Cursor.copiar(t)
            pildora.mostrarCerca(de: punto)
            pildora.mostrar(.listo(T("Texto copiado", "Text copied")), durante: 1.2)
        case .sumarPalabra:
            pildora.mostrarCerca(de: punto)
            sumarAlDiccionario(c?.texto ?? "")
        case .copiarLink:
            guard let url = c?.url?.absoluteString ?? c?.texto, !url.isEmpty else { return }
            Cursor.copiar(url)
            pildora.mostrarCerca(de: punto)
            pildora.mostrar(.listo(T("Link copiado", "Link copied")), durante: 1.2)
        case .copiarImagen, .copiarTodas, .collage:
            Task { @MainActor in
                var imagenes = miniaturas
                if imagenes.count < cosas.count {
                    imagenes = []
                    for cosa in cosas { if let i = await Pantalla.recorte(cosa.marco) { imagenes.append(NSImage(cgImage: i, size: cosa.marco.size)) } }
                }
                self.pildora.mostrarCerca(de: punto)
                guard !imagenes.isEmpty else {
                    self.pildora.mostrar(.aviso(T("Para copiar imágenes falta el permiso de Grabación de pantalla (General › Permisos).",
                                                  "To copy images, allow Screen Recording (General › Permissions).")), durante: 3)
                    return
                }
                if p == .collage, let collage = Varita.collage(imagenes) {
                    Cursor.copiarImagenes([collage])
                    self.pildora.mostrar(.listo(T("Collage copiado", "Collage copied")), durante: 1.4)
                } else {
                    Cursor.copiarImagenes(imagenes)
                    self.pildora.mostrar(.listo(imagenes.count == 1 ? T("Imagen copiada", "Image copied")
                                                                    : T("\(imagenes.count) imágenes copiadas juntas", "\(imagenes.count) images copied together")), durante: 1.4)
                }
            }
        case .sacarTexto, .leerQR:
            leerYMostrar(cosas, en: punto, copiar: false, qr: p == .leerQR)
        case .describir:
            mirarImagen(.describir, cosas, en: punto)
        case .sacarPrompt:
            mirarImagen(.prompt, cosas, en: punto)
        case .recrearLogo:
            mirarImagen(.logo, cosas, en: punto)
        case .recrearBanner:
            mirarImagen(.banner, cosas, en: punto)
        case .maqueta:
            mirarImagen(.maqueta, cosas, en: punto)
        case .colores:
            sacarColores(cosas, en: punto)
        case .adonde:
            guard let url = c?.url?.absoluteString, !url.isEmpty else { return }
            pildora.mostrarCerca(de: punto)
            mostrarRespuesta(Respuesta(pedido: url, texto: url, contexto: ctx, titulo: T("Link", "Link") + " · " + T("en la Mac", "on your Mac"),
                                       clase: .codigos))
        case .captura:
            break   // lo resuelve la Varita: recortás un recuadro con ella y queda elegido (Varita.empezarRecorte)
        case .leerEnVozAlta:
            guard let t = c?.texto, !t.isEmpty else { return leerYMostrar(cosas, en: punto, copiar: false) }
            pildora.mostrarCerca(de: punto)
            leerEnVozAlta(t)
        case .traducir, .reformular, .corregir:
            // Donde se puede escribir, lo cambia ahí mismo; en un texto que solo se lee, lo muestra en la tarjeta.
            if let c, c.editable, ajustes.datos.varitaReemplaza { return reemplazar(p, en: c, punto: punto) }
            guard let escrito = PedidoEscrito(p) else { return }
            preguntarSinVoz(escrito.instruccion, contexto: ctx, seleccion: c?.texto ?? "", pid: pid, en: punto)
        case .resumir:
            preguntarSinVoz(PedidoEscrito.resumir.instruccion, contexto: ctx, seleccion: c?.texto ?? "", pid: pid, en: punto)
        case .dictarAca:
            // Dictar en la caja que señalaste (aunque otra estuviera activa): se le pasa el foco y empieza a escuchar.
            if let pid = c?.pid, let app = NSRunningApplication(processIdentifier: pid), !app.isActive { app.activate() }
            if let el = c?.elemento { Senalador.enfocar(el) }
            pildora.mostrarCerca(de: punto)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                // Solo si esa app quedó adelante (si no, lo dictado iría a otra).
                if let pid = c?.pid, NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                    self?.pildora.mostrar(.aviso(T("No pude pasar a esa ventana: hacé clic en la caja y dictá.", "Couldn't switch to that window: click the box and dictate.")), durante: 2.5)
                    return
                }
                self?.empezarSinTecla(.dictar)
            }
        case .mandar(let agente):
            mandarA(agente, cosas, en: punto)
        case .arreglar:
            mandarA(.claude, cosas, en: punto, prefijo: T("Tengo este error. Revisalo y arreglalo:", "I'm getting this error. Look into it and fix it:"))
        case .queHace:
            preguntarSinVoz(T("¿Qué es esto y para qué sirve? Respondé corto.", "What is this and what is it for? Answer briefly."),
                            contexto: ctx, seleccion: c?.texto ?? "", pid: pid, en: punto)
        case .preguntar, .preguntarTodas:
            // Por voz, sobre lo elegido. Con imágenes, las mira tu IA si puede (responde al instante en la tarjeta) o,
            // si no, Claude Code (como archivos); sin ninguno, va su texto o lo que se lee en ellas.
            let d = varita.disponible
            let conClaude = cosas.contains { $0.esVisual } && (d.veImagenes || d.claudeResponde)   // respeta «Claude y Codex»
            Task { @MainActor in
                var partes: [String] = []
                var imagenes: [NSImage] = []
                for cosa in cosas {
                    if conClaude && cosa.esVisual {
                        if let i = await Pantalla.recorte(cosa.marco) { imagenes.append(NSImage(cgImage: i, size: cosa.marco.size)) }
                    } else if !cosa.texto.isEmpty { partes.append(cosa.texto) }
                    else if let i = await Pantalla.recorte(cosa.marco) {
                        let t = Pantalla.texto(de: i, tope: 3000)
                        if !t.isEmpty { partes.append(t) }
                    }
                }
                // Lo que parece una clave (un .env señalado) no va a la IA ni a Claude.
                self.seleccionVarita = Secretos.tapar(partes.joined(separator: "\n\n"))
                self.imagenesVarita = Mandar.guardar(imagenes)
                self.pildora.mostrarCerca(de: punto)
                self.empezarSinTecla(.preguntar)
                self.seleccionVarita = nil
                self.imagenesVarita = []
            }
        }
    }

    // Traducir, reformular o corregir algo donde se puede escribir: lo cambia ahí mismo, como si lo hubieras escrito
    // vos (⌘Z lo deshace en esa app). Traducir usa primero el traductor de Apple (gratis); lo demás, tu IA.
    // Para no pisar tu texto (revisión del 31/10), antes de pegar se comprueba que todo siga como al pedirlo: la misma
    // app adelante y la misma selección, o la caja con el mismo texto (ni cambiado ni más largo de lo que se leyó). Si
    // algo cambió, o «Corregir» devolvió mucho menos texto, la respuesta va a la tarjeta. Lo que parece una clave no
    // se manda a la IA.
    private func reemplazar(_ p: Varita.Pedido, en c: Senalador.Cosa, punto: CGPoint) {
        guard estado == .libre, let escrito = PedidoEscrito(p) else { return }
        let texto = c.texto
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Cómo estaba todo al pedirlo, para comprobarlo antes de pegar.
        let antes = Cursor.capturar(conTexto: false)
        let pidAntes = NSWorkspace.shared.frontmostApplication?.processIdentifier
        estado = .procesando
        pildora.mostrarCerca(de: punto)
        pildora.mostrar(.procesando, modo: .reescritura)
        let a = ajustes
        Task.detached { [weak self] in
            guard let motor = self else { return }
            var nuevo: String?
            var fallo: String?
            if case .traducir(let destino) = escrito,
               let t = await EnLaMac.traducirConIdiomas(texto, a: destino, idiomaPersona: T("es", "en")) { nuevo = t.texto }
            if nuevo == nil {
                if !a.iaLista {
                    fallo = T("Para esto hace falta una IA configurada en Proveedores (o, para traducir, bajar el idioma en Ajustes del Sistema › Idioma y región).",
                              "This needs an AI set up in Providers (or, to translate, the language downloaded in System Settings › Language & Region).")
                } else if Secretos.tapar(texto) != texto {
                    fallo = T("Parece tener una clave o una contraseña: no lo mando a la IA.", "It looks like it has a key or password: I won't send it to the AI.")
                } else {
                    do {
                        let r = try await Proveedores.completar(
                            sistema: Prompts.sistemaReescritura,
                            usuario: Prompts.usuarioReescritura(seleccion: texto, instruccion: escrito.instruccion, contexto: nil, terminos: []),
                            ajustes: a)
                        nuevo = Prompts.limpiarSalida(r)
                    } catch { fallo = error.localizedDescription }
                }
            }
            let listo = nuevo, problema = fallo
            await MainActor.run {
                motor.estado = .libre
                guard let listo, !listo.isEmpty else {
                    motor.pildora.mostrar(.aviso(problema ?? T("La IA no devolvió texto.", "The AI returned no text.")), durante: 3.5)
                    return
                }
                // Corregir no cambia el largo: si volvió mucho más corto, la IA lo cortó (no se pega).
                if escrito == .corregir && listo.count < texto.count * 6 / 10 {
                    return motor.enTarjeta(listo, hecho: escrito.hecho)
                }
                motor.ponerEnSuLugar(listo, en: c, hecho: escrito.hecho, antes: antes, pidAntes: pidAntes)
            }
        }
    }

    private func ponerEnSuLugar(_ texto: String, en c: Senalador.Cosa, hecho: String, antes: ContextoCursor, pidAntes: pid_t?) {
        let pegar = { [weak self] (t: String) in
            Cursor.pegar(t) { res in
                if res == .noEntro { self?.pildora.mostrar(.sinCampo(t), durante: 30) }
                else { self?.pildora.mostrar(.listo(hecho + " · " + T("⌘Z deshace", "⌘Z undoes")), durante: 1.8) }
            }
        }
        if Varita.esSeleccion(c) {
            // Lo seleccionado sigue seleccionado en la app (la Varita no le saca el foco): se pega encima, si seguís en
            // la misma app y con la misma selección. Se le devuelven los espacios y saltos que tenía al principio y al
            // final (un párrafo elegido con triple clic trae su salto).
            let ahora = Cursor.capturar(conTexto: false)
            let mismaApp = NSWorkspace.shared.frontmostApplication?.processIdentifier == pidAntes
            let mismaSeleccion = antes.seleccion.isEmpty || ahora.seleccion == antes.seleccion
            guard mismaApp, mismaSeleccion, !ahora.secreto else { return enTarjeta(texto, hecho: hecho) }
            let original = antes.seleccion
            let inicio = String(original.prefix { $0.isWhitespace })
            let fin = original.count > inicio.count ? String(original.reversed().prefix { $0.isWhitespace }.reversed()) : ""
            return pegar(inicio + texto.trimmingCharacters(in: .whitespacesAndNewlines) + fin)
        }
        // La caja entera: si su texto cambió o era más largo de lo que se leyó (se leen hasta 8.000 letras), no se pisa.
        guard let el = c.elemento, let actual = Cursor.valor(de: el), actual == c.texto else { return enTarjeta(texto, hecho: hecho) }
        if let app = NSRunningApplication(processIdentifier: c.pid), !app.isActive { app.activate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard Senalador.seleccionarTodo(el) else { self?.enTarjeta(texto, hecho: hecho); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { pegar(texto) }
        }
    }

    // No se pudo cambiar en su lugar con seguridad: el resultado se muestra en la tarjeta, para copiarlo o pegarlo.
    private func enTarjeta(_ texto: String, hecho: String) {
        mostrarRespuesta(Respuesta(pedido: hecho, texto: texto, contexto: Cursor.capturar(conTexto: false), titulo: hecho, clase: .texto))
    }

    // "Mandar a Claude / Codex" (y "Arreglalo con Claude"): pega lo elegido en su ventana abierta y lo deja listo, sin
    // escuchar (que el micrófono se prendiera solo sorprendía; 31/10): para sumarle algo, dictás con tu atajo.
    // Las imágenes se mandan como se ven; los textos, como texto; un link, su dirección.
    private func mandarA(_ agente: Agente, _ cosas: [Senalador.Cosa], en punto: CGPoint, prefijo: String? = nil) {
        Task { @MainActor in
            var imagenes: [NSImage] = []
            var textos: [String] = []
            for cosa in cosas {
                if cosa.tipo == .link, let u = cosa.url { textos.append(u.absoluteString) }
                else if (cosa.tipo == .texto || cosa.tipo == .campo) && !cosa.texto.isEmpty { textos.append(cosa.texto) }
                else if let i = await Pantalla.recorte(cosa.marco) { imagenes.append(NSImage(cgImage: i, size: cosa.marco.size)) }
            }
            guard !imagenes.isEmpty || !textos.isEmpty else {
                self.pildora.mostrarCerca(de: punto)
                self.pildora.mostrar(.aviso(T("Para mandar imágenes falta el permiso de Grabación de pantalla (General › Permisos).",
                                              "To send images, allow Screen Recording (General › Permissions).")), durante: 3)
                return
            }
            Mandar.mandar(a: agente, imagenes: imagenes, textos: textos, pagina: cosas.first?.pagina, prefijo: prefijo) { v in
                guard v != nil else {
                    self.pildora.mostrarCerca(de: punto)
                    self.pildora.mostrar(.aviso(T("No encontré \(agente.nombre) abierto: te lo dejé copiado para que lo pegues.",
                                                  "Couldn't find \(agente.nombre) open: it's copied so you can paste it.")), durante: 3.5)
                    return
                }
                let atajo = self.ajustes.datos.atajoDictar.descripcion
                self.pildora.mostrar(.listo(T("Listo en \(agente.nombre) · \(atajo) para decirle algo", "Ready in \(agente.nombre) · \(atajo) to add something")),
                                     durante: 2.5)
            }
        }
    }

    // Describir o Sacar prompt (Varita): tu IA mira lo elegido y responde en la tarjeta, junto al mouse, en un par de
    // segundos, sin grabar nada. Las imágenes quedan guardadas (Mandar.guardar, se borran al día) para seguir
    // preguntando sobre ellas con el atajo. Sin una IA que vea imágenes, Describir dice lo que reconoce la Mac.
    private func mirarImagen(_ q: PedidoImagen, _ cosas: [Senalador.Cosa], en punto: CGPoint) {
        guard estado == .libre, let primera = cosas.first else { return }
        estado = .procesando
        pildora.mostrarCerca(de: punto)
        pildora.mostrar(.procesando, modo: .pregunta)
        let ctx = Cursor.capturar(conTexto: false)
        Task { @MainActor in
            var imagenes: [CGImage] = []
            for cosa in cosas { if let i = await Pantalla.recorte(cosa.marco) { imagenes.append(i) } }
            guard !imagenes.isEmpty else {
                self.estado = .libre
                self.pildora.mostrar(.aviso(T("Para mirar imágenes falta el permiso de Grabación de pantalla (General › Permisos).",
                                              "To look at images, allow Screen Recording (General › Permissions).")), durante: 3)
                return
            }
            guard self.ajustes.iaVeImagenes else { return self.describirEnLaMac(imagenes, contexto: ctx) }
            let archivos = Mandar.guardar(imagenes.map { NSImage(cgImage: $0, size: .zero) })
            guard !archivos.isEmpty else {
                self.estado = .libre
                self.pildora.mostrar(.aviso(T("No pude guardar la imagen para mandarla. Probá de nuevo.", "Couldn't save the image to send it. Try again.")), durante: 3)
                return
            }
            // La maqueta lleva también los textos de la sección, leídos de la página, para copiarlos tal cual.
            var textos = ""
            if q == .maqueta, let el = primera.elemento {
                let caja = ElementoAX(el)
                textos = await Task.detached(priority: .userInitiated) { Senalador.textos(de: caja.el) }.value
            }
            var pedido = Pedido(wav: Data(), segundos: 0, accion: .preguntar, contexto: ctx, seleccion: Secretos.tapar(textos),
                                estilo: .comun, audio: nil, instruccion: q.instruccion(tam: primera.marco.size))
            pedido.imagenes = archivos
            pedido.claseImagen = q.clase
            self.lanzar(pedido, wavSiFalla: nil)
        }
    }

    // Sacar colores (Varita): los principales de lo elegido, en la Mac y gratis, en una tarjeta con sus muestras.
    private func sacarColores(_ cosas: [Senalador.Cosa], en punto: CGPoint) {
        guard estado == .libre else { return }
        let ctx = Cursor.capturar(conTexto: false)
        Task { @MainActor in
            var imagenes: [CGImage] = []
            for cosa in cosas { if let i = await Pantalla.recorte(cosa.marco, maxPixeles: 600) { imagenes.append(i) } }
            self.pildora.mostrarCerca(de: punto)
            guard let primera = imagenes.first else {
                self.pildora.mostrar(.aviso(T("Para sacar colores falta el permiso de Grabación de pantalla (General › Permisos).",
                                              "To get colors, allow Screen Recording (General › Permissions).")), durante: 3)
                return
            }
            let lista = await Task.detached(priority: .userInitiated) { Pantalla.colores(de: primera) }.value
            let texto = lista.map { "\($0.hex) · \(max(1, Int(($0.parte * 100).rounded()))) %" }.joined(separator: "\n")
            guard !texto.isEmpty else {
                self.pildora.mostrar(.aviso(T("No encontré colores para sacar.", "Couldn't find any colors.")), durante: 2.5)
                return
            }
            let titulo = T("Colores · en la Mac", "Colors · on your Mac")
            self.mostrarRespuesta(Respuesta(pedido: titulo, texto: texto, contexto: ctx, titulo: titulo, clase: .colores,
                                            miniaturas: imagenes.map { NSImage(cgImage: $0, size: .zero) }))
        }
    }

    // Describir sin una IA que vea imágenes: lo que la Mac reconoce (en tu idioma, si el traductor de Apple lo tiene
    // bajado) y el texto que se lee. Gratis y sin mandar nada.
    private func describirEnLaMac(_ imagenes: [CGImage], contexto: ContextoCursor?) {
        let persona = T("es", "en")
        Task.detached { [weak self] in
            guard let motor = self else { return }
            var vistas: [String] = []
            for e in imagenes.flatMap({ Pantalla.etiquetas(de: $0) }) where !vistas.contains(e) { vistas.append(e) }
            let leido = imagenes.map { Pantalla.texto(de: $0, tope: 3000) }.filter { !$0.isEmpty }.joined(separator: "\n")
            var lista = vistas.joined(separator: ", ")
            if persona != "en", !lista.isEmpty, let t = await EnLaMac.traducirConIdiomas(lista, a: persona, idiomaPersona: persona) {
                lista = t.texto
            }
            var partes: [String] = []
            if !lista.isEmpty { partes.append(T("Parece: ", "Looks like: ") + lista + ".") }
            if !leido.isEmpty { partes.append(T("Texto en la imagen:", "Text in the image:") + "\n" + leido) }
            let texto = partes.joined(separator: "\n\n")
            await MainActor.run {
                motor.estado = .libre
                guard !texto.isEmpty else {
                    motor.pildora.mostrar(.aviso(T("No reconocí nada. Para describirla de verdad, elegí en Proveedores una IA que vea imágenes (OpenAI, Claude, Grok u OpenRouter).",
                                                   "I couldn't recognize anything. To really describe it, choose an AI that sees images in Providers (OpenAI, Claude, Grok or OpenRouter).")), durante: 4)
                    return
                }
                let titulo = T("Lo que veo · en la Mac", "What I see · on your Mac")
                motor.mostrarRespuesta(Respuesta(pedido: titulo, texto: texto, contexto: contexto, titulo: titulo, clase: .imagen,
                                                 miniaturas: imagenes.map { NSImage(cgImage: $0, size: .zero) }))
            }
        }
    }

    // Sacar el texto o leer el QR de lo elegido (foto del recorte, en la Mac). Muestra la tarjeta o, con `copiar`,
    // lo deja copiado.
    private func leerYMostrar(_ cosas: [Senalador.Cosa], en punto: CGPoint, copiar: Bool, qr: Bool = false) {
        Task { @MainActor in
            var textos: [String] = []
            for cosa in cosas {
                guard let i = await Pantalla.recorte(cosa.marco) else { continue }
                if qr { textos += EnLaMac.codigos(en: i) } else { textos.append(Pantalla.texto(de: i, tope: 20_000)) }
            }
            let texto = textos.filter { !$0.isEmpty }.joined(separator: "\n")
            self.pildora.mostrarCerca(de: punto)
            guard !texto.isEmpty else {
                let motivo = !Pantalla.permitido
                    ? T("Para leer la pantalla falta el permiso de Grabación de pantalla (General › Permisos).", "To read the screen, allow Screen Recording (General › Permissions).")
                    : qr ? T("No encontré ningún código QR ni de barras.", "Couldn't find any QR code or barcode.")
                         : T("No encontré texto para leer.", "Couldn't find any text to read.")
                self.pildora.mostrar(.aviso(motivo), durante: 3)
                return
            }
            if copiar {
                Cursor.copiar(texto)
                self.pildora.mostrar(.listo(T("Texto copiado", "Text copied")), durante: 1.2)
                return
            }
            let quien = (qr ? T("Código leído", "Code read") : T("Texto leído", "Text read")) + " · " + T("en la Mac", "on your Mac")
            self.mostrarRespuesta(Respuesta(pedido: quien, texto: texto, contexto: Cursor.capturar(conTexto: false), titulo: quien,
                                            clase: qr ? .codigos : .textoLeido))
        }
    }

    /// El botón «Escuchar» de la página Varita: lee una frase corta con la voz elegida.
    func probarVoz() {
        leerEnVozAlta(T("Hola, así suena la Varita cuando te lee en voz alta un texto que seleccionaste.",
                        "Hi, this is how Wonder sounds when it reads selected text aloud."))
    }

    /// El botón «Devolver la flecha de macOS» de la página Varita (si alguna vez quedó una flecha rara).
    func devolverFlecha() {
        if varita.prendida { varita.apagar("desde el panel") }
        FlechaVarita.devolver()
    }

    // Leer en voz alta (Lector: la voz de OpenAI o la de la Mac). Esc o la ✕ lo paran.
    private let lector = Lector()
    private func leerEnVozAlta(_ texto: String) {
        lector.alTerminar = { [weak self] in
            guard let self else { return }
            self.pildora.esconder()
            if self.estado != .grabando && self.respuesta == nil && !self.varita.prendida { self.monitor.capturaEsc = false }
        }
        // La voz de OpenAI si está prendida y tenés su clave (la misma de Proveedores); si no, la de la Mac.
        let clave = ajustes.datos.leerConOpenAI ? ajustes.clave(ProveedorIA.openai.cuentaLlavero) : ""
        lector.leer(clave.isEmpty ? texto : Secretos.tapar(texto), claveOpenAI: clave)   // a OpenAI no viaja una clave
        monitor.capturaEsc = true
        pildora.mostrar(.listo(T("Leyendo en voz alta · Esc para parar", "Reading aloud · Esc to stop")))
    }

    // Lo mismo que Preguntar, con el pedido ya escrito (traducir se resuelve en la Mac si se puede).
    private func preguntarSinVoz(_ instruccion: String, contexto: ContextoCursor, seleccion: String, pid: pid_t?, en punto: CGPoint) {
        guard estado == .libre else { return }
        estado = .procesando
        pildora.mostrarCerca(de: punto)
        pildora.mostrar(.procesando, modo: .pregunta)
        var pedido = Pedido(wav: Data(), segundos: 0, accion: .preguntar, contexto: contexto, seleccion: seleccion,
                            estilo: .comun, audio: nil, instruccion: instruccion)
        pedido.pid = pid
        lanzar(pedido, wavSiFalla: nil)
    }

    // Empezar a grabar desde la Varita: no hay tecla apretada, así que queda como un toque (termina con el atajo, con ✓
    // en la píldora o con Esc).
    private func empezarSinTecla(_ a: MonitorAtajos.Accion) {
        guard estado == .libre else { return }
        empezar(a)
        if estado == .grabando {
            manosLibres = true
            pildora.modelo.manosLibres = true
        }
    }

    // Mientras preguntás, la píldora dice sobre qué va a trabajar: así sabés antes de hablar si tomó la selección.
    static func sobreQue(seleccion: String, ajustando: Bool, app: String) -> String {
        if ajustando { return T("Ajustando la respuesta", "Adjusting the answer") }
        let n = Respuestas.palabras(seleccion)
        if n > 0 { return n == 1 ? T("Sobre 1 palabra", "About 1 word") : T("Sobre \(n) palabras", "About \(n) words") }
        return app.isEmpty ? T("Sin selección", "No selection") : T("Sin selección · \(app)", "No selection · \(app)")
    }

    // Un botón de la tarjeta ("Pasar a inglés", "Más corto"…): cambia la respuesta ahí mismo y guarda la anterior para
    // Deshacer. Pasar de idioma usa primero el traductor de Apple (gratis); lo demás, tu IA, con un pedido corto. Si
    // falla, la respuesta queda como estaba y la tarjeta lo dice.
    func aplicarOpcion(_ o: Respuestas.Opcion) {
        guard let r = respuesta, estado == .libre, pildora.modelo.trabajando == nil else { return }
        let m = pildora.modelo
        switch o {
        case .cambiarAlgo:
            // Como mantener el atajo con la tarjeta abierta: escucha lo que querés cambiar y lo ajusta mirando la imagen.
            if ajustes.iaLista { return empezarSinTecla(.preguntar) }
        case .animar:
            // Antes de armar el video pregunta el formato, con los mismos botones (01/11/2026).
            withAnimation(Tema.expo) {
                m.opciones = [.animarEn("9:16"), .animarEn("16:9"), .volver]
                m.preguntaOpciones = T("¿En qué formato va el video?", "Which format for the video?")
                m.avisoTarjeta = nil
            }
            return
        case .volver:
            withAnimation(Tema.expo) {
                m.opciones = Respuestas.opciones(para: r.texto, clase: r.clase, idiomaPersona: T("es", "en"))
                m.preguntaOpciones = nil
            }
            return
        case .mandarClaude:
            // La maqueta (resumen e imagen) a la ventana de Claude abierta, lista para que le digas «armala».
            Mandar.mandar(a: .claude, imagenes: r.miniaturas, textos: [r.texto], pagina: nil,
                          prefijo: T("Armá esta sección como maqueta, con este resumen de diseño y la imagen de referencia:",
                                     "Build this section as a mockup, using this design brief and the reference image:")) { [weak self] v in
                guard let self else { return }
                if v == nil {
                    self.pildora.modelo.avisoBueno = false
                    self.pildora.modelo.avisoTarjeta = T("No encontré Claude abierto: te lo dejé copiado para que lo pegues.",
                                                         "Couldn't find Claude open: it's copied so you can paste it.")
                } else {
                    self.pildora.esconder()
                }
            }
            return
        case .copiarImagen:
            guard !r.miniaturas.isEmpty else { return }
            Cursor.copiarImagenes(r.miniaturas)
            withAnimation(Tema.expo) {
                m.avisoBueno = true
                m.avisoTarjeta = T("Imagen copiada: pegala como referencia en la app de video.", "Image copied: paste it as the reference in your video app.")
            }
            return
        default: break
        }
        if !o.sinIA && !ajustes.iaLista {
            pildora.modelo.avisoTarjeta = T("Este botón usa la IA: configurala en Proveedores.", "This button uses AI: set it up in Providers.")
            return
        }
        withAnimation(Tema.expo) { pildora.modelo.trabajando = o; pildora.modelo.avisoTarjeta = nil }
        let a = ajustes
        Task.detached { [weak self] in
            guard let motor = self else { return }
            var nuevo: (texto: String, clase: Respuestas.Clase, enLaMac: Bool)?
            var fallo: String?
            if o == .promptImagen {
                // La maqueta pasada a un prompt de imagen: tu IA vuelve a mirar la sección.
                let fotos = r.imagenes.compactMap { Pantalla.paraIA(archivo: $0) }
                if fotos.isEmpty || !a.iaVeImagenes {
                    fallo = T("Para esto hace falta la imagen y una IA que vea imágenes.", "This needs the image and an AI that sees images.")
                } else {
                    do {
                        let tam = r.miniaturas.first?.size ?? CGSize(width: 16, height: 9)
                        let salida = try await Proveedores.completar(
                            sistema: Prompts.sistemaRespuesta,
                            usuario: PedidoImagen.instruccionPromptMaqueta(resumen: r.texto, tam: tam), imagenes: fotos, ajustes: a)
                        let limpio = Prompts.limpiarSalida(salida)
                        if limpio.isEmpty { fallo = T("La IA no devolvió texto.", "The AI returned no text.") }
                        else { nuevo = (limpio, .prompt, false) }
                    } catch { fallo = error.localizedDescription }
                }
            } else if case .animarEn(let formato) = o {
                // Animarla: tu IA vuelve a mirar la imagen y arma el prompt del video a partir del de la imagen.
                let fotos = r.imagenes.compactMap { Pantalla.paraIA(archivo: $0) }
                if fotos.isEmpty || !a.iaVeImagenes {
                    fallo = T("Para animarla hace falta la imagen y una IA que vea imágenes.", "Animating needs the image and an AI that sees images.")
                } else {
                    do {
                        let salida = try await Proveedores.completar(
                            sistema: Prompts.sistemaRespuesta,
                            usuario: PedidoImagen.instruccionVideo(formato: formato, promptImagen: r.texto),
                            imagenes: fotos, ajustes: a)
                        let limpio = Prompts.limpiarSalida(salida)
                        if limpio.isEmpty { fallo = T("La IA no devolvió texto.", "The AI returned no text.") }
                        else { nuevo = (limpio, .video, false) }
                    } catch { fallo = error.localizedDescription }
                }
            } else if case .traducir(let destino) = o,
               let t = await EnLaMac.traducirConIdiomas(r.texto, a: destino, idiomaPersona: T("es", "en")) {
                nuevo = (t.texto, .traduccion(de: t.de, a: t.a, original: r.texto), true)
            } else if !a.iaLista {
                fallo = T("Para traducir a ese idioma falta bajarlo en Ajustes del Sistema › Idioma y región, o configurar una IA.",
                          "To translate to that language, download it in System Settings › Language & Region, or set up an AI.")
            } else {
                do {
                    let salida = try await Proveedores.completar(
                        sistema: Prompts.sistemaReescritura,
                        usuario: Prompts.usuarioReescritura(seleccion: r.texto, instruccion: o.instruccion, contexto: nil, terminos: []),
                        ajustes: a)
                    let limpio = Prompts.limpiarSalida(salida)
                    if limpio.isEmpty { fallo = T("La IA no devolvió texto.", "The AI returned no text.") }
                    else if case .traducir(let destino) = o {
                        nuevo = (limpio, .traduccion(de: Respuestas.idioma(de: r.texto) ?? "", a: destino, original: r.texto), false)
                    } else {
                        // Reescrita, deja de ser "texto leído" o "traducción": ahora es una respuesta común (la de un
                        // agente, una imagen o un prompt sigue siendo eso).
                        nuevo = (limpio, [.agente, .imagen, .prompt, .video, .maqueta].contains(r.clase) ? r.clase : .texto, false)
                        // Un prompt más detallado o más corto conserva el final del formato elegido.
                        if r.clase == .prompt {
                            nuevo?.texto = Respuestas.conFormato(limpio, r.formato, original: r.proporcionOriginal)
                        }
                    }
                } catch {
                    fallo = error.localizedDescription
                }
            }
            // Un prompt traducido sigue con sus botones (Más detallado, Animarla…), no pasa a ser una traducción.
            if case .traduccion = nuevo?.clase, [.prompt, .video, .maqueta].contains(r.clase) { nuevo?.clase = r.clase }
            let listo = nuevo, problema = fallo
            await MainActor.run {
                guard var actual = motor.respuesta, actual.texto == r.texto else { return }   // la cerraste mientras tanto
                guard let nuevo = listo else {
                    withAnimation(Tema.expo) { motor.pildora.modelo.trabajando = nil; motor.pildora.modelo.avisoTarjeta = problema }
                    return
                }
                actual.versiones.append((actual.texto, actual.clase))
                actual.texto = nuevo.texto
                actual.clase = nuevo.clase
                actual.titulo = nuevo.enLaMac ? T("Traductor de Apple", "Apple Translate") + " · " + T("en la Mac", "on your Mac") : nil
                motor.mostrarRespuesta(actual)
            }
        }
    }

    // Un formato de la tarjeta del prompt (Post 4:5, Historia 9:16…): cambia el final del prompt ahí mismo, sin IA.
    func elegirFormato(_ f: Respuestas.Formato) {
        guard var r = respuesta, r.clase == .prompt, pildora.modelo.trabajando == nil, f != r.formato else { return }
        r.texto = Respuestas.conFormato(r.texto, f, original: r.proporcionOriginal)
        r.formato = f
        mostrarRespuesta(r)
    }

    // ↶ en la tarjeta: vuelve a la versión anterior a un botón.
    func deshacerOpcion() {
        guard var r = respuesta, let anterior = r.versiones.popLast(), pildora.modelo.trabajando == nil else { return }
        r.texto = anterior.texto
        r.clase = anterior.clase
        r.titulo = nil
        mostrarRespuesta(r)
    }

    // Claude o Codex trabajan aparte (de segundos a minutos) y podés seguir dictando. Al terminar suena y la respuesta
    // aparece en la ventanita cuando no estés en medio de otra cosa. `hacer`: lo pidió el botón Hacelo (edita archivos).
    private func arrancarAgente(_ t: Agentes.Tarea, contexto: ContextoCursor?, hacer: Bool = false, plan: String = "") {
        if let otro = agenteTrabajando {
            pildora.mostrar(.aviso(T("\(otro.nombre) todavía está con el pedido anterior.", "\(otro.nombre) is still on the previous request.")), durante: 2.5)
            return
        }
        agenteTrabajando = t.agente
        let nombre = t.agente.nombre
        pildora.mostrar(.listo(hacer ? T("\(nombre) está trabajando · te aviso", "\(nombre) is working · I'll let you know")
                                     : T("Se lo pasé a \(nombre) · te aviso", "Sent to \(nombre) · I'll let you know")), durante: 2)
        let t0 = Date()
        Task.detached { [weak self] in
            guard let motor = self else { return }
            do {
                let r = try await Agentes.correr(t, hacer: hacer, plan: plan)
                await MainActor.run {
                    motor.agenteTrabajando = nil
                    let registro = Registro(modo: .respuesta, app: contexto?.app ?? "", transcripcion: "", final: r.texto,
                                            instruccion: "\(nombre): \(t.pedido)", segundosAudio: 0, msVoz: 0,
                                            msIA: Int(Date().timeIntervalSince(t0) * 1000), usoIA: false,
                                            proveedorIA: t.agente == .claude ? "Claude Code" : "Codex")
                    Motor.guardarRastro(registro, texto: r.texto, contexto: contexto)
                    var tarea = t
                    tarea.sesion = r.sesion
                    // Después de Hacelo no se ofrece de nuevo: ya está hecho. Tampoco cuando miró imágenes fuera de un
                    // proyecto (no hay nada que cambiar).
                    let puedeHacer = !hacer && t.carpeta != Mandar.carpeta
                    motor.mostrarCuandoPuedas(Respuesta(pedido: "\(nombre): \(t.pedido)", texto: r.texto, contexto: contexto,
                                                       tarea: puedeHacer ? tarea : nil, clase: hacer ? .agente : t.clase))
                }
            } catch {
                await MainActor.run {
                    motor.agenteTrabajando = nil
                    Motor.sonido("Basso")
                    motor.pildora.mostrar(.aviso(error.localizedDescription), durante: 5)
                }
            }
        }
    }

    // No pisa un dictado en curso ni otra respuesta abierta: espera a que estés libre.
    private func mostrarCuandoPuedas(_ r: Respuesta) {
        guard estado == .libre, respuesta == nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.mostrarCuandoPuedas(r) }
            return
        }
        Motor.sonido("Glass")
        mostrarRespuesta(r)
    }

    // El botón Hacelo: el mismo pedido, ahora con permiso para editar archivos del proyecto (nunca con ↩: hay que tocarlo).
    func hacerTarea() {
        guard let r = respuesta, let t = r.tarea else { return }
        pildora.esconder()
        arrancarAgente(t, contexto: r.contexto, hacer: true, plan: r.texto)
    }

    // ⌃⌥D: suma al diccionario la palabra (o el nombre corto) que tenés seleccionado.
    func sumarSeleccion() {
        guard estado == .libre else { return }
        let ctx = Cursor.capturar(conTexto: true)
        var texto = ctx.seleccion
        if texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texto = Cursor.seleccionPorCopia() }
        sumarAlDiccionario(texto)
    }

    // Lo comparten ⌃⌥D y «Sumar al diccionario» de la Varita: suma la selección y lo cuenta en la píldora.
    private func sumarAlDiccionario(_ seleccion: String) {
        let texto = Diccionario.deSeleccion(seleccion)
        guard !texto.isEmpty else {
            pildora.mostrar(.aviso(T("Seleccioná una palabra y apretá el atajo.", "Select a word and press the shortcut.")), durante: 2)
            return
        }
        guard Diccionario.esCorto(texto) else {
            pildora.mostrar(.aviso(T("Es muy largo: seleccioná una palabra o un nombre corto.", "Too long: select a word or a short name.")), durante: 2.5)
            return
        }
        let dicc = Diccionario.shared
        if dicc.terminos.contains(where: { $0.texto.lowercased() == texto.lowercased() }) {
            pildora.mostrar(.listo(T("Ya estaba: \(texto)", "Already there: \(texto)")), durante: 1.5)
        } else if dicc.agregar(texto) {
            pildora.mostrar(.listo(T("Al diccionario: \(texto)", "Added: \(texto)")), durante: 1.5)
        } else {
            pildora.mostrar(.aviso(T("El diccionario está lleno.", "The dictionary is full.")), durante: 2)
        }
    }

    struct Pedido {
        var wav: Data
        var segundos: Double
        var accion: MonitorAtajos.Accion
        var contexto: ContextoCursor?
        var seleccion: String
        var pantalla: Task<String, Never>? = nil
        var estilo: Estilo
        var trabajo: Bool { estilo == .trabajo }
        var audio: String?
        var reprocesoDe: UUID? = nil
        var instruccion: String? = nil    // acción rápida: reescribe la selección con esto, sin audio
        var anterior: (pedido: String, texto: String)? = nil   // Preguntar: la respuesta que se está ajustando
        var pid: pid_t? = nil              // Preguntar: la app de adelante, para leer su ventana (EnLaMac, "¿qué dice acá?")
        var imagenes: [URL] = []           // Preguntar desde la Varita sobre imágenes: las mira tu IA (o Claude Code)
        var claseImagen = Respuestas.Clase.imagen   // la tarjeta de lo que respondió tu IA mirando imágenes (o .prompt)
    }

    struct ErrorPaso: LocalizedError {
        let mensaje: String
        var errorDescription: String? { mensaje }
    }

    // El trabajo pesado, sin tocar la pantalla: sirve para dictar y para reprocesar desde el historial.
    // `clase`: qué forma tiene la tarjeta de la respuesta (Preguntar); en un dictado no se usa.
    static func procesar(_ p: Pedido) async throws
        -> (texto: String, registro: Registro, tarea: Agentes.Tarea?, clase: Respuestas.Clase) {
        let a = Ajustes.shared
        let datos = a.datos
        let dicc = Diccionario.shared
        let t0 = Date()
        // Una acción rápida trae la instrucción escrita: no hay audio que transcribir.
        let oido = if let fija = p.instruccion { fija }
                   else { dicc.aplicarAlias(try await Proveedores.transcribir(wav: p.wav, ajustes: a, pista: dicc.pistaVoz)) }
        let msVoz = p.instruccion == nil ? Int(Date().timeIntervalSince(t0) * 1000) : 0
        guard oido.rangeOfCharacter(from: .alphanumerics) != nil else { throw ErrorPaso(mensaje: T("No escuché nada. Probá hablar más cerca.", "Didn't hear anything. Try speaking closer to the mic.")) }

        // "…en formato correo", "traducilo al inglés": la frase elige el modo y se borra.
        var crudo = oido
        var estilo = p.estilo
        var idioma = a.idiomaDestino
        if p.accion == .dictar, let dicho = Prompts.estiloDicho(crudo) {
            crudo = dicho.texto
            estilo = dicho.estilo
            if let i = dicho.idioma { idioma = i }
        }
        var final = crudo
        var usoIA = false
        var barrera: String?
        var proyectoNombre: String?
        var herramienta: String?    // Preguntar resuelto en la Mac, sin IA (EnLaMac)
        var clase = Respuestas.Clase.texto
        let t1 = Date()
        let iaLista = a.iaLista
        let terminos = dicc.paraPrompt(transcripcion: crudo)
        // Lo leído de la pantalla ya está listo (se leyó mientras hablabas); si tardara, se sigue sin esperar de más.
        let pantalla = await Motor.conTope(segundos: 0.8) { await p.pantalla?.value ?? "" } ?? ""

        // Lo que va a la IA de la ventana: nada si "Mirar la ventana" está apagado, en cualquier modo.
        let ventanaIA = datos.mirarVentana ? p.contexto : nil
        // Tus preferencias, con las de esta app o sitio. Se elige por el nombre de la app y el título, que siempre se
        // miran (como el modo automático): lo único que va a la IA es tu instrucción.
        let instruccion = a.instruccionPara(p.contexto)
        // Dictado en un campo de contraseña: no pasa por la IA (iría a la nube) y se pega lo que se escuchó.
        let secreto = p.contexto?.secreto == true
        if p.accion == .preguntar, !p.imagenes.isEmpty, a.iaVeImagenes {
            // Imágenes elegidas con la Varita (Describir, Sacar prompt o una pregunta por voz): las mira tu IA y responde en
            // la tarjeta en un par de segundos (01/11/2026: antes iban a Claude Code, que tardaba). Va primero: el
            // pedido de Describir dice «qué dice», que EnLaMac tomaría como leer el texto de la ventana.
            guard !secreto else { throw ErrorPaso(mensaje: T("En un campo de contraseña no se pregunta.", "Ask isn't available in a password field.")) }
            let fotos = p.imagenes.compactMap { Pantalla.paraIA(archivo: $0) }
            guard !fotos.isEmpty else { throw ErrorPaso(mensaje: T("No pude leer la imagen elegida. Probá de nuevo.", "Couldn't read the chosen image. Try again.")) }
            let usuario = Prompts.usuarioRespuesta(pedido: crudo, seleccion: p.seleccion, anterior: p.anterior, contexto: ventanaIA,
                                                   terminos: terminos, extra: instruccion)
                + "\n(El pedido es sobre la imagen que te muestro: la eligió la persona en su pantalla.)"
            let r = try await Proveedores.completar(sistema: Prompts.sistemaRespuesta, usuario: usuario, imagenes: fotos, ajustes: a)
            final = Prompts.limpiarSalida(r)
            usoIA = true
            clase = p.claseImagen
            if final.isEmpty { throw ErrorPaso(mensaje: T("La IA no devolvió texto.", "The AI returned no text.")) }
        } else if p.accion == .preguntar, p.anterior == nil, let agentes = Agente.consultaUso(crudo) {
            // "¿Cuánto me queda de Claude?": se lee de la Mac, sin IA. La tarjeta lo dibuja con barras.
            let usos = agentes.compactMap { Agentes.datos($0) }
            final = agentes.map { Agentes.uso($0) }.joined(separator: "\n")
            herramienta = T("Uso · en la Mac", "Usage · on your Mac")
            if !usos.isEmpty { clase = .uso(usos) }
        } else if p.accion == .preguntar, p.anterior == nil, !datos.carpetasMarketing.isEmpty, Posteos.esPedido(crudo) {
            // "Armame un post para LinkedIn sobre Dixity": Claude lo arma en tu carpeta de marketing, solo leyendo.
            guard !secreto else { throw ErrorPaso(mensaje: T("En un campo de contraseña no se pregunta.", "Ask isn't available in a password field.")) }
            let marcas = Posteos.marcas(en: datos.carpetasMarketing)
            guard let marca = Posteos.elegir(crudo, marcas: marcas) else {
                let nombres = marcas.map(\.nombre).joined(separator: ", ")
                throw ErrorPaso(mensaje: T("¿Para qué marca? Decí el nombre: \(nombres).", "Which brand? Say its name: \(nombres)."))
            }
            guard Agentes.programa(.claude) != nil else {
                throw ErrorPaso(mensaje: T("Para armar posteos hace falta Claude Code en esta Mac.", "Drafting posts needs Claude Code on this Mac."))
            }
            let producto = Posteos.producto(crudo, carpetas: datos.carpetasProyectos)
            let tarea = Agentes.Tarea(agente: .claude, pedido: crudo, seleccion: p.seleccion, carpeta: marca.raiz,
                                      extras: producto.map { [$0] } ?? [], guiaPropia: Posteos.guia(marca, producto: producto),
                                      clase: .posteo(marca: marca.nombre))
            let vacio = Registro(modo: .respuesta, app: p.contexto?.app ?? "", transcripcion: "", final: "", segundosAudio: p.segundos,
                                 msVoz: msVoz, msIA: 0, usoIA: false)
            return ("", vacio, tarea, tarea.clase)
        } else if p.accion == .preguntar, p.anterior == nil, !p.imagenes.isEmpty {
            // Preguntar por imágenes elegidas con la Varita: las mira Claude (o Codex, si lo nombrás o no hay Claude), en
            // solo lectura, y responde en la tarjeta. Si la ventana es de un proyecto, trabaja ahí; si no, en la carpeta
            // de las imágenes.
            guard !secreto else { throw ErrorPaso(mensaje: T("En un campo de contraseña no se pregunta.", "Ask isn't available in a password field.")) }
            let nombrado = Agente.detectar(crudo)
            guard let agente = nombrado.map({ [$0.agente] })?.first(where: { Agentes.programa($0) != nil })
                    ?? [Agente.claude, .codex].first(where: { Agentes.programa($0) != nil }) else {
                throw ErrorPaso(mensaje: T("Para preguntar por una imagen hace falta Claude Code o Codex en esta Mac.",
                                           "Asking about an image needs Claude Code or Codex on this Mac."))
            }
            let carpeta = Proyectos.detectar(p.contexto, carpetas: datos.carpetasProyectos) ?? Mandar.carpeta
            let tarea = Agentes.Tarea(agente: agente, pedido: nombrado?.resto ?? crudo, seleccion: p.seleccion, carpeta: carpeta,
                                      extras: carpeta == Mandar.carpeta ? [] : [Mandar.carpeta], imagenes: p.imagenes)
            let vacio = Registro(modo: .respuesta, app: p.contexto?.app ?? "", transcripcion: "", final: "", segundosAudio: p.segundos,
                                 msVoz: msVoz, msIA: 0, usoIA: false)
            return ("", vacio, tarea, .agente)
        } else if p.accion == .preguntar, p.anterior == nil, let (agente, resto) = Agente.detectar(crudo) {
            guard !secreto else { throw ErrorPaso(mensaje: T("En un campo de contraseña no se pregunta.", "Ask isn't available in a password field.")) }
            guard let carpeta = Proyectos.detectar(p.contexto, carpetas: datos.carpetasProyectos) else {
                throw ErrorPaso(mensaje: T("No sé en qué proyecto: abrí su ventana (Terminal, Cursor, VS Code…) o sumá la carpeta en Modos › Proyectos.",
                                           "Which project? Open its window (Terminal, Cursor, VS Code…) or add its folder in Modes › Projects."))
            }
            guard Agentes.programa(agente) != nil else {
                throw ErrorPaso(mensaje: T("No encontré \(agente.nombre) en esta Mac.", "Couldn't find \(agente.nombre) on this Mac."))
            }
            let tarea = Agentes.Tarea(agente: agente, pedido: resto, seleccion: p.seleccion, carpeta: carpeta)
            let vacio = Registro(modo: .respuesta, app: p.contexto?.app ?? "", transcripcion: "", final: "", segundosAudio: p.segundos,
                                 msVoz: msVoz, msIA: 0, usoIA: false)
            return ("", vacio, tarea, .agente)
        } else if p.accion == .preguntar, p.anterior == nil, !secreto, let h = EnLaMac.entender(crudo),
                  let r = try await Motor.resolverEnLaMac(h, p) {
            // Traducir, sacar texto o leer un QR: en la Mac, gratis y sin mandar nada.
            final = r.texto
            herramienta = r.quien
            clase = r.clase
        } else if p.accion == .preguntar {
            guard !secreto else { throw ErrorPaso(mensaje: T("En un campo de contraseña no se pregunta.", "Ask isn't available in a password field.")) }
            guard iaLista else { throw ErrorPaso(mensaje: T("Para preguntar hace falta una IA configurada en Proveedores.", "Ask needs an AI set up in Providers.")) }
            // Sin selección y hablando de lo que se ve ("¿qué dice acá?", "resumime esta página"): va el texto de la
            // ventana, leído en la Mac, si "Leer la pantalla" y "Mirar la ventana" están prendidos.
            var ventana = ""
            if p.seleccion.isEmpty, p.anterior == nil, datos.leerPantalla, datos.mirarVentana, let pid = p.pid,
               EnLaMac.hablaDeLoVisible(crudo) {
                ventana = await Pantalla.leer(pid: pid, tope: 6000)
            }
            // Sin barrera de copia: la respuesta no se pega sola, la ves primero en la ventanita.
            let r = try await Proveedores.completar(
                sistema: Prompts.sistemaRespuesta,
                usuario: Prompts.usuarioRespuesta(pedido: crudo, seleccion: p.seleccion, anterior: p.anterior, contexto: ventanaIA,
                                                  terminos: terminos, extra: instruccion, ventana: ventana),
                ajustes: a)
            final = Prompts.limpiarSalida(r)
            usoIA = true
            if final.isEmpty { throw ErrorPaso(mensaje: T("La IA no devolvió texto.", "The AI returned no text.")) }
        } else if p.accion == .reescribir {
            guard !secreto else { throw ErrorPaso(mensaje: T("En un campo de contraseña no se reescribe.", "Rewriting isn't available in a password field.")) }
            guard iaLista else { throw ErrorPaso(mensaje: T("Para reescribir hace falta una IA configurada en Proveedores.", "Rewriting needs an AI set up in Providers.")) }
            let r = try await Proveedores.completar(
                sistema: Prompts.sistemaReescritura,
                usuario: Prompts.usuarioReescritura(seleccion: p.seleccion, instruccion: crudo, contexto: ventanaIA, terminos: terminos),
                ajustes: a)
            final = Prompts.limpiarSalida(r)
            usoIA = true
            if final.isEmpty { throw ErrorPaso(mensaje: T("La IA no devolvió texto.", "The AI returned no text.")) }
            // No se pega una reescritura que copie la memoria o el texto de alrededor del cursor (un mail ajeno puede
            // pedírselo a la IA): lo único que puede repetir es lo que elegiste y lo que dijiste (auditoría 23/10/2026).
            let ajeno = [Memoria.shared.paraPrompt, ventanaIA?.antes ?? "", ventanaIA?.despues ?? ""].joined(separator: "\n")
            if let copia = Prompts.copiaDeAjeno(transcripcion: p.seleccion + "\n" + crudo, salida: final, ajeno: ajeno) {
                throw ErrorPaso(mensaje: T("La IA copió texto que no estaba en lo que elegiste («\(copia)…»): no se pegó.",
                                           "The AI copied text that wasn't in your selection (“\(copia)…”), so nothing was pasted."))
            }
        } else if iaLista && !secreto && (datos.limpiarConIA || estilo != .comun)
                    && (crudo.split(whereSeparator: \.isWhitespace).count >= 3 || estilo == .traducir) {
            let usuario: String
            let sistema: String
            // Todo lo que fue en el pedido y no dijiste: la barrera frena si la IA lo copia.
            var ajeno = [Memoria.shared.paraPrompt, pantalla, ventanaIA?.ventana ?? "", ventanaIA?.antes ?? "", ventanaIA?.despues ?? ""]
            if estilo == .trabajo {
                let carpeta = Proyectos.detectar(p.contexto, carpetas: datos.carpetasProyectos)
                let proyecto = carpeta.map { Proyectos.contexto(de: $0) }
                proyectoNombre = proyecto?.nombre
                sistema = Prompts.sistemaTrabajo
                // Dictados recientes solo de la misma app: lo dictado en WhatsApp no tiene que aparecer en otra ventana.
                let recientes = Historial.shared.recientes(4, app: p.contexto?.app ?? "")
                ajeno += recientes.map(\.final) + [proyecto?.guia ?? ""]
                usuario = Prompts.usuarioTrabajo(transcripcion: crudo, contexto: ventanaIA,
                                                 pantalla: pantalla, proyecto: proyecto, recientes: recientes,
                                                 terminos: terminos, extra: instruccion)
            } else {
                sistema = Prompts.sistemaDictado
                usuario = Prompts.usuarioDictado(transcripcion: crudo, contexto: ventanaIA, pantalla: pantalla,
                                                 estilo: estilo, idioma: idioma, emojis: datos.emojisMensaje,
                                                 terminos: terminos, extra: instruccion)
            }
            do {
                let limpio = Prompts.limpiarSalida(try await Proveedores.completar(sistema: sistema, usuario: usuario, ajustes: a))
                // Los términos del diccionario y tus preferencias (por ejemplo cómo firmás) los puede escribir aunque no los digas.
                let conocidas = terminos.map(\.texto) + [instruccion]
                if let motivo = Prompts.barrera(transcripcion: crudo, salida: limpio, trabajo: estilo == .trabajo, estilo: estilo,
                                                conocidas: conocidas, ajeno: ajeno.joined(separator: "\n")) { barrera = motivo }
                else { final = limpio; usoIA = true }
            } catch {
                barrera = T("falló la IA: \(error.localizedDescription)", "AI failed: \(error.localizedDescription)")
            }
        } else {
            final = Prompts.arreglarCorto(datos.limpiezaBasica ? Prompts.limpiezaBasica(crudo) : crudo)
        }
        if barrera != nil && datos.limpiezaBasica { final = Prompts.arreglarCorto(Prompts.limpiezaBasica(crudo)) }
        guard final.rangeOfCharacter(from: .alphanumerics) != nil else {
            throw ErrorPaso(mensaje: T("No escuché nada. Probá hablar más cerca.", "Didn't hear anything. Try speaking closer to the mic."))
        }
        let msIA = usoIA || barrera != nil ? Int(Date().timeIntervalSince(t1) * 1000) : 0

        let modo: Registro.Modo = switch p.accion { case .reescribir: .reescritura; case .preguntar: .respuesta; default: .dictado }
        let registro = Registro(modo: modo, app: p.contexto?.app ?? "",
                                transcripcion: modo == .dictado ? crudo : p.seleccion, final: final,
                                instruccion: modo == .dictado ? nil : crudo,
                                segundosAudio: p.segundos, msVoz: msVoz, msIA: msIA, usoIA: usoIA, barrera: barrera,
                                proveedorVoz: datos.proveedorVoz.nombre + (datos.proveedorVoz.local ? "" : " · \(datos.modeloVoz)"),
                                proveedorIA: usoIA || barrera != nil ? "\(datos.proveedorIA.nombre) · \(datos.modeloIA)" : herramienta,
                                estilo: modo == .dictado ? estilo.corto : nil,
                                proyecto: proyectoNombre, audio: p.audio, reprocesoDe: p.reprocesoDe)
        return (final, registro, nil, clase)
    }

    // ¿Hay que dejarlo copiado en vez de pegarlo? Una reescritura de varias líneas en una terminal: cada línea podría
    // ejecutarse al pegar (el texto viene de la IA, que pudo seguir algo escrito en la selección o la pantalla).
    static func copiarEnVezDePegar(_ texto: String, modo: Registro.Modo, bundle: String) -> Bool {
        modo == .reescritura && Cursor.terminales.contains(bundle) && texto.contains("\n")
    }

    private func entregar(_ textoOriginal: String, contexto: ContextoCursor?, registro: Registro) {
        let texto = Prompts.sinControles(textoOriginal)
        let secreto = contexto?.secreto == true
        estado = .libre
        if !secreto { ultimoResultado = texto }
        Motor.guardarRastro(registro, texto: texto, contexto: contexto)
        // Si la app de adelante cambió o no hay campo de texto, lo dejamos en el portapapeles.
        let mismaApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == contexto?.bundle
        // Se pega si hay campo seguro o si la app no cuenta dónde está el cursor (Chrome, Electron): como Halyon.
        if secreto {
            // Campo de contraseña: se pega marcado como oculto, el portapapeles vuelve a como estaba y nunca se muestra.
            guard mismaApp else { pildora.mostrar(.aviso(T("No se pudo pegar.", "Couldn't paste.")), durante: 2); return }
            Cursor.pegar(texto, secreto: true) { [weak self] r in
                self?.pildora.mostrar(r == .noEntro ? .aviso(T("No se pudo pegar.", "Couldn't paste.")) : .listo(T("Listo", "Done")), durante: 1)
            }
        } else if mismaApp, let c = contexto, c.campo != .noHay, Motor.copiarEnVezDePegar(texto, modo: registro.modo, bundle: c.bundle) {
            Cursor.copiar(texto)
            pildora.mostrar(.sinCampo(texto), durante: 30)
        } else if mismaApp, let c = contexto, c.campo != .noHay {
            let etiqueta = registro.modo == .reescritura ? T("Reescrito", "Rewritten") : (registro.estilo == "Trabajo" ? T("Prompt listo", "Prompt ready") : T("Listo", "Done"))
            Cursor.pegar(texto) { [weak self] r in
                guard let self else { return }
                if r == .noEntro {
                    // La app no lo tomó: a la vista y copiado, en vez de un "Listo" engañoso.
                    Motor.sonido("Basso")
                    self.pildora.mostrar(.sinCampo(texto), durante: 30)
                } else {
                    self.pildora.mostrar(.listo(etiqueta), durante: 0.9)
                    // Si después corregís a mano un nombre de lo pegado, se sugiere para el diccionario.
                    if r == .entro && registro.modo == .dictado { Correcciones.shared.vigilar(pegado: texto) }
                    // Enter automático (solo si se comprobó que el texto entró): manda el prompt o el mensaje.
                    let enviar = registro.estilo == Estilo.trabajo.corto ? self.ajustes.datos.enviarTrabajo
                        : registro.estilo == Estilo.mensaje.corto ? self.ajustes.datos.enviarMensaje : .ninguna
                    if r == .entro && enviar != .ninguna {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Cursor.enviar(enviar) }
                    }
                }
            }
        } else {
            // No hay campo de texto: queda copiado y a la vista en la píldora, con botón para copiar.
            Cursor.copiar(texto)
            Motor.sonido("Basso")
            pildora.mostrar(.sinCampo(texto), durante: 30)
        }
    }

    // Lo que queda guardado de un dictado (lo llama entregar): historial, memoria, diccionario que aprende y portapapeles.
    // Nada si fue en un campo de contraseña: antes la contraseña dictada quedaba en el historial, en el audio y en el
    // historial del portapapeles (auditoría de seguridad del 23/10/2026).
    static func guardarRastro(_ registro: Registro, texto: String, contexto: ContextoCursor?) {
        guard contexto?.secreto != true else { return }
        let datos = Ajustes.shared.datos
        Historial.shared.sumar(registro)
        Memoria.shared.anotar(registro)
        Sugerencias.shared.aprender(de: registro, proyecto: registro.proyecto, contexto: datos.mirarVentana ? contexto : nil)
        if datos.portapapelesActivo { Portapapeles.shared.sumarTexto(texto, app: "Dixity") }
    }

    // Vuelve a procesar un audio del historial con los proveedores elegidos ahora (para comparar).
    func reprocesar(_ r: Registro, listo: @escaping (String?) -> Void) {
        guard r.modo == .dictado, let wav = Historial.shared.audio(de: r) else { listo(T("Ese dictado ya no tiene audio.", "That dictation no longer has audio.")); return }
        let ctx = ContextoCursor(app: r.app)
        let pedido = Pedido(wav: wav, segundos: r.segundosAudio, accion: .dictar, contexto: ctx, seleccion: "",
                            estilo: Estilo.desde(corto: r.estilo) ?? .comun, audio: r.audio, reprocesoDe: r.reprocesoDe ?? r.id)
        Task.detached {
            do {
                let res = try await Motor.procesar(pedido)
                await MainActor.run { Historial.shared.sumar(res.registro); listo(nil) }
            } catch {
                await MainActor.run { listo(error.localizedDescription) }
            }
        }
    }

    // La Mac se va a dormir: no dejar nada a medias ni modelos cargados que después "despiertan" pesados.
    /// Se bloqueó la pantalla o se cambió de usuario: la Varita se apaga (si no, sus clics quedaban retenidos ahí).
    func alBloquear() {
        varita.apagar("al bloquear la pantalla")
        lector.parar()
    }

    func antesDeDormir() {
        seguimiento = nil
        varita.apagar("al dormir la Mac")
        lector.parar()
        if estado == .grabando { cancelar(aviso: nil) }
        ultimoDictado?.wav = nil
        pildora.esconder()
        Task.detached { await Parakeet.shared.liberar() }
    }

    // Al despertar, macOS a veces apaga la escucha del teclado: se vuelve a armar.
    func alDespertar() {
        seguimiento = nil
        if estado == .grabando { cancelar(aviso: nil) }
        monitor.detener()
        monitor.arrancar()
    }

    // Espera algo como mucho `segundos`; si no llegó, sigue con nil.
    static func conTope<T: Sendable>(segundos: Double, _ trabajo: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { g in
            g.addTask { await trabajo() }
            g.addTask { try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000)); return nil }
            let primero = await g.next() ?? nil
            g.cancelAll()
            return primero
        }
    }

    // Mientras grabás un atajo nuevo en el panel, ningún atajo de Dixity actúa (si no, se lo "come" el que ya existe).
    func suspenderAtajos() {
        monitor.atajos = [:]
        monitor.atajosNumero = false
        monitor.atajosModo = [:]
        monitor.atajosAccion = [:]
    }

    func copiarUltimo() {
        guard !ultimoResultado.isEmpty else { return }
        Cursor.copiar(ultimoResultado)
        pildora.mostrar(.listo(T("Copiado", "Copied")), durante: 1)
    }
}
