import Foundation

// Registro de memoria (desde el 16/11/2026): después de varios días, Dixity llegaba a 330 MB y al reiniciarla volvía a
// 85 MB. La mayor parte era memoria «fuera» de la app (cobrada a ella pero sin usar, ~0,5 MB por dictado) y ninguna
// pieza probada por separado lo repetía. Este registro mide la memoria en cada paso de cada pedido y cada 30 minutos
// en reposo, para ver qué paso la deja. Una línea JSON por pedido en `registro-memoria.jsonl` (carpeta de datos).
// Nunca guarda texto, audio, nombres de apps ni nada de lo dictado: solo cifras, el tipo de pedido y los proveedores.
enum RegistroMemoria {
    static let archivo = Almacen.carpeta.appendingPathComponent("registro-memoria.jsonl")
    // Hasta ~2 MB (unos 5 mil pedidos); al pasarse queda la segunda mitad.
    private static let tope = 2_000_000
    private static let cola = DispatchQueue(label: "dixity.registro-memoria")
    // El pedido que se está midiendo: hay uno a la vez (el Motor no empieza otro mientras procesa). Al cerrarlo pasa
    // a `cerrados` hasta su foto de 25 s después: así un dictado seguido del otro no se pisan (16/11/2026).
    private static var actual: Medicion?
    private static var cerrados: [UUID: Medicion] = [:]
    private static var ultimoCerrado: UUID?
    private static var pedidos = 0
    private static var reloj: DispatchSourceTimer?
    private static let arranque = Date()

    private struct Medicion {
        let id = UUID()
        var que: String
        var datos: [String: Any] = [:]
        var pasos: [(String, Foto)] = []
    }

    /// La memoria del proceso en MB, separada como la muestra `footprint`. Se puede llamar desde cualquier hilo.
    struct Foto {
        var huella = 0.0       // lo que muestra el Monitor de Actividad (phys_footprint)
        var fuera = 0.0        // cobrada a Dixity pero fuera de su memoria normal: huella − interna − comprimida
        var interna = 0.0      // la memoria normal de la app (con el modelo de voz cargado, «fuera» se esconde acá)
        var comprimida = 0.0   // lo que macOS comprimió o mandó al disco
        var malloc = 0.0       // lo que el código tiene reservado de verdad (objetos vivos)
        var graficos = 0.0, red = 0.0, media = 0.0, neural = 0.0

        static func ahora() -> Foto {
            var info = task_vm_info_data_t()
            var n = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            let r = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &n) }
            }
            guard r == KERN_SUCCESS else { return Foto() }
            var estadistica = malloc_statistics_t()
            malloc_zone_statistics(nil, &estadistica)
            let mb = { (b: Double) in (b / 104_857.6).rounded() / 10 }   // bytes → MB con un decimal
            let dentro = Double(info.internal) + Double(info.compressed)
            return Foto(huella: mb(Double(info.phys_footprint)),
                        fuera: mb(max(0, Double(info.phys_footprint) - dentro)),
                        interna: mb(Double(info.internal)),
                        comprimida: mb(Double(info.compressed)),
                        malloc: mb(Double(estadistica.size_in_use)),
                        graficos: mb(Double(info.ledger_tag_graphics_footprint)),
                        red: mb(Double(info.ledger_tag_network_nonvolatile)),
                        media: mb(Double(info.ledger_tag_media_footprint)),
                        neural: mb(Double(info.ledger_tag_neural_footprint)))
        }

        var json: [String: Decimal] {
            ["huella": uno(huella), "fuera": uno(fuera), "interna": uno(interna), "comprimida": uno(comprimida), "malloc": uno(malloc),
             "graficos": uno(graficos), "red": uno(red), "media": uno(media), "neural": uno(neural)]
        }
    }

    /// Arranca la medición de un pedido (dictar, reescribir, preguntar, varita-…). Si quedó uno sin cerrar, se
    /// guarda como "sin cerrar" para no perderlo.
    static func empezar(_ que: String) {
        let foto = Foto.ahora()
        cola.async {
            if let viejo = actual { escribir(viejo, cierre: "sin cerrar") }
            pedidos += 1
            actual = Medicion(que: que, pasos: [("inicio", foto)])
        }
    }

    /// Un paso del pedido en curso. Sin pedido en curso (reprocesar desde el historial) no hace nada.
    static func paso(_ nombre: String) {
        let foto = Foto.ahora()
        cola.async { actual?.pasos.append((nombre, foto)) }
    }

    /// Datos sueltos del pedido (segundos de audio, proveedores, si leyó la pantalla…). Solo cifras y nombres fijos.
    static func anotar(_ datos: [String: Any]) {
        cola.async { actual?.datos.merge(datos) { _, nuevo in nuevo } }
    }

    /// Datos que llegan después de cerrar (el resultado del pegado, ~1 s más tarde): van al último pedido cerrado
    /// mientras no se haya escrito (25 s). Solo cifras y nombres fijos, como `anotar`.
    static func anotarAlCerrado(_ datos: [String: Any]) {
        cola.async {
            guard let id = ultimoCerrado, cerrados[id] != nil else { return }
            cerrados[id]?.datos.merge(datos) { _, nuevo in nuevo }
        }
    }

    /// Cierra el pedido: la última foto se saca 25 s después, cuando ya pasó la devolución de memoria del Motor
    /// (20 s), así se ve lo que de verdad queda. `como`: "ok", "error", "cancelado".
    static func cerrar(_ como: String) {
        cola.async {
            guard let m = actual else { return }
            actual = nil
            cerrados[m.id] = m
            ultimoCerrado = m.id
            cola.asyncAfter(deadline: .now() + 25) {
                guard var c = cerrados.removeValue(forKey: m.id) else { return }
                c.pasos.append(("asentado", Foto.ahora()))
                escribir(c, cierre: como)
            }
        }
    }

    /// Cada 30 minutos, una línea de reposo: muestra si crece sin usarla (portapapeles, sacudida, temporizadores).
    static func arrancarReposo() {
        cola.async {
            guard reloj == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: cola)
            t.schedule(deadline: .now() + 60, repeating: 1800, leeway: .seconds(60))
            t.setEventHandler {
                var linea: [String: Any] = ["fecha": fecha(), "que": "reposo", "horas": horasAbierta(), "pedidos": pedidos]
                linea["memoria"] = Foto.ahora().json
                guardar(linea)
            }
            t.resume()
            reloj = t
        }
    }

    // MARK: Escritura (siempre en `cola`)

    private static func escribir(_ m: Medicion, cierre: String) {
        var linea: [String: Any] = ["fecha": fecha(), "que": m.que, "cierre": cierre, "horas": horasAbierta(), "pedidos": pedidos]
        linea.merge(m.datos) { ya, _ in ya }
        // Cada paso con su foto entera, y cuánto cambió la huella y lo de «fuera» del inicio al final.
        var pasos: [[String: Any]] = []
        for (nombre, foto) in m.pasos {
            var p: [String: Any] = foto.json
            p["paso"] = nombre
            pasos.append(p)
        }
        linea["pasos"] = pasos
        if let primero = m.pasos.first?.1, let ultimo = m.pasos.last?.1 {
            linea["sube"] = uno(ultimo.huella - primero.huella)
            linea["subeFuera"] = uno(ultimo.fuera - primero.fuera)
        }
        guardar(linea)
    }

    private static func guardar(_ linea: [String: Any]) {
        guard var datos = try? JSONSerialization.data(withJSONObject: linea, options: [.sortedKeys]) else { return }
        datos.append(0x0A)
        let fm = FileManager.default
        if !fm.fileExists(atPath: archivo.path) { fm.createFile(atPath: archivo.path, contents: nil) }
        // Si falla escribir, se pierde esa línea y nada más: es un registro de diagnóstico, no datos de la persona.
        guard let h = try? FileHandle(forWritingTo: archivo) else { return }
        defer { try? h.close() }
        let tam = (try? h.seekToEnd()) ?? 0
        try? h.write(contentsOf: datos)
        if tam > UInt64(tope) { recortar() }
    }

    // Deja la segunda mitad del archivo, desde un salto de línea (así no queda una línea cortada).
    private static func recortar() {
        guard let todo = try? Data(contentsOf: archivo) else { return }
        let mitad = todo.count / 2
        guard let corte = todo[mitad...].firstIndex(of: 0x0A) else { return }
        try? Data(todo[(corte + 1)...]).write(to: archivo, options: .atomic)
    }

    private static func fecha() -> String { ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime]) }
    private static func horasAbierta() -> Decimal { uno(Date().timeIntervalSince(arranque) / 3600) }
    // Un decimal también en el archivo (con Double, JSONSerialization escribe 0.69999999999999996).
    static func uno(_ x: Double) -> Decimal { Decimal(string: String(format: "%.1f", x == 0 ? 0 : x)) ?? 0 }
}
