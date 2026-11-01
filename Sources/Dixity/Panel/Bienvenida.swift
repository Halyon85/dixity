import AppKit
import Combine
import SwiftUI

// Bienvenida de la primera vez, en cinco pasos: cómo funciona, permisos, con qué IA, probarlo y listo.
// Mismo estilo que el asistente de Relevo (misma familia de apps de Halyon Team). Se puede volver a ver en General.
struct Bienvenida: View {
    @ObservedObject var ajustes: Ajustes
    let motor: Motor
    let pedirTeclado: () -> Void
    let cerrar: () -> Void
    @Estado private var paso = 1
    @Estado private var usarAPI = true
    @Estado private var clave = ""
    @Estado private var prueba: String?
    @Estado private var descarga: String?
    @Estado private var practica = ""
    @Estado private var refresco = 0
    private let reloj = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let total = 6

    init(ajustes: Ajustes, motor: Motor, pedirTeclado: @escaping () -> Void, cerrar: @escaping () -> Void, paso: Int = 1) {
        self.ajustes = ajustes
        self.motor = motor
        self.pedirTeclado = pedirTeclado
        self.cerrar = cerrar
        _paso = Estado(initialValue: paso)
    }

    // Para la opción "con tu API": los que sirven para pasar en limpio, con la página donde se saca la clave.
    private static let conClave: [ProveedorIA] = [.openai, .anthropic, .grok, .groq, .openrouter]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(T("Paso \(paso) de \(total)", "Step \(paso) of \(total)"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.acento)
                Spacer()
                Button { terminar() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Tema.apagado)
                    .help(T("Cerrar (la podés volver a ver en General)", "Close (you can see it again in General)"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch paso {
                    case 1: pasoComoFunciona
                    case 2: pasoAtajos
                    case 3: pasoPermisos
                    case 4: pasoIA
                    case 5: pasoProbar
                    default: pasoListo
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if paso > 1 { BotonSecundario(texto: T("Atrás", "Back"), icono: "chevron.left") { paso -= 1 } }
                Spacer()
                if paso < total {
                    BotonPrimario(texto: T("Seguir", "Continue")) { seguir() }
                } else {
                    BotonPrimario(texto: T("Empezar a dictar", "Start dictating")) { terminar() }
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 560)
        .background(Tema.fondo)
        .foregroundStyle(Tema.texto)
        .onReceive(reloj) { _ in refresco += 1 }
        .onAppear {
            usarAPI = !ajustes.todoLocal
            if Bienvenida.conClave.contains(ajustes.datos.proveedorIA) { clave = ajustes.claveIA }
        }
    }

    // MARK: Pasos

    private var pasoComoFunciona: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                LogoApp(tam: 64)
                VStack(alignment: .leading, spacing: 8) {
                    Text(T("Bienvenido a Dixity", "Welcome to Dixity")).font(.titulo(20)).foregroundStyle(Tema.titulo)
                    Text(T("Dictá en cualquier app y el texto aparece prolijo donde está el cursor.",
                           "Dictate in any app and clean text appears wherever your cursor is."))
                        .font(.system(size: 14)).foregroundStyle(Tema.subtitulo)
                }
            }
            Text(T("Cómo funciona", "How it works")).font(.titulo(16, .semibold)).foregroundStyle(Tema.titulo)
            numerado("1", T("Mantené tu atajo de dictar mientras hablás (o tocalo una vez para empezar y otra para terminar). Lo elegís en el paso que sigue.",
                            "Hold your dictation shortcut while you talk (or tap it once to start and again to finish). You'll pick it in the next step."))
            numerado("2", T("Dixity pasa en limpio lo que dijiste: saca muletillas, aplica tus correcciones (\"a las tres, no, a las cuatro\") y puntúa.",
                            "Dixity cleans up what you said: drops filler words, applies your corrections (\"at three, no, at four\") and adds punctuation."))
            numerado("3", T("El texto aparece donde está el cursor. Para cambiar un texto, seleccionalo y usá el atajo de reescribir: decí \"más formal\" o \"traducilo al inglés\".",
                            "The text appears at your cursor. To change some text, select it and use the rewrite shortcut: say \"more formal\" or \"translate it to Spanish\"."))
        }
    }

    private var pasoAtajos: some View {
        VStack(alignment: .leading, spacing: 14) {
            TituloPagina(titulo: T("Elegí tus atajos", "Pick your shortcuts"),
                         subtitulo: T("Los que vienen sirven, pero elegí los que te queden cómodos. Puede ser una tecla sola, como ⌥ derecha o fn, o una combinación. Después se cambian en Atajos.",
                                      "The defaults work, but pick whatever feels comfortable. It can be a single key, like right ⌥ or fn, or a combination. You can change them later in Shortcuts."))
            TarjetaAtajo(titulo: T("Dictar", "Dictate"), accion: .dictar, ajustes: ajustes, motor: motor, dices: "", escribe: "")
            TarjetaAtajo(titulo: T("Reescribir selección", "Rewrite selection"), accion: .reescribir, ajustes: ajustes, motor: motor, dices: "", escribe: "")
            HStack {
                Text(T("Cómo funciona la tecla", "How the key works")).font(.titulo(14, .regular)).foregroundStyle(Tema.titulo)
                Spacer()
                Selector(valor: $ajustes.datos.modoTecla, opciones: ModoTecla.allCases, nombre: \.nombre, ancho: 260)
            }
            .padding(.horizontal, 4)
        }
    }

    private var pasoPermisos: some View {
        let _ = refresco
        return VStack(alignment: .leading, spacing: 14) {
            TituloPagina(titulo: T("Permisos", "Permissions"),
                         subtitulo: T("Dixity los usa solo para dictar. Se dan una vez en Ajustes del Sistema.",
                                      "Dixity only uses them to dictate. You grant them once in System Settings."))
            Tarjeta {
                Fila(titulo: T("Micrófono", "Microphone"), detalle: T("Para escucharte, solo mientras dictás.", "To hear you, only while you dictate.")) {
                    if Grabador.permitido { Etiqueta(ok: true) }
                    else { BotonSecundario(texto: T("Permitir", "Allow"), icono: "mic") { Grabador.pedirPermiso { _ in refresco += 1 } } }
                }
                Fila(titulo: T("Accesibilidad", "Accessibility"),
                     detalle: T("Para escuchar tu atajo en cualquier app y pegar el texto donde está el cursor.",
                                "To catch your shortcut in any app and paste the text at your cursor.")) {
                    if Cursor.accesibilidadPermitida { Etiqueta(ok: true) }
                    else { BotonSecundario(texto: T("Abrir Ajustes", "Open Settings"), icono: "hand.raised") { Cursor.pedirAccesibilidad() } }
                }
                Fila(titulo: T("Grabación de pantalla (opcional)", "Screen Recording (optional)"),
                     detalle: T("Para leer el texto de la ventana y escribir bien los nombres. Se lee en la Mac y la imagen no se guarda.",
                                "To read the window's text and spell names right. It's read on your Mac and the image isn't saved."),
                     divisor: false) {
                    if Pantalla.permitido { Etiqueta(ok: true) }
                    else { BotonSecundario(texto: T("Permitir", "Allow"), icono: "rectangle.dashed") { Pantalla.pedirPermiso() } }
                }
            }
            Text(T("Si después de dar Accesibilidad el atajo no responde, cerrá y volvé a abrir Dixity.",
                   "If the shortcut doesn't respond after granting Accessibility, quit and reopen Dixity."))
                .font(.system(size: 12)).foregroundStyle(Tema.apagado)
        }
        .onChange(of: Cursor.accesibilidadPermitida) { _, si in if si { pedirTeclado() } }
    }

    private var pasoIA: some View {
        VStack(alignment: .leading, spacing: 14) {
            TituloPagina(titulo: T("¿Con qué IA?", "Which AI?"),
                         subtitulo: T("Para mejores resultados se recomienda usar una API. Si no, podés usar solo los modelos de tu Mac.",
                                      "For the best results we recommend an API. Otherwise you can use only the models on your Mac."))
            opcion(titulo: T("Con tu API (recomendado)", "With your API (recommended)"),
                   detalle: T("Entiende mejor y acomoda el texto. Pagás directo al proveedor, por uso (centavos por día); Dixity no cobra ni ve nada.",
                              "Understands better and shapes the text. You pay the provider directly, per use (cents a day); Dixity charges nothing and sees nothing."),
                   icono: "key.fill", elegida: usarAPI) { usarAPI = true }
            opcion(titulo: T("Todo en la Mac", "Everything on your Mac"),
                   detalle: T("Sin claves ni internet. Funciona bien, pero corrige menos que una API.",
                              "No keys, no internet. Works well, but fixes less than an API."),
                   icono: "lock.laptopcomputer", elegida: !usarAPI) { usarAPI = false; ajustes.usarTodoLocal() }
            if usarAPI { configurarAPI } else { configurarLocal }
        }
    }

    private var configurarAPI: some View {
        let p = ajustes.datos.proveedorIA
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(T("Proveedor", "Provider")).font(.titulo(14, .regular)).foregroundStyle(Tema.titulo)
                Spacer()
                Selector(valor: Binding(get: { Bienvenida.conClave.contains(p) ? p : .openai },
                                        set: { elegirProveedor($0) }),
                         opciones: Bienvenida.conClave, nombre: \.nombre, ancho: 230)
            }
            numerado("1", T("Entrá a la página de \(p.nombre), creá tu usuario y generá una clave de API.",
                            "Go to the \(p.nombre) page, create your account and generate an API key."))
            if let url = p.paginaClave {
                BotonSecundario(texto: T("Abrir \(p.nombre)", "Open \(p.nombre)"), icono: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
                    .padding(.leading, 28)
            }
            numerado("2", T("Pegala acá. Queda guardada en el llavero de tu Mac.", "Paste it here. It's stored in your Mac's Keychain."))
            HStack(spacing: 8) {
                SecureField(T("Pegá tu clave", "Paste your key"), text: $clave).textFieldStyle(.roundedBorder)
                    .onSubmit { guardarYProbar() }
                BotonSecundario(texto: T("Probar", "Test")) { guardarYProbar() }
            }
            .padding(.leading, 28)
            if let prueba { Text(prueba).font(.system(size: 12)).foregroundStyle(Tema.apagado).padding(.leading, 28) }
            Text(T("La voz a texto sigue en tu Mac (Parakeet o el motor de macOS): es rápida y gratis. Podés cambiarlo en Proveedores.",
                   "Speech to text stays on your Mac (Parakeet or the macOS engine): it's fast and free. You can change it in Providers."))
                .font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tema.radioTarjeta).fill(Tema.tarjeta))
    }

    private var configurarLocal: some View {
        let m = ajustes.datos.modeloLocal
        return VStack(alignment: .leading, spacing: 10) {
            Text(VozApple.disponible
                 ? T("Voz: ya funciona con el motor de macOS, sin bajar nada. Para que entienda mejor, bajá uno de estos (una sola vez):",
                     "Speech: it already works with the macOS engine, nothing to download. For better accuracy, download one of these (just once):")
                 : T("Voz: bajá uno de estos (una sola vez) para dictar sin internet:", "Speech: download one of these (just once) to dictate offline:"))
                .font(.system(size: 12)).foregroundStyle(Tema.subtitulo).fixedSize(horizontal: false, vertical: true)
            ForEach(ModeloLocal.allCases) { opcionModelo($0) }
            if Parakeet.encontrado(m) != nil {
                Etiqueta(ok: true, textoOk: T("\(m.nombre) instalado", "\(m.nombre) installed"))
            } else {
                BotonSecundario(texto: descarga ?? T("Bajar \(m.nombre) (\(m.peso))", "Download \(m.nombre) (\(m.peso))"), icono: "arrow.down.circle") {
                    descarga = T("Descargando… (puede tardar unos minutos)", "Downloading… (may take a few minutes)")
                    Task {
                        do {
                            try await Parakeet.descargar(m)
                            await MainActor.run { descarga = nil; ajustes.datos.proveedorVoz = .parakeet }
                        } catch { await MainActor.run { descarga = T("Falló, reintentar", "Failed, retry") } }
                    }
                }
                .disabled(descarga != nil && descarga != T("Falló, reintentar", "Failed, retry"))
            }
            Text(IAApple.disponible
                 ? T("Limpieza: con Apple Intelligence, en tu Mac.", "Clean-up: with Apple Intelligence, on your Mac.")
                 : T("Limpieza: tu Mac no tiene Apple Intelligence, así que pega lo que escuchó tal cual (con puntuación).",
                     "Clean-up: your Mac doesn't have Apple Intelligence, so it pastes what it heard as is (with punctuation)."))
                .font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tema.radioTarjeta).fill(Tema.tarjeta))
    }

    private var pasoProbar: some View {
        VStack(alignment: .leading, spacing: 14) {
            TituloPagina(titulo: T("Probalo", "Try it"),
                         subtitulo: T("Hacé clic en el cuadro, mantené \(ajustes.datos.atajoDictar.descripcion) y decí una frase. Probá corregirte: \"mañana a las tres, no, a las cuatro\".",
                                      "Click the box, hold \(ajustes.datos.atajoDictar.descripcion) and say a sentence. Try correcting yourself: \"tomorrow at three, no, at four\"."))
            TextEditor(text: $practica)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 150)
                .background(RoundedRectangle(cornerRadius: 12).fill(Tema.tarjeta))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tema.bordeSuave))
            if !Cursor.accesibilidadPermitida || !Grabador.permitido {
                Label(T("Falta algún permiso del paso 3: sin eso el atajo no responde.", "A permission from step 3 is missing: without it the shortcut won't respond."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Tema.acento)
            }
        }
    }

    private var pasoListo: some View {
        let k = ajustes.datos.teclaModos.simbolo
        return VStack(alignment: .leading, spacing: 14) {
            TituloPagina(titulo: T("¡Listo!", "All set!"), subtitulo: T("Algunas cosas que te van a servir:", "A few things that will help:"))
            let modos = ajustes.modosActivos.enumerated().map { "\(k)\($0.offset + 1) \($0.element.etiqueta)" }.joined(separator: ", ")
            numerado("1", T("Modos: \(modos). También elige solo según la app.", "Modes: \(modos). It also picks one by app."))
            numerado("2", T("Esc cancela mientras dictás. Si no hay dónde pegar, el texto queda copiado y a la vista.",
                            "Esc cancels while dictating. If there's nowhere to paste, the text stays copied and on screen."))
            numerado("3", T("Sumá al Diccionario los nombres que uses seguido. Atajos, colores y orden de los modos están en Modos.",
                            "Add the names you use often to the Dictionary. Shortcuts, colors and mode order are in Modes."))
            Text(T("Dixity vive en la barra de menú (la \"d\" de arriba a la derecha).", "Dixity lives in the menu bar (the \"d\" at the top right)."))
                .font(.system(size: 12)).foregroundStyle(Tema.apagado)
        }
    }

    // MARK: Piezas

    private func numerado(_ n: String, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(Tema.acento))
            Text(texto).font(.system(size: 13)).foregroundStyle(Tema.subtitulo).fixedSize(horizontal: false, vertical: true)
        }
    }

    // Una fila por Parakeet: nombre, peso y qué tal anda. Elegirlo deja ese para bajar (y para dictar, si ya está).
    private func opcionModelo(_ x: ModeloLocal) -> some View {
        let elegido = ajustes.datos.modeloLocal == x
        let instalado = Parakeet.encontrado(x) != nil
        return Button {
            ajustes.datos.modeloLocal = x
            if instalado { ajustes.datos.proveedorVoz = .parakeet }
            descarga = nil
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: elegido ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(elegido ? Tema.acento : Tema.apagado).font(.system(size: 14)).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(x.nombre).font(.titulo(13, .semibold)).foregroundStyle(Tema.titulo)
                        Text(x.peso).font(.system(size: 11)).foregroundStyle(Tema.apagado)
                        if instalado { Text(T("instalado", "installed")).font(.system(size: 11, weight: .medium)).foregroundStyle(Tema.exito) }
                    }
                    Text(x.rinde).font(.system(size: 12)).foregroundStyle(Tema.apagado)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func opcion(titulo: String, detalle: String, icono: String, elegida: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 12) {
                Image(systemName: icono).font(.system(size: 20)).frame(width: 32).foregroundStyle(Tema.titulo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(.titulo(14, .semibold)).foregroundStyle(Tema.titulo)
                    Text(detalle).font(.system(size: 12)).foregroundStyle(Tema.apagado)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer()
                if elegida { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.acento) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Tema.tarjeta))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(elegida ? Tema.acento : Tema.bordeSuave, lineWidth: elegida ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Lógica

    private func elegirProveedor(_ p: ProveedorIA) {
        ajustes.datos.proveedorIA = p
        ajustes.datos.modeloIA = p.modeloSugerido
        clave = Llavero.leer(p.cuentaLlavero)
        prueba = nil
    }

    private func guardarYProbar() {
        var p = ajustes.datos.proveedorIA
        if !Bienvenida.conClave.contains(p) { p = .openai; elegirProveedor(p) }
        Llavero.guardar(p.cuentaLlavero, clave)
        ajustes.datos.limpiarConIA = true
        prueba = T("Probando…", "Testing…")
        Task { let r = await Proveedores.probarIA(ajustes); await MainActor.run { prueba = r } }
    }

    private func seguir() {
        // Al salir del paso de la IA con "tu API" elegida, queda ese proveedor aunque no hayan tocado el selector.
        if paso == 4 && usarAPI && !Bienvenida.conClave.contains(ajustes.datos.proveedorIA) { elegirProveedor(.openai) }
        paso += 1
    }

    private func terminar() {
        ajustes.datos.bienvenidaVista = true
        cerrar()
    }
}
