import AppKit
import Carbon

// Todo lo que Dixity hace para no tocar contraseñas, claves ni tokens: reconocerlos, taparlos antes de mandar texto a
// la IA y saber qué apps y qué marcas del portapapeles son de gestores de contraseñas. Lo usan Contexto (campo y texto
// alrededor del cursor), Pantalla (lo que se lee de la ventana), Portapapeles, Motor y el diccionario que aprende solo.
// Salió de la auditoría de seguridad del 23/10/2026.
enum Secretos {
    // ¿Parece una clave, un token, una contraseña o un mail? Prefijos de claves conocidas, tiras largas de letras y
    // números, una mezcla de mayúsculas, minúsculas y números (como una contraseña) o una arroba.
    static func pareceSecreto(_ p: String) -> Bool {
        let prefijos = ["sk-", "sk_", "pk_", "rk_", "ghp_", "gho_", "ghs_", "github_pat_", "xai-", "gsk_", "hf_",
                        "AKIA", "AIza", "eyJ", "xox", "glpat-"]
        if p.contains("@") || prefijos.contains(where: { p.hasPrefix($0) }) { return true }
        let letras = p.filter(\.isLetter).count, digitos = p.filter(\.isNumber).count
        if p.count >= 16 && letras > 0 && digitos > 0 { return true }
        let mayus = p.contains { $0.isUppercase }, minus = p.contains { $0.isLowercase }
        return p.count >= 8 && mayus && minus && digitos > 0 && digitos * 4 >= p.count
    }

    // Tapa en un texto lo que parece secreto (palabra por palabra) y lo que sigue a "contraseña:", "token=" y
    // parecidos en la misma línea. Se usa con el texto de la pantalla y del campo antes de mandarlo a la IA.
    static func tapar(_ texto: String) -> String {
        let rotulo = #"(?i)\b(contrase(ñ|n)a|password|passwd|clave|secret|secreto|token|api[ _-]?key|apikey)\b(\s*[:=]\s*)\S.*"#
        let lineas = texto.components(separatedBy: "\n").map { l in
            l.replacingOccurrences(of: rotulo, with: "$1$3[oculto]", options: .regularExpression)
        }
        return lineas.map { l in
            l.split(separator: " ", omittingEmptySubsequences: false).map { w in
                let limpio = w.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`«»“”()[]{}<>,;"))
                return pareceSecreto(limpio) && limpio.count >= 8 ? "[oculto]" : String(w)
            }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    // Gestores de contraseñas: con uno adelante no se lee la pantalla ni se guarda lo que copiás.
    static let gestores: Set<String> = ["com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop", "org.keepassxc.keepassxc", "net.antelle.keeweb", "com.apple.Passwords",
        "com.apple.keychainaccess", "com.dashlane.dashlanephonefinal", "com.lastpass.LastPass", "com.nordpass.macos.NordPass",
        "com.enpass.Enpass", "com.protonpass.mac", "com.1password.1password7", "com.keepassxc.keepassxc",
        "com.lastpass.LastPassMacDesktop", "com.roboform.mac", "com.nordpass.nordpass"]
    // Gestores cuyo identificador puede variar según de dónde se bajó (Keeper, RoboForm…): por el comienzo del nombre.
    static let nombresGestores = ["1password", "bitwarden", "keepassxc", "keeweb", "keeper", "roboform", "lastpass",
        "dashlane", "nordpass", "enpass", "proton pass"]
    // Gestores abiertos en el navegador, por el título de la pestaña: el de Google (passwords.google.com y el de
    // Chrome), las bóvedas web y "Contraseñas" de Safari en versiones viejas de macOS.
    static let paginasGestores = ["password manager", "contraseñas de google", "administrador de contraseñas",
        "gestor de contraseñas", "bitwarden", "1password", "lastpass", "dashlane", "nordpass", "keeper", "roboform",
        "proton pass"]

    // ¿Lo que está adelante es un gestor de contraseñas? Con uno adelante no se lee la pantalla ni se guarda lo que
    // copiás (Pantalla, Portapapeles). Si duda, dice que sí: lo peor que pasa es no leer una pestaña de más.
    static func esGestor(bundle: String, app: String, ventana: String) -> Bool {
        if gestores.contains(bundle) { return true }
        let nombre = app.lowercased()
        if nombresGestores.contains(where: { nombre.hasPrefix($0) }) { return true }
        guard Ajustes.navegadores.contains(bundle) else { return false }
        let titulo = ventana.lowercased()
        return paginasGestores.contains { titulo.contains($0) }
    }

    // Lo mismo para una app abierta: el título de la ventana solo se pide si es un navegador.
    static func esGestor(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        let bundle = app.bundleIdentifier ?? ""
        let ventana = Ajustes.navegadores.contains(bundle) ? Cursor.tituloVentana(pid: app.processIdentifier) : ""
        return esGestor(bundle: bundle, app: app.localizedName ?? "", ventana: ventana)
    }

    // Marcas del portapapeles que piden no guardar lo copiado (nspasteboard.org y las viejas que respetan otros
    // gestores del portapapeles).
    static let marcasPrivadas: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword", "com.apple.passwordmanager", "net.antelle.keeweb",
        "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping", "Pasteboard generator type"]

    // ¿Se está escribiendo una contraseña? El campo enfocado es de contraseña o macOS tiene la entrada segura prendida.
    static func campoSeguro(subrol: String) -> Bool {
        subrol == "AXSecureTextField" || IsSecureEventInputEnabled()
    }
}
