import AppKit
import SwiftUI

// Modos: cómo da forma a lo que dictás (Común, Prompt, Correo…), cuál usa cada app, sus atajos y colores,
// qué hace después de pegar y los proyectos que lee el modo Prompt. Todo lo de modos vive acá (30/10/2026).
struct PaginaModos: View {
    @ObservedObject var ajustes: Ajustes
    let motor: Motor

    private func listaApps(_ modo: String, _ lista: Binding<[String]>, ejemplo: String) -> some View {
        HStack(spacing: 10) {
            Text(modo).font(.system(size: 12, weight: .medium)).foregroundStyle(Tema.titulo).frame(width: 64, alignment: .leading)
            TextField(ejemplo, text: Binding(
                get: { lista.wrappedValue.joined(separator: ", ") },
                set: { lista.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                .textFieldStyle(.roundedBorder)
        }
    }

    var body: some View {
        TituloPagina(titulo: T("Modos", "Modes"), subtitulo: T("Cómo da forma a lo que dictás según dónde estés. Los cambios valen desde el próximo dictado.",
                                                          "How Dixity shapes what you dictate depending on where you are. Changes apply from your next dictation."))
        Tarjeta(titulo: T("Modo de tus dictados", "Your dictation mode")) {
            Fila(titulo: T("Cómo pasa en limpio", "How it cleans up"),
                 detalle: T("Común: prolijo, para notas y textos (punto coral). Prompt para IA: ordena lo que decís (idas, vueltas, correcciones) en un pedido claro para un asistente de IA o de programación —Claude, ChatGPT, Codex, Cursor o el que uses—, con el contexto del proyecto si lo tenés (punto violeta). Correo, Mensaje, Formal y Traducir le dan esa forma. Automático elige según la app.",
                            "Standard: tidy, for notes and everyday text (coral dot). AI prompt: turns what you say (back-and-forth, corrections) into a clear request for an AI or coding assistant —Claude, ChatGPT, Codex, Cursor or whichever you use—, with your project's context if you have one (violet dot). Email, Message, Formal and Translate shape it that way. Automatic picks based on the app."),
                 divisor: ajustes.datos.estilo == .automatico) {
                Selector(valor: $ajustes.datos.estilo, opciones: Estilo.allCases, nombre: \.nombre, ancho: 240)
            }
            if ajustes.datos.estilo == .automatico {
                VStack(alignment: .leading, spacing: 6) {
                    Text(T("Qué modo usa en cada app", "Which mode each app uses")).font(.titulo(14, .regular)).foregroundStyle(Tema.titulo)
                    Text(T("Separadas por coma. Alcanza con una parte del nombre de la app; en el navegador vale el título de la pestaña (Gmail, WhatsApp, Claude). El resto, Común.",
                            "Comma-separated. Part of the app name is enough; in a browser, the tab title counts (Gmail, WhatsApp, Claude). Everything else uses Standard."))
                        .font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
                    listaApps(T("Correo", "Email"), $ajustes.datos.appsCorreo, ejemplo: "Mail, Gmail, Outlook…")
                    listaApps(T("Mensaje", "Message"), $ajustes.datos.appsMensaje, ejemplo: "WhatsApp, Slack, Telegram…")
                    listaApps(T("Prompt", "Prompt"), $ajustes.datos.appsTrabajo, ejemplo: "Claude, ChatGPT, Terminal, Cursor…")
                }
                .padding(16)
            }
        }
        TarjetaModos(ajustes: ajustes, motor: motor)
        TarjetaAcciones(ajustes: ajustes, motor: motor)
        Tarjeta(titulo: T("Al pegar y traducir", "Pasting and translating")) {
            Fila(titulo: T("Después de pegar en Prompt", "After pasting in Prompt"),
                 detalle: T("Para mandar el prompt solo en tu asistente (Claude, ChatGPT, Codex, la Terminal…). Solo si Dixity comprobó que el texto entró.",
                            "Sends the prompt automatically in your assistant (Claude, ChatGPT, Codex, Terminal…). Only if Dixity confirmed the text went in.")) {
                Selector(valor: $ajustes.datos.enviarTrabajo, opciones: TeclaEnviar.allCases, nombre: \.nombre, ancho: 200)
            }
            Fila(titulo: T("Después de pegar en Mensaje", "After pasting in Message"), detalle: T("Para mandar el mensaje solo en WhatsApp o Slack.", "Sends the message automatically in WhatsApp or Slack.")) {
                Selector(valor: $ajustes.datos.enviarMensaje, opciones: TeclaEnviar.allCases, nombre: \.nombre, ancho: 200)
            }
            Fila(titulo: T("Emojis en Mensaje", "Emojis in Message"),
                 detalle: T("Con IA, suma uno o dos emojis que acompañen el tono. Nunca en temas serios.", "With AI, adds one or two emojis that fit the tone. Never on serious topics.")) {
                Toggle("", isOn: $ajustes.datos.emojisMensaje).toggleStyle(.switch).labelsHidden()
            }
            Fila(titulo: T("Traducir a", "Translate to"), detalle: T("El idioma del modo Traducir. Escribilo como quieras: inglés, portugués, italiano…", "The language for Translate mode. Write it however you like: English, Portuguese, Italian…"), divisor: false) {
                TextField(T("inglés", "Spanish"), text: $ajustes.datos.idiomaTraduccion).textFieldStyle(.roundedBorder).frame(width: 160)
            }
        }
        Tarjeta(titulo: T("Proyectos y marketing", "Projects and marketing")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(T("Carpetas de proyectos", "Project folders")).font(.titulo(14, .regular)).foregroundStyle(Tema.titulo)
                Text(T("Opcional, para programar: en modo Prompt, Dixity busca qué proyecto aparece en el título de la ventana y lee su README, AGENTS.md o CLAUDE.md para entender tus palabras. Puede ser un proyecto o una carpeta con varios.",
                        "Optional, for coding: in Prompt mode, Dixity looks for the project named in the window title and reads its README, AGENTS.md or CLAUDE.md to understand your words. Add a single project or a folder that holds several."))
                    .font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
                ListaCarpetas(carpetas: $ajustes.datos.carpetasProyectos)
                Divider().padding(.vertical, 6)
                Text(T("Carpetas de marca y marketing", "Brand and marketing folders")).font(.titulo(14, .regular)).foregroundStyle(Tema.titulo)
                Text(T("Para postear: preguntá «armame un post para LinkedIn sobre…» y Claude Code lo arma leyendo la ficha de la marca (si la carpeta tiene «marcas/», cada subcarpeta es una) y el proyecto del producto. Solo lee y nunca publica: «Guardar borrador» lo deja en la carpeta de la marca.",
                        "For posts: ask “write a LinkedIn post about…” and Claude Code drafts it from the brand's files (if the folder has “marcas/”, each subfolder is a brand) and the product's project. It only reads and never publishes: “Save draft” leaves it in the brand's folder."))
                    .font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
                ListaCarpetas(carpetas: $ajustes.datos.carpetasMarketing)
            }
            .padding(16)
        }
    }
}

// Una lista de carpetas con su ✕ y «Agregar carpeta» (proyectos y marketing).
private struct ListaCarpetas: View {
    @Binding var carpetas: [String]

    var body: some View {
        ForEach(carpetas, id: \.self) { c in
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(Tema.apagado)
                Text(c).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { carpetas.removeAll { $0 == c } } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Tema.apagado)
                }
                .buttonStyle(.plain)
            }
        }
        BotonSecundario(texto: T("Agregar carpeta", "Add folder"), icono: "plus") { elegir() }
    }

    private func elegir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = T("Agregar", "Add")
        guard panel.runModal() == .OK else { return }
        for u in panel.urls where !carpetas.contains(u.path) { carpetas.append(u.path) }
    }
}

// Modos: con qué combinación se eligen, si se cambian con números mientras grabás, y cada modo con su número,
// su color en la píldora y su lugar en la lista (subir/bajar cambia el número).
private struct TarjetaModos: View {
    @ObservedObject var ajustes: Ajustes
    let motor: Motor

    var body: some View {
        let k = ajustes.datos.teclaModos.simbolo
        Tarjeta(titulo: T("Atajos, orden y colores", "Shortcuts, order and colors")) {
            Fila(titulo: T("Elegir modo con atajo", "Pick a mode with a shortcut"),
                 detalle: T("\(k) + el número del modo lo elige para tus próximos dictados (no graba: la píldora te muestra a cuál pasaste); \(k)0 vuelve a Automático. A cada modo también le podés poner un atajo propio, abajo. O decilo: \"…en formato correo\", \"traducilo al inglés\".",
                            "\(k) + the mode's number picks it for your next dictations (it doesn't record: the pill shows which one you switched to); \(k)0 goes back to Automatic. You can also give each mode its own shortcut below. Or say it: \"…in email format\", \"translate it to Spanish\".")) {
                Toggle("", isOn: $ajustes.datos.atajosNumero).toggleStyle(.switch).labelsHidden()
            }
            Fila(titulo: T("Combinación", "Combo"),
                 detalle: T("fn + número cambia de equipo en muchos teclados Bluetooth: por eso viene ⌃⌥.", "On many Bluetooth keyboards, fn + number switches devices: that's why the default is ⌃⌥.")) {
                Selector(valor: $ajustes.datos.teclaModos, opciones: TeclaModos.allCases, nombre: \.nombre, ancho: 260)
            }
            Fila(titulo: T("Cambiar mientras grabás", "Switch while recording"),
                 detalle: T("Tocá el número de un modo mientras dictás: la píldora muestra a cuál pasaste, con su color.",
                            "Press a mode's number while dictating: the pill shows which one you switched to, in its color.")) {
                Toggle("", isOn: $ajustes.datos.numerosGrabando).toggleStyle(.switch).labelsHidden()
            }
            VStack(spacing: 6) {
                filaAutomatico(k: k)
                ForEach(Array(ajustes.datos.modos.enumerated()), id: \.element.id) { i, m in
                    fila(i, m, k: k)
                }
            }
            .padding(16)
        }
    }

    // Automático: no es un modo más sino "que elija según la app"; siempre está y siempre es el 0.
    private func filaAutomatico(k: String) -> some View {
        HStack(spacing: 12) {
            Text("\(k)0")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 46, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Tema.bordeSuave))
            Circle().fill(AngularGradient(colors: ajustes.datos.modos.filter(\.activo).map { Color(hex: $0.color) }, center: .center))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(T("Automático", "Automatic")).font(.system(size: 13)).foregroundStyle(Tema.titulo)
                Text(T("Elige el modo según la app (Correo en Mail, Prompt en Claude…)", "Picks the mode by app (Email in Mail, Prompt in Claude…)"))
                    .font(.system(size: 11)).foregroundStyle(Tema.apagado)
            }
            Spacer()
            GrabadorAtajoPropio(ajustes: ajustes, motor: motor, atajo: $ajustes.datos.atajoAutomatico,
                                ayuda: T("Ponerle un atajo propio a Automático", "Give Automatic its own shortcut"))
            Color.clear.frame(width: 156, height: 1)   // donde los demás tienen color, interruptor y flechas
        }
    }

    private func numero(_ e: Estilo) -> Int? { ajustes.modosActivos.firstIndex(of: e).map { $0 + 1 } }

    private func fila(_ i: Int, _ m: ConfigModo, k: String) -> some View {
        HStack(spacing: 12) {
            Text(numero(m.estilo).map { "\(k)\($0)" } ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 46, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Tema.bordeSuave))
                .opacity(m.activo ? 1 : 0.4)
            Circle().fill(Color(hex: m.color)).frame(width: 10, height: 10)
            Text(m.estilo.etiqueta).font(.system(size: 13)).foregroundStyle(m.activo ? Tema.titulo : Tema.apagado)
                .help(m.estilo.nombre)
            Spacer()
            GrabadorAtajoPropio(ajustes: ajustes, motor: motor, atajo: $ajustes.datos.modos[i].atajo,
                                ayuda: T("Ponerle un atajo propio a este modo", "Give this mode its own shortcut"))
            ColorPicker("", selection: Binding(get: { Color(hex: m.color) },
                                               set: { ajustes.datos.modos[i].color = $0.hex }), supportsOpacity: false)
                .labelsHidden()
                .help(T("Color del modo en la píldora", "Mode color in the pill"))
            Toggle("", isOn: Binding(get: { m.activo }, set: { v in
                ajustes.datos.modos[i].activo = v
                ajustes.datos.modos = ConfigModo.normalizar(ajustes.datos.modos)
            })).toggleStyle(.switch).labelsHidden().controlSize(.small)
                .help(T("Mostrar este modo", "Show this mode"))
            Button { mover(i, -1) } label: { Image(systemName: "chevron.up").frame(width: 22, height: 22) }
                .buttonStyle(.plain).disabled(i == 0).opacity(i == 0 ? 0.3 : 1)
                .help(T("Subir", "Move up"))
            Button { mover(i, 1) } label: { Image(systemName: "chevron.down").frame(width: 22, height: 22) }
                .buttonStyle(.plain).disabled(i == ajustes.datos.modos.count - 1).opacity(i == ajustes.datos.modos.count - 1 ? 0.3 : 1)
                .help(T("Bajar", "Move down"))
        }
    }

    private func mover(_ i: Int, _ d: Int) {
        let j = i + d
        guard ajustes.datos.modos.indices.contains(j) else { return }
        withAnimation(.easeOut(duration: 0.15)) { ajustes.datos.modos.swapAt(i, j) }
    }
}
