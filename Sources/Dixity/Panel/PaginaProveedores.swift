import AppKit
import SwiftUI

struct PaginaProveedores: View {
    @ObservedObject var ajustes: Ajustes
    @Estado private var claveVoz = ""
    @Estado private var claveIA = ""
    @Estado private var pruebaVoz: String?
    @Estado private var pruebaIA: String?
    @Estado private var probando = false
    @Estado private var estadoDescarga: String?

    var body: some View {
        TituloPagina(titulo: T("Proveedores", "Providers"), subtitulo: T("Elegí qué servicios usa Dixity y cargá tus claves. Quedan guardadas en el llavero de la Mac.",
                                                                 "Choose which services Dixity uses and add your keys. They're stored in your Mac's Keychain."))

        Tarjeta(titulo: T("Cómo querés usar Dixity", "How you want to use Dixity")) {
            Fila(titulo: T("Todo en la Mac", "Everything on your Mac"),
                 detalle: T("Sin claves ni internet: la voz con Parakeet o el motor de la Mac, y la limpieza con Apple Intelligence (si tu Mac lo tiene). Nada sale de tu Mac.",
                            "No keys, no internet: speech with Parakeet or the Mac's engine, and clean-up with Apple Intelligence (if your Mac has it). Nothing leaves your Mac.")) {
                if ajustes.todoLocal { Etiqueta(ok: true, textoOk: T("En uso", "In use")) }
                else { BotonSecundario(texto: T("Usar así", "Use this"), icono: "lock.laptopcomputer") { ajustes.usarTodoLocal() } }
            }
            Fila(titulo: T("Con tus propias claves", "Bring your own API"),
                 detalle: T("Elegí abajo el proveedor de voz y el de IA y pegá tu clave: OpenAI, Anthropic, Grok, Groq, OpenRouter o cualquiera compatible con OpenAI. Pagás directo a ellos; Dixity no cobra ni ve nada.",
                            "Pick a speech and an AI provider below and paste your key: OpenAI, Anthropic, Grok, Groq, OpenRouter or anything OpenAI-compatible. You pay them directly; Dixity charges nothing and sees nothing."), divisor: false) {
                if !ajustes.todoLocal { Etiqueta(ok: true, textoOk: T("En uso", "In use")) }
            }
        }

        Tarjeta(titulo: T("Voz a texto", "Speech to text")) {
            Fila(titulo: T("Proveedor", "Provider"), detalle: T("Parakeet corre en tu Mac, sin internet ni costo. Grok es el más rápido en la nube; OpenAI, muy preciso.",
                                                       "Parakeet runs on your Mac, offline and free. Grok is the fastest in the cloud; OpenAI is very accurate.")) {
                Selector(valor: $ajustes.datos.proveedorVoz, opciones: ProveedorVoz.allCases, nombre: \.nombre, ancho: 230)
                .onChange(of: ajustes.datos.proveedorVoz) { _, p in
                    ajustes.datos.modeloVoz = p.modeloSugerido
                    claveVoz = Llavero.leer(p.cuentaLlavero); pruebaVoz = nil
                }
            }
            if ajustes.datos.proveedorVoz == .parakeet {
                Fila(titulo: T("Modelo local", "Local model"), detalle: T("\(ajustes.datos.modeloLocal.rinde) Los dos entienden 25 idiomas.",
                                                               "\(ajustes.datos.modeloLocal.rinde) Both understand 25 languages.")) {
                    Selector(valor: $ajustes.datos.modeloLocal, opciones: ModeloLocal.allCases, nombre: \.nombre, ancho: 290)
                }
                let m = ajustes.datos.modeloLocal
                Fila(titulo: T("En esta Mac", "On this Mac"),
                     detalle: Parakeet.encontrado(m).map { T("Guardado en \($0.deletingLastPathComponent().path)", "Saved in \($0.deletingLastPathComponent().path)") }
                        ?? T("No está. Se baja una vez (\(m.peso)) y después funciona sin internet.", "Not installed. Download it once (\(m.peso)) and then it works offline."), divisor: false) {
                    if Parakeet.encontrado(m) != nil { Etiqueta(ok: true, textoOk: T("Instalado", "Installed")) }
                    else {
                        BotonSecundario(texto: estadoDescarga ?? T("Descargar", "Download"), icono: "arrow.down.circle") {
                            estadoDescarga = T("Descargando…", "Downloading…")
                            Task {
                                do { try await Parakeet.descargar(m); await MainActor.run { estadoDescarga = nil } }
                                catch { await MainActor.run { estadoDescarga = T("Falló, reintentar", "Failed, try again") } }
                            }
                        }
                    }
                }
                .id(m)
            }
            if ajustes.datos.proveedorVoz == .apple {
                Fila(titulo: T("Motor de la Mac", "Mac engine"), detalle: VozApple.disponible
                     ? T("Viene con macOS: no suma memoria a Dixity ni hay que bajar nada. Usa tu diccionario para los nombres. Con palabras en inglés se equivoca más que Parakeet.",
                         "Built into macOS: no extra memory for Dixity and nothing to download. Uses your dictionary for names. Makes more mistakes than Parakeet with English words.")
                     : T("Necesita macOS 26 o más nuevo.", "Requires macOS 26 or later."), divisor: false) {
                    Etiqueta(ok: VozApple.disponible, textoOk: T("Listo", "Ready"))
                }
            }
            if ajustes.datos.proveedorVoz == .personalizado {
                Fila(titulo: T("Dirección base", "Base URL"), detalle: T("Termina en /v1. Se usa /audio/transcriptions.", "Ends in /v1. Uses /audio/transcriptions.")) {
                    campo("https://…/v1", $ajustes.datos.urlVozPersonalizada)
                }
            }
            if !ajustes.datos.proveedorVoz.local {
            Fila(titulo: T("Modelo", "Model")) { modelo($ajustes.datos.modeloVoz, sugeridos: ajustes.datos.proveedorVoz.modelos) }
            if let url = ajustes.datos.proveedorVoz.paginaClave { filaConseguir(ajustes.datos.proveedorVoz.nombre, url) }
            Fila(titulo: T("Clave de API", "API key"), detalle: pruebaVoz, divisor: false) {
                SecureField(T("Pegá tu clave", "Paste your key"), text: $claveVoz).textFieldStyle(.roundedBorder).frame(width: 220)
                    .onSubmit { ajustes.guardarClave(ajustes.datos.proveedorVoz.cuentaLlavero, claveVoz) }
                BotonSecundario(texto: T("Probar", "Test")) {
                    ajustes.guardarClave(ajustes.datos.proveedorVoz.cuentaLlavero, claveVoz)
                    pruebaVoz = T("Probando…", "Testing…")
                    Task { let r = await Proveedores.probarVoz(ajustes); await MainActor.run { pruebaVoz = r } }
                }
            }
            }
        }

        Tarjeta(titulo: T("IA para pasar en limpio y reescribir", "AI for clean-up and rewriting")) {
            Fila(titulo: T("Proveedor", "Provider"), detalle: T("Recibe lo que escuchó, el texto alrededor del cursor y tu diccionario.", "Receives what it heard, the text around your cursor and your dictionary.")) {
                Selector(valor: $ajustes.datos.proveedorIA, opciones: ProveedorIA.allCases, nombre: \.nombre, ancho: 230)
                .onChange(of: ajustes.datos.proveedorIA) { _, p in
                    ajustes.datos.modeloIA = p.modeloSugerido
                    claveIA = Llavero.leer(p.cuentaLlavero); pruebaIA = nil
                }
            }
            if ajustes.datos.proveedorIA == .apple {
                Fila(titulo: T("Modelo de la Mac", "Mac model"), detalle: IAApple.disponible
                     ? T("Apple Intelligence, en tu Mac: no manda nada afuera ni necesita clave. Es más chico que los de la nube: a veces reformula de más o cambia el voseo.",
                         "Apple Intelligence, on your Mac: nothing leaves the device and no key is needed. It's smaller than cloud models, so it sometimes rewords too much.")
                     : T("Necesita macOS 26 con Apple Intelligence activado (Ajustes › Apple Intelligence y Siri).", "Requires macOS 26 with Apple Intelligence turned on (Settings › Apple Intelligence & Siri)."), divisor: false) {
                    Etiqueta(ok: IAApple.disponible, textoOk: T("Listo", "Ready"))
                }
            }
            if ajustes.datos.proveedorIA != .ninguno && ajustes.datos.proveedorIA != .apple {
                if ajustes.datos.proveedorIA == .personalizado {
                    Fila(titulo: T("Dirección base", "Base URL"), detalle: T("Termina en /v1. Se usa /chat/completions.", "Ends in /v1. Uses /chat/completions.")) {
                        campo("https://…/v1", $ajustes.datos.urlIAPersonalizada)
                    }
                }
                Fila(titulo: T("Modelo", "Model"), detalle: ajustes.datos.proveedorIA == .anthropic
                         ? T("Haiku 5.5: ~1,4 s y USD 0,10 / 0,50 por millón de tokens. Opus 5.5 es más fino pero más lento y caro.",
                             "Haiku 5.5: ~1.4 s and USD 0.10 / 0.50 per million tokens. Opus 5.5 is sharper but slower and pricier.")
                         : ajustes.datos.proveedorIA == .openai
                         ? T("gpt-6-luna: ~1,7 s y el mismo precio que Haiku 5.5 (USD 0,10 / 0,50). Sol es mucho más caro.",
                             "gpt-6-luna: ~1.7 s and the same price as Haiku 5.5 (USD 0.10 / 0.50). Sol costs much more.") : nil) {
                    modelo($ajustes.datos.modeloIA, sugeridos: ajustes.datos.proveedorIA.modelos)
                }
                if let url = ajustes.datos.proveedorIA.paginaClave { filaConseguir(ajustes.datos.proveedorIA.nombre, url) }
                Fila(titulo: T("Clave de API", "API key"), detalle: pruebaIA, divisor: false) {
                    SecureField(T("Pegá tu clave", "Paste your key"), text: $claveIA).textFieldStyle(.roundedBorder).frame(width: 220)
                        .onSubmit { ajustes.guardarClave(ajustes.datos.proveedorIA.cuentaLlavero, claveIA) }
                    BotonSecundario(texto: T("Probar", "Test")) {
                        ajustes.guardarClave(ajustes.datos.proveedorIA.cuentaLlavero, claveIA)
                        pruebaIA = T("Probando…", "Testing…")
                        Task { let r = await Proveedores.probarIA(ajustes); await MainActor.run { pruebaIA = r } }
                    }
                }
            }
        }
        Text(T("Una clave por empresa: la de OpenAI o la de Grok sirve para voz y para texto. Se guardan al tocar Probar o Enter.",
                "One key per company: your OpenAI or Grok key works for both voice and text. Keys are saved when you click Test or press Enter."))
            .font(.system(size: 12)).foregroundStyle(Tema.apagado)
            .onAppear {
                claveVoz = Llavero.leer(ajustes.datos.proveedorVoz.cuentaLlavero)
                claveIA = Llavero.leer(ajustes.datos.proveedorIA.cuentaLlavero)
            }
            .onDisappear {
                ajustes.guardarClave(ajustes.datos.proveedorVoz.cuentaLlavero, claveVoz)
                if ajustes.datos.proveedorIA != .ninguno { ajustes.guardarClave(ajustes.datos.proveedorIA.cuentaLlavero, claveIA) }
            }
    }

    // "Entrá acá, creá tu usuario y generá tu clave": lleva a la página del proveedor.
    private func filaConseguir(_ nombre: String, _ url: URL) -> some View {
        Fila(titulo: T("Conseguir tu clave", "Get your key"),
             detalle: T("Entrá a \(nombre), creá tu usuario y generá una clave de API; después pegala abajo. Si no querés usar una API, arriba podés elegir \"Todo en la Mac\". Para mejores resultados se recomienda una API.",
                        "Go to \(nombre), create your account and generate an API key, then paste it below. If you'd rather not use an API, pick \"Everything on your Mac\" above. An API gives the best results.")) {
            BotonSecundario(texto: T("Abrir \(nombre)", "Open \(nombre)"), icono: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
        }
    }

    private func campo(_ placeholder: String, _ valor: Binding<String>) -> some View {
        TextField(placeholder, text: valor).textFieldStyle(.roundedBorder).frame(width: 260)
    }

    private func modelo(_ valor: Binding<String>, sugeridos: [String]) -> some View {
        HStack(spacing: 6) {
            TextField(T("modelo", "model"), text: valor).textFieldStyle(.roundedBorder).frame(width: 220)
            if !sugeridos.isEmpty {
                Menu {
                    ForEach(sugeridos, id: \.self) { m in Button(m) { valor.wrappedValue = m } }
                } label: { Image(systemName: "chevron.down") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
            }
        }
    }
}
