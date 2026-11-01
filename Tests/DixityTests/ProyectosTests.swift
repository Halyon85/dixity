import Foundation
import Testing
@testable import Dixity

// Guías de proyecto (Proyectos.leer): solo se leen archivos del propio proyecto. Auditoría del 23/10/2026.
@Suite struct GuiasDeProyecto {
    init() { Ayudas.preparar() }

    // Arma <tmp>/repo y un archivo "secreto" afuera, con texto largo para que pase el mínimo de 80 caracteres.
    private func armar() throws -> (repo: URL, secreto: URL) {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("dixity-guia-\(UUID().uuidString)")
        let repo = raiz.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let secreto = raiz.appendingPathComponent("secreto.txt")
        try String(repeating: "CLAVE-PRIVADA-DE-PRUEBA ", count: 10).write(to: secreto, atomically: true, encoding: .utf8)
        return (repo, secreto)
    }

    @Test func elArrobaNoSaleDeLaCarpeta() throws {
        let (repo, _) = try armar()
        try "@../secreto.txt\n".write(to: repo.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        #expect(!Proyectos.contexto(de: repo).guia.contains("CLAVE-PRIVADA"))
    }

    @Test func unaGuiaQueEsEnlaceNoSeSigue() throws {
        let (repo, secreto) = try armar()
        try FileManager.default.createSymbolicLink(at: repo.appendingPathComponent("AGENTS.md"), withDestinationURL: secreto)
        #expect(!Proyectos.contexto(de: repo).guia.contains("CLAVE-PRIVADA"))
    }

    @Test func elArrobaAOtroArchivoDelProyectoSigueAndando() throws {
        let (repo, _) = try armar()
        try "@AGENTS.md\n".write(to: repo.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try String(repeating: "Guía del proyecto de prueba. ", count: 5).write(to: repo.appendingPathComponent("docs/guia.md"), atomically: true, encoding: .utf8)
        try "@docs/guia.md".write(to: repo.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        #expect(Proyectos.contexto(de: repo).guia.contains("Guía del proyecto de prueba"))
    }
}
