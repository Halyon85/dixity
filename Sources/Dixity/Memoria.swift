import Foundation

// Memoria propia: un archivo chico (memoria.md, hasta ~1.500 caracteres) donde Dixity anota lo que más le sirve para
// entenderte: quién sos, con quién y en qué trabajás, nombres que repetís y cómo te gusta que quede el texto.
// La arma la app sola: cada tantos dictados le pide a la IA elegida que la actualice con los últimos. Vive en la Mac
// (nunca en un servidor); se puede ver, editar y borrar en Voz › Memoria. Va en cada pedido a la IA.
final class Memoria: ObservableObject {
    static let shared = Memoria()
    static let tope = 1500
    static let cadaCuantos = 12        // dictados entre una actualización y la siguiente

    private let archivo = Almacen.carpeta.appendingPathComponent("memoria.md")
    @Published var texto: String { didSet { if texto != oldValue { guardar() } } }
    @Published private(set) var actualizando = false
    private(set) var pendientes: [String] = []
    // Sube cada vez que la memoria se borra, se edita a mano o se vacía el historial: una actualización que estaba
    // en camino con la versión vieja se descarta en vez de resucitar lo borrado (auditoría del 23/10/2026).
    private(set) var generacion = 0

    private init() {
        texto = (try? String(contentsOf: archivo, encoding: .utf8)) ?? ""
    }

    private func guardar() {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { try? FileManager.default.removeItem(at: archivo) }
        else { try? t.write(to: archivo, atomically: true, encoding: .utf8) }
    }

    // Lo que va en el pedido a la IA.
    var paraPrompt: String {
        guard Ajustes.shared.datos.memoriaActiva else { return "" }
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : String(t.prefix(Memoria.tope + 200))
    }

    // Después de cada dictado (lo llama Motor.entregar): se junta y, cada `cadaCuantos`, se actualiza en segundo plano.
    // Solo aprende de lo que dijiste (la transcripción), nunca de lo que escribió la IA ni de una reescritura: esos
    // textos pueden traer cosas de la pantalla o de un mail ajeno que después irían en cada pedido (auditoría 23/10/2026).
    func anotar(_ r: Registro) {
        guard Ajustes.shared.datos.memoriaActiva, let linea = Memoria.linea(de: r) else { return }
        pendientes.append(linea)
        if pendientes.count >= Memoria.cadaCuantos { actualizar() }
    }

    // La línea que aporta un dictado a la memoria, o nil si no corresponde (reescritura, reproceso o muy corto).
    static func linea(de r: Registro) -> String? {
        let dicho = r.transcripcion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.modo == .dictado, r.reprocesoDe == nil, dicho.count >= 20 else { return nil }
        let estilo = r.estilo.map { " [\($0)]" } ?? ""
        return "- \(r.app)\(estilo): \(dicho.prefix(300))"
    }

    // Lo llama Historial.vaciar: los dictados borrados no tienen que llegar a la memoria después.
    func olvidarPendientes() {
        pendientes = []
        generacion += 1
    }

    func actualizar(listo: ((String?) -> Void)? = nil) {
        let a = Ajustes.shared
        guard !actualizando, a.iaLista else { listo?(T("Hace falta una IA en Proveedores.", "You need an AI set up in Providers.")); return }
        let nuevos = pendientes.isEmpty
            ? Array(Historial.shared.registros.compactMap(Memoria.linea(de:)).prefix(Memoria.cadaCuantos))
            : pendientes
        guard !nuevos.isEmpty else { listo?(T("Todavía no hay dictados para aprender.", "No dictations to learn from yet.")); return }
        pendientes = []
        actualizando = true
        let actual = texto
        let gen = generacion
        Task.detached {
            var fallo: String?
            do {
                let r = Prompts.limpiarSalida(try await Proveedores.completar(
                    sistema: Prompts.sistemaMemoria, usuario: Prompts.usuarioMemoria(actual: actual, dictados: nuevos), ajustes: a))
                // Si vuelve vacía o enorme, se queda la anterior.
                if r.isEmpty || r.count > Memoria.tope * 2 { fallo = T("La IA devolvió algo raro; quedó la memoria anterior.", "The AI returned something odd; kept the previous memory.") }
                else {
                    let guardada = await MainActor.run { Memoria.shared.aplicar(String(r.prefix(Memoria.tope)), generacion: gen, anterior: actual) }
                    if !guardada { fallo = T("La memoria cambió mientras se actualizaba: no se tocó.", "The memory changed while updating; it was left as is.") }
                }
            } catch { fallo = error.localizedDescription }
            let mensaje = fallo
            await MainActor.run {
                Memoria.shared.actualizando = false
                listo?(mensaje)
            }
        }
    }

    // Guarda la memoria nueva solo si nadie la borró ni la editó mientras la IA la armaba. Devuelve si la guardó.
    @discardableResult
    func aplicar(_ nueva: String, generacion gen: Int, anterior: String) -> Bool {
        guard gen == generacion, texto == anterior, Ajustes.shared.datos.memoriaActiva else { return false }
        texto = nueva
        return true
    }

    func borrar() {
        pendientes = []
        generacion += 1
        texto = ""
    }
}
