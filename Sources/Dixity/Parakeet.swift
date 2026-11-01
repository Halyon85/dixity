import FluidAudio
import CryptoKit
import Foundation

// Los tres Parakeet que entiende FluidAudio 0.17.7. Mismos 25 idiomas; cambian los pesos.
enum ModeloLocal: String, Codable, CaseIterable, Identifiable {
    // Medido el 21/10 con dictados reales: Ultra = v3 en velocidad y memoria y acierta un poco más. Redux (~200 MB)
    // se probó y se descartó (tarda el doble, más memoria, pierde puntuación): v3 quedó como el chico.
    case v3, ultra
    var id: String { rawValue }
    var version: AsrModelVersion {
        switch self {
        case .v3: .v3
        case .ultra: .ultra
        }
    }
    // Nombre de carpeta que usa FluidAudio para cada uno (su `folderName`, sin "-coreml").
    var carpeta: String {
        switch self {
        case .v3: "parakeet-tdt-0.6b-v3"
        case .ultra: "parakeet-ultra"
        }
    }
    var nombre: String {
        switch self {
        // Sin aclaraciones entre paréntesis: lo que rinde cada uno va en `rinde`, al lado.
        case .v3: "Parakeet v3"
        case .ultra: "Parakeet Ultra"
        }
    }
    var peso: String {
        switch self {
        case .v3: "~460 MB"
        case .ultra: "~600 MB"
        }
    }
    // Para elegir al bajarlo: qué tal anda cada uno.
    var rinde: String {
        switch self {
        case .v3: T("El más rápido y ocupa menos. Muy bueno; se equivoca un poco más que Ultra con el voseo y las palabras en inglés.", "The fastest and smallest. Very good; slightly more mistakes than Ultra with English words and regional Spanish.")
        case .ultra: T("El más preciso (voseo, comas, palabras en inglés) y igual de rápido. Recomendado.", "The most accurate (commas, English words, regional Spanish) and just as fast. Recommended.")
        }
    }
}

// Voz a texto local con Parakeet (multilenguaje, entiende español). Sin internet ni claves.
// El modelo se carga mientras hablás y se libera a los 3 minutos sin usarlo (volver a cargarlo tarda ~0,3 s).
actor Parakeet {
    static let shared = Parakeet()

    private var gestor: AsrManager?
    private var cargado: ModeloLocal?
    private var descarga: Task<Void, Never>?

    // Dónde buscar el modelo (no se descarga nada si ya está en la Mac).
    static func ubicaciones(_ m: ModeloLocal) -> [URL] {
        let soporte = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return [
            Almacen.carpeta.appendingPathComponent("Modelos/\(m.carpeta)"),
            soporte.appendingPathComponent("FluidAudio/Models/\(m.carpeta)"),
            AsrModels.defaultCacheDirectory(for: m.version),
        ]
    }

    static func encontrado(_ m: ModeloLocal) -> URL? {
        ubicaciones(m).first { AsrModels.modelsExist(at: $0, version: m.version) }
    }

    // El elegido en Proveedores.
    static var elegido: ModeloLocal { Ajustes.shared.datos.modeloLocal }
    static var modeloEncontrado: URL? { encontrado(elegido) }

    func cargar() async throws -> AsrManager {
        descarga?.cancel()
        programarDescarga()
        let m = Parakeet.elegido
        if let g = gestor, cargado == m { return g }
        if gestor != nil { await liberar() }     // cambiaste de modelo: se suelta el anterior
        guard let carpeta = Parakeet.encontrado(m) else { throw ErrorApp.sinModeloLocal }
        // Cargar nunca baja nada: si un modelo falla, FluidAudio lo borraba y lo volvía a bajar solo (también de la
        // carpeta de otra app) desde una versión que se puede cambiar. Bajar es solo con Descargar (auditoría 23/10/2026).
        if !Parakeet.descargando { ModelHub.offlineMode = true }
        let modelos = try await AsrModels.load(from: carpeta, version: m.version)
        let g = AsrManager(config: Parakeet.configuracion)
        try await g.loadModels(modelos)
        gestor = g
        cargado = m
        return g
    }

    // Cómo corta los audios largos (más de ~15 s). FluidAudio 0.17.7 cambió dos cosas que con v3 en español
    // empeoraban los dictados largos (mezclaba inglés/italiano y tardaba ~4 veces más). Medido el 21/10 con un
    // audio de 1,7 min: con contexto de mel y sin la pasada de reparación da el mismo texto que la versión de mayo.
    static let configuracion = ASRConfig(melChunkContext: true, seamGapRepair: false)

    func transcribir(pcm16: Data, idioma: Idioma) async throws -> String {
        let g = try await cargar()
        // Convierte a Float sin copias intermedias.
        let n = pcm16.count / 2
        var muestras = [Float](repeating: 0, count: n)
        pcm16.withUnsafeBytes { buf in
            let enteros = buf.bindMemory(to: Int16.self)
            for i in 0..<n { muestras[i] = Float(enteros[i]) / 32768 }
        }
        guard muestras.count > 16_000 / 4 else { return "" }
        var estado = TdtDecoderState.make()
        let lengua: Language? = idioma == .es ? .spanish : idioma == .en ? .english : nil
        let r = try await g.transcribe(muestras, decoderState: &estado, language: lengua)
        return r.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Baja el modelo a la carpeta de Dixity. Solo si el usuario lo pide. Lo bajado tiene que coincidir, archivo por
    // archivo, con las huellas de los modelos probados (HuellasModelos): Hugging Face sirve la rama "main", que su
    // dueño puede cambiar, y FluidAudio solo mira el tamaño. Si no coincide, se borra y no se usa.
    static private(set) var descargando = false
    static func descargar(_ m: ModeloLocal) async throws {
        let destino = Almacen.carpeta.appendingPathComponent("Modelos/\(m.carpeta)")
        descargando = true
        ModelHub.offlineMode = false
        defer { descargando = false; ModelHub.offlineMode = true }
        _ = try await AsrModels.download(to: destino, version: m.version)
        do { try verificar(destino, m) } catch {
            try? FileManager.default.removeItem(at: destino)
            throw error
        }
        // La 1.ª carga de un modelo tarda ~10 s (macOS lo prepara para el chip una sola vez): se hace ahora, no en el
        // primer dictado. Se suelta solo a los 3 minutos, como siempre.
        if m == elegido { _ = try? await shared.cargar() }
    }

    // Compara cada archivo de la carpeta con su huella. Falla si falta uno, si sobra uno o si alguno cambió.
    static func verificar(_ carpeta: URL, _ m: ModeloLocal) throws {
        guard let esperadas = HuellasModelos.porCarpeta[m.carpeta] else { throw ErrorApp.modeloDistinto(m.nombre) }
        let fm = FileManager.default
        var vistas = Set<String>()
        let enumerador = fm.enumerator(at: carpeta, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let u = enumerador?.nextObject() as? URL {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let relativa = String(u.standardizedFileURL.path.dropFirst(carpeta.standardizedFileURL.path.count + 1))
            guard let esperada = esperadas[relativa], let h = huella(u), h == esperada else { throw ErrorApp.modeloDistinto(m.nombre) }
            vistas.insert(relativa)
        }
        guard vistas == Set(esperadas.keys) else { throw ErrorApp.modeloDistinto(m.nombre) }
    }

    // SHA-256 de un archivo, leyéndolo de a pedazos (los pesos pasan los 400 MB).
    static func huella(_ u: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        var sha = SHA256()
        while let pedazo = try? h.read(upToCount: 4 << 20), !pedazo.isEmpty { sha.update(data: pedazo) }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func liberar() async {
        guard gestor != nil else { return }
        await gestor?.cleanup()
        gestor = nil
        cargado = nil
        // Le devuelve a macOS la memoria que quedó libre: si no, la app seguía marcando 80–90 MB un buen rato después
        // de soltar el modelo (eran páginas ya liberadas, sin pérdidas según `leaks`; medido el 30/10/2026).
        malloc_zone_pressure_relief(nil, 0)
    }

    private func programarDescarga() {
        descarga = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
            if !Task.isCancelled { await self?.liberar() }
        }
    }
}
