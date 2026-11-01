import AppKit
import Carbon.HIToolbox

// Modificadores con lado (izquierdo/derecho) y la tecla 🌐 fn.
enum Modificador: String, Codable, CaseIterable, Hashable {
    case ctrlIzq, ctrlDer, opcionIzq, opcionDer, shiftIzq, shiftDer, cmdIzq, cmdDer, fn

    var codigo: Int64 {
        switch self {
        case .ctrlIzq: 59
        case .ctrlDer: 62
        case .opcionIzq: 58
        case .opcionDer: 61
        case .shiftIzq: 56
        case .shiftDer: 60
        case .cmdIzq: 55
        case .cmdDer: 54
        case .fn: 63
        }
    }

    // Bits "por lado" que trae cada evento de teclado.
    var mascara: UInt64 {
        switch self {
        case .ctrlIzq: 0x0001
        case .ctrlDer: 0x2000
        case .opcionIzq: 0x0020
        case .opcionDer: 0x0040
        case .shiftIzq: 0x0002
        case .shiftDer: 0x0004
        case .cmdIzq: 0x0008
        case .cmdDer: 0x0010
        case .fn: 0x800000
        }
    }

    var familia: String {
        switch self {
        case .ctrlIzq, .ctrlDer: "ctrl"
        case .opcionIzq, .opcionDer: "opcion"
        case .shiftIzq, .shiftDer: "shift"
        case .cmdIzq, .cmdDer: "cmd"
        case .fn: "fn"
        }
    }

    var simbolo: String {
        switch familia {
        case "ctrl": "⌃"
        case "opcion": "⌥"
        case "shift": "⇧"
        case "cmd": "⌘"
        default: "🌐"
        }
    }

    var lado: String? {
        switch self {
        case .ctrlIzq, .opcionIzq, .shiftIzq, .cmdIzq: T("izq.", "left")
        case .ctrlDer, .opcionDer, .shiftDer, .cmdDer: T("der.", "right")
        case .fn: nil
        }
    }

    var nombreLargo: String {
        let base: String
        switch familia {
        case "ctrl": base = "Control"
        case "opcion": base = T("Opción", "Option")
        case "shift": base = T("Mayúsculas", "Shift")
        case "cmd": base = T("Comando", "Command")
        default: base = T("Globo (fn)", "Globe (fn)")
        }
        switch self {
        case .ctrlIzq, .opcionIzq, .shiftIzq, .cmdIzq: return base + T(" izquierda", " (left)")
        case .ctrlDer, .opcionDer, .shiftDer, .cmdDer: return base + T(" derecha", " (right)")
        case .fn: return base
        }
    }

    static func desdeCodigo(_ c: Int64) -> Modificador? { allCases.first { $0.codigo == c } }
    static let orden: [String] = ["fn", "ctrl", "opcion", "shift", "cmd"]
}

// Un atajo: solo modificadores (p. ej. ⌥ derecha) o modificadores + una tecla (p. ej. ⌥ Espacio, F5).
struct Atajo: Codable, Hashable {
    var modificadores: [Modificador]
    var tecla: Int64?

    static let dictarPredeterminado = Atajo(modificadores: [.opcionDer], tecla: nil)
    static let reescribirPredeterminado = Atajo(modificadores: [.shiftIzq, .opcionIzq], tecla: nil)   // ⇧⌥ izquierdas: no choca con ⌥ derecha de dictar
    static let portapapelesPredeterminado = Atajo(modificadores: [.ctrlIzq, .opcionIzq], tecla: 9)   // ⌃⌥V
    static let reprocesarPredeterminado = Atajo(modificadores: [.ctrlIzq, .opcionIzq], tecla: 15)    // ⌃⌥R
    static let sumarPalabraPredeterminado = Atajo(modificadores: [.ctrlIzq, .opcionIzq], tecla: 2)   // ⌃⌥D
    // ⌃⌥P: no ⌃⌥Espacio, que macOS usa para cambiar la fuente de entrada.
    static let preguntarPredeterminado = Atajo(modificadores: [.ctrlIzq, .opcionIzq], tecla: 35)

    var soloModificadores: Bool { tecla == nil }
    var familias: Set<String> { Set(modificadores.map(\.familia)) }

    var partes: [String] {
        var p = modificadores.sorted { Modificador.orden.firstIndex(of: $0.familia)! < Modificador.orden.firstIndex(of: $1.familia)! }
            .map { m -> String in
                if tecla == nil, let lado = m.lado { return "\(m.simbolo) \(lado)" }
                return m.simbolo
            }
        if let t = tecla { p.append(Atajo.nombreTecla(t)) }
        return p
    }

    var descripcion: String { partes.joined(separator: " ") }

    static func nombreTecla(_ codigo: Int64) -> String {
        let especiales: [Int64: String] = [
            49: T("Espacio", "Space"), 36: "Return", 48: "Tab", 51: T("Borrar", "Delete"), 117: T("Supr", "Fwd Del"), 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: T("Inicio", "Home"), 119: T("Fin", "End"), 116: T("Re Pág", "Page Up"), 121: T("Av Pág", "Page Down"),
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        ]
        if let n = especiales[codigo] { return n }
        return caracterDeTecla(UInt16(codigo))?.uppercased() ?? T("Tecla \(codigo)", "Key \(codigo)")
    }

    static let teclasF: Set<Int64> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    // Qué letra escribe una tecla con la distribución de teclado actual.
    static func caracterDeTecla(_ codigo: UInt16, modificadores: UInt32 = 0) -> String? {
        guard let fuente = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(fuente, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let datos = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var estado: UInt32 = 0
        var largo = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let res = datos.withUnsafeBytes { buf -> OSStatus in
            guard let layout = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, codigo, UInt16(kUCKeyActionDisplay), (modificadores >> 8) & 0xFF,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &estado, 4, &largo, &chars)
        }
        guard res == noErr, largo > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: largo)
        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
    }

    // Reglas para aceptar un atajo nuevo. Devuelve el problema o nil si está bien.
    func problema(otros: [Atajo]) -> String? {
        if modificadores.isEmpty && tecla == nil { return T("No apretaste ninguna tecla.", "You didn't press any key.") }
        if modificadores.count > 3 { return T("Hasta 3 modificadores.", "Up to 3 modifiers.") }
        let porFamilia = Dictionary(grouping: modificadores, by: \.familia)
        if porFamilia.values.contains(where: { $0.count > 1 }) {
            return T("No se puede usar el mismo modificador de los dos lados a la vez.", "You can't use the same modifier on both sides at once.")
        }
        if tecla == 53 { return T("Esc sirve para cancelar; no puede ser parte de un atajo.", "Esc is for canceling; it can't be part of a shortcut.") }
        if let t = tecla {
            let fuertes = familias.subtracting(["shift"])
            if !Atajo.teclasF.contains(t) && fuertes.isEmpty {
                return familias.isEmpty
                    ? T("Esta tecla va con ⌃, ⌥ o ⌘ (podés sumar ⇧). Solo F1–F20 sirven solas.", "This key needs ⌃, ⌥ or ⌘ (you can add ⇧). Only F1–F20 work on their own.")
                    : T("Solo ⇧ molesta al escribir: sumá ⌃, ⌥ o ⌘.", "⇧ alone gets in the way when typing: add ⌃, ⌥ or ⌘.")
            }
            if familias == ["cmd"] && [8, 9, 7, 0, 6, 1, 12, 13, 3, 45, 17, 31, 35, 15, 4, 11, 46, 14, 16, 2].contains(t) {
                return T("Esa combinación la usan todas las apps (como ⌘C o ⌘V). Elegí otra.", "Every app uses that combination (like ⌘C or ⌘V). Pick another.")
            }
            if [Set(["cmd"]), Set(["cmd", "shift"])].contains(familias) && t == 49 {
                return T("macOS ya usa esa combinación.", "macOS already uses that combination.")
            }
        } else if familias == ["shift"] {
            return T("Mayúsculas sola molesta al escribir: sumá otro modificador.", "Shift alone gets in the way when typing: add another modifier.")
        }
        for o in otros {
            if o == self { return T("Es igual a otro atajo (\(o.descripcion)).", "Same as another shortcut (\(o.descripcion)).") }
            if soloModificadores && o.soloModificadores {
                let a = Set(modificadores), b = Set(o.modificadores)
                if a.isSubset(of: b) || b.isSubset(of: a) { return T("Un atajo no puede ser parte de otro (\(o.descripcion)).", "A shortcut can't contain another one (\(o.descripcion)).") }
            }
        }
        return nil
    }

    // Aviso suave (se acepta igual).
    var aviso: String? {
        if let t = tecla, familias == ["opcion"] || familias == ["opcion", "shift"],
           Atajo.caracterDeTecla(UInt16(t), modificadores: UInt32(optionKey)) != nil {
            return T("Con tu teclado esta combinación escribe un carácter; como atajo, ya no lo va a escribir.", "On your keyboard this combination types a character; as a shortcut, it won't type it anymore.")
        }
        if tecla == nil && familias == ["fn"] {
            return T("Si al tocar 🌐 se abre otra cosa, en Ajustes del Sistema › Teclado poné «Al pulsar 🌐» en «No hacer nada».", "If pressing 🌐 opens something else, go to System Settings › Keyboard and set “Press 🌐 key to” to “Do Nothing”.")
        }
        return nil
    }
}

// Escucha el teclado de toda la Mac (necesita permiso de Accesibilidad).
final class MonitorAtajos {
    enum Accion { case dictar, reescribir, portapapeles, reprocesar, sumarPalabra, preguntar }
    enum Evento {
        case apretar(Accion), soltar(Accion, sostenido: TimeInterval), anular(Accion), escape, modo(Int), modoPropio(Estilo)
        case accionRapida(UUID), confirmar, teclaSuelta
        case menu(TeclaMenu)
    }
    // Con la Varita prendida: 1…9 eligen, ↑↓ mueven, ⌥↑⌥↓ agrandan o achican lo marcado, ↩ elige y otra tecla la apaga.
    enum TeclaMenu: Equatable { case numero(Int), arriba, abajo, elegir, otra, agrandar, achicar }

    var alEvento: ((Evento) -> Void)?
    var atajos: [Accion: Atajo] = [:]
    var capturaEsc = false   // mientras dicta, Esc cancela y no llega a la app
    var capturaNumeros = false   // mientras dicta, 1…6 cambian el modo y no llegan a la app
    // Con la ventana de respuesta abierta: ↩ pega (y no llega a la app) y cualquier otra tecla que escribas avisa
    // (`teclaSuelta`) para cerrarla, así ↩ no queda tomado mientras escribís en otro lado.
    var capturaRespuesta = false
    var capturaMenu = false
    // Con la Varita prendida, hiciste clic en una caja de texto para escribir: 1…9, ↑↓ y ↩ ya no eligen sugerencias,
    // llegan a la caja (antes ↩ ejecutaba «Pasar a inglés» en vez de mandar tu mensaje). La primera tecla apaga la Varita.
    var menuEscribiendo = false
    var atajosNumero = true      // ⌃⌥ (o la combinación elegida) + 0…9 elige el modo (no graba)
    var familiasModos: Set<String> = ["ctrl", "opcion"]
    private static let numeros: [Int64: Int] = [29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
    var atajosModo: [Estilo: Atajo] = [:]   // atajo propio de cada modo (Modos), si lo eligió
    var atajosAccion: [UUID: Atajo] = [:]   // acciones rápidas (Modos › Acciones rápidas)

    private var tap: CFMachPort?
    private var fuente: CFRunLoopSource?
    private var presionados = Set<Modificador>()
    private var activa: Accion?
    private var inicio: TimeInterval = 0   // hora de la tecla al apretar (ver `hora(de:)`)
    private var otraTecla = false

    var activo: Bool { tap != nil }

    @discardableResult
    func arrancar() -> Bool {
        if tap != nil { return true }
        let mascara = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let yo = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mascara),
                                        callback: { _, tipo, evento, ref in
                                            let m = Unmanaged<MonitorAtajos>.fromOpaque(ref!).takeUnretainedValue()
                                            return m.procesar(tipo, evento)
                                        }, userInfo: yo) else { return false }
        tap = t
        fuente = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), fuente, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func detener() {
        if let f = fuente { CFRunLoopRemoveSource(CFRunLoopGetMain(), f, .commonModes) }
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        tap = nil; fuente = nil
    }

    // Cuándo pasó la tecla según el propio evento, en segundos desde que arrancó la Mac. A propósito no es la hora en
    // que la atendemos: el teclado se escucha en el hilo principal y, si empezar a grabar lo tiene ocupado (leer la
    // ventana, prender el micrófono), el "soltar" se atiende tarde y un toque corto parecía mantenido: cortaba la
    // grabación al toque y quedaba "como si no hubieras hablado" (30/10/2026).
    // macOS a veces la da en nanosegundos y a veces en tics del reloj; en nanosegundos siempre es mayor que los tics
    // de ahora, y así se distinguen.
    static func hora(de e: CGEvent) -> TimeInterval {
        let t = e.timestamp
        guard t > 0 else { return ProcessInfo.processInfo.systemUptime }
        if t > mach_absolute_time() { return Double(t) / 1e9 }
        var base = mach_timebase_info()
        mach_timebase_info(&base)
        return Double(t) * Double(base.numer) / Double(base.denom) / 1e9
    }

    func procesar(_ tipo: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        let codigo = e.getIntegerValueField(.keyboardEventKeycode)
        if e.getIntegerValueField(.eventSourceUserData) == Motor.marcaPropia { return Unmanaged.passUnretained(e) }

        if tipo == .flagsChanged {
            guard let m = Modificador.desdeCodigo(codigo) else { return Unmanaged.passUnretained(e) }
            let abajo = e.flags.rawValue & m.mascara != 0
            if abajo { presionados.insert(m) } else { presionados.remove(m) }
            revisarModificadores(abajo: abajo, hora: Self.hora(de: e))
            return Unmanaged.passUnretained(e)
        }

        let repite = e.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if tipo == .keyDown && codigo == 53 && capturaEsc {
            if !repite { alEvento?(.escape) }
            return nil
        }

        // Atajo propio de un modo (por ejemplo ⌃⌥M): lo elige.
        if tipo == .keyDown || tipo == .keyUp {
            for (e, a) in atajosModo where a.tecla == codigo && Set(a.modificadores.map(\.familia)) == Set(presionados.map(\.familia)) {
                if tipo == .keyDown && !repite { alEvento?(.modoPropio(e)) }
                return nil
            }
            for (id, a) in atajosAccion where a.tecla == codigo && Set(a.modificadores.map(\.familia)) == Set(presionados.map(\.familia)) {
                if tipo == .keyDown && !repite { alEvento?(.accionRapida(id)) }
                return nil
            }
        }

        // Combinación + número (o el número solo mientras dicta): elige el modo.
        if tipo == .keyDown || tipo == .keyUp, let n = Self.numeros[codigo] {
            let conCombinacion = atajosNumero && !presionados.isEmpty && Set(presionados.map(\.familia)) == familiasModos
            if conCombinacion || (capturaNumeros && presionados.isEmpty) {
                if tipo == .keyDown && !repite { alEvento?(.modo(n)) }
                return nil
            }
        }

        // Atajos con tecla.
        for (accion, atajo) in atajos where atajo.tecla == codigo {
            if Set(atajo.modificadores.map(\.familia)) == Set(presionados.map(\.familia)) {
                if tipo == .keyDown {
                    if !repite { activa = accion; inicio = Self.hora(de: e); otraTecla = false; alEvento?(.apretar(accion)) }
                } else if activa == accion {
                    activa = nil
                    alEvento?(.soltar(accion, sostenido: Self.hora(de: e) - inicio))
                }
                return nil
            }
        }
        if tipo == .keyUp, let a = activa, atajos[a]?.tecla == codigo {
            activa = nil
            alEvento?(.soltar(a, sostenido: Self.hora(de: e) - inicio))
            return nil
        }

        if tipo == .keyDown && capturaMenu && menuEscribiendo {
            if !repite { alEvento?(.menu(.otra)) }
        } else if tipo == .keyDown && capturaMenu {
            let sinModificadores = presionados.isEmpty
            if sinModificadores, let n = Self.numeros[codigo], n >= 1 { if !repite { alEvento?(.menu(.numero(n))) }; return nil }
            if sinModificadores && codigo == 126 { alEvento?(.menu(.arriba)); return nil }
            if sinModificadores && codigo == 125 { alEvento?(.menu(.abajo)); return nil }
            // ⌥↑ / ⌥↓: la Varita agranda o achica lo marcado (a la sección, a la ventana).
            let soloOpcion = !presionados.isEmpty && presionados.allSatisfy { $0.familia == "opcion" }
            if soloOpcion && codigo == 126 { alEvento?(.menu(.agrandar)); return nil }
            if soloOpcion && codigo == 125 { alEvento?(.menu(.achicar)); return nil }
            if sinModificadores && (codigo == 36 || codigo == 76) { if !repite { alEvento?(.menu(.elegir)) }; return nil }
            if !repite { alEvento?(.menu(.otra)) }   // escribís otra cosa: se cierra y la tecla llega a la app
        }

        if tipo == .keyDown && capturaRespuesta && !repite {
            let escribe = !presionados.contains { ["cmd", "ctrl", "opcion"].contains($0.familia) }
            if escribe && (codigo == 36 || codigo == 76) && presionados.isEmpty {
                alEvento?(.confirmar)
                return nil
            }
            if escribe { alEvento?(.teclaSuelta) }
        }

        // Otra tecla mientras se sostiene un atajo de solo modificadores: era una combinación común.
        if tipo == .keyDown, let a = activa, atajos[a]?.soloModificadores == true, !otraTecla {
            otraTecla = true
            alEvento?(.anular(a))
        }
        return Unmanaged.passUnretained(e)
    }

    private func revisarModificadores(abajo: Bool, hora: TimeInterval) {
        if let a = activa, let atajo = atajos[a], atajo.soloModificadores {
            if !Set(atajo.modificadores).isSubset(of: presionados) {
                activa = nil
                if !otraTecla { alEvento?(.soltar(a, sostenido: hora - inicio)) }
            }
            return
        }
        guard abajo, activa == nil else { return }
        for (accion, atajo) in atajos where atajo.soloModificadores && Set(atajo.modificadores) == presionados {
            activa = accion; inicio = hora; otraTecla = false
            alEvento?(.apretar(accion))
            return
        }
    }
}
