import SwiftUI

struct PaginaDiccionario: View {
    @ObservedObject var diccionario: Diccionario
    @ObservedObject var sugerencias: Sugerencias = .shared
    @ObservedObject var ajustes: Ajustes = .shared
    @Estado private var busqueda = ""
    @Estado private var nuevo = ""
    @Estado private var nuevoAlias = ""
    @Estado private var importando = false
    @Estado private var lista = ""
    @Estado private var nota: String?

    private var filtrados: [Termino] {
        let b = Diccionario.normalizar(busqueda)
        guard !b.isEmpty else { return diccionario.terminos }
        return diccionario.terminos.filter { t in
            Diccionario.normalizar(([t.texto] + t.alias).joined(separator: " ")).contains(b)
        }
    }

    var body: some View {
        TituloPagina(titulo: T("Diccionario", "Dictionary"), subtitulo: T("Nombres y palabras que Dixity tiene que escribir bien. Van en cada dictado.",
                                                                   "Names and words Dixity should always spell right. They go with every dictation."))
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Tema.apagado)
                TextField(T("Buscar en el diccionario", "Search dictionary"), text: $busqueda).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(Capsule().fill(Tema.tarjeta))
            .overlay(Capsule().strokeBorder(Tema.bordeSuave))
            BotonSecundario(texto: T("Importar lista", "Import list"), icono: "square.and.arrow.down") { importando.toggle() }
        }
        if importando {
            Tarjeta(titulo: T("Pegar una lista", "Paste a list")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(T("Una palabra por línea. Para una corrección escribí «como sale mal, como va»: p. ej. «Halión, Halyon».",
                            "One word per line. For a correction, write “how it comes out, how it should be”: e.g. “Halion, Halyon”."))
                        .font(.system(size: 12)).foregroundStyle(Tema.apagado)
                    TextEditor(text: $lista).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .padding(6).frame(height: 110)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Tema.rellenoSuave))
                    HStack {
                        Spacer()
                        BotonSecundario(texto: T("Cancelar", "Cancel")) { importando = false; lista = "" }
                        BotonPrimario(texto: T("Agregar", "Add")) {
                            let n = diccionario.importarLista(lista)
                            nota = n == 0 ? T("No había palabras nuevas.", "No new words.") : T("Se agregaron \(n).", "Added \(n).")
                            lista = ""; importando = false
                        }
                    }
                }
                .padding(16)
            }
        }
        if let n = nota { Text(n).font(.system(size: 12)).foregroundStyle(Tema.apagado) }
        Tarjeta {
            Fila(titulo: T("Aprender solo", "Learn automatically"),
                 detalle: T("Dixity suma directo los nombres de tus proyectos y lo que escribe la IA entre `comillas`. Lo que ve en tus ventanas (en 2 dictados) y las correcciones que cambian una palabra por otra te las sugiere acá, para que elijas. Nunca anota claves, contraseñas ni mails. Apagado, todo queda como sugerencia. Si editás una palabra y apretás Enter, pasa a ser tuya (con sus alias).",
                            "Dixity adds your project names and what the AI writes in `backticks` right away. Words it sees in your windows (in 2 dictations) and corrections that swap one word for another are suggested here for you to pick. It never stores keys, passwords or emails. When off, everything stays a suggestion. Edit a word and press Enter to make it yours (with its aliases)."), divisor: false) {
                Toggle("", isOn: $ajustes.datos.aprenderSolo).toggleStyle(.switch).labelsHidden()
            }
        }
        if !sugerencias.sumadasSolas.isEmpty {
            let sumadas = sugerencias.sumadasSolas.prefix(8).joined(separator: ", ")
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Tema.acento)
                Text(T("Dixity sumó sola: \(sumadas). Si alguna no va, borrala de la lista.", "Dixity added on its own: \(sumadas). If any are wrong, delete them from the list."))
                    .font(.system(size: 12)).foregroundStyle(Tema.subtitulo).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(T("Entendido", "Got it")) { sugerencias.limpiarAvisoSumadas() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Tema.apagado)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Tema.acento.opacity(0.08)))
        }
        if !sugerencias.lista.isEmpty {
            Tarjeta(titulo: T("Sugeridas por Dixity", "Suggested by Dixity")) {
                Text(T("Palabras que corrigió la IA o que aparecen en tus ventanas y proyectos. Si las sumás, la próxima vez las escribe bien de entrada.",
                        "Words the AI corrected or that appear in your windows and projects. Add them and next time they'll be right from the start."))
                    .font(.system(size: 12)).foregroundStyle(Tema.apagado)
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(sugerencias.lista.prefix(12)) { sug in
                    Fila(titulo: sug.texto, detalle: detalle(sug), divisor: sug.id != sugerencias.lista.prefix(12).last?.id) {
                        Button(T("Descartar", "Dismiss")) { withAnimation(Tema.expo) { sugerencias.descartar(sug) } }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Tema.apagado)
                        BotonPrimario(texto: T("Agregar", "Add")) { withAnimation(Tema.expo) { sugerencias.aceptar(sug) } }
                    }
                }
            }
        }
        Tarjeta {
            HStack(spacing: 8) {
                TextField(T("Palabra o nombre (ej.: Halyon)", "Word or name (e.g. Halyon)"), text: $nuevo).textFieldStyle(.plain).frame(maxWidth: .infinity)
                TextField(T("Cómo sale mal, separado por |", "Misspellings, separated by |"), text: $nuevoAlias).textFieldStyle(.plain).frame(maxWidth: .infinity)
                BotonPrimario(texto: T("Agregar", "Add")) { agregar() }
            }
            .padding(.horizontal, 16).frame(minHeight: 48)
            .onSubmit { agregar() }
            Rectangle().fill(Tema.bordeSuave).frame(height: 1)
            if filtrados.isEmpty {
                Text(busqueda.isEmpty ? T("Todavía no hay palabras. Sumá nombres de personas, marcas o términos que uses seguido.", "No words yet. Add names of people, brands or terms you use often.")
                                       : T("No hay coincidencias.", "No matches."))
                    .font(.system(size: 13)).foregroundStyle(Tema.apagado)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(filtrados) { t in
                FilaTermino(termino: t, diccionario: diccionario)
            }
        }
        Text(T("\(diccionario.terminos.count) de \(Diccionario.maximo) palabras. En cada dictado van hasta \(Diccionario.maximoEnPrompt), primero las que se parecen a lo que dijiste.",
                "\(diccionario.terminos.count) of \(Diccionario.maximo) words. Up to \(Diccionario.maximoEnPrompt) go with each dictation, starting with those closest to what you said."))
            .font(.system(size: 12)).foregroundStyle(Tema.apagado)
    }

    private func detalle(_ s: Sugerencia) -> String {
        let origen = ["corrección": T("La corrigió la IA", "Corrected by the AI"), "código": T("Nombre de código", "Code name"),
                      "pantalla": T("Apareció en tus ventanas", "Seen in your windows"),
                      "a mano": T("La corregiste a mano", "You fixed it by hand")][s.origen] ?? T("Proyecto", "Project")
        var partes = [origen]
        if s.veces > 1 { partes.append(T("\(s.veces) veces", "\(s.veces) times")) }
        if !s.alias.isEmpty { partes.append(T("se escuchó «\(s.alias.joined(separator: "», «"))»", "heard as “\(s.alias.joined(separator: "”, “"))”")) }
        return partes.joined(separator: " · ")
    }

    private func agregar() {
        let alias = nuevoAlias.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if diccionario.agregar(nuevo, alias: alias) { nuevo = ""; nuevoAlias = ""; nota = nil }
        else if !nuevo.isEmpty { nota = T("El diccionario está lleno.", "The dictionary is full.") }
    }
}

private struct FilaTermino: View {
    let termino: Termino
    @ObservedObject var diccionario: Diccionario
    @Estado private var texto = ""
    @Estado private var alias = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("", text: $texto, onCommit: guardar).textFieldStyle(.plain)
                    .font(.titulo(14, .regular)).frame(maxWidth: .infinity)
                TextField(T("sin alias", "no aliases"), text: $alias, onCommit: guardar).textFieldStyle(.plain)
                    .font(.system(size: 13)).foregroundStyle(Tema.apagado).frame(maxWidth: .infinity)
                Button { diccionario.terminos.removeAll { $0.id == termino.id } } label: {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Tema.apagado)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(T("Borrar", "Delete"))
            }
            .padding(.horizontal, 16).frame(minHeight: 44)
            Rectangle().fill(Tema.bordeSuave).frame(height: 1).padding(.leading, 16)
        }
        .onAppear {
            texto = termino.texto
            alias = termino.alias.joined(separator: " | ")
        }
    }

    private func guardar() {
        guard let i = diccionario.terminos.firstIndex(where: { $0.id == termino.id }) else { return }
        let t = Diccionario.limpiar(texto)
        guard !t.isEmpty else { texto = termino.texto; return }
        diccionario.terminos[i].texto = t
        diccionario.terminos[i].alias = alias.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // Lo revisaste vos: deja de ser "aprendido solo" y sus alias vuelven a aplicarse (Diccionario.aplicarAlias).
        diccionario.terminos[i].automatico = nil
    }
}
