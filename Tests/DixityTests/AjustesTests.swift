import Testing
@testable import Dixity

// "Todo en la Mac" (Ajustes.todoLocal) solo cuando ninguna IA de la nube puede recibir nada. Auditoría del 23/10/2026.
@Suite(.serialized) struct TodoEnLaMac {
    init() { Ayudas.preparar() }

    @Test func conUnaIAEnLaNubeNoEsLocalAunqueLimpiarEsteApagado() {
        let a = Ajustes.shared, antes = a.datos
        defer { a.datos = antes }
        a.datos.proveedorVoz = .parakeet
        a.datos.proveedorIA = .openai
        a.datos.limpiarConIA = false
        #expect(!a.todoLocal)
        a.datos.proveedorIA = .ninguno
        #expect(a.todoLocal)
    }
}
