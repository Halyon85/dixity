import SwiftUI

// Acciones rápidas (Modos): con texto seleccionado, un atajo lo reescribe con una instrucción fija y lo pega en su
// lugar, sin hablar (Motor.ejecutarAccion). Vienen Ordenar, Resumir y Corregir; se pueden cambiar, borrar y sumar.
struct TarjetaAcciones: View {
    @ObservedObject var ajustes: Ajustes
    let motor: Motor

    var body: some View {
        Tarjeta(titulo: T("Acciones rápidas", "Quick actions")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(T("Seleccioná un texto y apretá el atajo: Dixity lo reescribe con esa instrucción y lo pega en su lugar, sin que hables. Usa la IA de Proveedores. Para pedir otra cosa, mantené Reescribir y decila.",
                        "Select some text and press the shortcut: Dixity rewrites it with that instruction and pastes it in place, no talking needed. It uses the AI in Providers. For anything else, hold Rewrite and say it."))
                    .font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
                ForEach($ajustes.datos.acciones) { $accion in
                    HStack(alignment: .top, spacing: 10) {
                        TextField(T("Nombre", "Name"), text: $accion.nombre).textFieldStyle(.roundedBorder).frame(width: 110)
                        TextField(T("Qué hacer con el texto", "What to do with the text"), text: $accion.instruccion, axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(1...3)
                        GrabadorAtajoPropio(ajustes: ajustes, motor: motor, atajo: $accion.atajo,
                                            ayuda: T("Ponerle un atajo a esta acción", "Give this action a shortcut"))
                            .padding(.top, 2)
                        Button { borrar(accion.id) } label: { Image(systemName: "trash").font(.system(size: 12)) }
                            .buttonStyle(.plain).foregroundStyle(Tema.apagado).padding(.top, 5)
                            .help(T("Borrar esta acción", "Delete this action"))
                    }
                }
                if ajustes.datos.acciones.count < AccionRapida.maximo {
                    BotonSecundario(texto: T("Sumar acción", "Add action"), icono: "plus") {
                        ajustes.datos.acciones.append(AccionRapida(nombre: "", instruccion: ""))
                    }
                }
            }
            .padding(16)
        }
    }

    private func borrar(_ id: UUID) {
        ajustes.datos.acciones.removeAll { $0.id == id }
        motor.actualizarAtajos()
    }
}
