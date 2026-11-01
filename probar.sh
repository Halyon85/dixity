#!/bin/zsh
# Corre las pruebas automáticas de Dixity (Tests/DixityTests, framework Testing de Swift). Uso: ./probar.sh [--filter Nombre]
# Sin Xcode, a veces swift test no encuentra solo el complemento de Testing (las macros @Test/#expect): se le pasa la carpeta.
set -euo pipefail
cd "$(dirname "$0")"
extra=()
for d in /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
         "$(xcode-select -p 2>/dev/null)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing"; do
  [[ -d "$d" ]] && { extra=(-Xswiftc -plugin-path -Xswiftc "$d"); break; }
done
# De a una: varias pruebas usan los mismos ajustes compartidos (Ajustes.shared) y en paralelo se pisan.
swift test --no-parallel "${extra[@]}" "$@"
