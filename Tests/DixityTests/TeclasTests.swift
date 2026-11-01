import CoreGraphics
import Darwin
import Foundation
import Testing
@testable import Dixity

// Tocar o mantener el atajo: el tiempo sostenido sale de cuándo pasaron las teclas, no de cuándo la app las atendió.
struct TeclasTests {
    // Un toque de 0,2 s con la app ocupada 0,7 s en el medio (como cuando empieza a grabar y lee la ventana).
    private func sostenido(enTics: Bool) -> TimeInterval? {
        let monitor = MonitorAtajos()
        monitor.atajos = [.dictar: Atajo(modificadores: [], tecla: 0)]
        var medido: TimeInterval?
        monitor.alEvento = { if case .soltar(_, let s) = $0 { medido = s } }
        var base = mach_timebase_info()
        mach_timebase_info(&base)
        let ahora = enTics ? mach_absolute_time() : clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let toque = enTics ? UInt64(0.2e9) * UInt64(base.denom) / UInt64(base.numer) : UInt64(0.2e9)
        let abajo = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        let arriba = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
        abajo.timestamp = ahora
        arriba.timestamp = ahora + toque
        _ = monitor.procesar(.keyDown, abajo)
        Thread.sleep(forTimeInterval: 0.7)
        _ = monitor.procesar(.keyUp, arriba)
        return medido
    }

    @Test func unToqueCortoSigueSiendoToqueAunqueLaAppTardeEnAtenderlo() throws {
        for enTics in [false, true] {
            let s = try #require(sostenido(enTics: enTics))
            #expect(abs(s - 0.2) < 0.01)
            #expect(s < ModoTecla.toqueMaximo)
        }
    }
}
