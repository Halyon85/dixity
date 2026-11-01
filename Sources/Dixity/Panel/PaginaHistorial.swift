import SwiftUI

struct PaginaHistorial: View {
    @ObservedObject var historial: Historial
    let motor: Motor
    @Estado private var reprocesando: UUID?
    @Estado private var errorReproceso: String?
    @Estado private var confirmar = false
    @Estado private var abierto: UUID?
    @Estado private var copiado: UUID?

    private var grupos: [(String, [Registro])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        let ingles = IdiomaInterfaz.actual == .en
        fmt.locale = IdiomaInterfaz.locale
        fmt.dateFormat = ingles ? "EEEE, MMMM d" : "EEEE d 'de' MMMM"
        var orden: [String] = []
        var mapa: [String: [Registro]] = [:]
        for r in historial.registros {
            let clave = cal.isDateInToday(r.fecha) ? T("Hoy", "Today") : cal.isDateInYesterday(r.fecha) ? T("Ayer", "Yesterday") : fmt.string(from: r.fecha).capitalized
            if mapa[clave] == nil { orden.append(clave) }
            mapa[clave, default: []].append(r)
        }
        return orden.map { ($0, mapa[$0]!) }
    }

    var body: some View {
        HStack(alignment: .top) {
            TituloPagina(titulo: T("Historial", "History"), subtitulo: T("Lo que dictaste en las últimas 24 horas, con su audio. Después se borra solo.",
                                                                "What you dictated in the last 24 hours, with audio. It clears itself after that."))
            Spacer()
            if !historial.registros.isEmpty {
                BotonSecundario(texto: T("Vaciar", "Clear"), icono: "trash", peligro: true) { confirmar = true }
            }
        }
        .confirmationDialog(T("¿Vaciar el historial?", "Clear history?"), isPresented: $confirmar) {
            Button(T("Vaciar", "Clear"), role: .destructive) { historial.vaciar() }
        } message: { Text(T("Se borran todos los dictados guardados. No se puede deshacer.", "All saved dictations will be deleted. This can't be undone.")) }

        if !historial.registros.isEmpty {
            Text(T("\(historial.registros.count) dictados · \(historial.palabrasDictadas) palabras", "\(historial.registros.count) dictations · \(historial.palabrasDictadas) words"))
                .font(.system(size: 12)).foregroundStyle(Tema.apagado)
        }
        if historial.registros.isEmpty {
            Tarjeta {
                Text(T("Todavía no dictaste nada.", "Nothing dictated yet.")).font(.system(size: 13)).foregroundStyle(Tema.apagado)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        ForEach(grupos, id: \.0) { titulo, registros in
            Tarjeta(titulo: titulo) {
                ForEach(registros) { r in fila(r, ultimo: r.id == registros.last?.id) }
            }
        }
    }

    private func fila(_ r: Registro, ultimo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(r.fecha.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(Tema.apagado).frame(width: 44, alignment: .leading)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.final).font(.system(size: 14)).foregroundStyle(Tema.titulo).textSelection(.enabled)
                        .lineLimit(abierto == r.id ? nil : 3)
                    HStack(spacing: 6) {
                        if r.reprocesoDe != nil { Text(T("Reproceso", "Reprocessed")).foregroundStyle(Tema.acento) }
                        if r.modo == .reescritura { Text(T("Reescritura", "Rewrite")).foregroundStyle(Tema.acento) }
                        if r.modo == .respuesta { Text(T("Respuesta", "Answer")).foregroundStyle(Tema.acento) }
                        if r.estilo == "Trabajo" { Text(Estilo.trabajo.etiqueta + (r.proyecto.map { " · \($0)" } ?? "")).foregroundStyle(Tema.acento) }
                        if !r.app.isEmpty { Text(r.app) }
                        Text(String(format: T("%.1f s de audio", "%.1f s of audio"), r.segundosAudio))
                        if r.barrera != nil { Text(T("· sin limpiar", "· not cleaned up")).foregroundStyle(Tema.error) }
                    }
                    .font(.system(size: 11)).foregroundStyle(Tema.apagado)
                    if abierto == r.id { detalle(r) }
                }
                Spacer(minLength: 0)
                Button {
                    Cursor.copiar(r.final)
                    copiado = r.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copiado == r.id { copiado = nil } }
                } label: {
                    Image(systemName: copiado == r.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12)).foregroundStyle(copiado == r.id ? Tema.exito : Tema.apagado)
                        .frame(width: 32, height: 32).background(Circle().fill(Tema.rellenoSuave))
                }
                .buttonStyle(.plain).help(T("Copiar", "Copy"))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Tema.expo) { abierto = abierto == r.id ? nil : r.id } }
            if !ultimo { Rectangle().fill(Tema.bordeSuave).frame(height: 1).padding(.leading, 72) }
        }
    }

    private func detalle(_ r: Registro) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let i = r.instruccion {
                bloque(T("Instrucción", "Instruction"), i)
                bloque(T("Texto original", "Original text"), r.transcripcion.isEmpty ? T("(no había selección)", "(nothing was selected)") : r.transcripcion)
            } else {
                bloque(T("Lo que escuchó", "What it heard"), r.transcripcion)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(T("Voz a texto: \(r.proveedorVoz ?? "—") · \(r.msVoz) ms", "Speech to text: \(r.proveedorVoz ?? "—") · \(r.msVoz) ms"))
                if let ia = r.proveedorIA { Text(T("IA: \(ia) · \(r.msIA) ms", "AI: \(ia) · \(r.msIA) ms")) }
                if let b = r.barrera { Text(T("Barrera: \(b)", "Guardrail: \(b)")).foregroundStyle(Tema.error) }
            }
            .font(.system(size: 11).monospacedDigit()).foregroundStyle(Tema.apagado)
            if r.modo == .dictado && r.audio != nil {
                HStack(spacing: 8) {
                    BotonSecundario(texto: reprocesando == r.id ? T("Procesando…", "Processing…") : T("Reprocesar con lo elegido ahora", "Reprocess with current settings"), icono: "arrow.triangle.2.circlepath") {
                        guard reprocesando == nil else { return }
                        reprocesando = r.id; errorReproceso = nil
                        motor.reprocesar(r) { err in reprocesando = nil; errorReproceso = err }
                    }
                    if let e = errorReproceso { Text(e).font(.system(size: 11)).foregroundStyle(Tema.error) }
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 6)
    }

    private func bloque(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(Tema.apagado)
            Text(s).font(.system(size: 12)).foregroundStyle(Tema.subtitulo).textSelection(.enabled)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Tema.fondoMedio))
    }
}
