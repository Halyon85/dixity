import Foundation
import Testing
@testable import Dixity

// Modelos Parakeet (Parakeet.verificar): solo se acepta lo que coincide con las huellas probadas. Auditoría 23/10/2026.
@Suite struct ModelosVerificados {
    init() { Ayudas.preparar() }

    // Una copia de prueba con los nombres de v3 y contenido inventado: no coincide con ninguna huella.
    private func copiaFalsa(faltando: Bool = false) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("dixity-modelo-\(UUID().uuidString)")
        for (relativa, _) in HuellasModelos.porCarpeta["parakeet-tdt-0.6b-v3"]! {
            let f = u.appendingPathComponent(relativa)
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("falso".utf8).write(to: f)
        }
        return u
    }

    @Test func unModeloCambiadoSeRechaza() throws {
        let u = try copiaFalsa()
        #expect(throws: ErrorApp.self) { try Parakeet.verificar(u, .v3) }
    }

    @Test func lasHuellasCubrenLosDosModelos() {
        #expect(HuellasModelos.porCarpeta["parakeet-tdt-0.6b-v3"]?.keys.contains("parakeet_vocab.json") == true)
        #expect(HuellasModelos.porCarpeta["parakeet-ultra"]?.keys.contains("Encoder.mlmodelc/weights/weight.bin") == true)
    }

    @Test func elModeloInstaladoPasa() throws {
        // DIXITY_MODELO_REAL=<carpeta Modelos>: comprueba que los modelos que andan en esta Mac pasan la verificación.
        guard let base = ProcessInfo.processInfo.environment["DIXITY_MODELO_REAL"] else { return }
        for m in ModeloLocal.allCases {
            try Parakeet.verificar(URL(fileURLWithPath: base).appendingPathComponent(m.carpeta), m)
        }
    }
}
