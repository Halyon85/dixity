import AppKit
import SwiftUI

struct PaginaVoz: View {
    @ObservedObject var ajustes: Ajustes
    @ObservedObject private var memoria = Memoria.shared
    @Estado private var avisoMemoria: String?

    // El de la Mac, los conectados y el elegido aunque no esté conectado (así no se pierde la elección).
    private var microfonos: [Microfono] {
        var l = [Microfonos.sistema] + Microfonos.lista()
        let elegido = ajustes.datos.microfono
        if !elegido.isEmpty && !l.contains(where: { $0.id == elegido }) {
            l.append(Microfono(id: elegido, nombre: T("El elegido (no conectado)", "Your pick (not connected)")))
        }
        return l
    }
    private var microfono: Binding<Microfono> {
        Binding(get: { microfonos.first { $0.id == ajustes.datos.microfono } ?? Microfonos.sistema },
                set: { ajustes.datos.microfono = $0.id })
    }

    var body: some View {
        TituloPagina(titulo: T("Voz", "Voice"), subtitulo: T("Cómo escucha, qué mira y cómo pasa en limpio. Los cambios valen desde el próximo dictado.",
                                                        "How it listens, what it looks at and how it cleans up. Changes apply from your next dictation."))
        Tarjeta(titulo: T("Reconocimiento", "Recognition")) {
            Fila(titulo: T("Idioma", "Language"), detalle: T("Automático detecta español o inglés en cada dictado.", "Automatic detects Spanish or English on each dictation.")) {
                Selector(valor: $ajustes.datos.idioma, opciones: Idioma.allCases, nombre: \.nombre, ancho: 160)
            }
            Fila(titulo: T("Micrófono", "Microphone"),
                 detalle: T("Si tenés más de uno, elegí con cuál dictar. Si no está conectado, Dixity usa el de la Mac.",
                            "If you have more than one, pick which one to dictate with. If it's not connected, Dixity uses the system default."), divisor: false) {
                Selector(valor: microfono, opciones: microfonos, nombre: \.nombre, ancho: 240)
            }
        }
        Tarjeta(titulo: T("Contexto", "Context")) {
            Fila(titulo: T("Mirar la ventana", "Look at the window"),
                 detalle: T("Lee el texto alrededor del cursor y el nombre de la app para escribir bien nombres y seguir la frase.",
                            "Reads the text around your cursor and the app name to spell names right and continue your sentence.")) {
                Toggle("", isOn: $ajustes.datos.mirarVentana).toggleStyle(.switch).labelsHidden()
            }
            Fila(titulo: T("Leer la pantalla", "Read the screen"),
                 detalle: T("Al empezar a dictar lee el texto de la ventana de adelante, acá en la Mac, y descarta la imagen: no se guarda ni se manda. A la IA le llega solo el texto (hasta 1.500 caracteres), con lo que parece una clave tapado. No lee nada si estás escribiendo una contraseña o tenés un gestor de contraseñas adelante. Si tenés claves a la vista, apagalo.",
                            "When you start dictating, it reads the text in the front window right here on your Mac and discards the image: it's never saved or sent. The AI only gets the text (up to 1,500 characters), with anything that looks like a key hidden. It reads nothing while you type a password or with a password manager in front. If you have keys on screen, turn it off."), divisor: false) {
                if ajustes.datos.leerPantalla && !Pantalla.permitido {
                    BotonSecundario(texto: T("Dar permiso", "Grant access"), icono: "rectangle.dashed") { Pantalla.pedirPermiso() }
                }
                Toggle("", isOn: $ajustes.datos.leerPantalla).toggleStyle(.switch).labelsHidden()
                    .disabled(!ajustes.datos.mirarVentana)
                    .onChange(of: ajustes.datos.leerPantalla) { _, si in if si && !Pantalla.permitido { Pantalla.pedirPermiso() } }
            }
        }
        Tarjeta(titulo: T("Pasar en limpio", "Clean-up")) {
            Fila(titulo: T("Limpiar con IA", "Clean up with AI"),
                 detalle: T("Saca muletillas, aplica tus correcciones (\"a las tres, no, a las cuatro\") y pone puntuación. Apagado, en el modo Común pega lo que escuchó tal cual; los otros modos, la reescritura y la memoria siguen usando la IA de Proveedores.",
                            "Removes filler words, applies your corrections (\"at three, no, at four\") and adds punctuation. When off, Common mode pastes exactly what it heard; the other modes, rewriting and memory still use the AI in Providers.")) {
                Toggle("", isOn: $ajustes.datos.limpiarConIA).toggleStyle(.switch).labelsHidden()
            }
            Fila(titulo: T("Limpieza básica sin IA", "Basic clean-up without AI"),
                 detalle: T("Cuando el dictado no pasa por la IA (o la IA falla), saca muletillas como \"eh\", \"em\" o \"mmm\" y marcas como \"[música]\".",
                            "When a dictation doesn't go through the AI (or the AI fails), it removes fillers like \"uh\", \"um\" or \"hmm\" and tags like \"[music]\".")) {
                Toggle("", isOn: $ajustes.datos.limpiezaBasica).toggleStyle(.switch).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(T("Preferencias para la IA", "AI preferences")).font(.titulo(14, .regular)).foregroundStyle(Tema.titulo)
                Text(T("Opcional. Ej.: \"Escribí en español rioplatense (vos)\", \"Nunca uses emojis\", \"Firmá los mails como Ana\".",
                        "Optional. E.g. \"Write in British English\", \"Never use emojis\", \"Sign emails as Alex\"."))
                    .font(.system(size: 12)).foregroundStyle(Tema.apagado)
                TextEditor(text: $ajustes.datos.instruccionesExtra)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 70)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Tema.rellenoSuave))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Tema.bordeSuave))
                instruccionesPorApp.padding(.top, 10)
            }
            .padding(16)
        }
        Tarjeta(titulo: T("Memoria", "Memory")) {
            Fila(titulo: T("Memoria propia", "Personal memory"),
                 detalle: avisoMemoria ?? T("Dixity anota en un archivo chico de esta Mac lo que más le sirve para entenderte (nombres, proyectos, cómo hablás). Se actualiza sola cada \(Memoria.cadaCuantos) dictados con tu IA y va en cada pedido. Podés corregirla acá.",
                                            "Dixity keeps a small file on this Mac with what helps it understand you best (names, projects, how you talk). Your AI updates it every \(Memoria.cadaCuantos) dictations and it goes with every request. You can edit it here.")) {
                Toggle("", isOn: $ajustes.datos.memoriaActiva).toggleStyle(.switch).labelsHidden()
            }
            if ajustes.datos.memoriaActiva {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $memoria.texto)
                        .font(.system(size: 12))
                        .frame(height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tema.bordeSuave))
                    HStack {
                        Text(T("\(memoria.texto.count) / \(Memoria.tope) caracteres", "\(memoria.texto.count) / \(Memoria.tope) characters")).font(.system(size: 11)).foregroundStyle(Tema.apagado)
                        Spacer()
                        BotonSecundario(texto: memoria.actualizando ? T("Actualizando…", "Updating…") : T("Actualizar ahora", "Update now"), icono: "arrow.clockwise") {
                            avisoMemoria = nil
                            memoria.actualizar { error in avisoMemoria = error }
                        }
                        BotonSecundario(texto: T("Borrar", "Clear"), icono: "trash") { memoria.borrar() }
                    }
                }
                .padding(16)
            }
        }
        Tarjeta(titulo: T("Mientras dictás", "While dictating")) {
            Fila(titulo: T("Pausar la música", "Pause music"),
                 detalle: T("Pausa lo que esté sonando mientras dictás y lo vuelve a poner al terminar. Si no sonaba nada, no toca nada. Con Spotify o Música, la primera vez macOS te pide permiso.",
                            "Pauses whatever is playing while you dictate and resumes it when you finish. If nothing was playing, it does nothing. With Spotify or Music, macOS asks for permission the first time.")) {
                Toggle("", isOn: $ajustes.datos.pausarMusica).toggleStyle(.switch).labelsHidden()
            }
            Fila(titulo: T("Sonidos", "Sounds"), detalle: T("Uno al empezar a escuchar y otro al terminar.", "One when it starts listening, another when it stops."), divisor: false) {
                Toggle("", isOn: $ajustes.datos.sonidoAlEmpezar).toggleStyle(.switch).labelsHidden()
            }
        }
    }

    // Instrucción por app o sitio: se suma a las preferencias cuando dictás ahí (Ajustes.instruccionPara).
    private var instruccionesPorApp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("Por app o sitio", "Per app or site")).font(.titulo(14, .regular)).foregroundStyle(Tema.titulo)
            Text(T("Se suman a las de arriba cuando dictás ahí. Alcanza con una parte del nombre; en el navegador vale el título de la pestaña. Ej.: LinkedIn → \"tono profesional, sin emojis\".",
                    "Added to the ones above when you dictate there. Part of the name is enough; in a browser, the tab title counts. E.g. LinkedIn → \"professional tone, no emojis\"."))
                .font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
            ForEach($ajustes.datos.instruccionesApp) { $i in
                HStack(alignment: .top, spacing: 10) {
                    TextField(T("App o sitio", "App or site"), text: $i.app).textFieldStyle(.roundedBorder).frame(width: 130)
                    TextField(T("Cómo escribir ahí", "How to write there"), text: Binding(
                        get: { i.texto }, set: { i.texto = String($0.prefix(InstruccionApp.tope)) }), axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...3)
                    Button { ajustes.datos.instruccionesApp.removeAll { $0.id == i.id } } label: {
                        Image(systemName: "trash").font(.system(size: 12))
                    }
                    .buttonStyle(.plain).foregroundStyle(Tema.apagado).padding(.top, 5)
                    .help(T("Borrar", "Delete"))
                }
            }
            if ajustes.datos.instruccionesApp.count < InstruccionApp.maximo {
                BotonSecundario(texto: T("Sumar app o sitio", "Add app or site"), icono: "plus") {
                    ajustes.datos.instruccionesApp.append(InstruccionApp(app: "", texto: ""))
                }
            }
        }
    }
}
