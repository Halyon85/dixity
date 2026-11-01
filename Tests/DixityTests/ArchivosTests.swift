import Foundation
import Testing
@testable import Dixity

// Archivos de la carpeta de datos (Almacen.archivoPropio / borrarSueltos): nombres con "../" no salen de la carpeta
// y la limpieza no sigue enlaces. Auditoría de seguridad del 23/10/2026.
@Suite struct ArchivosPropios {
    init() { Ayudas.preparar() }

    private func carpetaTemporal() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("dixity-arch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func unNombreConBarrasNoSeUsa() {
        let c = URL(fileURLWithPath: "/tmp/x")
        #expect(Almacen.archivoPropio("../../Documents/x.wav", extension: "wav", en: c) == nil)
        #expect(Almacen.archivoPropio("\(UUID().uuidString).wav", extension: "wav", en: c) != nil)
        #expect(Historial.shared.audio(nombre: "../../../etc/hosts") == nil)
    }

    @Test func laLimpiezaNoVaciaLaCarpetaAdondeApuntaUnEnlace() throws {
        let base = try carpetaTemporal()
        let victima = base.appendingPathComponent("victima")
        try FileManager.default.createDirectory(at: victima, withIntermediateDirectories: true)
        try "importante".write(to: victima.appendingPathComponent("\(UUID().uuidString).png"), atomically: true, encoding: .utf8)
        let enlace = base.appendingPathComponent("Portapapeles")
        try FileManager.default.createSymbolicLink(at: enlace, withDestinationURL: victima)
        Almacen.borrarSueltos(en: enlace, extension: "png", vivos: [])
        #expect(try FileManager.default.contentsOfDirectory(atPath: victima.path).count == 1)
    }

    @Test func laLimpiezaSoloBorraArchivosPropios() throws {
        let c = try carpetaTemporal()
        let suelto = "\(UUID().uuidString).wav", vivo = "\(UUID().uuidString).wav"
        for n in [suelto, vivo, "notas.txt"] { try "x".write(to: c.appendingPathComponent(n), atomically: true, encoding: .utf8) }
        try FileManager.default.createDirectory(at: c.appendingPathComponent("sub"), withIntermediateDirectories: true)
        Almacen.borrarSueltos(en: c, extension: "wav", vivos: [vivo])
        let quedan = Set(try FileManager.default.contentsOfDirectory(atPath: c.path))
        #expect(quedan == [vivo, "notas.txt", "sub"])
    }
}
