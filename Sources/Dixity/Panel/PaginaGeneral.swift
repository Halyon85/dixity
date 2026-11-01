import AppKit
import SwiftUI

// General: permisos, píldora, inicio, apariencia, idioma y Acerca de.
struct PaginaGeneral: View {
    @ObservedObject var ajustes: Ajustes
    let motor: Motor
    let refresco: Int
    let pedirTeclado: () -> Void
    var verBienvenida: () -> Void = {}
    @Estado private var alInicio = InicioSesion.activo

    var body: some View {
        let _ = refresco
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        TituloPagina(titulo: T("General", "General"), subtitulo: T("Permisos, inicio y apariencia.", "Permissions, startup and appearance."))
        Tarjeta(titulo: T("Permisos", "Permissions")) {
            Fila(titulo: T("Micrófono", "Microphone"), detalle: T("Solo se prende mientras dictás.", "Only on while you dictate.")) {
                if Grabador.permitido { Etiqueta(ok: true) }
                else {
                    BotonSecundario(texto: T("Permitir", "Allow")) {
                        Grabador.pedirPermiso { ok in
                            if !ok { abrirAjustes("Privacy_Microphone") }
                        }
                    }
                }
            }
            Fila(titulo: T("Accesibilidad", "Accessibility"), detalle: T("Para escuchar tu atajo en cualquier app y pegar el texto donde está el cursor.", "To catch your shortcut in any app and paste the text where your cursor is."), divisor: false) {
                if Cursor.accesibilidadPermitida && motor.monitor.activo { Etiqueta(ok: true) }
                else if Cursor.accesibilidadPermitida {
                    BotonSecundario(texto: T("Activar", "Turn on")) { pedirTeclado() }
                } else {
                    BotonSecundario(texto: T("Permitir", "Allow")) {
                        Cursor.pedirAccesibilidad()
                        abrirAjustes("Privacy_Accessibility")
                        pedirTeclado()
                    }
                }
            }
        }
        Tarjeta(titulo: T("Píldora", "Pill")) {
            Fila(titulo: T("Estilo", "Style")) {
                Selector(valor: $ajustes.datos.estiloPildora, opciones: EstiloPildora.allCases, nombre: \.nombre, ancho: 270)
            }
            Fila(titulo: T("Transparencia", "Transparency"), detalle: T("Más a la izquierda, más se ve lo que hay detrás.", "Slide left to see more of what's behind it.")) {
                Slider(value: $ajustes.datos.opacidadPildora, in: 0.4...1).frame(width: 200)
            }
            Fila(titulo: T("Tamaño", "Size")) {
                Segmentos(valor: $ajustes.datos.tamanoPildora, opciones: TamanoPildora.allCases, nombre: \.nombre)
            }
            Fila(titulo: T("Posición", "Position"), detalle: T("Arrastrá la píldora con el mouse a donde quieras; se acuerda del lugar.", "Drag the pill anywhere with your mouse; it remembers the spot."), divisor: false) {
                BotonSecundario(texto: T("Mostrarla para moverla", "Show to move"), icono: "hand.draw") { motor.pildora.mostrarParaMover() }
                BotonSecundario(texto: T("Al centro", "Recenter"), icono: "arrow.down.to.line") {
                    motor.pildora.volverAlCentro()
                    motor.pildora.mostrarParaMover()
                }
            }
        }
        Tarjeta(titulo: T("Aplicación", "App")) {
            Fila(titulo: T("Abrir al iniciar sesión", "Open at login"),
                 detalle: InicioSesion.esperaAprobacion ? T("Falta aprobarlo en Ajustes del Sistema › General › Ítems de inicio.", "Approve it in System Settings › General › Login Items.")
                                                        : T("Así el atajo funciona siempre.", "So your shortcut always works.")) {
                Toggle("", isOn: $alInicio).toggleStyle(.switch).labelsHidden()
                    .onChange(of: alInicio) { _, v in InicioSesion.cambiar(v) }
            }
            Fila(titulo: T("Apariencia", "Appearance")) {
                Selector(valor: $ajustes.datos.apariencia, opciones: Apariencia.allCases, nombre: \.nombre, ancho: 180)
            }
            Fila(titulo: T("Idioma de la interfaz", "Interface language"), detalle: T("Cambia los textos de Dixity. No cambia el idioma en el que dictás.", "Changes Dixity's own texts. It doesn't change the language you dictate in."), divisor: false) {
                Selector(valor: $ajustes.datos.idiomaInterfaz, opciones: IdiomaInterfaz.allCases, nombre: \.nombre, ancho: 180)
            }
        }
        Tarjeta(titulo: T("Acerca de", "About")) {
            Fila(titulo: "Dixity", detalle: T("Versión \(version). Dictado por voz para Mac, con tus propias API o todo en tu Mac. Código abierto, licencia Apache 2.0.",
                                              "Version \(version). Voice dictation for Mac, with your own API keys or fully on your Mac. Open source, Apache 2.0 license.")) {
                LogoApp(tam: 32)
            }
            // Solo en las versiones publicadas: la que compila cada uno se actualiza con git pull (ver Actualizaciones).
            if Actualizaciones.disponibles {
                Fila(titulo: T("Actualizaciones", "Updates"), detalle: T("Dixity busca una versión nueva una vez por día y te pregunta antes de instalarla.",
                                                                          "Dixity checks for a new version once a day and asks before installing it.")) {
                    BotonSecundario(texto: T("Buscar ahora", "Check now"), icono: "arrow.down.circle") { Actualizaciones.buscar() }
                }
            }
            Fila(titulo: T("Bienvenida", "Welcome"), detalle: T("Los pasos de la primera vez: permisos, IA y una prueba.", "The first-run steps: permissions, AI and a quick test.")) {
                BotonSecundario(texto: T("Ver de nuevo", "Show again"), icono: "sparkles") { verBienvenida() }
            }
            Fila(titulo: T("Tus datos", "Your data"),
                 detalle: T("El audio va solo al proveedor de voz que elegiste y el texto al de IA. Historial, audios y portapapeles (24 horas), diccionario y ajustes quedan en esta Mac; las claves, en el llavero. Con Parakeet, el audio no sale de la Mac.",
                            "Audio only goes to the voice provider you chose, and text to your AI provider. History, recordings and clipboard (24 hours), dictionary and settings stay on this Mac; keys stay in the Keychain. With Parakeet, audio never leaves your Mac.")) {
                BotonSecundario(texto: T("Ver carpeta", "Show folder"), icono: "folder") { NSWorkspace.shared.open(Almacen.carpeta) }
            }
            Fila(titulo: T("Créditos", "Credits"),
                 detalle: T("Voz a texto: Parakeet (NVIDIA y moondream, CC BY 4.0) con FluidAudio (FluidInference, Apache 2.0). Detalle en el archivo NOTICE.",
                            "Speech to text: Parakeet (NVIDIA and moondream, CC BY 4.0) via FluidAudio (FluidInference, Apache 2.0). Details in the NOTICE file."), divisor: false) {
                EmptyView()
            }
        }
    }

    private func abrirAjustes(_ ancla: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(ancla)") { NSWorkspace.shared.open(url) }
    }
}

struct Etiqueta: View {
    let ok: Bool
    var textoOk = T("Permitido", "Allowed")
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(ok ? textoOk : T("Falta", "Missing"))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(ok ? Tema.exito : Tema.error)
    }
}
