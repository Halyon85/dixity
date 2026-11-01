import Foundation

enum ErrorApp: LocalizedError {
    case sinMicrofono, sinClave(String), http(Int, String), red(String), respuesta, rechazo, sinModeloLocal, modeloDistinto(String), sinMotorApple, sinIAApple, sinVision

    var errorDescription: String? {
        switch self {
        case .sinMicrofono: T("No encontré un micrófono.", "No microphone found.")
        case .sinClave(let q): T("Falta la clave de \(q). Cargala en Dixity › Proveedores.", "Missing key for \(q). Add it in Dixity › Providers.")
        case .http(let c, let m): c == 401 || c == 403 ? T("La clave no es válida (\(c)).", "Invalid key (\(c)).")
            : c == 429 ? T("El servicio está ocupado o sin saldo (429).", "The service is busy or out of credit (429).")
            : T("El servicio respondió \(c): \(m)", "The service returned \(c): \(m)")
        case .red(let m): T("Sin conexión con el servicio: \(m)", "Can't reach the service: \(m)")
        case .respuesta: T("La respuesta del servicio vino rara.", "The service sent an unexpected response.")
        case .rechazo: T("La IA no quiso procesar este texto.", "The AI declined to process this text.")
        case .sinModeloLocal: T("No encontré el modelo Parakeet en esta Mac. Descargalo en Proveedores.", "Parakeet model not found on this Mac. Download it in Providers.")
        case .modeloDistinto(let n): T("Lo que se bajó de \(n) no es el modelo probado (cambió en el servidor), así que se borró. Avisale a Halyon Team.", "The downloaded \(n) isn't the tested model (it changed on the server), so it was deleted. Let Halyon Team know.")
        case .sinVision: T("Tu IA no puede mirar imágenes: elegí OpenAI, Claude, Grok u OpenRouter en Proveedores.", "Your AI can't look at images: choose OpenAI, Claude, Grok or OpenRouter in Providers.")
        case .sinIAApple: T("El modelo de la Mac no está disponible (hace falta macOS 26 con Apple Intelligence activado).", "The Mac model isn't available (requires macOS 26 with Apple Intelligence turned on).")
        case .sinMotorApple: T("El motor de voz de la Mac no está listo para este idioma (hace falta macOS 26 y el idioma instalado en Ajustes › Teclado › Dictado).", "The Mac speech engine isn't ready for this language (requires macOS 26 and the language installed in Settings › Keyboard › Dictation).")
        }
    }
}

enum Proveedores {
    private static let sesion: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 45
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private static func pedir(_ req: URLRequest) async throws -> [String: Any] {
        let (datos, resp): (Data, URLResponse)
        do { (datos, resp) = try await sesion.data(for: req) }
        catch { throw ErrorApp.red(error.localizedDescription) }
        let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any]
        guard (200..<300).contains(codigo) else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? (json?["detail"] as? [String: Any])?["message"] as? String
                ?? String(data: datos.prefix(200), encoding: .utf8) ?? ""
            throw ErrorApp.http(codigo, msg)
        }
        guard let json else { throw ErrorApp.respuesta }
        return json
    }

    // MARK: Voz a texto

    static func transcribir(wav: Data, ajustes a: Ajustes, pista: String) async throws -> String {
        let d = a.datos
        if d.proveedorVoz == .parakeet {
            return try await Parakeet.shared.transcribir(pcm16: wav.dropFirst(44), idioma: d.idioma)
        }
        if d.proveedorVoz == .apple {
            return try await VozApple.transcribir(wav: wav, idioma: d.idioma, terminos: pista.isEmpty ? [] : pista.components(separatedBy: ", "))
        }
        let clave = a.claveVoz
        guard !clave.isEmpty else { throw ErrorApp.sinClave(d.proveedorVoz.nombre) }
        let modelo = d.modeloVoz.isEmpty ? d.proveedorVoz.modeloSugerido : d.modeloVoz
        var form = Formulario()
        var req: URLRequest
        switch d.proveedorVoz {
        case .grok:
            req = URLRequest(url: URL(string: d.proveedorVoz.urlBase + "/stt")!)
            req.setValue("Bearer \(clave)", forHTTPHeaderField: "Authorization")
            form.campo("model", modelo)
            if d.idioma != .automatico { form.campo("language", d.idioma.rawValue) }
        default:
            guard let url = URL(string: a.urlVoz.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + "/audio/transcriptions") else { throw ErrorApp.respuesta }
            req = URLRequest(url: url)
            req.setValue("Bearer \(clave)", forHTTPHeaderField: "Authorization")
            form.campo("model", modelo)
            form.campo("response_format", "json")
            form.campo("temperature", "0")
            if d.idioma != .automatico { form.campo("language", d.idioma.rawValue) }
            if !pista.isEmpty { form.campo("prompt", pista) }
        }
        // El archivo va al final (Grok lo exige; al resto le da igual).
        form.archivo("file", nombre: "dictado.wav", tipo: "audio/wav", datos: wav)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(form.limite)", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.cerrar()
        let json = try await pedir(req)
        guard let texto = json["text"] as? String else { throw ErrorApp.respuesta }
        return texto.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Abre la conexión con el servicio mientras hablás: el pedido real sale unos cientos de ms antes.
    static func precalentar(_ base: String) {
        guard let url = URL(string: base), url.host != nil else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 5
        sesion.dataTask(with: req).resume()
    }

    // MARK: IA (pasar en limpio / reescribir)

    /// `imagenes`: JPEG para que la IA las mire (Pantalla.paraIA); solo con una IA que ve imágenes (`veImagenes`).
    static func completar(sistema: String, usuario: String, imagenes: [Data] = [], ajustes a: Ajustes) async throws -> String {
        let d = a.datos
        if !imagenes.isEmpty && !d.proveedorIA.veImagenes { throw ErrorApp.sinVision }
        if d.proveedorIA == .apple { return try await IAApple.completar(sistema: sistema, usuario: usuario) }
        let clave = a.claveIA
        guard !clave.isEmpty else { throw ErrorApp.sinClave(d.proveedorIA.nombre) }
        let modelo = d.modeloIA.isEmpty ? d.proveedorIA.modeloSugerido : d.modeloIA
        let base = a.urlIA.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        if d.proveedorIA == .anthropic {
            var req = URLRequest(url: URL(string: base + "/messages")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(clave, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            // Con imágenes, van primero y el texto al final (así lo recomienda Anthropic).
            var partes: [[String: Any]] = imagenes.map {
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0.base64EncodedString()]]
            }
            partes.append(["type": "text", "text": usuario])
            var cuerpo: [String: Any] = [
                "model": modelo,
                "max_tokens": 8000,
                "system": sistema,
                "messages": [["role": "user", "content": imagenes.isEmpty ? usuario as Any : partes]],
            ]
            // Modelos actuales: poco "pensar" alcanza para pasar en limpio y responde más rápido.
            if modelo.hasPrefix("claude-") && !modelo.contains("-4-") && !modelo.contains("-3") {
                cuerpo["output_config"] = ["effort": "low"]
            }
            // Haiku 5.5 permite no "pensar" con esfuerzo bajo: pasa en limpio igual de bien y responde antes.
            if modelo.hasPrefix("claude-haiku-5") { cuerpo["thinking"] = ["type": "disabled"] }
            // Si un filtro de seguridad rechaza el pedido, Anthropic lo reintenta solo con otro modelo.
            if ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"].contains(modelo) {
                req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                cuerpo["fallbacks"] = "default"
            }
            req.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)
            let json = try await pedir(req)
            if json["stop_reason"] as? String == "refusal" { throw ErrorApp.rechazo }
            let bloques = json["content"] as? [[String: Any]] ?? []
            let texto = bloques.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            return texto
        }

        guard let url = URL(string: base + "/chat/completions") else { throw ErrorApp.respuesta }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(clave)", forHTTPHeaderField: "Authorization")
        if d.proveedorIA == .openrouter {
            req.setValue("https://halyon.team", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("Dixity", forHTTPHeaderField: "X-Title")
        }
        var partes: [[String: Any]] = [["type": "text", "text": usuario]]
        partes += imagenes.map { ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + $0.base64EncodedString()]] }
        var cuerpo: [String: Any] = [
            "model": modelo,
            "messages": [["role": "system", "content": sistema],
                         ["role": "user", "content": imagenes.isEmpty ? usuario as Any : partes]],
        ]
        // Modelos GPT-5 de OpenAI: sin "pensar" responden mucho más rápido (para pasar en limpio alcanza).
        if d.proveedorIA == .openai && (modelo.hasPrefix("gpt-5") || modelo.hasPrefix("gpt-6")) {
            cuerpo["reasoning_effort"] = (modelo == "gpt-5" || modelo.hasPrefix("gpt-5-")) ? "minimal" : "none"
            // Agrupa los pedidos de Dixity para que OpenAI reuse el comienzo igual (instrucciones y memoria): responde antes.
            if d.proveedorIA == .openai { cuerpo["prompt_cache_key"] = "dixity" }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)
        let json = try await pedir(req)
        guard let elec = (json["choices"] as? [[String: Any]])?.first,
              let msg = elec["message"] as? [String: Any] else { throw ErrorApp.respuesta }
        return msg["content"] as? String ?? ""
    }

    // Pedido mínimo para el botón "Probar".
    static func probarIA(_ a: Ajustes) async -> String {
        do {
            let r = try await completar(sistema: "Respondé solo con la palabra OK.", usuario: "Decí OK.", ajustes: a)
            return r.isEmpty ? T("Respondió vacío.", "Empty response.") : T("Funciona ✓", "Works ✓")
        } catch { return error.localizedDescription }
    }

    static func probarVoz(_ a: Ajustes) async -> String {
        // Medio segundo de silencio: alcanza para ver si la clave y el modelo andan.
        let pcm = Data(count: 16_000)
        var wav = Data("RIFF".utf8)
        func u32(_ v: UInt32) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 2)) }
        u32(UInt32(36 + pcm.count)); wav.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(16_000); u32(32_000); u16(2); u16(16); wav.append(Data("data".utf8)); u32(UInt32(pcm.count)); wav.append(pcm)
        do { _ = try await transcribir(wav: wav, ajustes: a, pista: ""); return T("Funciona ✓", "Works ✓") }
        catch { return error.localizedDescription }
    }
}

private struct Formulario {
    let limite = "dicta-\(UUID().uuidString)"
    private var cuerpo = Data()

    mutating func campo(_ nombre: String, _ valor: String) {
        cuerpo.append(Data("--\(limite)\r\nContent-Disposition: form-data; name=\"\(nombre)\"\r\n\r\n\(valor)\r\n".utf8))
    }

    mutating func archivo(_ nombre: String, nombre archivo: String, tipo: String, datos: Data) {
        cuerpo.append(Data("--\(limite)\r\nContent-Disposition: form-data; name=\"\(nombre)\"; filename=\"\(archivo)\"\r\nContent-Type: \(tipo)\r\n\r\n".utf8))
        cuerpo.append(datos)
        cuerpo.append(Data("\r\n".utf8))
    }

    mutating func cerrar() -> Data {
        cuerpo.append(Data("--\(limite)--\r\n".utf8))
        return cuerpo
    }
}
