import Foundation
@testable import Dixity

// Ayudas compartidas de las pruebas. Toda suite que use algo con datos (Memoria, Historial, Diccionario, Ajustes…)
// llama a Ayudas.preparar() en su init: así la carpeta de datos es una temporal y nunca la de tu Mac, y no se guardan
// ajustes. Tiene que correr antes de que alguien toque Almacen.carpeta (se calcula una sola vez).
enum Ayudas {
    static let carpeta: URL = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("dixity-pruebas-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        setenv("DIXITY_CARPETA", u.path, 1)
        setenv("DIXITY_IDIOMA", "es", 1)
        Ajustes.soloLectura = true
        return u
    }()

    static func preparar() {
        _ = carpeta
        precondition(Almacen.carpeta.standardizedFileURL.path == carpeta.standardizedFileURL.path,
                     "Almacen.carpeta se calculó antes de las pruebas: no se usa la carpeta real")
    }

    // Un dictado de prueba.
    static func registro(_ dicho: String, final: String? = nil, modo: Registro.Modo = .dictado, app: String = "Prueba",
                         estilo: String? = "Común", usoIA: Bool = true) -> Registro {
        Registro(modo: modo, app: app, transcripcion: dicho, final: final ?? dicho, segundosAudio: 1, msVoz: 0, msIA: 0,
                 usoIA: usoIA, estilo: estilo)
    }
}
