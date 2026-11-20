import Foundation
import Testing
@testable import Dixity

// El ayudante que lee la pantalla (20/11/2026): solo lo puede usar la propia Dixity.
@Suite struct AyudantePantallaPruebas {
    // Las pruebas las corre `swift test`, que no es Dixity: el ayudante tiene que negarse.
    @Test func otroProgramaNoPuedeUsarElAyudante() {
        #expect(AyudantePantalla.padreEsDixity() == false)
    }

    // El argumento del ayudante no es un modo de prueba con permisos: no muestra «¿Permitir?» porque se protege solo
    // (firma del que lo abre). Si alguien lo suma a esa lista, cada dictado preguntaría.
    @Test func elAyudanteNoPreguntaAntesDeLeer() {
        #expect(!Principal.modosConPermisos.contains(AyudantePantalla.argumento))
    }
}
