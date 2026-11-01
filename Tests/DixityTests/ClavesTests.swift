import Testing
@testable import Dixity

// Clave del proveedor compatible atada a su dirección (Ajustes.clave/guardarClave). Usa otro servicio del llavero
// para no tocar tus claves, y lo borra al terminar. Auditoría de seguridad del 23/10/2026.
@Suite(.serialized) struct ClaveAtadaALaDireccion {
    init() {
        Ayudas.preparar()
        Llavero.servicio = "team.halyon.dixity.pruebas"
        Llavero.servicioViejo = "team.halyon.dixity.pruebas.viejo"
    }

    // Cambio de identificador del 30/10/2026: las claves guardadas con el nombre viejo pasan solas al nuevo.
    @Test func lasClavesDelNombreViejoSeMudan() {
        let nuevo = Llavero.servicio
        defer { Llavero.servicio = nuevo; Llavero.guardar("openai", ""); Llavero.guardar("xai", "") }
        Llavero.servicio = Llavero.servicioViejo
        Llavero.guardar("openai", "sk-vieja")
        Llavero.guardar("xai", "xai-vieja")
        Llavero.servicio = nuevo
        Llavero.guardar("xai", "xai-nueva")   // si ya hay una nueva, gana la nueva

        Llavero.mudarDelServicioViejo()
        #expect(Llavero.leer("openai") == "sk-vieja")
        #expect(Llavero.leer("xai") == "xai-nueva")
        #expect(Llavero.leer("openai", servicio: Llavero.servicioViejo).isEmpty)
        #expect(Llavero.leer("xai", servicio: Llavero.servicioViejo).isEmpty)
    }

    @Test func siCambiaLaDireccionLaClaveNoSeUsa() {
        let a = Ajustes.shared, antes = a.datos
        let cuenta = ProveedorIA.personalizado.cuentaLlavero
        defer { a.datos = antes; Llavero.guardar(cuenta, ""); Llavero.guardar(cuenta + ".url", "") }
        a.datos.proveedorIA = .personalizado
        a.datos.urlIAPersonalizada = "https://mi-servidor.example/v1"
        a.guardarClave(cuenta, "clave-de-prueba-123")
        #expect(a.claveIA == "clave-de-prueba-123")
        a.datos.urlIAPersonalizada = "https://otro.example/v1"   // como si alguien editara ajustes.json
        #expect(a.claveIA.isEmpty)
    }

    @Test func lasClavesDeLosProveedoresConocidosNoCambian() {
        let cuenta = ProveedorIA.openai.cuentaLlavero
        defer { Llavero.guardar(cuenta, "") }
        Ajustes.shared.guardarClave(cuenta, "sk-prueba")
        #expect(Ajustes.shared.clave(cuenta) == "sk-prueba")
    }
}
