import AVFoundation
import OSLog

// Leer en voz alta (la Varita, con un texto seleccionado o señalado). Uno a la vez: leer otra cosa corta lo anterior.
// - Con tu clave de OpenAI y "Con la voz de OpenAI" prendido en la página Varita del panel (viene apagado: cuesta): la voz de OpenAI,
//   que suena como una persona (≈ 1,5 centavos de dólar por minuto leído). El texto va en partes de hasta ~3.500
//   letras: mientras suena una, se pide la siguiente. Si falla (sin saldo, sin internet), sigue con la voz de la Mac.
// - Si no: las voces de la Mac, gratis y sin internet (la del 31/10 sonaba muy robótica al lado de la de OpenAI).
final class Lector: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private var sintetizador: AVSpeechSynthesizer?
    private var reproductor: AVAudioPlayer?
    private var sonando: CheckedContinuation<Void, Never>?
    private var tarea: Task<Void, Never>?
    private var siguiente: Task<Data, Error>?   // el pedido a OpenAI en curso: se cancela al parar (si no, se cobra igual)
    var alTerminar: () -> Void = {}
    var leyendo: Bool { sintetizador?.isSpeaking == true || tarea != nil }

    private static let registro = Logger(subsystem: "team.halyon.dixity", category: "lector")

    /// `claveOpenAI`: con una clave, lee con la voz de OpenAI; sin clave, con la de la Mac.
    func leer(_ texto: String, claveOpenAI: String? = nil) {
        parar()
        let texto = String(texto.prefix(20_000))
        if let clave = claveOpenAI, !clave.isEmpty { leerConOpenAI(texto, clave: clave) } else { leerEnLaMac(texto) }
    }

    func parar() {
        let habia = sintetizador != nil || tarea != nil
        tarea?.cancel(); tarea = nil
        siguiente?.cancel(); siguiente = nil
        reproductor?.stop(); reproductor = nil
        sonando?.resume(); sonando = nil
        if let s = sintetizador { sintetizador = nil; s.stopSpeaking(at: .immediate) }
        if habia { alTerminar() }
    }

    // MARK: Con la voz de OpenAI

    private func leerConOpenAI(_ texto: String, clave: String) {
        let partes = Lector.partes(texto)
        let idioma = Respuestas.idioma(de: texto) ?? "es"
        tarea = Task { @MainActor [weak self] in
            self?.siguiente = Task { try await Lector.voz(partes[0], idioma: idioma, clave: clave) }
            for i in partes.indices {
                guard let pedido = self?.siguiente else { break }
                let audio: Data
                do { audio = try await pedido.value } catch {
                    guard !Task.isCancelled, let self else { return }
                    Lector.registro.notice("OpenAI no leyó: \(error.localizedDescription, privacy: .private)")
                    // La primera parte falló: lee todo con la voz de la Mac. Más adelante: lo que falta.
                    self.tarea = nil
                    self.leerEnLaMac(partes[i...].joined(separator: " "))
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.siguiente = i + 1 < partes.count ? Task { try await Lector.voz(partes[i + 1], idioma: idioma, clave: clave) } : nil
                await self.tocar(audio)
                if Task.isCancelled { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.tarea = nil
            self.siguiente = nil
            self.alTerminar()
        }
    }

    // Suena un pedazo y espera a que termine (o a que lo pares).
    @MainActor private func tocar(_ audio: Data) async {
        guard let r = try? AVAudioPlayer(data: audio) else { return }
        r.delegate = self
        reproductor = r
        await withCheckedContinuation { c in
            sonando = c
            if !r.play() { sonando = nil; c.resume() }
        }
        reproductor = nil
    }

    // Si el audio llega roto, macOS avisa por acá y no por "terminó": sin esto la lectura quedaba esperando para siempre.
    func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) { audioPlayerDidFinishPlaying(p, successfully: false) }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.reproductor === p else { return }
            self.sonando?.resume(); self.sonando = nil
        }
    }

    /// El texto en partes de hasta `tope` letras, cortando en el final de una oración (o de una palabra) para que la
    /// voz no se corte en medio. OpenAI acepta hasta 4.096 letras por pedido.
    static func partes(_ texto: String, tope: Int = 3500) -> [String] {
        var resto = Substring(texto.trimmingCharacters(in: .whitespacesAndNewlines))
        var lista: [String] = []
        while resto.count > tope {
            let ventana = resto.prefix(tope)
            var corte = ventana.lastIndex(where: { ".!?…\n".contains($0) }).map { ventana.index(after: $0) }
                ?? ventana.lastIndex(of: " ") ?? ventana.endIndex
            // Nunca un corte vacío: con un texto largo sin puntos ni espacios (un registro, base64, chino) el corte
            // caía al principio y el bucle no terminaba nunca, con la app colgada (revisión del 31/10).
            if corte == ventana.startIndex { corte = ventana.endIndex }
            lista.append(String(resto[..<corte]).trimmingCharacters(in: .whitespacesAndNewlines))
            resto = resto[corte...].drop(while: \.isWhitespace)
        }
        lista.append(resto.trimmingCharacters(in: .whitespacesAndNewlines))
        let llenas = lista.filter { !$0.isEmpty }
        return llenas.isEmpty ? [""] : llenas
    }

    // Un pedazo leído por OpenAI (gpt-4o-mini-tts, voz "marin"), en MP3. En español se le pide acento rioplatense.
    private static func voz(_ texto: String, idioma: String, clave: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!, timeoutInterval: 40)
        req.httpMethod = "POST"
        req.setValue("Bearer \(clave)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let como = idioma == "es"
            ? "Leé en español con acento rioplatense (de Argentina), natural y cálido, a un ritmo cómodo, como una persona que lee en voz alta para otra."
            : "Read naturally and warmly, at a comfortable pace, like a person reading aloud to someone."
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": "gpt-4o-mini-tts", "voice": "marin", "input": texto,
                                                                   "instructions": como, "response_format": "mp3"])
        let (datos, resp) = try await URLSession.shared.data(for: req)
        let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(codigo), !datos.isEmpty else {
            let msg = ((try? JSONSerialization.jsonObject(with: datos)) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? ""
            throw ErrorApp.http(codigo, msg)
        }
        return datos
    }

    // MARK: Con la voz de la Mac

    private func leerEnLaMac(_ texto: String) {
        let s = AVSpeechSynthesizer()   // se crea al leer y se suelta al terminar: no queda ocupando memoria
        s.delegate = self
        sintetizador = s
        let frase = AVSpeechUtterance(string: texto)
        frase.voice = Lector.voz(para: Respuestas.idioma(de: texto) ?? "es")
        s.speak(frase)
    }

    /// La voz para un idioma ("es", "en"…): la de **mejor calidad** que tengas bajada (Premium, después Mejorada) y,
    /// a igual calidad, la de Argentina o EE. UU. primero. La voz básica suena muy robótica (31/10/2026): las mejores
    /// se bajan gratis en Ajustes del Sistema › Accesibilidad › Contenido leído › Voz del sistema › Administrar voces.
    /// Las voces de Siri no se pueden usar desde otras apps.
    static func voz(para idioma: String) -> AVSpeechSynthesisVoice? {
        let orden = ["es": ["es-AR", "es-MX", "es-US", "es-ES"], "en": ["en-US", "en-GB", "en-AU"]][idioma] ?? []
        let candidatas = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(idioma) }
        func puntaje(_ v: AVSpeechSynthesisVoice) -> Int {
            let calidad = v.quality == .premium ? 200 : v.quality == .enhanced ? 100 : 0
            // Las neuronales y las naturales suenan como una persona; las "eloquence" (Eddy, Flo…) son las robóticas.
            let id = v.identifier
            let natural = id.contains("neural") || id.contains("siri.natural") ? 50 : id.contains("eloquence") ? -50 : 0
            let pais = orden.firstIndex(of: v.language).map { 10 - $0 } ?? 0
            return calidad + natural + pais
        }
        return candidatas.max { puntaje($0) < puntaje($1) } ?? AVSpeechSynthesisVoice(language: "es-AR")
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sintetizador === s else { return }
            self.sintetizador = nil
            self.alTerminar()
        }
    }
}
