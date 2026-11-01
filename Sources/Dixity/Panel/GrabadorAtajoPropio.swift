import AppKit
import SwiftUI

// Atajo propio de un modo o de una acción rápida (por ejemplo ⌃⌥M para Correo, ⌃⌥O para Ordenar). Tiene que llevar
// una tecla, no solo modificadores, y no chocar con ningún otro atajo de Dixity ni con "combinación + número".
// Lo usan Modos (TarjetaModos) y Acciones rápidas (TarjetaAcciones).
struct GrabadorAtajoPropio: View {
    @ObservedObject var ajustes: Ajustes
    let motor: Motor
    @Binding var atajo: Atajo?
    let ayuda: String
    @Estado private var grabando = false
    @Estado private var vistos = Set<Modificador>()
    @Estado private var mensaje: String?
    @Estado private var monitorLocal: Any?

    var body: some View {
        HStack(spacing: 4) {
            if grabando {
                Text(mensaje ?? (vistos.isEmpty ? T("Apretá el atajo…", "Press the shortcut…") : Atajo(modificadores: Array(vistos), tecla: nil).descripcion + " + …"))
                    .font(.system(size: 11)).foregroundStyle(mensaje == nil ? Tema.acento : Tema.error).lineLimit(1)
                Button { terminar() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(Tema.apagado).help(T("Cancelar", "Cancel"))
            } else if let a = atajo {
                Button { empezar() } label: { Teclas(atajo: a) }.buttonStyle(.plain).help(T("Cambiar el atajo", "Change the shortcut"))
                Button { atajo = nil } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(Tema.apagado).help(T("Quitar el atajo", "Remove the shortcut"))
            } else {
                Button { empezar() } label: {
                    Text(T("+ Atajo", "+ Shortcut")).font(.system(size: 11, weight: .medium)).foregroundStyle(Tema.apagado)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Tema.bordeSuave))
                }
                .buttonStyle(.plain).help(ayuda)
            }
        }
        .frame(minWidth: 70, alignment: .trailing)
        .onDisappear { terminar() }
    }

    // Todos los atajos de Dixity menos el que se está cambiando.
    private var otros: [Atajo] {
        let d = ajustes.datos
        let todos = [d.atajoDictar, d.atajoReescribir, d.atajoPortapapeles, d.atajoReprocesar, d.atajoSumarPalabra, d.atajoPreguntar]
            + d.modos.compactMap(\.atajo) + [d.atajoAutomatico].compactMap { $0 } + d.acciones.compactMap(\.atajo)
        return todos.filter { $0 != atajo }
    }

    private func empezar() {
        mensaje = nil; vistos = []; grabando = true
        motor.suspenderAtajos()
        monitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { e in
            procesar(e)
            return nil
        }
    }

    private func terminar() {
        if let m = monitorLocal { NSEvent.removeMonitor(m) }
        monitorLocal = nil
        grabando = false
        vistos = []
        motor.actualizarAtajos()
    }

    private func procesar(_ e: NSEvent) {
        if e.type == .flagsChanged {
            guard let m = Modificador.desdeCodigo(Int64(e.keyCode)) else { return }
            if UInt64(e.modifierFlags.rawValue) & m.mascara != 0 { vistos.insert(m) } else { vistos.remove(m) }
            return
        }
        if e.keyCode == 53 && vistos.isEmpty { terminar(); return }
        if e.isARepeat { return }
        let nuevo = Atajo(modificadores: Array(vistos), tecla: Int64(e.keyCode))
        if let p = nuevo.problema(otros: otros) { mensaje = p; vistos = []; return }
        let d = ajustes.datos
        let digitos: Set<Int64> = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
        if d.atajosNumero && digitos.contains(Int64(e.keyCode)) && Set(vistos.map(\.familia)) == d.teclaModos.familias {
            mensaje = T("Esa ya la usa \"combinación + número\".", "That one is already used by \"combo + number\".")
            vistos = []
            return
        }
        atajo = nuevo
        terminar()
    }
}
