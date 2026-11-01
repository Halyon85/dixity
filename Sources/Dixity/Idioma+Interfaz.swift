import Foundation

// Idioma de la interfaz: español o inglés (o el del sistema). Los textos se escriben juntos con T("…", "…"):
// así no hay archivos de traducción aparte y cada texto queda al lado de su versión en inglés.
enum IdiomaInterfaz: String, Codable, CaseIterable, Identifiable {
    case sistema, es, en
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .sistema: T("Como el sistema", "Same as system")
        case .es: "Español"
        case .en: "English"
        }
    }

    // DIXITY_IDIOMA=es|en fuerza uno (sirve para las capturas de prueba).
    static var actual: IdiomaInterfaz {
        if let e = ProcessInfo.processInfo.environment["DIXITY_IDIOMA"], let i = IdiomaInterfaz(rawValue: e), i != .sistema { return i }
        let elegido = Ajustes.shared.datos.idiomaInterfaz
        if elegido != .sistema { return elegido }
        let preferido = Locale.preferredLanguages.first?.prefix(2) ?? "es"
        return preferido == "es" ? .es : .en
    }

    // Para fechas y horas en el idioma de la interfaz ("hace 7 minutos" / "7 minutes ago").
    static var locale: Locale { Locale(identifier: actual == .en ? "en_US" : "es_AR") }
}

// Texto de la interfaz en el idioma elegido.
func T(_ es: String, _ en: String) -> String {
    IdiomaInterfaz.actual == .en ? en : es
}
