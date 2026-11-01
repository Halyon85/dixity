import Foundation
import SwiftUI
import Security

// Carpeta de datos: ~/Library/Application Support/Dixity (antes Dicta)
enum Almacen {
    static let carpeta: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // DIXITY_CARPETA=/ruta: otra carpeta de datos (para probar como una instalación nueva sin tocar la tuya).
        if let otra = ProcessInfo.processInfo.environment["DIXITY_CARPETA"] {
            let url = URL(fileURLWithPath: otra, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let url = base.appendingPathComponent("Dixity", isDirectory: true)
        // Versiones anteriores guardaban todo en "Dicta": se muda una vez, entera (modelos, historial, diccionario).
        let vieja = base.appendingPathComponent("Dicta", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) && fm.fileExists(atPath: vieja.path) { try? fm.moveItem(at: vieja, to: url) }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func leer<T: Decodable>(_ tipo: T.Type, _ archivo: String) -> T? {
        guard let datos = try? Data(contentsOf: carpeta.appendingPathComponent(archivo)) else { return nil }
        return try? JSONDecoder().decode(tipo, from: datos)
    }

    // Archivos propios de una subcarpeta (Audio, Portapapeles): solo los que tienen el nombre que les pone Dixity
    // (un UUID con su extensión). Los nombres vienen de historial.json y portapapeles.json, que cualquier programa
    // puede editar: con "../" hacían leer o mandar otro archivo de la Mac (auditoría del 23/10/2026).
    static func archivoPropio(_ nombre: String, extension ext: String, en carpeta: URL) -> URL? {
        guard nombre.hasSuffix("." + ext), UUID(uuidString: String(nombre.dropLast(ext.count + 1))) != nil else { return nil }
        return carpeta.appendingPathComponent(nombre)
    }

    // Borra de una subcarpeta los archivos propios que no están en `vivos`. No hace nada si la subcarpeta es un enlace
    // (otro programa podría apuntarla a Documentos y Dixity la vaciaría) y nunca borra carpetas ni archivos ajenos.
    static func borrarSueltos(en carpeta: URL, extension ext: String, vivos: Set<String>) {
        let fm = FileManager.default
        guard let v = try? carpeta.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
              v.isSymbolicLink == false, v.isDirectory == true else { return }
        for nombre in (try? fm.contentsOfDirectory(atPath: carpeta.path)) ?? [] where !vivos.contains(nombre) {
            guard let u = archivoPropio(nombre, extension: ext, en: carpeta),
                  (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            try? fm.removeItem(at: u)
        }
    }

    static func guardar<T: Encodable>(_ valor: T, _ archivo: String) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let datos = try? enc.encode(valor) else { return }
        try? datos.write(to: carpeta.appendingPathComponent(archivo), options: .atomic)
    }
}

// Claves de API en el llavero de la Mac (nunca en archivos).
enum Llavero {
    static var servicio = "team.halyon.dixity"     // las pruebas usan otro, para no tocar tus claves
    // Hasta el 30/10/2026 la app se identificaba como team.halyon.dicta y guardaba las claves con ese nombre.
    static var servicioViejo = "team.halyon.dicta"

    static func leer(_ cuenta: String, servicio: String = servicio) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: servicio,
                                kSecAttrAccount as String: cuenta,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var res: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &res) == errSecSuccess,
              let datos = res as? Data else { return "" }
        return String(data: datos, encoding: .utf8) ?? ""
    }

    static func guardar(_ cuenta: String, _ valor: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: servicio,
                                   kSecAttrAccount as String: cuenta]
        SecItemDelete(base as CFDictionary)
        let limpio = valor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }
        var nuevo = base
        nuevo[kSecValueData as String] = Data(limpio.utf8)
        nuevo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(nuevo as CFDictionary, nil)
    }

    // Pasa las claves guardadas con el nombre viejo al nuevo. La llama la app al arrancar, antes de mirar si faltan
    // claves. Listar no pide permiso; leer cada una sí puede (macOS pregunta una vez porque cambió el nombre de la
    // app). A propósito: la vieja se borra solo si se pudo leer, así nunca se pierde una clave. Sin claves viejas,
    // no hace nada.
    static func mudarDelServicioViejo() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: servicioViejo,
                                kSecReturnAttributes as String: true,
                                kSecMatchLimit as String: kSecMatchLimitAll]
        var res: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &res) == errSecSuccess,
              let items = res as? [[String: Any]] else { return }
        for cuenta in items.compactMap({ $0[kSecAttrAccount as String] as? String }) {
            let valor = leer(cuenta, servicio: servicioViejo)
            guard !valor.isEmpty else { continue }
            if leer(cuenta).isEmpty { guardar(cuenta, valor) }
            let vieja: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                        kSecAttrService as String: servicioViejo,
                                        kSecAttrAccount as String: cuenta]
            SecItemDelete(vieja as CFDictionary)
        }
    }
}

// Proveedores de voz a texto.
enum ProveedorVoz: String, Codable, CaseIterable, Identifiable {
    case parakeet, apple, grok, openai, groq, personalizado
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .parakeet: T("Parakeet (local, sin internet)", "Parakeet (local, offline)")
        case .apple: T("Apple (de la Mac, sin internet)", "Apple (on this Mac, offline)")
        case .grok: "Grok (xAI)"
        case .openai: "OpenAI"
        case .groq: "Groq (Whisper)"
        case .personalizado: T("Compatible con OpenAI", "OpenAI-compatible")
        }
    }
    var modeloSugerido: String {
        switch self {
        case .parakeet: "parakeet-tdt-0.6b-v3"
        case .apple: "SpeechAnalyzer"
        case .grok: "grok-voice-transcribe-2.0"
        case .openai: "gpt-4o-mini-transcribe"
        case .groq: "whisper-large-v3-turbo"
        case .personalizado: "whisper-1"
        }
    }
    var modelos: [String] {
        switch self {
        case .parakeet, .apple: []
        case .grok: ["grok-voice-transcribe-2.0"]
        case .openai: ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "gpt-transcribe", "whisper-1"]
        case .groq: ["whisper-large-v3-turbo", "whisper-large-v3"]
        case .personalizado: []
        }
    }
    var urlBase: String {
        switch self {
        case .parakeet, .apple: ""
        case .grok: "https://api.x.ai/v1"
        case .openai: "https://api.openai.com/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .personalizado: ""
        }
    }
    var local: Bool { self == .parakeet || self == .apple }
    var paginaClave: URL? {
        switch self {
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .grok: URL(string: "https://console.x.ai")
        case .groq: URL(string: "https://console.groq.com/keys")
        default: nil
        }
    }   // sin internet ni clave
    // Una clave por empresa: la de OpenAI o la de Grok sirven para voz y para texto.
    var cuentaLlavero: String {
        switch self {
        case .grok: "xai"
        case .personalizado: "voz.personalizado"
        default: rawValue
        }
    }
}

// Proveedores de IA para pasar en limpio y reescribir.
enum ProveedorIA: String, Codable, CaseIterable, Identifiable {
    case anthropic, openai, grok, groq, openrouter, apple, personalizado, ninguno
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .anthropic: "Claude (Anthropic)"
        case .grok: "Grok (xAI)"
        case .openai: "OpenAI"
        case .groq: "Groq"
        case .openrouter: "OpenRouter"
        case .apple: T("Apple (en la Mac, sin clave)", "Apple (on this Mac, no key)")
        case .personalizado: T("Compatible con OpenAI", "OpenAI-compatible")
        case .ninguno: T("Sin limpieza (texto tal cual)", "No clean-up (raw text)")
        }
    }
    var modeloSugerido: String {
        switch self {
        case .anthropic: "claude-haiku-5-5"
        case .grok: "grok-4.20-0309-non-reasoning"
        case .openai: "gpt-6-luna"
        case .groq: "llama-3.3-70b-versatile"
        case .openrouter: "anthropic/claude-haiku-5.5"
        case .apple: "apple-on-device"
        case .personalizado, .ninguno: ""
        }
    }
    var modelos: [String] {
        switch self {
        case .anthropic: ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]
        case .grok: ["grok-4.20-0309-non-reasoning", "grok-4.7", "grok-4.3"]
        case .openai: ["gpt-6-luna", "gpt-4.1-mini", "gpt-6-sol"]
        case .groq: ["llama-3.3-70b-versatile", "openai/gpt-oss-120b", "openai/gpt-oss-20b"]
        default: []
        }
    }
    var urlBase: String {
        switch self {
        case .anthropic: "https://api.anthropic.com/v1"
        case .grok: "https://api.x.ai/v1"
        case .openai: "https://api.openai.com/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .openrouter: "https://openrouter.ai/api/v1"
        case .apple, .personalizado, .ninguno: ""
        }
    }
    // Donde se crea la cuenta y la clave (21/10: OpenAI y xAI devuelven 403 a los robots, pero son esas).
    var paginaClave: URL? {
        switch self {
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")
        case .grok: URL(string: "https://console.x.ai")
        case .groq: URL(string: "https://console.groq.com/keys")
        case .openrouter: URL(string: "https://openrouter.ai/settings/keys")
        default: nil
        }
    }
    // Puede mirar imágenes (Describir, Sacar prompt y Preguntar sobre una imagen en la Varita): los modelos de estos
    // cuatro las aceptan. Groq (Llama), la de Apple y una compatible cualquiera no, o no se sabe: ahí la Varita
    // describe con lo que se puede en la Mac.
    var veImagenes: Bool { [.anthropic, .openai, .grok, .openrouter].contains(self) }
    var cuentaLlavero: String {
        switch self {
        case .grok: "xai"
        case .personalizado: "ia.personalizado"
        default: rawValue
        }
    }
}

enum Idioma: String, Codable, CaseIterable, Identifiable {
    case automatico, es, en
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .automatico: T("Automático", "Automatic")
        case .es: T("Español", "Spanish")
        case .en: T("Inglés", "English")
        }
    }
}

enum Apariencia: String, Codable, CaseIterable, Identifiable {
    case sistema, claro, oscuro
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .sistema: T("Como el sistema", "Same as system")
        case .claro: T("Claro", "Light")
        case .oscuro: T("Oscuro", "Dark")
        }
    }
}

// Cómo pasa en limpio: Común (todos los días) o Trabajo (arma un prompt para Claude/Codex).
enum Estilo: String, Codable, CaseIterable, Identifiable {
    case automatico, comun, trabajo, correo, mensaje, formal, traducir
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .automatico: T("Automático según la app", "Automatic by app")
        case .comun: T("Común", "Standard")
        case .trabajo: T("Prompt para IA (Claude, ChatGPT, Codex…)", "AI prompt (Claude, ChatGPT, Codex…)")
        case .correo: T("Correo", "Email")
        case .mensaje: T("Mensaje (chat)", "Message (chat)")
        case .formal: T("Formal", "Formal")
        case .traducir: T("Traducir", "Translate")
        }
    }
    // Nombre corto para mostrar (píldora, historial, menú), en el idioma de la interfaz.
    var etiqueta: String {
        switch self {
        case .automatico: T("Automático", "Automatic")
        case .comun: T("Común", "Standard")
        case .trabajo: T("Prompt", "Prompt")
        case .correo: T("Correo", "Email")
        case .mensaje: T("Mensaje", "Message")
        case .formal: T("Formal", "Formal")
        case .traducir: T("Traducir", "Translate")
        }
    }
    // Cómo se anota en el historial (valor guardado: no se traduce; para mostrar, `etiqueta`).
    var corto: String {
        switch self {
        case .automatico: "Automático"
        case .comun: "Común"
        case .trabajo: "Trabajo"
        case .correo: "Correo"
        case .mensaje: "Mensaje"
        case .formal: "Formal"
        case .traducir: "Traducir"
        }
    }
    static func desde(corto: String?) -> Estilo? { allCases.first { $0.corto == corto } }
    static let elegibles: [Estilo] = [.comun, .trabajo, .correo, .mensaje, .formal, .traducir]
}

// Cada modo: su color en la píldora, si aparece y su lugar (la posición es su número: ⌃⌥1, ⌃⌥2…).
// Instrucción para una app o un sitio ("LinkedIn": "tono profesional"). Se suma a las preferencias generales.
struct InstruccionApp: Codable, Equatable, Identifiable {
    var id = UUID()
    var app: String       // parte del nombre de la app o, en el navegador, del título de la pestaña
    var texto: String
    static let tope = 500        // caracteres por instrucción
    static let maximo = 30
}

// Acción rápida: con texto seleccionado, un atajo lo reescribe con una instrucción fija, sin hablar (30/10/2026).
struct AccionRapida: Codable, Equatable, Identifiable {
    var id = UUID()
    var nombre: String
    var instruccion: String
    var atajo: Atajo? = nil
    static let maximo = 9

    // A propósito sin T(): se arman mientras se cargan los ajustes y T() lee los ajustes, así que la app se trababa
    // al abrir (30/10/2026). Van en el idioma de la Mac, que es el que tiene la interfaz la primera vez.
    static var predeterminadas: [AccionRapida] {
        let es = Locale.preferredLanguages.first?.hasPrefix("es") ?? true
        func t(_ a: String, _ b: String) -> String { es ? a : b }
        return [
            AccionRapida(nombre: t("Ordenar", "Tidy up"),
                         instruccion: t("Ordená y reacomodá este texto para que se entienda mejor: corregí ortografía y puntuación y armá párrafos, sin cambiar lo que dice ni el tono.",
                                        "Tidy up and reorganize this text so it reads better: fix spelling and punctuation and add paragraphs, without changing what it says or its tone."),
                         atajo: Atajo(modificadores: [.ctrlIzq, .opcionIzq], tecla: 31)),    // ⌃⌥O
            AccionRapida(nombre: t("Resumir", "Summarize"),
                         instruccion: t("Resumí este texto en pocas líneas, con lo importante, en el mismo idioma.",
                                        "Summarize this text in a few lines, keeping what matters, in the same language."),
                         atajo: Atajo(modificadores: [.ctrlIzq, .opcionIzq], tecla: 1)),     // ⌃⌥S
            AccionRapida(nombre: t("Corregir", "Proofread"),
                         instruccion: t("Corregí solo ortografía, tildes y puntuación. No cambies palabras ni el orden.",
                                        "Fix only spelling and punctuation. Don't change words or their order.")),
        ]
    }
}

struct ConfigModo: Codable, Equatable, Identifiable {
    var estilo: Estilo
    var color: UInt32
    var activo = true
    var atajo: Atajo? = nil      // atajo propio, además de combinación + número
    var id: String { estilo.rawValue }

    static let predeterminados: [ConfigModo] = [
        ConfigModo(estilo: .comun, color: 0xF56138),      // coral
        ConfigModo(estilo: .trabajo, color: 0x8B5CF6),    // violeta
        ConfigModo(estilo: .correo, color: 0x3B82F6),     // azul
        ConfigModo(estilo: .mensaje, color: 0x22C55E),    // verde
        ConfigModo(estilo: .formal, color: 0x64748B),     // gris pizarra
        ConfigModo(estilo: .traducir, color: 0xF59E0B),   // ámbar
    ]

    // Deja la lista sana: cada modo una vez y ninguno perdido (por si cambia la versión).
    static func normalizar(_ l: [ConfigModo]) -> [ConfigModo] {
        var vistos = Set<Estilo>()
        var r = l.filter { Estilo.elegibles.contains($0.estilo) && vistos.insert($0.estilo).inserted }
        for p in predeterminados where !vistos.contains(p.estilo) { r.append(p) }
        if !r.contains(where: \.activo) { r[0].activo = true }
        return r
    }
}

// Con qué se aprieta el número para elegir modo. fn quedó como opción y no por defecto: en teclados Bluetooth
// (Logitech y otros) fn + 1/2/3 cambia de equipo.
enum TeclaModos: String, Codable, CaseIterable, Identifiable {
    case ctrlOpcion, ctrlShift, cmdOpcion, fn
    var id: String { rawValue }
    var familias: Set<String> {
        switch self {
        case .ctrlOpcion: ["ctrl", "opcion"]
        case .ctrlShift: ["ctrl", "shift"]
        case .cmdOpcion: ["cmd", "opcion"]
        case .fn: ["fn"]
        }
    }
    var simbolo: String {
        switch self {
        case .ctrlOpcion: "⌃⌥"
        case .ctrlShift: "⌃⇧"
        case .cmdOpcion: "⌘⌥"
        case .fn: "fn "
        }
    }
    var nombre: String {
        switch self {
        case .ctrlOpcion: T("⌃⌥ Control + Opción", "⌃⌥ Control + Option")
        case .ctrlShift: "⌃⇧ Control + Shift"
        case .cmdOpcion: T("⌘⌥ Cmd + Opción", "⌘⌥ Cmd + Option")
        case .fn: T("fn (ojo con teclados Bluetooth)", "fn (careful with Bluetooth keyboards)")
        }
    }
}

// Qué tecla manda Dixity después de pegar (para enviar el prompt o el mensaje sin tocar nada).
enum TeclaEnviar: String, Codable, CaseIterable, Identifiable {
    case ninguna, enter, shiftEnter, cmdEnter
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .ninguna: T("Nada", "Nothing")
        case .enter: "↩ Enter"
        case .shiftEnter: "⇧↩ Shift + Enter"
        case .cmdEnter: "⌘↩ Cmd + Enter"
        }
    }
}

enum ModoTecla: String, Codable, CaseIterable, Identifiable {
    case ambos, mantener, alternar
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .ambos: T("Las dos: tocar o mantener", "Both: tap or hold")
        case .mantener: T("Apretar y soltar (al soltar, pega)", "Hold and release (pastes on release)")
        case .alternar: T("Un toque empieza, otro termina", "Tap to start, tap to stop")
        }
    }
    // En "Las dos": si soltás antes de esto fue un toque (sigue grabando); si no, mantuviste (termina). Medio segundo se siente natural.
    static let toqueMaximo: TimeInterval = 0.5
}

// Cuánto espera la Varita sin que la uses antes de apagarse sola.
enum ApagadoVarita: Int, Codable, CaseIterable, Identifiable {
    case quince = 15, treinta = 30, minuto = 60, nunca = 0
    var id: Int { rawValue }
    var nombre: String {
        switch self {
        case .quince: T("A los 15 segundos", "After 15 seconds")
        case .treinta: T("A los 30 segundos", "After 30 seconds")
        case .minuto: T("Al minuto", "After 1 minute")
        case .nunca: T("Nunca (con Esc)", "Never (use Esc)")
        }
    }
}

enum EstiloPildora: String, Codable, CaseIterable, Identifiable {
    case automatica, clara, oscura, vidrio, cristal
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .automatica: T("Automática (contraste con el sistema)", "Automatic (contrasts with system)")
        case .clara: T("Clara", "Light")
        case .oscura: T("Oscura", "Dark")
        case .vidrio: T("Vidrio (deja ver lo de atrás)", "Glass (see-through)")
        case .cristal: T("Cristal 3D (Liquid Glass)", "3D Glass (Liquid Glass)")
        }
    }
}

enum TamanoPildora: String, Codable, CaseIterable, Identifiable {
    case chica, normal, grande
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .chica: T("Chica", "Small")
        case .normal: T("Normal", "Medium")
        case .grande: T("Grande", "Large")
        }
    }
    var escala: CGFloat {
        switch self {
        case .chica: 0.85
        case .normal: 1
        case .grande: 1.2
        }
    }
}

struct DatosAjustes: Codable, Equatable {
    var atajoDictar: Atajo = .dictarPredeterminado
    var atajoReescribir: Atajo = .reescribirPredeterminado
    var idioma: Idioma = .automatico
    var mirarVentana = true
    var bienvenidaVista = false               // la bienvenida de la primera vez (Panel/Bienvenida.swift)
    var memoriaActiva = true                 // memoria propia en memoria.md (Memoria.swift)
    var leerPantalla = true                   // texto de la ventana con Vision (necesita Grabación de pantalla)
    var sonidoAlEmpezar = true
    var limpiarConIA = true
    var apariencia: Apariencia = .sistema
    var idiomaInterfaz: IdiomaInterfaz = .sistema
    // Instalación nueva: anda sin ninguna API. Voz con el motor de la Mac (no hay que bajar nada) y limpieza con
    // Apple Intelligence si está; si no, Parakeet (se baja una vez) y texto tal cual. Cada uno suma sus claves después.
    var proveedorVoz: ProveedorVoz = VozApple.disponible ? .apple : .parakeet
    var modeloVoz = ProveedorVoz.parakeet.modeloSugerido
    var modeloLocal: ModeloLocal = .ultra
    var urlVozPersonalizada = ""
    var proveedorIA: ProveedorIA = IAApple.disponible ? .apple : .ninguno
    var modeloIA = (IAApple.disponible ? ProveedorIA.apple : ProveedorIA.ninguno).modeloSugerido   // con clave: gpt-6-luna sin razonamiento es el que mejor acomoda (21/10); Haiku 5.5, el rápido
    var urlIAPersonalizada = ""
    var instruccionesExtra = ""
    var atajoPortapapeles: Atajo = .portapapelesPredeterminado
    var portapapelesActivo = true
    var estilo: Estilo = .automatico
    var appsTrabajo = ["Claude", "Terminal", "iTerm", "Warp", "Ghostty", "Cursor", "Code", "Codex", "ChatGPT",
                       "Antigravity", "Orca", "Zed", "Xcode"] + DatosAjustes.nuevasTrabajo
    var appsCorreo = ["Mail", "Outlook", "Spark", "Gmail", "Superhuman", "Airmail"] + DatosAjustes.nuevasCorreo
    var appsMensaje = ["WhatsApp", "Slack", "Telegram", "Mensajes", "Messages", "Discord", "Signal", "Teams"] + DatosAjustes.nuevasMensaje
    // Apps y sitios sumados el 30/10/2026. En el navegador valen por el título de la pestaña ("Gemini", "Proton Mail").
    // Se dejaron afuera nombres que aparecen dentro de otras palabras o títulos (HEY, Canary, LINE, Hyper, v0).
    static let nuevasTrabajo = ["Windsurf", "Kiro", "Trae", "IntelliJ", "PyCharm", "WebStorm", "Android Studio", "Fleet",
                                "Sublime Text", "kitty", "Alacritty", "WezTerm", "Tabby", "Gemini", "Grok", "Perplexity",
                                "DeepSeek", "Copilot", "Lovable", "Replit"]
    static let nuevasCorreo = ["Mimestream", "Proton Mail", "Thunderbird", "iCloud Mail", "Yahoo Mail"]
    static let nuevasMensaje = ["Messenger", "Beeper", "Google Chat", "Zoom", "Element", "Viber", "Skype", "WeChat"]
    // 1: las listas de antes del 30/10. 2: con las apps nuevas. Sirve para sumarlas una sola vez a tus listas guardadas.
    var listasApps = 2
    var emojisMensaje = true                  // en modo Mensaje, la IA puede sumar uno o dos emojis que acompañen
    var instruccionesApp: [InstruccionApp] = []   // se eligen en Voz › Pasar en limpio (Ajustes.instruccionPara)
    var acciones: [AccionRapida] = AccionRapida.predeterminadas   // se eligen en Modos › Acciones rápidas
    var idiomaTraduccion = ""                // vacío = inglés (o español si la interfaz está en inglés); ver idiomaDestino
    var enviarTrabajo: TeclaEnviar = .ninguna   // después de pegar en modo Trabajo
    var enviarMensaje: TeclaEnviar = .ninguna   // después de pegar en modo Mensaje
    var teclaModos: TeclaModos = .ctrlOpcion
    var modos: [ConfigModo] = ConfigModo.predeterminados
    var atajoAutomatico: Atajo? = nil         // atajo propio para volver a Automático (además de combinación + 0)
    var numerosGrabando = true                // mientras grabás, 1…9 cambian el modo
    var atajosNumero = true                   // fn + 1…6 dicta en ese modo; mientras grabás, 1…6 lo cambia
    var carpetasProyectos: [String] = []      // se eligen en Modos › Proyectos
    var carpetasMarketing: [String] = []      // Modos › Proyectos: de dónde sale la marca al pedir un posteo (Posteos)
    var sacudirMouse = true                   // sacudir el mouse abre el menú junto al cursor (Atajos)
    var sensibilidadSacudida: DetectorSacudida.Sensibilidad = .media
    var leerConOpenAI = false                 // la Varita lee en voz alta con la voz de OpenAI (cuesta: se elige a propósito)
    // La Varita (página Varita del panel).
    var varitaApagado: ApagadoVarita = .treinta   // se apaga sola si no la usás este rato
    var varitaFlecha = true                   // la flecha del sistema se vuelve la de la Varita (FlechaVarita)
    var varitaReemplaza = true                // donde se puede escribir, traducir/reformular/corregir lo cambia ahí mismo
    var varitaAgentes = true                  // ofrece Mandar a Claude / Codex y Preguntale a Claude
    var varitaQR = true                       // mira si las imágenes tienen un QR para ofrecer leerlo
    var modoTecla: ModoTecla = .ambos
    var estiloPildora: EstiloPildora = .automatica
    var opacidadPildora: Double = 1
    var tamanoPildora: TamanoPildora = .normal
    var posicionPildora: [Double]? = nil      // esquina de la ventanita, si la moviste
    var aprenderSolo = true                   // suma solo lo seguro; lo de pantalla y los alias quedan como sugerencia (Sugerencias.registrar)
    var microfono = ""                        // identificador del micrófono elegido; vacío = el de la Mac (sistema)
    var pausarMusica = false                  // pausa lo que suena mientras dictás (Musica.swift)
    var limpiezaBasica = true                 // sin IA: saca muletillas y marcas como [música] (Prompts.limpiezaBasica)
    var atajoReprocesar: Atajo = .reprocesarPredeterminado
    var atajoSumarPalabra: Atajo = .sumarPalabraPredeterminado
    var atajoPreguntar: Atajo = .preguntarPredeterminado   // la respuesta se ve antes de pegar (Motor.mostrarRespuesta)

    init() {}

    // Si mañana sumamos campos, los archivos viejos siguen abriendo.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ actual: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil ?? actual }
        atajoDictar = v(.atajoDictar, atajoDictar)
        atajoReescribir = v(.atajoReescribir, atajoReescribir)
        idioma = v(.idioma, idioma)
        mirarVentana = v(.mirarVentana, mirarVentana)
        leerPantalla = v(.leerPantalla, leerPantalla)
        memoriaActiva = v(.memoriaActiva, memoriaActiva)
        bienvenidaVista = v(.bienvenidaVista, true)   // quien ya tenía ajustes no la ve sola (está en General)
        sonidoAlEmpezar = v(.sonidoAlEmpezar, sonidoAlEmpezar)
        limpiarConIA = v(.limpiarConIA, limpiarConIA)
        apariencia = v(.apariencia, apariencia)
        proveedorVoz = v(.proveedorVoz, proveedorVoz)
        modeloVoz = v(.modeloVoz, modeloVoz)
        // Un proveedor que ya no existe (p. ej. ElevenLabs) cae en el de por defecto, con su modelo.
        if let viejo = try? c.decodeIfPresent(String.self, forKey: .proveedorVoz), ProveedorVoz(rawValue: viejo) == nil {
            modeloVoz = proveedorVoz.modeloSugerido
        }
        urlVozPersonalizada = v(.urlVozPersonalizada, urlVozPersonalizada)
        proveedorIA = v(.proveedorIA, proveedorIA)
        modeloIA = v(.modeloIA, modeloIA)
        urlIAPersonalizada = v(.urlIAPersonalizada, urlIAPersonalizada)
        instruccionesExtra = v(.instruccionesExtra, instruccionesExtra)
        atajoPortapapeles = v(.atajoPortapapeles, atajoPortapapeles)
        portapapelesActivo = v(.portapapelesActivo, portapapelesActivo)
        estilo = v(.estilo, estilo)
        appsTrabajo = v(.appsTrabajo, appsTrabajo)
        carpetasProyectos = v(.carpetasProyectos, carpetasProyectos)
        carpetasMarketing = v(.carpetasMarketing, carpetasMarketing)
        sacudirMouse = v(.sacudirMouse, sacudirMouse)
        sensibilidadSacudida = v(.sensibilidadSacudida, sensibilidadSacudida)
        leerConOpenAI = v(.leerConOpenAI, leerConOpenAI)
        varitaApagado = v(.varitaApagado, varitaApagado)
        varitaFlecha = v(.varitaFlecha, varitaFlecha)
        varitaReemplaza = v(.varitaReemplaza, varitaReemplaza)
        varitaAgentes = v(.varitaAgentes, varitaAgentes)
        varitaQR = v(.varitaQR, varitaQR)
        modoTecla = v(.modoTecla, modoTecla)
        idiomaInterfaz = v(.idiomaInterfaz, idiomaInterfaz)
        appsCorreo = v(.appsCorreo, appsCorreo)
        appsMensaje = v(.appsMensaje, appsMensaje)
        // Tus listas se guardan enteras: las apps nuevas se suman una sola vez, y las que sacaste vos no vuelven.
        if v(.listasApps, 1) < 2 {
            appsTrabajo = DatosAjustes.sumar(DatosAjustes.nuevasTrabajo, a: appsTrabajo)
            appsCorreo = DatosAjustes.sumar(DatosAjustes.nuevasCorreo, a: appsCorreo)
            appsMensaje = DatosAjustes.sumar(DatosAjustes.nuevasMensaje, a: appsMensaje)
        }
        emojisMensaje = v(.emojisMensaje, emojisMensaje)
        instruccionesApp = v(.instruccionesApp, instruccionesApp)
        acciones = v(.acciones, acciones)
        idiomaTraduccion = v(.idiomaTraduccion, idiomaTraduccion)
        atajosNumero = v(.atajosNumero, atajosNumero)
        teclaModos = v(.teclaModos, teclaModos)
        modos = ConfigModo.normalizar(v(.modos, modos))
        atajoAutomatico = v(.atajoAutomatico, atajoAutomatico)
        numerosGrabando = v(.numerosGrabando, numerosGrabando)
        enviarTrabajo = v(.enviarTrabajo, enviarTrabajo)
        enviarMensaje = v(.enviarMensaje, enviarMensaje)
        modeloLocal = v(.modeloLocal, modeloLocal)
        estiloPildora = v(.estiloPildora, estiloPildora)
        opacidadPildora = v(.opacidadPildora, opacidadPildora)
        tamanoPildora = v(.tamanoPildora, tamanoPildora)
        posicionPildora = (try? c.decodeIfPresent([Double].self, forKey: .posicionPildora)) ?? nil
        aprenderSolo = v(.aprenderSolo, aprenderSolo)
        microfono = v(.microfono, microfono)
        pausarMusica = v(.pausarMusica, pausarMusica)
        limpiezaBasica = v(.limpiezaBasica, limpiezaBasica)
        atajoReprocesar = v(.atajoReprocesar, atajoReprocesar)
        atajoSumarPalabra = v(.atajoSumarPalabra, atajoSumarPalabra)
        atajoPreguntar = v(.atajoPreguntar, atajoPreguntar)
    }

    // Suma a `lista` las de `nuevas` que no tenga (sin mirar mayúsculas), al final y en orden.
    static func sumar(_ nuevas: [String], a lista: [String]) -> [String] {
        let tiene = Set(lista.map { $0.lowercased() })
        return lista + nuevas.filter { !tiene.contains($0.lowercased()) }
    }
}

final class Ajustes: ObservableObject {
    static let shared = Ajustes()

    @Published var datos: DatosAjustes {
        didSet { if datos != oldValue { if !Ajustes.soloLectura { Almacen.guardar(datos, "ajustes.json") }; alCambiar?() } }
    }
    var alCambiar: (() -> Void)?
    // En los modos de prueba (--medir, --probar-…) no se guarda nada: antes, al terminar, pisaban lo que habías
    // cambiado en la app abierta (pasó el 21/10 con el estilo automático).
    static var soloLectura = false

    private init() {
        datos = Almacen.leer(DatosAjustes.self, "ajustes.json") ?? DatosAjustes()
    }

    var claveVoz: String { clave(datos.proveedorVoz.cuentaLlavero) }
    var claveIA: String { clave(datos.proveedorIA.cuentaLlavero) }

    // Las claves de los proveedores "Compatible con OpenAI" van atadas a la dirección con que las guardaste en
    // Proveedores: esa dirección vive en ajustes.json, que cualquier programa puede cambiar (o hacer leer otro con
    // DIXITY_CARPETA), y así se llevaba tu clave a otro servidor (auditoría de seguridad del 23/10/2026). Si la
    // dirección ya no es la misma, la clave no se usa hasta que la vuelvas a guardar.
    func clave(_ cuenta: String) -> String {
        let valor = Llavero.leer(cuenta)
        guard let url = urlAtada(a: cuenta) else { return valor }
        return Llavero.leer(cuenta + ".url") == url ? valor : ""
    }

    // Guarda una clave (desde Proveedores) y, si es de un proveedor compatible, la ata a la dirección de ahora.
    func guardarClave(_ cuenta: String, _ valor: String) {
        Llavero.guardar(cuenta, valor)
        if let url = urlAtada(a: cuenta) { Llavero.guardar(cuenta + ".url", url) }
    }

    private func urlAtada(a cuenta: String) -> String? {
        let url = cuenta == ProveedorVoz.personalizado.cuentaLlavero ? datos.urlVozPersonalizada
            : cuenta == ProveedorIA.personalizado.cuentaLlavero ? datos.urlIAPersonalizada : nil
        return url?.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }
    // "Todo en la Mac": voz e IA locales, nada sale de la Mac ni hace falta ninguna clave. Mira solo los proveedores:
    // con "Limpiar con IA" apagado, los modos Correo, Mensaje, Trabajo, la reescritura y la memoria igual usan la IA
    // elegida, así que una IA en la nube no cuenta como local (antes el panel decía "nada sale de tu Mac" igual;
    // auditoría de seguridad del 23/10/2026).
    var todoLocal: Bool { datos.proveedorVoz.local && (datos.proveedorIA == .apple || datos.proveedorIA == .ninguno) }

    func usarTodoLocal() {
        var d = datos
        d.proveedorVoz = Parakeet.encontrado(d.modeloLocal) != nil || !VozApple.disponible ? .parakeet : .apple
        d.modeloVoz = d.proveedorVoz.modeloSugerido
        d.proveedorIA = IAApple.disponible ? .apple : .ninguno
        d.modeloIA = d.proveedorIA.modeloSugerido
        datos = d
    }

    // A qué idioma traduce el modo Traducir.
    var idiomaDestino: String {
        let t = datos.idiomaTraduccion.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? T("inglés", "Spanish") : t
    }

    // Los modos que se ven, en el orden elegido: el primero es ⌃⌥1.
    var modosActivos: [Estilo] { datos.modos.filter(\.activo).map(\.estilo) }
    func color(de e: Estilo) -> Color {
        Color(hex: datos.modos.first { $0.estilo == e }?.color ?? 0xF56138)
    }

    // Hay IA para pasar en limpio: el modelo de la Mac no necesita clave.
    var iaLista: Bool { datos.proveedorIA == .apple ? IAApple.disponible : (datos.proveedorIA != .ninguno && !claveIA.isEmpty) }
    var iaVeImagenes: Bool { datos.proveedorIA.veImagenes && iaLista }

    var urlVoz: String {
        datos.proveedorVoz == .personalizado ? datos.urlVozPersonalizada : datos.proveedorVoz.urlBase
    }
    var urlIA: String {
        datos.proveedorIA == .personalizado ? datos.urlIAPersonalizada : datos.proveedorIA.urlBase
    }

    // Navegadores: ahí el modo sale del título de la pestaña (Gmail → Correo, WhatsApp Web → Mensaje, Claude → Trabajo).
    // Navegadores: en ellos el modo automático y los gestores de contraseñas (Secretos) miran el título de la pestaña.
    static let navegadores: Set<String> = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser",
        "com.brave.Browser", "com.microsoft.edgemac", "org.mozilla.firefox", "ai.perplexity.comet", "com.openai.atlas",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.google.Chrome.beta", "org.chromium.Chromium",
        "company.thebrowser.dia", "com.kagi.kagimacOS", "app.zen-browser.zen", "org.mozilla.firefoxdeveloperedition",
        "com.apple.SafariTechnologyPreview", "com.google.Chrome.canary", "com.operasoftware.OperaGX",
        "com.microsoft.edgemac.Beta", "com.brave.Browser.beta"]

    // El estilo de este dictado (nunca "automático").
    func estiloPara(_ c: ContextoCursor?) -> Estilo {
        guard datos.estilo == .automatico else { return datos.estilo }
        guard let c, !c.app.isEmpty else { return .comun }
        func coincide(_ lista: [String]) -> Bool { lista.contains { Ajustes.coincide($0, con: c) } }
        if coincide(datos.appsCorreo) { return .correo }
        if coincide(datos.appsMensaje) { return .mensaje }
        if coincide(datos.appsTrabajo) { return .trabajo }
        return .comun
    }

    // ¿`nombre` es la app de adelante? Alcanza una parte del nombre; en el navegador vale el título de la pestaña.
    static func coincide(_ nombre: String, con c: ContextoCursor) -> Bool {
        let n = nombre.trimmingCharacters(in: .whitespaces).lowercased()
        guard !n.isEmpty else { return false }
        if c.app.lowercased().contains(n) { return true }
        return navegadores.contains(c.bundle) && c.ventana.lowercased().contains(n)
    }

    // Preferencias que van a la IA: las generales y las de la app o sitio donde dictás (Voz › Pasar en limpio).
    func instruccionPara(_ c: ContextoCursor?) -> String {
        let general = datos.instruccionesExtra.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c else { return general }
        let deApp = datos.instruccionesApp
            .filter { Ajustes.coincide($0.app, con: c) && !$0.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "En \($0.app): " + String($0.texto.prefix(InstruccionApp.tope)) }
        return ([general] + deApp).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var faltanClaves: Bool {
        (!datos.proveedorVoz.local && claveVoz.isEmpty) || (datos.limpiarConIA && datos.proveedorIA != .ninguno && datos.proveedorIA != .apple && claveIA.isEmpty)
    }
}
