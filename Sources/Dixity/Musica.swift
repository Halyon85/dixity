import AppKit

// Pausa lo que suena mientras dictás y lo vuelve a poner al terminar (opcional: Voz › Mientras dictás).
// Solo reanuda lo que pausó Dixity: si no había nada sonando, no toca nada (nunca arranca música).
// 1) Lo que la Mac muestra como "Reproduciendo ahora" (MediaRemote, privado de Apple: sirve fuera de la App Store).
// 2) Si eso no responde (macOS lo restringe desde la 15.4), Spotify y Música por AppleScript, solo si están abiertas.
enum Musica {
    private static let cola = DispatchQueue(label: "dixity.musica")
    private static var pausoSistema = false
    private static var pausadas: [String] = []        // apps que pausó por AppleScript
    private static var vuelta = 0                     // si el dictado terminó antes de pausar, no pausa tarde

    private static let apps = ["com.spotify.client", "com.apple.Music"]

    private typealias EstaSonando = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias Mandar = @convention(c) (UInt32, CFDictionary?) -> Bool
    private static let marco = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    private static let estaSonando = dlsym(marco, "MRMediaRemoteGetNowPlayingApplicationIsPlaying").map { unsafeBitCast($0, to: EstaSonando.self) }
    private static let mandar = dlsym(marco, "MRMediaRemoteSendCommand").map { unsafeBitCast($0, to: Mandar.self) }

    static func pausar() {
        cola.async {
            vuelta += 1
            let esta = vuelta
            pausoSistema = false
            pausadas = []
            let sonando = consultar()
            guard esta == vuelta else { return }
            if sonando, let mandar, mandar(1, nil) {   // 1 = pausa (no alterna: si no suena, no hace nada)
                pausoSistema = true
                return
            }
            for id in apps where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                let r = correr("tell application id \"\(id)\" to if player state is playing then\npause\nreturn true\nend if\nreturn false")
                if r == true { pausadas.append(id) }
            }
        }
    }

    static func reanudar() {
        cola.async {
            vuelta += 1
            if pausoSistema { _ = mandar?(0, nil) }   // 0 = reproducir
            for id in pausadas { _ = correr("tell application id \"\(id)\" to play") }
            pausoSistema = false
            pausadas = []
        }
    }

    // Espera la respuesta de MediaRemote como mucho 0,3 s.
    private static func consultar() -> Bool {
        guard let estaSonando else { return false }
        let listo = DispatchSemaphore(value: 0)
        var sonando = false
        estaSonando(DispatchQueue.global()) { s in sonando = s; listo.signal() }
        return listo.wait(timeout: .now() + 0.3) == .success && sonando
    }

    private static func correr(_ codigo: String) -> Bool? {
        var error: NSDictionary?
        let r = NSAppleScript(source: codigo)?.executeAndReturnError(&error)
        return error == nil ? r?.booleanValue : nil
    }
}
