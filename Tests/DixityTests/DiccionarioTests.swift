import Testing
@testable import Dixity

// Diccionario que aprende solo (Sugerencias.aprender): nada de lo que se ve en pantalla ni de lo que escribe la IA
// puede cambiar dictados futuros ni salir de la Mac sin que lo aceptes. Auditoría de seguridad del 23/10/2026.
@Suite(.serialized) struct DiccionarioAprendeSolo {
    init() {
        Ayudas.preparar()
        Diccionario.shared.terminos = []
    }

    @Test func unaCorreccionDeLaIANoInstalaUnAliasSola() {
        let r = Ayudas.registro("el usuario quedó activo en el sistema", final: "El usuario quedó Inactivo en el sistema.")
        Sugerencias.shared.aprender(de: r, proyecto: nil)
        #expect(Diccionario.shared.aplicarAlias("dejalo activo por favor") == "dejalo activo por favor")
    }

    @Test func loDeLaPantallaNoEntraSoloAlDiccionario() {
        let c = ContextoCursor(app: "Chrome", ventana: "Zorvex9 · Zorvex9 · tablero")
        Sugerencias.shared.aprender(de: Ayudas.registro("anotá esto para mañana", usoIA: false), proyecto: nil, contexto: c)
        Sugerencias.shared.aprender(de: Ayudas.registro("y esto también para mañana", usoIA: false), proyecto: nil, contexto: c)
        #expect(!Diccionario.shared.terminos.contains { $0.texto == "Zorvex9" })
    }

    @Test func loQueParececlaveNiSiquieraSeSugiere() {
        let clave = "ghp_" + "DUMMYDUMMYDUMMYDUMMYDUMMYDUMMY1234"   // partida: así ningún buscador de claves la toma por real
        let c = ContextoCursor(app: "Terminal", antes: "export TOKEN " + clave + " " + clave + " jane.doe@corp.com")
        Sugerencias.shared.aprender(de: Ayudas.registro("listo ya lo exporté", usoIA: false), proyecto: nil, contexto: c)
        Sugerencias.shared.aprender(de: Ayudas.registro("listo ya lo exporté de nuevo", usoIA: false), proyecto: nil, contexto: c)
        let todo = Diccionario.shared.terminos.map(\.texto) + Sugerencias.shared.lista.map(\.texto)
        #expect(!todo.contains { $0.hasPrefix("ghp_") || $0.contains("@") })
    }

    @Test func lasPalabrasAprendidasSolasNoVanComoPistaALaVoz() {
        Diccionario.shared.agregar("Kubernetes")
        Diccionario.shared.agregar("Qlarn-x", automatico: true)
        #expect(Diccionario.shared.pistaVoz.contains("Kubernetes"))
        #expect(!Diccionario.shared.pistaVoz.contains("Qlarn-x"))
    }

    @Test func unAliasViejoAprendidoSoloNoSeAplica() {
        Diccionario.shared.agregar("Inactivo", alias: ["activo"], automatico: true)
        Diccionario.shared.agregar("Dixity", alias: ["dick city"])
        #expect(Diccionario.shared.aplicarAlias("quedó activo en dick city") == "quedó activo en Dixity")
    }

    @Test func sumarAManoUnaPalabraAprendidaSolaLaHaceTuya() {
        Diccionario.shared.agregar("Dixity", automatico: true)
        #expect(Diccionario.shared.aplicarAlias("probando dick city") == "probando dick city")
        Diccionario.shared.agregar("Dixity", alias: ["dick city"])
        #expect(Diccionario.shared.aplicarAlias("probando dick city") == "probando Dixity")
        // Y al revés no: aprenderla sola otra vez no le quita lo tuyo.
        Diccionario.shared.agregar("Dixity", automatico: true)
        #expect(Diccionario.shared.aplicarAlias("probando dick city") == "probando Dixity")
    }
}
