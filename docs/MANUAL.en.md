# Dixity — quick manual

*Leelo en español: [MANUAL.md](MANUAL.md).*

Dixity lives in the menu bar. Press a shortcut, talk, and clean text appears wherever your cursor is, in any app.
Everything is set up in the panel (click the menu bar icon › Settings).

## 1. First time

1. **Permissions** (General › Permissions): Microphone and Accessibility. Without Accessibility the shortcut isn't
   heard and nothing can be pasted. "Read the screen" also needs Screen Recording.
2. **How you want to use it** (Providers):
   - **Everything on your Mac**: speech with Parakeet or the Mac's own engine, and clean-up with Apple Intelligence.
     No keys and no internet; nothing leaves your Mac.
   - **Bring your own API**: OpenAI, Anthropic, Grok, Groq, OpenRouter or any OpenAI-compatible service. You pay them
     directly. Keys stay in the Mac's Keychain, never in a file.
3. **General › Open at login**, so the shortcut always works. You can see the welcome screens again from General.

## 2. Shortcuts (change them in Shortcuts)

| Shortcut | What it does |
|---|---|
| **Right ⌥** | **Dictate.** Tap once to start and again to finish, or hold and let go. **Esc** cancels. |
| **Left ⇧⌥** | **Rewrite** your selection ("shorter", "for an email"). With nothing selected, it writes what you ask for. |
| **⌃⌥P** | **Ask**: the answer shows up in a small window before it's pasted. It also talks to Claude and Codex. |
| **⌃⌥V** | **Clipboard**: what you copied in the last 24 h. ↩ pastes, ⌘1–9 pastes fast, ⌘⌫ deletes. |
| **⌃⌥R** | **Process again** your last dictation (if it came out wrong or the AI failed). |
| **⌃⌥D** | **Add to dictionary** the word you have selected. |
| **⌃⌥O / ⌃⌥S** | Quick actions on a selection: **Tidy up** and **Summarize** (no talking). |
| **⌃⌥1…6** | Dictate in a specific mode. **⌃⌥0** goes back to Automatic. While recording, 1…6 switch the mode. |
| **Shake the mouse** | Turns on **Wonder** (see 5b). Everything about Wonder is set on its own panel page, **Wonder**. |

## 3. The pill

It's the little bar that shows up while you dictate. The dot takes the mode's color. Hover over it: ✕ cancels and
✓ finishes. You can drag it and it remembers where you left it. If it can't hear you, it says so; if something fails,
it stays with **Retry** and plays a sound. Style (light, dark, glass, crystal), size and transparency: General › Pill.

## 4. Modes: how it cleans up (Modes page)

- **Automatic** (the default) picks by app. The list is edited in "Which mode each app uses".
- **Standard**: emails, chats and notes, the way you'd say it but tidy.
- **Prompt**: arranges what you say as a request for an AI (Claude, ChatGPT, Codex…). If the window belongs to a
  project in your **Project folders**, it uses that project's guide (AGENTS.md or CLAUDE.md) to spell names right.
- **Email**, **Message** (with one or two emojis if you want), **Formal** and **Translate** (the language is picked in
  "Translate to").
- **After pasting**: in Prompt or Message it can press Enter for you, to send without touching anything.
- **Quick actions**: Tidy up, Summarize and Fix spelling come ready. You can edit them, give them a shortcut and add
  more.

## 5. Ask (⌃⌥P)

Hold ⌃⌥P and ask for something: "reply that Thursday works for me", "how do you say this in Spanish?". With text
selected, it works on that text.

- While you talk, the pill says **what it's going to work on** ("About 34 words", "No selection · Safari").
- The answer shows up in a **card** that adapts to what it shows: formatted text (lists, code with its own Copy),
  a translation ("Spanish → English" with the original folded away), text it read, links from a QR code (with the
  domain in large type, and Open only on click), your Claude and Codex usage with bars, or a social post with one tab
  per network. **↩** or **Paste** pastes it, **Copy** copies it, **Esc** (or typing somewhere else) closes it.
- **Buttons to keep working** under the answer: To English/Spanish (free with Apple's translator, green dot),
  Rephrase, Shorter, More formal or casual, Summarize if it's long. **Undo** goes back to the previous version.
- **Hold ⌃⌥P again** to adjust it: "shorter", "more formal".
- It's kept in History as "Answer".

**With nothing selected, it looks at the window:** "what does this say?", "summarize this page" or "explain this
error" hand the text of the front window to your AI (with "Look at the window" and "Read the screen" turned on).

**Free, on your Mac and without AI** (the small window says "on your Mac"):
- **"Translate it to English"** with text selected: uses Apple's translator. It needs the languages downloaded in
  System Settings › General › Language & Region › Translation Languages; if they're missing, your AI translates it.
- **"Scan the QR code"**: reads the QR codes or barcodes in the window (or in the image you copied). It shows the link
  and never opens it on its own.
- **"Get the text from here"** or **"…from the image I copied"**: the text of the window or the image, ready to copy
  or paste.
- Looking at the window needs the Screen Recording permission.

## 5b. Wonder

Shake the mouse from side to side and **the pointer turns into Wonder** (blue, with a glow that swirls inside). Whatever
is under it gets outlined in the same colors, and a small box with things to do shows up at the bottom right of the
pointer:
- **A text box (or selected text inside one):** To English/Spanish, Rephrase and Fix **change it right there**, as if
  you had typed it yourself (**⌘Z** undoes it). An empty box offers **Dictate here**.
- **Text you had selected:** Read aloud, To English/Spanish, Summarize, Ask about this. If it looks like an error from
  a program: **Fix it with Claude** and Explain this error.
- **An image:** **Describe** (your AI looks at it and tells you what's there, in a couple of seconds, with a small copy
  of the image on top), **Get a prompt** (an English prompt to recreate it with an image generator, always in high
  resolution; on the card you pick the format —Original, 1:1, Post 4:5, Story 9:16 or 16:9—, **Change something** by
  voice ("make it nighttime"), **Animate it** —it asks whether the video goes vertical 9:16 or horizontal 16:9 and
  writes a 15-second prompt to use with the image as a reference in Sora, Veo, Runway or Kling, with "Copy image"—,
  switch it to Spanish or make it more detailed), Read the QR (only if it has one), Copy image, Grab the text and Send
  to Claude or to Codex. To ask anything else about the image, hold the Ask shortcut while the card is open.
  Describe and Get a prompt use an AI that can see images (OpenAI, Claude, Grok or OpenRouter): the image travels to it
  only when you ask. Without one of those, Describe tells you what the Mac recognizes (free) and the question goes to
  Claude Code if it's there.
- **Text:** To English/Spanish, Read aloud, Summarize, Send to Claude, Copy text.
- **A link:** Where does it go?, Copy link. **A table:** Copy as spreadsheet.
- **Always, at the end:** Capture: drag a box with Wonder and the snipped area is picked, with the same options as an
  image (you can also do it directly with **⌥ + drag**). Whatever uses AI only shows up if you have one set up; Claude
  and Codex, only if they're on your Mac.
- **Send to Claude / Codex** pastes what you picked into its open window (the terminal with Claude Code, the Claude app
  or the ChatGPT/Codex app), with the page it came from, and starts listening so you can say what you want ("I want
  this button on my landing page"). It doesn't press Enter: you send it. If no window is open, it's copied.
- **Read aloud** uses the Mac's voices, for free. If you turn on "With OpenAI's voice" on the Wonder page, it uses your
  OpenAI key and sounds like a person, with a Rioplatense (Argentine) accent (around 1.5 US cents per minute).

How to use it:
- **Click** picks what's under the pointer (the click doesn't reach the app, except in a text box, which becomes active
  that way). **Dragging** selects text as usual, and the small box switches to offering what to do with it.
- **⇧ + click** adds more things: they go into the small box as thumbnails and are **copied together**; with several,
  it offers Copy all together, Send to Claude or to Codex, Make a collage or Ask about all (your AI looks at them;
  without one that sees images, Claude Code).
- **It recognizes more than images:**
  - **A video** (on a web page): Describe, Get a prompt and **Copy this frame** (a picture of what's on screen, even
    while it plays).
  - **A logo** (its text says so, or it's small and links to the site's home page): **Recreate logo** (a prompt to make
    an original one in that style, with the text in quotes: with "Change something" you tell it "make it say Halyon"),
    **Get colors**, Describe.
  - **A banner** (a wide image): **Recreate banner** (with its texts), Describe, Get colors.
  - **A section, the window or a snip:** **Make a mockup**: your AI writes a design summary (what it is, structure,
    texts word for word —it reads them from the page—, colors, typography and details), with **Send to Claude** so it
    builds it and **Image prompt** for a visual mockup.
  - **Get colors** runs on your Mac and is free: it shows each color with its code and how much of the area it takes;
    click one to copy it.
- **⌥ + scroll** (or the trackpad, or **⌥↑ / ⌥↓**) grows the outline to whatever contains it: from a photo to its card,
  to the page section and to the whole window (the outline says "Section · 2/4"); the other way, it shrinks. A section
  or the window are handled like an image: Describe, Get a prompt, Copy, Grab the text, Send to Claude.
- **1…6** pick a suggestion; **Esc** lets go of what you picked and, pressed again, turns it off. It turns itself off
  after 30 seconds without use, when you shake again or when you ask for something. The answer shows up next to where
  you were.
- It needs Accessibility (you already have it) and, to copy, send or read images, Screen Recording.
- **On the panel's Wonder page** you'll find the shake sensitivity, when it turns itself off, whether it changes text
  in place, Claude and Codex, looking for QR codes, the pointer (with a button to restore the macOS one), the reading
  voice (with "Listen" to try it) and the permissions.
- If macOS enlarges the pointer with the same gesture, turn off "Shake mouse pointer to locate" in System Settings ›
  Accessibility › Display › Pointer.

## 5c. Posting with your folders

In **Modes › Projects and marketing › Brand and marketing folders** pick your marketing folder (if it has `marcas/`,
each subfolder is a brand). Then, with ⌃⌥P: **"Write a LinkedIn post about Dixity"** or **"this week's content plan
for my coffee shop"**.
- Claude Code writes it in that folder, **read-only** and with your subscription: it reads the brand's profile and, if
  you name a product from your Project folders, its README.
- The card has one tab per network, the character count against each one's limit and its own Copy.
- **Save draft** (only on click) saves it in `marcas/<brand>/organico/`. **Dixity never posts anything.**
- If there are several brands and you don't name one, it asks which.

## 6. Claude and Codex by voice

With the project's window in front (Terminal, Cursor, VS Code…), hold ⌃⌥P and start with the name:
**"Claude, why is the login failing?"** or **"Codex, check the tests"**.

- It uses the `claude` and `codex` programs installed on your Mac, with your subscription.
- The project folder has to be in **Modes › Projects › Project folders**. If not, it says "I don't know which project".
- **At first it only looks**: Claude in plan mode, unable to edit, and Codex read-only. Meanwhile you keep dictating.
  When it's done, it plays a sound and the small window with the answer shows up.
- **Have Claude do it** (or Codex): a button that only works on click. Only then does it edit the project's files:
  Claude picks up the same conversation and Codex works inside the folder. **It never gets full permissions.**
- **"How much Claude do I have left?"** (or Codex, or "how much usage do I have left?" for both) answers instantly,
  with no AI and no internet, with bars: how much of the session and the week you've used, how much is left, when it
  resets and, for Claude, how many conversations you opened today in each project. The data is from the last time you
  used each program.

## 7. Dictionary

Names and words Dixity always has to get right. For a correction, write "how it comes out wrong, how it should be".

- Add them by hand, with **⌃⌥D** on a selection or with **Import list**.
- **Suggested by Dixity**: words the AI corrected, names from code, the ones that show up in your windows and the ones
  you **fixed by hand** after a dictation was pasted. They never go in on their own: you tap Add or Dismiss.

## 8. Voice (how it listens and what it looks at)

- **Recognition**: language (automatic, Spanish or English) and microphone.
- **Look at the window**: reads the text around the cursor and the app's name, to follow your sentence and spell names
  right.
- **Read the screen**: reads the text of the front window on your Mac; the image is never saved or sent.
- **Clean-up**: clean up with AI, basic clean-up without AI, preferences ("write casually", "sign as Ana") and
  **per-app or per-site instructions** ("LinkedIn: professional tone").
- **Personal memory**: a short summary of how you talk and your names. It's updated every 12 dictations and you can
  edit or delete it.
- **While dictating**: pause the music, and start and finish sounds.

## 9. History

The last 24 hours, with the audio. For each dictation you see what it heard, what it pasted and which service it used.
**Reprocess** runs the same audio through the services you have picked now, to compare. **Clear** deletes everything.

## 10. Privacy

- **Passwords**: it never reads password fields or password manager windows, and doesn't keep passwords in the
  clipboard.
- **Keys**: anything on screen that looks like a key is covered before it's sent to the AI.
- **Data**: settings, dictionary and history live on your Mac (General › Your data › Show folder).
- **No keys**: with "Everything on your Mac", nothing leaves your computer.

## 11. If something doesn't work

- **The shortcut doesn't respond**: General › Permissions (Accessibility). If you just updated the app, macOS may ask
  for the permissions again.
- **"Can't hear you"**: check the microphone in Voice › Recognition.
- **Claude "isn't logged in"**: open `claude` in the Terminal and log in with `/login`.
- **"I don't know which project"**: add the folder in Modes › Projects.
- **A dictation came out wrong**: ⌃⌥R processes it again. If you select what it pasted before, it replaces it.

## 12. For developers

- `./compilar.sh` builds `build/Dixity.app`, and `./compilar.sh instalar` also installs and opens it. It only needs the
  Mac's command line tools.
- `./probar.sh` runs the tests. They use a separate folder and keychain, so they never touch your data.
- The test with the real Claude and Codex (read-only, uses your subscription) runs with
  `DIXITY_PRUEBA_REAL=1 ./probar.sh --filter AgentesDeVerdad`.
- `Dixity --capturas <folder>` renders every screen to PNG.
