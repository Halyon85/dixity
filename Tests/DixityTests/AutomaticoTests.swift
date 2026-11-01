import Foundation
import Testing
@testable import Dixity

// Modo automático con las apps y sitios sumados el 30/10/2026, gestores de contraseñas y emojis en Mensaje.
@Suite(.serialized) struct AutomaticoYGestores {
    init() { Ayudas.preparar() }

    private func leer(_ json: String) throws -> DatosAjustes {
        try JSONDecoder().decode(DatosAjustes.self, from: Data(json.utf8))
    }

    @Test func lasAppsNuevasSeSumanUnaVezYLasQueSacasteNoVuelven() throws {
        // Ajustes de antes del 30/10: sacaste "Spark" de Correo y sumaste "Fastmail".
        let viejo = try leer(#"{"appsCorreo": ["Mail", "Gmail", "Fastmail"], "appsMensaje": ["WhatsApp"], "appsTrabajo": ["Claude"]}"#)
        #expect(viejo.appsCorreo == ["Mail", "Gmail", "Fastmail"] + DatosAjustes.nuevasCorreo)
        #expect(viejo.appsMensaje.contains("Messenger") && viejo.appsTrabajo.contains("Gemini"))
        #expect(viejo.listasApps == 2)
        // Ya sumadas: si después sacás "Zoom", no vuelve.
        let nuevo = try leer(#"{"listasApps": 2, "appsMensaje": ["WhatsApp", "Messenger"]}"#)
        #expect(nuevo.appsMensaje == ["WhatsApp", "Messenger"])
    }

    @Test func reconoceAppsYPestanasNuevas() {
        let a = Ajustes.shared, antes = a.datos
        defer { a.datos = antes }
        a.datos = DatosAjustes()
        a.datos.estilo = .automatico
        func estilo(_ app: String, _ bundle: String = "", _ ventana: String = "") -> Estilo {
            a.estiloPara(ContextoCursor(app: app, bundle: bundle, ventana: ventana))
        }
        #expect(estilo("Mimestream") == .correo)
        #expect(estilo("Windsurf") == .trabajo)
        #expect(estilo("Dia", "company.thebrowser.dia", "Gemini") == .trabajo)
        #expect(estilo("Orion", "com.kagi.kagimacOS", "Bandeja de entrada | Proton Mail") == .correo)
        #expect(estilo("Arc", "company.thebrowser.Browser", "Messenger") == .mensaje)
        #expect(estilo("Notas") == .comun)
    }

    @Test func gestoresPorIdentificadorNombreYPestana() {
        #expect(Secretos.esGestor(bundle: "com.roboform.mac", app: "RoboForm", ventana: ""))
        #expect(Secretos.esGestor(bundle: "com.otra.cosa", app: "Keeper Password Manager", ventana: ""))
        #expect(Secretos.esGestor(bundle: "com.google.Chrome", app: "Google Chrome", ventana: "Administrador de contraseñas de Google"))
        #expect(Secretos.esGestor(bundle: "com.apple.Safari", app: "Safari", ventana: "Vaults | Bitwarden Web vault"))
        #expect(!Secretos.esGestor(bundle: "com.google.Chrome", app: "Google Chrome", ventana: "WhatsApp"))
        // Fuera del navegador, el título no cuenta (un documento que se llama "bitwarden.md").
        #expect(!Secretos.esGestor(bundle: "com.microsoft.VSCode", app: "Code", ventana: "bitwarden.md"))
    }

    @Test func emojisSoloEnMensajeYSiEstanPrendidos() {
        #expect(Prompts.formato(.mensaje, idioma: "", emojis: true).contains("Emojis"))
        // Se pide uno por mensaje (no "podés"), con ejemplo y los casos en que no va.
        #expect(Prompts.formato(.mensaje, idioma: "", emojis: true).contains("¿cómo estás? 😊"))
        #expect(Prompts.emojisMensaje.contains("terminá el mensaje con un emoji") && Prompts.emojisMensaje.contains("reclamo"))
        #expect(!Prompts.formato(.mensaje, idioma: "", emojis: false).lowercased().contains("emoji"))
        #expect(!Prompts.formato(.correo, idioma: "", emojis: true).lowercased().contains("emoji"))
        #expect(Prompts.barrera(transcripcion: "hola cómo estás", salida: "Hola, ¿cómo estás? 😊", estilo: .mensaje) == nil)
        // Un emoji sumado no lo frena la barrera.
        #expect(Prompts.barrera(transcripcion: "dale nos vemos mañana en la plaza", salida: "Dale, nos vemos mañana en la plaza 🙌",
                                estilo: .mensaje) == nil)
    }
}
