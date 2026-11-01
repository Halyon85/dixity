# Security / Seguridad

Dixity listens to your microphone, reads the text around your cursor, can take a picture of what you point at with
Wonder, keeps your AI keys in the macOS Keychain and can ask Claude Code or Codex to work in your projects. A bug in
any of those can expose private things, so security reports get priority.

## Reporting a vulnerability

**Please do not open a public issue.** Use GitHub's private reporting instead: the **Security** tab of this
repository → **Report a vulnerability**. Include what you did, what happened and, if you can, how to reproduce it
(never send real keys, recordings or screenshots with private data).

We will confirm we received it within a few days, tell you what we plan to do and credit you in the fix if you want.

## What counts

- Anything that sends audio, text, screenshots or keys somewhere you didn't choose, or without you asking.
- Reading or pasting into password fields, or taking text from a password manager.
- Reading the Keychain entries of another app, or leaking your AI keys (logs, history, files, screenshots).
- Making Claude Code or Codex run with more permissions than the read-only / edit-files modes Dixity asks for.
- An update that installs without a valid signature.

Only the latest version is supported.

---

## Avisar un problema de seguridad

Dixity escucha el micrófono, lee el texto alrededor del cursor, puede sacarle una foto a lo que señalás con la Varita,
guarda tus claves de IA en el Llavero de macOS y puede pedirle a Claude Code o a Codex que trabajen en tus proyectos.
Un error en cualquiera de esas partes puede dejar a la vista cosas privadas, así que estos avisos tienen prioridad.

**No abras un issue público.** Usá el aviso privado de GitHub: pestaña **Security** de este repositorio → **Report a
vulnerability**. Contá qué hiciste, qué pasó y, si podés, cómo repetirlo (nunca mandes claves reales, grabaciones ni
capturas con datos privados).

Te confirmamos que lo recibimos en unos días, te contamos qué vamos a hacer y, si querés, te nombramos en el arreglo.

Cuenta como problema de seguridad: que algo viaje a donde no elegiste o sin que lo pidas; leer o pegar en campos de
contraseña o tomar texto de un gestor de contraseñas; filtrar tus claves; que Claude Code o Codex corran con más
permisos que los que pide Dixity; o una actualización que se instale sin una firma válida. Solo se mantiene la última
versión.
