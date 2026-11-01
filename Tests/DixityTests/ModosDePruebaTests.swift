import Testing
@testable import Dixity

// Modos de prueba (Principal.modoConPermisos): los que usan permisos o claves piden confirmación. Auditoría 23/10/2026.
@Suite struct ModosDePrueba {
    init() { Ayudas.preparar() }

    @Test func losQueUsanPermisosPiden() {
        for m in ["--probar-pantalla", "--diagnostico-campo", "--probar-pegado", "--probar-trabajo", "--importar-claves", "--medir"] {
            #expect(Principal.modoConPermisos(["Dixity", m, "x"]) == m)
        }
    }

    @Test func losQueSoloDibujanOCalculanNo() {
        for m in ["--capturas", "--demo-pildora", "--probar-limpieza", "--probar-barrera", "--probar-teclas"] {
            #expect(Principal.modoConPermisos(["Dixity", m]) == nil)
        }
        #expect(Principal.modoConPermisos(["Dixity"]) == nil)
    }
}
