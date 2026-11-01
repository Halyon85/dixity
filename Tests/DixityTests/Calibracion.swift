import Foundation
import Testing
@testable import Dixity

// Medición contra el historial real (no corre en las pruebas de siempre): DIXITY_HISTORIAL_REAL=<historial.json>
// swift test --filter Calibracion. Solo imprime cuentas, nunca los textos.
@Suite struct Calibracion {
    init() { Ayudas.preparar() }

    @Test func barreraContraElHistorialReal() throws {
        guard let ruta = ProcessInfo.processInfo.environment["DIXITY_HISTORIAL_REAL"] else { return }
        let registros = try JSONDecoder().decode([Registro].self, from: Data(contentsOf: URL(fileURLWithPath: ruta)))
        var aceptados = 0, ahoraFrena = 0
        var motivos: [String: Int] = [:]
        for r in registros where r.usoIA && r.barrera == nil && r.modo == .dictado {
            aceptados += 1
            let e = Estilo.desde(corto: r.estilo) ?? .comun
            if let m = Prompts.barrera(transcripcion: r.transcripcion, salida: r.final, trabajo: e == .trabajo, estilo: e) {
                ahoraFrena += 1
                motivos[String(m.prefix(28)), default: 0] += 1
            }
        }
        print("CALIBRACION aceptados=\(aceptados) ahoraFrena=\(ahoraFrena) motivos=\(motivos)")
    }
}

extension Calibracion {
    @Test func detalleNegaciones() throws {
        guard let ruta = ProcessInfo.processInfo.environment["DIXITY_HISTORIAL_DETALLE"] else { return }
        let registros = try JSONDecoder().decode([Registro].self, from: Data(contentsOf: URL(fileURLWithPath: ruta)))
        for r in registros where r.usoIA && r.barrera == nil && r.modo == .dictado {
            guard let p = Prompts.negacionPerdida(transcripcion: r.transcripcion, salida: r.final) else { continue }
            let w = String(p.split(separator: " ").last ?? "")
            let raiz = String(Prompts.sonido(w).prefix(3))
            let s = Diccionario.normalizar(r.final).split(separator: " ").map(String.init)
            let ctx = s.indices.filter { s[$0].count >= 4 && Prompts.sonido(s[$0]).hasPrefix(raiz) }
                .map { s[max(0, $0 - 4)...min(s.count - 1, $0 + 2)].joined(separator: " ") }
            let d = Diccionario.normalizar(r.transcripcion).split(separator: " ").map(String.init)
            let ctxD = d.indices.filter { d[$0] == w }.map { d[max(0, $0 - 4)...min(d.count - 1, $0 + 2)].joined(separator: " ") }
            print("DETALLE [\(r.estilo ?? "")] dicho: \(ctxD) | salida: \(ctx)")
        }
    }
}

extension Calibracion {
    // Cuántas palabras con contenido trae la salida que no dijiste, por modo (percentiles), para elegir el tope.
    @Test func palabrasNuevasPorModo() throws {
        guard let ruta = ProcessInfo.processInfo.environment["DIXITY_HISTORIAL_REAL"] else { return }
        let registros = try JSONDecoder().decode([Registro].self, from: Data(contentsOf: URL(fileURLWithPath: ruta)))
        var por: [String: [(Int, Int)]] = [:]
        for r in registros where r.usoIA && r.barrera == nil && r.modo == .dictado {
            let nuevas = Prompts.palabrasAgregadas(transcripcion: r.transcripcion, salida: r.final).count
            let dichas = Diccionario.normalizar(r.transcripcion).split(separator: " ").count
            por[r.estilo ?? "?", default: []].append((nuevas, dichas))
        }
        for (modo, v) in por {
            let ratios = v.map { Double($0.0) / Double(max(1, $0.1)) }.sorted()
            let abs = v.map(\.0).sorted()
            func p(_ x: [Double], _ q: Double) -> String { String(format: "%.2f", x[min(x.count - 1, Int(Double(x.count) * q))]) }
            print("NUEVAS \(modo) n=\(v.count) abs p50=\(abs[abs.count/2]) p90=\(abs[min(abs.count-1, abs.count*9/10)]) max=\(abs.last!) ratio p50=\(p(ratios,0.5)) p90=\(p(ratios,0.9)) p95=\(p(ratios,0.95)) max=\(p(ratios,1))")
        }
    }
}
