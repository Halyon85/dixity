# Contributing / Colaborar

Thanks for wanting to help. Issues and pull requests are welcome in **English or Spanish**. The code, its comments and
the commit messages are in Spanish (Argentina); new code should follow the same style.

## Before you send a change

1. Run the tests (no Xcode needed; they never touch your real settings, keys or history):

   ```bash
   ./probar.sh
   ```

2. Build the app and try your change in it: `./compilar.sh` leaves it in `build/Dixity.app`.
3. A fix comes with a test that failed before it.
4. One topic per pull request, with a short description of what changes for the person using the app. If it changes
   what the app looks like, add a screenshot (`Dixity --capturas <folder>` with `DIXITY_CARPETA` pointing to an empty
   folder renders them without your data).

## Ground rules

- Nothing leaves the Mac unless the person asked for it, and only to the provider they chose.
- Password fields and password managers are never read, recorded or pasted into.
- Keys live in the Keychain, never in files, logs or history.
- Claude Code and Codex never get full permissions.
- Comments say what the code does, who calls it and why.

By contributing you agree that your contribution is licensed under the [Apache License 2.0](LICENSE).

---

## Colaborar

Gracias por querer ayudar. Los issues y pull requests pueden ser en **español o en inglés**. El código, los
comentarios y los commits están en español rioplatense; lo nuevo tiene que seguir el mismo estilo.

Antes de mandar un cambio: corré `./probar.sh`, probalo en la app (`./compilar.sh`), sumá una prueba que fallaba antes
del arreglo y mandá un tema por pull request (con una captura si cambia cómo se ve). Las reglas son las de arriba: nada
sale de la Mac sin que lo pidas y solo al proveedor que elegiste, los campos de contraseña no se tocan, las claves van
al Llavero, Claude Code y Codex nunca tienen permisos totales, y los comentarios dicen qué hace el código, quién lo
llama y por qué.

Al colaborar aceptás que tu aporte queda bajo la [licencia Apache 2.0](LICENSE).
