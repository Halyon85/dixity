import Foundation

// Palabras que Dicta tiene que escribir bien, con "alias" (cómo suele salir mal transcripto).
struct Termino: Codable, Identifiable, Hashable {
    var id = UUID()
    var texto: String
    var alias: [String] = []
    var creado = Date()
    var automatico: Bool? = nil      // lo sumó Dicta sola
}

final class Diccionario: ObservableObject {
    static let shared = Diccionario()
    static let maximo = 1000
    static let maximoEnPrompt = 120

    @Published var terminos: [Termino] { didSet { Almacen.guardar(terminos, "diccionario.json") } }

    private init() { terminos = Almacen.leer([Termino].self, "diccionario.json") ?? [] }

    @discardableResult
    func agregar(_ texto: String, alias: [String] = [], automatico: Bool = false) -> Bool {
        let t = Diccionario.limpiar(texto)
        guard !t.isEmpty, terminos.count < Diccionario.maximo else { return false }
        if let i = terminos.firstIndex(where: { $0.texto.lowercased() == t.lowercased() }) {
            terminos[i].alias = Array(Set(terminos[i].alias + alias)).sorted()
            // Sumarla a mano (panel, sugerencia o ⌃⌥D) la hace tuya, como editarla: si no, sus alias no se aplican
            // (30/10/2026: "Dixity" aprendida sola + el alias "Dick City" seguía saliendo "Dick City").
            if !automatico { terminos[i].automatico = nil }
            return true
        }
        terminos.insert(Termino(texto: t, alias: alias.map(Diccionario.limpiar).filter { !$0.isEmpty },
                                automatico: automatico ? true : nil), at: 0)
        return true
    }

    // Una palabra por línea; una corrección se escribe "mal, bien" (o "mal -> bien").
    func importarLista(_ lista: String) -> Int {
        var n = 0
        for linea in lista.components(separatedBy: .newlines) {
            let l = linea.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty, !l.hasPrefix("#") else { continue }
            let partes = l.replacingOccurrences(of: "->", with: ",").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if partes.count >= 2 { if agregar(partes[1], alias: [partes[0]]) { n += 1 } }
            else if agregar(partes[0]) { n += 1 }
        }
        return n
    }

    static func limpiar(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix("#") { t.removeFirst() }
        return String(t.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    // Qué términos mandar a la IA: primero los que se parecen a algo de la transcripción.
    func paraPrompt(transcripcion: String) -> [Termino] {
        let palabras = Set(Diccionario.normalizar(transcripcion).split(separator: " ").map(String.init))
        let puntuados = terminos.map { t -> (Termino, Int) in
            let candidatos = [t.texto] + t.alias
            var mejor = 0
            for c in candidatos {
                for p in Diccionario.normalizar(c).split(separator: " ").map(String.init) where p.count >= 3 {
                    if palabras.contains(p) { mejor = max(mejor, 3) }
                    else if palabras.contains(where: { Diccionario.parecidas($0, p) }) { mejor = max(mejor, 2) }
                }
            }
            return (t, mejor)
        }
        let coinciden = puntuados.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
        // De relleno van solo los que sumaste vos: lo que Dixity aprendió sola va únicamente si se parece a lo dicho.
        let resto = puntuados.filter { $0.1 == 0 && $0.0.automatico != true }.map(\.0)
        return Array((coinciden + resto).prefix(Diccionario.maximoEnPrompt))
    }

    // Reemplazos fijos: si la voz a texto escribió un alias, se cambia por el término correcto antes de la IA
    // (palabra completa, sin importar mayúsculas ni tildes, en una sola pasada). Así funciona aunque la IA esté apagada.
    // Solo los alias de términos que sumaste vos: un alias que Dixity aprendió sola (versiones viejas lo hacían con
    // cualquier palabra que la IA escribió distinto, como "activo" → "Inactivo") cambiaría lo que dijiste antes de
    // la IA y de la barrera (auditoría de seguridad del 23/10/2026).
    func aplicarAlias(_ texto: String) -> String {
        var pares: [(String, String)] = []
        for t in terminos where t.automatico != true { for a in t.alias where a.count >= 3 { pares.append((a, t.texto)) } }
        guard !pares.isEmpty else { return texto }
        pares.sort { $0.0.count > $1.0.count }          // primero los más largos
        var resultado = texto
        var protegidos: [String] = []
        for (alias, correcto) in pares {
            let patron = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: alias) + "(?![\\p{L}\\p{N}])"
            guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { continue }
            let marca = "\u{F8FF}\(protegidos.count)\u{F8FF}"
            let nuevo = re.stringByReplacingMatches(in: resultado, range: NSRange(resultado.startIndex..., in: resultado), withTemplate: marca)
            if nuevo != resultado { protegidos.append(correcto); resultado = nuevo }
        }
        for (i, correcto) in protegidos.enumerated() { resultado = resultado.replacingOccurrences(of: "\u{F8FF}\(i)\u{F8FF}", with: correcto) }
        return resultado
    }

    // Pista para la voz a texto (Whisper acepta un "prompt" corto con vocabulario). Solo con lo que sumaste vos: lo que
    // Dixity aprendió sola puede venir de la pantalla, y la voz a texto a veces "escribe" la pista aunque no se dijo.
    var pistaVoz: String {
        let lista = terminos.filter { $0.automatico != true }.prefix(60).map(\.texto).joined(separator: ", ")
        return lista.isEmpty ? "" : String(lista.prefix(700))
    }

    static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func parecidas(_ a: String, _ b: String) -> Bool {
        guard abs(a.count - b.count) <= 2, a.count >= 4 else { return false }
        return distancia(Array(a), Array(b)) <= (b.count >= 7 ? 2 : 1)
    }

    static func distancia(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var fila = Array(0...b.count)
        for i in 1...a.count {
            var previo = fila[0]; fila[0] = i
            for j in 1...b.count {
                let tmp = fila[j]
                fila[j] = a[i - 1] == b[j - 1] ? previo : min(previo, fila[j], fila[j - 1]) + 1
                previo = tmp
            }
        }
        return fila[b.count]
    }
}

// Último día: cada dictado (con su audio) se borra solo a las 24 horas.
struct Registro: Codable, Identifiable {
    enum Modo: String, Codable { case dictado, reescritura, respuesta }   // respuesta: Preguntar (se ve antes de pegar)
    var id = UUID()
    var fecha = Date()
    var modo: Modo
    var app: String
    var transcripcion: String
    var final: String
    var instruccion: String? = nil
    var segundosAudio: Double
    var msVoz: Int
    var msIA: Int
    var usoIA: Bool
    var barrera: String? = nil
    var proveedorVoz: String? = nil
    var proveedorIA: String? = nil
    var estilo: String? = nil          // "Común" o "Trabajo"
    var proyecto: String? = nil
    var audio: String? = nil           // archivo .wav en Dicta/Audio
    var reprocesoDe: UUID? = nil
}

final class Historial: ObservableObject {
    static let shared = Historial()
    static let horas: Double = 24
    static let maximo = 500
    static let carpetaAudio: URL = {
        let u = Almacen.carpeta.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    @Published private(set) var registros: [Registro]
    private var reloj: Timer?

    private init() {
        registros = Almacen.leer([Registro].self, "historial.json") ?? []
        podar()
        reloj = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.podar() }
    }

    func guardarAudio(_ wav: Data) -> String? {
        let nombre = UUID().uuidString + ".wav"
        do { try wav.write(to: Historial.carpetaAudio.appendingPathComponent(nombre), options: .atomic) } catch { return nil }
        return nombre
    }

    func audio(de r: Registro) -> Data? {
        r.audio.flatMap(audio(nombre:))
    }

    func audio(nombre: String) -> Data? {
        Almacen.archivoPropio(nombre, extension: "wav", en: Historial.carpetaAudio).flatMap { try? Data(contentsOf: $0) }
    }

    func sumar(_ r: Registro) {
        registros.insert(r, at: 0)
        podar()
    }

    func vaciar() {
        registros = []
        guardar()
        borrarAudiosSueltos()
        Memoria.shared.olvidarPendientes()   // lo que esperaba para la memoria también se va
    }

    func podar() {
        let limite = Date().addingTimeInterval(-Historial.horas * 3600)
        let antes = registros.count
        registros = Array(registros.filter { $0.fecha > limite }.prefix(Historial.maximo))
        guardar()
        if registros.count != antes || antes == 0 { borrarAudiosSueltos() }
    }

    private func guardar() { Almacen.guardar(registros, "historial.json") }

    // Borra audios que ya no tienen dictado (o quedaron de una sesión cortada).
    private func borrarAudiosSueltos() {
        Almacen.borrarSueltos(en: Historial.carpetaAudio, extension: "wav", vivos: Set(registros.compactMap(\.audio)))
    }

    var palabrasDictadas: Int { registros.reduce(0) { $0 + $1.final.split(whereSeparator: \.isWhitespace).count } }

    // Lo último que dictaste en esa misma app (para que el modo Trabajo use las mismas palabras). Antes eran los de
    // cualquier app, y un mensaje privado podía terminar en el prompt de otra ventana (auditoría del 23/10/2026).
    func recientes(_ n: Int, app: String, minutos: Double = 120) -> [Registro] {
        let limite = Date().addingTimeInterval(-minutos * 60)
        return Array(registros.filter { $0.fecha > limite && $0.modo == .dictado && $0.reprocesoDe == nil && $0.app == app }.prefix(n))
    }
}

// Sugerencias para el diccionario: Dicta mira lo que corrigió la IA (nombres y términos que la voz a texto
// escribió mal) y el proyecto en el que trabajás, y te propone sumarlos. Vos decidís: agregar o descartar.
struct Sugerencia: Codable, Identifiable, Hashable {
    var id = UUID()
    var texto: String
    var alias: [String] = []
    var veces = 1
    var ultima = Date()
    var origen: String
}

final class Sugerencias: ObservableObject {
    static let shared = Sugerencias()
    @Published private(set) var lista: [Sugerencia]
    @Published private(set) var sumadasSolas: [String]
    private var descartadas: Set<String>
    private var enPantalla: [String: Int]          // términos vistos en la ventana y cuántas veces

    private init() {
        lista = Almacen.leer([Sugerencia].self, "sugerencias.json") ?? []
        descartadas = Set(Almacen.leer([String].self, "sugerencias-descartadas.json") ?? [])
        enPantalla = Almacen.leer([String: Int].self, "sugerencias-pantalla.json") ?? [:]
        sumadasSolas = Almacen.leer([String].self, "sugerencias-sumadas.json") ?? []
    }

    private static let comunes: Set<String> = ["quiero", "que", "para", "como", "pero", "este", "esta", "esto", "porque",
        "también", "después", "antes", "primero", "además", "ahora", "cuando", "donde", "hola", "gracias", "bueno",
        "dicta", "dixis", "claude", "codex", "the", "and", "for", "with", "this", "that"]

    // ¿Parece un nombre o término (no una palabra común)?
    static func pareceTermino(_ p: String, inicioDeOracion: Bool) -> Bool {
        guard p.count >= 3, p.count <= 40, !comunes.contains(p.lowercased()) else { return false }
        let letras = p.filter(\.isLetter)
        guard !letras.isEmpty else { return false }
        let mayusInternas = p.dropFirst().contains { $0.isUppercase }
        let conDigitos = p.contains { $0.isNumber }
        let tecnico = p.contains(".") || p.contains("_") || p.contains("-") || p.contains("/")
        let nombrePropio = p.first?.isUppercase == true && !inicioDeOracion
        return mayusInternas || conDigitos || tecnico || nombrePropio
    }

    // Claves, tokens, contraseñas y mails no se anotan nunca (ni como sugerencia): el diccionario va en cada pedido.
    static func pareceSecreto(_ p: String) -> Bool { Secretos.pareceSecreto(p) }

    private static func palabras(_ s: String) -> [(String, Bool)] {
        var r: [(String, Bool)] = []
        var inicio = true
        for bruto in s.split(whereSeparator: { $0.isWhitespace }) {
            let p = String(bruto).trimmingCharacters(in: CharacterSet(charactersIn: "`'\"“”«»()[]{}¿?¡!,;:"))
            if !p.isEmpty { r.append((p.hasSuffix(".") && !p.dropLast().contains(".") ? String(p.dropLast()) : p, inicio)) }
            inicio = bruto.last.map { ".!?\n".contains($0) } ?? false
        }
        return r
    }

    func aprender(de r: Registro, proyecto: String?, contexto: ContextoCursor? = nil) {
        guard r.reprocesoDe == nil, r.modo == .dictado else { return }
        var nuevas: [(String, [String], String)] = []
        // 0. Lo que se ve en la ventana (título y texto cerca del cursor): si aparece en 2 dictados, se sugiere.
        if let c = contexto {
            let visto = c.ventana + ". " + String(c.antes.suffix(300)) + " " + String(c.despues.prefix(150))
            var yaContados = Set<String>()     // una vez por dictado: dos veces en la misma ventana no son "2 dictados"
            for (p, inicio) in Self.palabras(visto) where Self.pareceTermino(p, inicioDeOracion: inicio) && !Self.pareceSecreto(p) {
                let n = Diccionario.normalizar(p)
                guard yaContados.insert(n).inserted else { continue }
                enPantalla[n, default: 0] += 1
                if enPantalla[n] == 2 { nuevas.append((p, [], "pantalla")) }
            }
            if enPantalla.count > 400 { enPantalla = enPantalla.filter { $0.value > 1 } }
        }
        guard r.usoIA else { registrar(nuevas); return }
        let conocidos = Set(Diccionario.shared.terminos.flatMap { [$0.texto] + $0.alias }.map { Diccionario.normalizar($0) })
        let crudo = Self.palabras(r.transcripcion).map { Diccionario.normalizar($0.0) }
        let crudoSet = Set(crudo)
        // 1. Lo que la IA escribió distinto de lo que escuchó la voz a texto (probable corrección de un nombre).
        for (p, inicio) in Self.palabras(r.final) where Self.pareceTermino(p, inicioDeOracion: inicio) && !Self.pareceSecreto(p) {
            let n = Diccionario.normalizar(p)
            guard !crudoSet.contains(n) else { continue }
            let alias = crudo.filter { !$0.isEmpty && $0 != n && Diccionario.parecidas($0, n) }.prefix(2)
            nuevas.append((p, Array(alias), "corrección"))
        }
        // 2. Términos entre `comillas invertidas` del modo Trabajo y el nombre del proyecto.
        for parte in r.final.components(separatedBy: "`").enumerated() where parte.offset % 2 == 1 {
            let t = parte.element.trimmingCharacters(in: .whitespaces)
            if t.count >= 3 && t.count <= 40 && !t.contains(" ") && !Self.pareceSecreto(t) { nuevas.append((t, [], "código")) }
        }
        if let p = proyecto, p.count >= 3 { nuevas.append((p, [], "proyecto")) }
        registrar(nuevas, conocidos: conocidos)
    }

    // Nombres que corregiste a mano después de pegar (Correcciones): siempre como sugerencia, porque traen alias. Si el
    // nombre ya está en el diccionario sin ese alias, igual se sugiere: aceptarla le suma el alias.
    func aprenderCorreccion(_ cambios: [(nuevo: String, viejo: String)]) {
        let dicc = Diccionario.shared.terminos
        let nuevas = cambios.filter { c in
            let n = Diccionario.normalizar(c.nuevo)
            let yaEsta = dicc.contains { Diccionario.normalizar($0.texto) == n && $0.alias.map(Diccionario.normalizar).contains(c.viejo) }
            let esAlias = dicc.contains { $0.alias.map(Diccionario.normalizar).contains(c.viejo) }
            return !yaEsta && !esAlias
        }
        registrar(nuevas.map { ($0.nuevo, [$0.viejo], "a mano") }, conocidos: [])
    }

    private func registrar(_ nuevas: [(String, [String], String)], conocidos: Set<String>? = nil) {
        let conocidos = conocidos ?? Set(Diccionario.shared.terminos.flatMap { [$0.texto] + $0.alias }.map { Diccionario.normalizar($0) })
        for (texto, alias, origen) in nuevas {
            let n = Diccionario.normalizar(texto)
            guard !n.isEmpty, !conocidos.contains(n), !descartadas.contains(n) else { continue }
            if let i = lista.firstIndex(where: { Diccionario.normalizar($0.texto) == n }) {
                lista[i].veces += 1
                lista[i].ultima = Date()
                lista[i].alias = Array(Set(lista[i].alias + alias)).sorted()
            } else {
                lista.insert(Sugerencia(texto: texto, alias: alias, origen: origen), at: 0)
            }
        }
        lista = Array(lista.sorted { $0.veces != $1.veces ? $0.veces > $1.veces : $0.ultima > $1.ultima }.prefix(60))
        // Aprender solo: entra directo al diccionario lo que no trae riesgo. Se queda como sugerencia (decidís vos):
        // lo visto en la pantalla (puede ser de otra persona o de una página) y toda corrección con alias, porque un
        // alias cambia lo que dijiste antes de la IA y de la barrera (auditoría de seguridad del 23/10/2026).
        if Ajustes.shared.datos.aprenderSolo {
            let directas = lista.filter { $0.origen != "pantalla" && $0.alias.isEmpty }
            for s in directas {
                Diccionario.shared.agregar(s.texto, automatico: true)
                sumadasSolas.insert(s.texto, at: 0)
            }
            lista.removeAll { s in directas.contains { $0.id == s.id } }
            sumadasSolas = Array(sumadasSolas.prefix(20))
        }
        guardar()
    }

    func limpiarAvisoSumadas() { sumadasSolas = []; guardar() }

    func aceptar(_ s: Sugerencia) {
        Diccionario.shared.agregar(s.texto, alias: s.alias)
        lista.removeAll { $0.id == s.id }
        guardar()
    }

    func descartar(_ s: Sugerencia) {
        descartadas.insert(Diccionario.normalizar(s.texto))
        lista.removeAll { $0.id == s.id }
        guardar()
    }

    private func guardar() {
        Almacen.guardar(lista, "sugerencias.json")
        Almacen.guardar(Array(descartadas), "sugerencias-descartadas.json")
        Almacen.guardar(enPantalla, "sugerencias-pantalla.json")
        Almacen.guardar(sumadasSolas, "sugerencias-sumadas.json")
    }
}
