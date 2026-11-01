import AppKit

// Sacudir el mouse prende la Varita. Se cuenta cuántas veces el puntero cambia de dirección
// de izquierda a derecha en poco tiempo, con tramos largos: moverlo normal, apuntar o arrastrar nunca llega.
// Apagado no se escucha nada; prendido, solo se miran las coordenadas del mouse (nunca la pantalla).
struct DetectorSacudida {
    enum Sensibilidad: String, Codable, CaseIterable, Identifiable {
        case baja, media, alta
        var id: String { rawValue }
        var nombre: String {
            switch self {
            case .baja: T("Baja", "Low")
            case .media: T("Media", "Medium")
            case .alta: T("Alta", "High")
            }
        }
    }

    // Media pide 4 idas y vueltas de 36 pt en 0,8 s, bien de costado. Hasta el 31/10 a la noche eran 3 de 28 pt (lo que
    // hoy es Alta) y se prendía sola moviendo el mouse normal.
    var vueltas = 4                         // cambios de dirección que hacen falta…
    var ventana: TimeInterval = 0.8         // …dentro de este tiempo
    var tramo: CGFloat = 36                 // cada ida o vuelta, de al menos tantos puntos
    var desvio: CGFloat = 0.6               // y cada tramo, más de costado que de arriba abajo (vertical < horizontal × esto)
    var espera: TimeInterval = 1.2          // después de una sacudida, no cuenta otra enseguida…
    var calma: TimeInterval = 0.25          // …ni hasta que el mouse se quede quieto este rato
    // A propósito: si seguís sacudiendo después de que se prendió, no se apaga (antes, una sacudida larga la prendía
    // y a los 1,5 s la apagaba: parecía que andaba una vez sí y otra no; 31/10/2026).
    private var esperandoCalma = false

    private var ultimo: CGPoint?
    private var hora: TimeInterval = 0
    private var direccion: CGFloat = 0      // -1 izquierda, 1 derecha
    private var horizontal: CGFloat = 0     // lo recorrido en este tramo
    private var vertical: CGFloat = 0
    private var cambios: [TimeInterval] = []
    private var ultimaSacudida: TimeInterval = -.infinity

    init(_ s: Sensibilidad = .media) {
        switch s {
        case .baja: vueltas = 5; tramo = 44; ventana = 0.95
        case .media: break
        case .alta: vueltas = 3; tramo = 28; ventana = 0.7; desvio = 0.8
        }
    }

    // Una posición nueva del mouse. true = fue una sacudida.
    mutating func mover(a p: CGPoint, hora t: TimeInterval) -> Bool {
        defer { ultimo = p; hora = t }
        guard let u = ultimo else { return false }
        // Una pausa corta el gesto: se empieza de nuevo (y, si veníamos de una sacudida, ya hubo calma).
        if t - hora > calma { esperandoCalma = false }
        if t - hora > 0.15 { reiniciar(); return false }
        guard !esperandoCalma else { return false }
        let dx = p.x - u.x, dy = p.y - u.y
        guard abs(dx) > 0.5 else { vertical += abs(dy); return false }
        let sentido: CGFloat = dx > 0 ? 1 : -1
        if sentido == direccion {
            horizontal += abs(dx)
            vertical += abs(dy)
            return false
        }
        // Cambió de dirección: cuenta si el tramo anterior fue largo y más de costado que de arriba abajo.
        if direccion != 0 && horizontal >= tramo && vertical < horizontal * desvio { cambios.append(t) }
        direccion = sentido
        horizontal = abs(dx)
        vertical = abs(dy)
        cambios.removeAll { t - $0 > ventana }
        guard cambios.count >= vueltas, t - ultimaSacudida > espera else { return false }
        ultimaSacudida = t
        esperandoCalma = true
        reiniciar()
        return true
    }

    private mutating func reiniciar() {
        cambios = []
        direccion = 0
        horizontal = 0
        vertical = 0
    }
}

// Escucha el mouse en todas las apps (sin pedir permisos nuevos: macOS deja mirar el movimiento) y avisa al sacudirlo.
// Mientras arrastrás no llegan movimientos sueltos, así que arrastrar nunca cuenta.
final class Sacudida {
    var alSacudir: ((CGPoint) -> Void)?
    private var monitor: Any?
    private var detector = DetectorSacudida()

    func prender(_ sensibilidad: DetectorSacudida.Sensibilidad) {
        detector = DetectorSacudida(sensibilidad)
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            guard let self else { return }
            let p = NSEvent.mouseLocation
            if self.detector.mover(a: p, hora: e.timestamp) { self.alSacudir?(p) }
        }
    }

    func apagar() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}
