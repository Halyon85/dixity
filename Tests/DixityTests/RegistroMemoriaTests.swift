import Foundation
import Testing
@testable import Dixity

// Registro de memoria (16/11/2026): las cifras tienen sentido y una memoria reservada se ve en «malloc».
@Suite struct RegistroMemoriaPruebas {
    @Test func laFotoDeMemoriaTraeCifrasConSentido() {
        let f = RegistroMemoria.Foto.ahora()
        #expect(f.huella > 0)
        #expect(f.fuera >= 0)
        #expect(f.malloc > 0)
        #expect(f.huella >= f.comprimida)
        // Solo cifras: nada de texto en lo que se guarda.
        #expect(Set(f.json.keys) == ["huella", "fuera", "interna", "comprimida", "malloc", "graficos", "red", "media", "neural"])
    }

    @Test func unaReservaGrandeSeVeEnMalloc() {
        let antes = RegistroMemoria.Foto.ahora().malloc
        let bloque = UnsafeMutableRawPointer.allocate(byteCount: 50_000_000, alignment: 16)
        defer { bloque.deallocate() }
        bloque.initializeMemory(as: UInt8.self, repeating: 1, count: 50_000_000)
        #expect(RegistroMemoria.Foto.ahora().malloc - antes > 40)
    }
}
