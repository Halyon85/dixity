import Foundation

// Modo de prueba: `Dixity --medir <audio.wav>` pasa el mismo audio por cada proveedor de voz que tenga clave
// (o el modelo local) y el texto por cada IA, y muestra cuánto tardó cada uno. No toca los ajustes guardados.
enum Medir {
    static func correr(_ ruta: String) async {
        guard let wav = try? Data(contentsOf: URL(fileURLWithPath: ruta)) else { print("No pude leer \(ruta)"); return }
        let a = Ajustes.shared
        let original = a.datos
        defer { a.datos = original }
        // DICTA_IDIOMA=es|en|automatico: prueba con otro idioma sin tocar el guardado.
        if let i = ProcessInfo.processInfo.environment["DICTA_IDIOMA"].flatMap(Idioma.init(rawValue:)) { a.datos.idioma = i }
        print("== Voz a texto (\(String(format: "%.1f", Double(wav.count - 44) / 32_000)) s de audio)")
        var ultimoTexto = ""
        let soloIA = ProcessInfo.processInfo.environment["DICTA_SOLO_IA"] != nil
        for p in (soloIA ? [ProveedorVoz.parakeet, .apple] : [ProveedorVoz.parakeet, .apple, .grok, .openai, .groq]) {
            a.datos.proveedorVoz = p
            a.datos.modeloVoz = p.modeloSugerido
            if !p.local && a.claveVoz.isEmpty { print("- \(p.nombre): sin clave"); continue }
            // Parakeet: cada modelo local que esté en la Mac (o solo DICTA_MODELO=v3|redux|ultra).
            let soloModelo = ProcessInfo.processInfo.environment["DICTA_MODELO"].flatMap(ModeloLocal.init(rawValue:))
            if p == .apple && !VozApple.disponible { print("- \(p.nombre): no disponible"); continue }
            let locales: [ModeloLocal?] = p == .parakeet ? ModeloLocal.allCases.filter { (soloModelo == nil || $0 == soloModelo) && Parakeet.encontrado($0) != nil } : [nil]
            if p == .parakeet && locales.isEmpty { print("- \(p.nombre): sin modelo"); continue }
            for m in locales {
                if let m { a.datos.modeloLocal = m }
                let nombre = m.map { $0.nombre } ?? p.nombre
                for vuelta in 1...(p == .parakeet ? 2 : 1) {   // Parakeet: la 1.ª vuelta incluye cargar el modelo
                    let t = Date()
                    do {
                        let texto = try await Proveedores.transcribir(wav: wav, ajustes: a, pista: Diccionario.shared.pistaVoz)
                        let ms = Int(Date().timeIntervalSince(t) * 1000)
                        print("- \(nombre)\(p == .parakeet ? (vuelta == 1 ? " (cargando)" : " (cargado)") : ""): \(ms) ms → \(texto)")
                        if !texto.isEmpty { ultimoTexto = texto }
                    } catch { print("- \(nombre): error \(error.localizedDescription)") }
                }
            }
        }
        // DICTA_SOLO_VOZ=1: no pasa por la IA (para medir solo los modelos de voz).
        guard !ultimoTexto.isEmpty, ProcessInfo.processInfo.environment["DICTA_SOLO_VOZ"] == nil else { return }
        print("\n== Pasar en limpio")
        let modelos: [(ProveedorIA, String)] = [(.anthropic, "claude-haiku-5-5"), (.anthropic, "claude-opus-5-5"),
                                               (.openai, "gpt-6-luna"), (.openai, "gpt-4.1-mini"),
                                               (.grok, "grok-4.20-0309-non-reasoning"), (.apple, "apple-on-device")]
        for (estilo, sistema) in [("Común", Prompts.sistemaDictado), ("Trabajo", Prompts.sistemaTrabajo)] {
            print("-- \(estilo)")
            for (p, m) in modelos {
                a.datos.proveedorIA = p
                a.datos.modeloIA = m
                if !a.iaLista { print("- \(p.nombre) \(m): sin clave"); continue }
                let usuario = estilo == "Común"
                    ? Prompts.usuarioDictado(transcripcion: ultimoTexto, contexto: nil, terminos: [], extra: "")
                    : Prompts.usuarioTrabajo(transcripcion: ultimoTexto, contexto: nil, proyecto: nil, recientes: [], terminos: [], extra: "")
                let t = Date()
                do {
                    let r = Prompts.limpiarSalida(try await Proveedores.completar(sistema: sistema, usuario: usuario, ajustes: a))
                    let b = Prompts.barrera(transcripcion: ultimoTexto, salida: r, trabajo: estilo == "Trabajo")
                    print("- \(p.nombre) \(m): \(Int(Date().timeIntervalSince(t) * 1000)) ms\(b.map { " [BARRERA: \($0)]" } ?? " [pasa la barrera]") → \(r.replacingOccurrences(of: "\n", with: " ⏎ "))")
                } catch { print("- \(p.nombre) \(m): error \(error.localizedDescription)") }
            }
        }
    }

    // Memoria real del proceso (la misma cifra que "Physical footprint" de `leaks`).
    static func memoriaMB() -> Int {
        var info = task_vm_info_data_t()
        var n = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &n) }
        }
        return r == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
