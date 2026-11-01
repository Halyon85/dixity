import AppKit
import SwiftUI

struct PaginaAtajos: View {
    @ObservedObject var ajustes: Ajustes
    let motor: Motor

    private var subtitulo: String {
        switch ajustes.datos.modoTecla {
        case .ambos: T("Mantené el atajo mientras hablás y soltalo, o tocalo una vez para empezar y otra para terminar.",
                         "Hold the shortcut while you talk and let go, or tap it once to start and again to finish.")
        case .mantener: T("Apretá el atajo y hablá; al soltarlo, Dixity escribe en donde está el cursor.",
                            "Hold the shortcut and talk; when you let go, Dixity types wherever your cursor is.")
        case .alternar: T("Un toque empieza a escuchar y otro toque termina y escribe.",
                            "Tap once to start listening, tap again to finish and type.")
        }
    }

    var body: some View {
        TituloPagina(titulo: T("Atajos", "Shortcuts"), subtitulo: subtitulo)
        Tarjeta {
            Fila(titulo: T("Cómo funciona la tecla", "How the key works"), divisor: false) {
                Selector(valor: $ajustes.datos.modoTecla, opciones: ModoTecla.allCases, nombre: \.nombre, ancho: 260)
            }
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            TarjetaAtajo(titulo: T("Dictar", "Dictate"), accion: .dictar, ajustes: ajustes, motor: motor,
                         dices: T("Pasame el informe el martes, no, mejor el miércoles a primera hora, y eh, avisale a Caro que la reunión se corre.",
                                  "Send me the report on Tuesday, no, actually Wednesday first thing, and uh, let Caro know the meeting's moving."),
                         escribe: T("Pasame el informe el miércoles a primera hora y avisale a Caro que la reunión se corre.",
                                    "Send me the report Wednesday first thing, and let Caro know the meeting's moving."))
            TarjetaAtajo(titulo: T("Reescribir selección", "Rewrite selection"), accion: .reescribir, ajustes: ajustes, motor: motor,
                         dices: T("«Para un mail»  ·  che no llego con lo del viernes, si les sirve lo mando el lunes",
                                  "“For an email”  ·  hey can't make friday's deadline, can send it monday if that works"),
                         escribe: T("Hola, ¿cómo están? No voy a llegar con la entrega del viernes. Si les parece bien, la envío el lunes. ¡Gracias!",
                                    "Hi team, I won't be able to make Friday's deadline. Would Monday work instead? Thanks!"))
        }
        TarjetaAtajo(titulo: T("Preguntar", "Ask"), accion: .preguntar, ajustes: ajustes, motor: motor, dices: "", escribe: "",
                     detalle: T("Mantenelo y pedí lo que quieras («respondele que el jueves puedo», «¿cómo se dice plazo en inglés?»). La respuesta aparece en una ventanita antes de pegar: ↩ la pega, Esc la cierra y, si volvés a mantener el atajo, la ajustás («más corto»). Si tenés un texto seleccionado, trabaja sobre él. Empezá con «Claude, …» o «Codex, …» para preguntarle a ese agente sobre el proyecto que tenés abierto (de Modos › Proyectos): solo mira, y edita archivos únicamente si tocás «Hacelo». «¿Cuánto me queda de Claude?» te dice tu uso.",
                                "Hold it and ask for anything (“reply that Thursday works”, “how do you say deadline in Spanish?”). The answer shows up in a small window before pasting: ↩ pastes it, Esc closes it, and holding the shortcut again lets you adjust it (“shorter”). If you have text selected, it works on that. Start with “Claude, …” or “Codex, …” to ask that agent about the project you have open (from Modes › Projects): it only looks, and edits files only if you click “Have it do it”. “How much Claude do I have left?” tells you your usage."))
        TarjetaAtajo(titulo: T("Portapapeles", "Clipboard"), accion: .portapapeles, ajustes: ajustes, motor: motor, dices: "", escribe: "")
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            TarjetaAtajo(titulo: T("Volver a procesar", "Process again"), accion: .reprocesar, ajustes: ajustes, motor: motor, dices: "", escribe: "",
                         detalle: T("Si el último dictado salió mal (o falló la IA), lo procesa de nuevo y lo pega donde está el cursor. Si seleccionás lo que pegó antes, lo reemplaza.",
                                    "If your last dictation came out wrong (or the AI failed), it processes it again and pastes it at your cursor. Select what it pasted before to replace it."))
            TarjetaAtajo(titulo: T("Sumar al diccionario", "Add to dictionary"), accion: .sumarPalabra, ajustes: ajustes, motor: motor, dices: "", escribe: "",
                         detalle: T("Seleccioná una palabra o un nombre en cualquier app y apretá el atajo: Dixity lo suma al diccionario para escribirlo siempre bien.",
                                    "Select a word or a name in any app and press the shortcut: Dixity adds it to your dictionary so it always spells it right."))
        }
        Tarjeta {
            Fila(titulo: T("Historial del portapapeles", "Clipboard history"),
                 detalle: T("Guarda lo que copiás (textos, imágenes y archivos) durante 24 horas y se borra solo. Las contraseñas no se guardan.",
                            "Keeps what you copy (text, images and files) for 24 hours, then clears itself. Passwords are never saved."), divisor: false) {
                Toggle("", isOn: $ajustes.datos.portapapelesActivo).toggleStyle(.switch).labelsHidden()
            }
        }
        Tarjeta(titulo: T("Mientras dictás", "While dictating")) {
            Fila(titulo: T("Cancelar", "Cancel"), detalle: T("Apretá Esc y no se escribe nada.", "Press Esc and nothing gets typed.")) { TeclaVisual(texto: "Esc") }
            Fila(titulo: T("Combinaciones comunes", "Regular key combos"),
                 detalle: T("Si mientras sostenés un atajo de solo modificadores tocás otra tecla, Dixity lo toma como combinación normal y no dicta.",
                            "If you press another key while holding a modifier-only shortcut, Dixity treats it as a normal key combo and doesn't dictate."), divisor: false) { EmptyView() }
        }
    }
}

// También la usa la bienvenida (sin ejemplo: dices y escribe vacíos).
struct TarjetaAtajo: View {
    let titulo: String
    let accion: MonitorAtajos.Accion
    @ObservedObject var ajustes: Ajustes
    let motor: Motor
    let dices: String
    let escribe: String
    var detalle = ""

    @Estado private var grabando = false
    @Estado private var vistos = Set<Modificador>()
    @Estado private var maximo = Set<Modificador>()
    @Estado private var mensaje: String?
    @Estado private var aviso: String?
    @Estado private var monitorLocal: Any?

    private var atajo: Atajo {
        switch accion {
        case .dictar: ajustes.datos.atajoDictar
        case .reescribir: ajustes.datos.atajoReescribir
        case .portapapeles: ajustes.datos.atajoPortapapeles
        case .reprocesar: ajustes.datos.atajoReprocesar
        case .sumarPalabra: ajustes.datos.atajoSumarPalabra
        case .preguntar: ajustes.datos.atajoPreguntar
        }
    }
    private var otros: [Atajo] {
        let d = ajustes.datos
        return [(MonitorAtajos.Accion.dictar, d.atajoDictar), (.reescribir, d.atajoReescribir), (.portapapeles, d.atajoPortapapeles),
                (.reprocesar, d.atajoReprocesar), (.sumarPalabra, d.atajoSumarPalabra), (.preguntar, d.atajoPreguntar)]
            .filter { $0.0 != accion }.map(\.1) + d.modos.compactMap(\.atajo) + [d.atajoAutomatico].compactMap { $0 }
            + d.acciones.compactMap(\.atajo)
    }
    private var predeterminado: Atajo {
        switch accion {
        case .dictar: .dictarPredeterminado
        case .reescribir: .reescribirPredeterminado
        case .portapapeles: .portapapelesPredeterminado
        case .reprocesar: .reprocesarPredeterminado
        case .sumarPalabra: .sumarPalabraPredeterminado
        case .preguntar: .preguntarPredeterminado
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !dices.isEmpty { ejemplo.padding(8) }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(titulo).font(.titulo(14)).foregroundStyle(Tema.titulo)
                    Spacer()
                    if atajo != predeterminado && !grabando {
                        Button(T("Restaurar", "Reset")) { guardar(predeterminado) }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Tema.apagado)
                    }
                }
                HStack(spacing: 8) {
                    if grabando {
                        if vistos.isEmpty { Text(T("Apretá la combinación nueva…", "Press the new combination…")).font(.system(size: 13)).foregroundStyle(Tema.acento) }
                        else { Teclas(atajo: Atajo(modificadores: Array(vistos), tecla: nil), grande: true) }
                    } else {
                        Teclas(atajo: atajo, grande: true)
                    }
                    Spacer()
                    BotonSecundario(texto: grabando ? T("Cancelar", "Cancel") : T("Cambiar", "Change"), icono: grabando ? nil : "pencil") {
                        grabando ? terminarCaptura() : empezarCaptura()
                    }
                }
                if !detalle.isEmpty {
                    Text(detalle).font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
                }
                if let m = mensaje {
                    Text(m).font(.system(size: 12)).foregroundStyle(Tema.error).fixedSize(horizontal: false, vertical: true)
                } else if let a = aviso ?? atajo.aviso {
                    Text(a).font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 18, trailing: 16))
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Tema.tarjeta))
        .shadow(color: .black.opacity(0.02), radius: 4, y: 2)
        .onDisappear { terminarCaptura() }
    }

    private var ejemplo: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(T("Vos decís", "You say")).font(.system(size: 11, weight: .medium)).foregroundStyle(Tema.apagado)
                Text(dices).font(.system(size: 12)).foregroundStyle(Tema.subtitulo).italic()
            }
            HStack { Spacer(); PildoraDemo(reescritura: accion == .reescribir); Spacer() }
            VStack(alignment: .leading, spacing: 3) {
                Text(T("Dixity escribe", "Dixity types")).font(.system(size: 11, weight: .medium)).foregroundStyle(Tema.apagado)
                Text(escribe).font(.system(size: 12)).foregroundStyle(Tema.titulo)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Tema.fondoMedio))
    }

    private func empezarCaptura() {
        mensaje = nil; aviso = nil; vistos = []; maximo = []
        grabando = true
        motor.suspenderAtajos()   // que no dicte ni cambie de modo mientras grabás el atajo
        monitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { e in
            procesar(e)
            return nil
        }
    }

    private func terminarCaptura() {
        if let m = monitorLocal { NSEvent.removeMonitor(m) }
        monitorLocal = nil
        grabando = false
        vistos = []; maximo = []
        motor.actualizarAtajos()
    }

    private func procesar(_ e: NSEvent) {
        if e.type == .flagsChanged {
            guard let m = Modificador.desdeCodigo(Int64(e.keyCode)) else { return }
            let flags = UInt64(e.modifierFlags.rawValue)
            if flags & m.mascara != 0 { vistos.insert(m) } else { vistos.remove(m) }
            if vistos.count >= maximo.count { maximo = vistos }
            if vistos.isEmpty && !maximo.isEmpty { proponer(Atajo(modificadores: Array(maximo), tecla: nil)) }
            return
        }
        if e.keyCode == 53 && vistos.isEmpty { terminarCaptura(); return }
        if e.isARepeat { return }
        proponer(Atajo(modificadores: Array(vistos), tecla: Int64(e.keyCode)))
    }

    private func proponer(_ nuevo: Atajo) {
        if let p = nuevo.problema(otros: otros) {
            mensaje = p
            vistos = []; maximo = []
            return
        }
        guardar(nuevo)
        terminarCaptura()
    }

    private func guardar(_ a: Atajo) {
        mensaje = nil
        aviso = a.aviso
        switch accion {
        case .dictar: ajustes.datos.atajoDictar = a
        case .reescribir: ajustes.datos.atajoReescribir = a
        case .portapapeles: ajustes.datos.atajoPortapapeles = a
        case .reprocesar: ajustes.datos.atajoReprocesar = a
        case .sumarPalabra: ajustes.datos.atajoSumarPalabra = a
        case .preguntar: ajustes.datos.atajoPreguntar = a
        }
    }
}

// Mini píldora que se anima sola: grabando → pensando → listo.
private struct PildoraDemo: View {
    let reescritura: Bool
    @Environment(\.colorScheme) private var esquema
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let fase = Int(t.truncatingRemainder(dividingBy: 6) / 2)   // 0 graba, 1 piensa, 2 listo
            // Igual que la píldora real: contrasta con el sistema; cada fase entra y sale sin mezclarse.
            let oscura = esquema == .light
            let tinta: Color = oscura ? .white : Color(hex: 0x0A0A0A)
            ZStack {
                switch fase {
                case 0:
                    HStack(spacing: 9) {
                        Circle().fill(Tema.acento).frame(width: 7, height: 7)
                        HStack(spacing: 2.2) {
                            ForEach(0..<11, id: \.self) { i in
                                let forma = max(0.15, 1 - pow(Double(abs(i - 5)) / 6, 1.6))
                                Capsule().frame(width: 2.2, height: max(2.2, 14 * forma * abs(sin(t * 5 + Double(i) * 0.7))))
                            }
                        }
                        .frame(height: 16)
                        Image(systemName: reescritura ? "wand.and.stars" : "mic.fill").font(.system(size: 12, weight: .semibold))
                    }
                    .transition(.opacity)
                case 1:
                    Text(reescritura ? T("Reescribiendo…", "Rewriting…") : T("Puliendo…", "Polishing…")).font(.system(size: 12)).opacity(0.75)
                        .transition(.opacity)
                default:
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.exito).font(.system(size: 13))
                        Text(T("Listo", "Done")).font(.system(size: 12))
                    }
                    .transition(.opacity)
                }
            }
            .id(fase)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(oscura ? Color(hex: 0x1D1D1C) : Color(hex: 0xF8F6F4)))
            .overlay(Capsule().strokeBorder(reescritura ? AnyShapeStyle(Tema.arcoiris) : AnyShapeStyle(tinta.opacity(0.1)), lineWidth: reescritura ? 1.5 : 1))
            .clipShape(Capsule())
            .foregroundStyle(tinta)
            .animation(Tema.expo, value: fase)
        }
    }
}
