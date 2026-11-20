import AppKit
import Carbon
import Security

// Leer la pantalla en un proceso aparte (desde el 20/11/2026). Sacarle la foto a la ventana (ScreenCaptureKit) y leer
// su texto (Vision) dejaba ~0,5 MB por dictado que macOS le seguía cobrando a Dixity y no devolvía hasta cerrarla: 85 MB
// en 155 dictados con la lectura prendida y ~0 en 188 con la lectura apagada (registro de memoria, 16 al 20/11/2026).
// Probado por separado no se repetía: parece una falla de Apple. Ahora lo hace esta misma Dixity abierta como
// «ayudante» (`--ayudante-pantalla <pid> <tope>`): saca la foto, lee el texto, lo devuelve por la salida y se cierra,
// y al cerrarse macOS recupera toda su memoria.
// Solo acepta que la abra la propia Dixity (misma firma que el ayudante); si la abre otro programa, no lee nada.
// Además macOS le da el permiso de Grabación de pantalla por quien la abrió: otro programa no gana nada con abrirla.
enum AyudantePantalla {
    static let argumento = "--ayudante-pantalla"
    // Si en 8 s no contestó (una app colgada que no deja sacar la foto), se corta: el dictado sigue sin la pantalla.
    static let espera: TimeInterval = 8

    /// El texto visible de la ventana de `pid`, leído por el ayudante. "" si no se puede, no conviene o tardó demasiado.
    /// Lo llama el Motor al empezar a dictar y al preguntar. Si se cancela la tarea (empezaste otro dictado), se
    /// cierra el ayudante.
    static func leer(pid: pid_t, tope: Int = 1500) async -> String {
        // Los mismos frenos que la lectura de siempre, antes de abrir nada: sin permiso, con una contraseña activa o
        // con un gestor de contraseñas adelante, no se lee.
        guard Pantalla.permitido, !IsSecureEventInputEnabled(),
              !Secretos.esGestor(NSRunningApplication(processIdentifier: pid)),
              let ejecutable = Bundle.main.executableURL else { return "" }
        let proceso = Process()
        proceso.executableURL = ejecutable
        proceso.arguments = [argumento, String(pid), String(tope)]
        let salida = Pipe()
        proceso.standardOutput = salida
        proceso.standardError = FileHandle.nullDevice
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
                DispatchQueue.global(qos: .utility).async {
                    do { try proceso.run() } catch { c.resume(returning: ""); return }
                    let corte = DispatchWorkItem { if proceso.isRunning { proceso.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + espera, execute: corte)
                    // Lee hasta que el ayudante se cierra (o lo corta la espera).
                    let datos = salida.fileHandleForReading.readDataToEndOfFile()
                    proceso.waitUntilExit()
                    corte.cancel()
                    let bien = proceso.terminationReason == .exit && proceso.terminationStatus == 0
                    c.resume(returning: bien ? String(decoding: datos, as: UTF8.self) : "")
                }
            }
        } onCancel: {
            if proceso.isRunning { proceso.terminate() }
        }
    }

    /// Del lado del ayudante: lee la ventana, escribe el texto y se cierra. Nunca vuelve.
    static func correr(_ argumentos: [String]) -> Never {
        guard padreEsDixity() else { exit(2) }
        guard let i = argumentos.firstIndex(of: argumento), i + 2 < argumentos.count,
              let pid = pid_t(argumentos[i + 1]), let tope = Int(argumentos[i + 2]) else { exit(3) }
        Task.detached(priority: .userInitiated) {
            // `Pantalla.leer` ya tapa lo que parece una clave antes de devolverlo.
            let texto = await Pantalla.leer(pid: pid, tope: min(max(tope, 0), 20_000))
            FileHandle.standardOutput.write(Data(texto.utf8))
            exit(0)
        }
        RunLoop.main.run()
        exit(0)
    }

    /// El proceso que abrió al ayudante tiene la misma firma que él (mismo identificador y mismo equipo de Apple; en
    /// una copia con firma local, el mismo programa exacto). Si no se puede comprobar, no (falla cerrado).
    static func padreEsDixity() -> Bool {
        var propio: SecCode?
        guard SecCodeCopySelf([], &propio) == errSecSuccess, let propio else { return false }
        var estatico: SecStaticCode?
        guard SecCodeCopyStaticCode(propio, [], &estatico) == errSecSuccess, let estatico else { return false }
        var requisito: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(estatico, [], &requisito) == errSecSuccess, let requisito else { return false }
        var padre: SecCode?
        let atributos = [kSecGuestAttributePid: getppid()] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, atributos, [], &padre) == errSecSuccess, let padre else { return false }
        return SecCodeCheckValidity(padre, [], requisito) == errSecSuccess
    }
}
