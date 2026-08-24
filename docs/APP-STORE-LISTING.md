# App Store listing copy

Every text field App Store Connect asks for, in every language Belay ships,
ready to paste. Nothing here is written from imagination: every claim maps to
something the app does, because a claim the binary does not support is
inaccurate metadata under guideline 2.3 and is refused at review.

**This file is the copy of what is in App Store Connect, not a draft of it.** The
descriptions below were pulled back out of the API on 2026-08-16 and then
edited, rather than retyped from an older draft that had already drifted. When
a field is changed in the store, change it here in the same sitting.

Character limits are Apple's and are counted below each field. Cyrillic counts
the same as Latin, so the Russian lines were written to the same budget rather
than translated and hoped over.

Two rules the copy follows throughout. No superlatives, because a utility that
shouts is a utility nobody believes. And no price words anywhere: 2.3.7 forbids
them in metadata other than the price field, which is also why "Free" appears on
no screenshot.

---

## Fields that are the same in every language

**Name** `Belay - Awake for AI Agents`, in every localisation. App Store Connect
keeps a name per localisation, and there is no reason for them to differ: the
app is called Belay everywhere, and the tail is three English words that read
the same in the five other stores this ships to. It must not contain "Mac" or
any other Apple product name in any of them, which is what guideline 5.2.5 is
about and what the 2026-08-16 rejection was.

**Bundle ID** `com.perfectoweb.belay`
**SKU** `belay-mac-1`
**Apple ID** `6801207644`, issued when the record was created
**Primary category** Developer Tools
**Secondary category** Utilities
**Age rating** 4+
**Price** Free
**Copyright** `2026 PerfectoWeb`
**Support URL** `https://perfecto-web.com/en/contacts/`, and
`https://perfecto-web.com/ru/contacts/` in Russian. Chinese uses the English one
because `/zh/contacts/` returns 404, and Apple loads these at review.
**Marketing URL** `https://perfectoweb.github.io/Belay/` (redirects to the reader's language)

Both were `perfecto-web.com/belay` addresses and both returned 404 on the day
of the first release. Apple requires these to load without a login and checks
them at review, so they point at pages that exist. Move them back to the
product's own domain whenever those pages are built.
**Privacy policy URL**, one per App Store Connect localisation:

| Localisation | URL |
|---|---|
| English (U.S.) | `https://perfectoweb.github.io/Belay/privacy/` |
| Russian | `https://perfectoweb.github.io/Belay/ru/privacy/` |
| German | `https://perfectoweb.github.io/Belay/de/privacy/` |
| Spanish (Spain) | `https://perfectoweb.github.io/Belay/es/privacy/` |
| French | `https://perfectoweb.github.io/Belay/fr/privacy/` |
| Italian | `https://perfectoweb.github.io/Belay/it/privacy/` |
| Simplified Chinese | `https://perfectoweb.github.io/Belay/zh/privacy/` |

Apple would have accepted the English address in every box. It is a real policy
in each language instead, because this is the one document where a reader needs
to understand exactly what is read off their disk, and the app already speaks
all seven. Each translation says it is a translation and links to the English,
which governs.
---

## Names and subtitles, all seven at once

Set them together, because the rule that forced this change applies to every
localisation and three of them were still wrong on 2026-08-16: `de-DE`, `it` and
`es-ES` were still reading `Belay - Keep Mac Awake` in App Store Connect while
`en-US`, `ru` and `fr-FR` had been changed. One rejected localisation rejects
the submission.

Each name is localised rather than left in English. It costs one field per
store, "Belay" leads every one of them so the brand does not move, and the tail
is what somebody in that store would actually type. `Belay` alone is taken here
by an SSH client and by an assistant, which is why the name carries a
description at all.

| Locale | Name | | Subtitle | |
|---|---|---|---|---|
| English (U.S.) | `Belay - Awake for AI Agents` | 27 | `Sleeps again when they finish` | 29 |
| Russian | `Belay - Для AI агентов` | 22 | `Не спит, пока агент работает` | 28 |
| German | `Belay - Wach für KI-Agenten` | 27 | `Schläft, wenn sie fertig sind` | 29 |
| Spanish (Spain) | `Belay - Despierto para tu IA` | 28 | `Duerme cuando ellos terminan` | 28 |
| French | `Belay - Éveillé pour vos IA` | 27 | `Se rendort quand ils ont fini` | 29 |
| Italian | `Belay - Sveglio per le tue IA` | 29 | `Si riaddormenta a fine lavoro` | 29 |
| Simplified Chinese | `Belay - 为 AI 智能体保持唤醒` | 20 | `工作结束后自动进入睡眠` | 11 |

**If you would rather keep one name everywhere**, use
`Belay - Awake for AI Agents` in all seven and keep the localised subtitles
above. Search still works in each store, because Apple pools the name, the
subtitle and the keywords, and the other two fields are in the local language.
What is lost is the first line reading as the reader's own language.

**"Mac" must not appear in a name or a subtitle in any localisation.** That is
guideline 5.2.5 and it is what the 2026-08-16 rejection was. It stays in the
descriptions, where it is ordinary referential use and where Apple did not
object.

---

## What changed in the descriptions for 1.3

The text below is what is live in App Store Connect, pulled back out of the API
rather than retyped, with four edits applied to every language.

**Precise Detection is gone from the copy.** The paragraph promising that Claude
Code can tell Belay exactly when a turn starts and stops describes a feature the
App Store build does not have: the hook listener and its entitlement were
removed on 2026-08-16, and the feature could never have worked in a sandbox
anyway. Leaving the paragraph in would be inaccurate metadata under 2.3, which
is a rejection in its own right.

**Folders are remembered.** The one line about pointing Belay at a folder now
says that the choice survives a relaunch, which is what the security-scoped
bookmarks in 1.3 bought.

**The menu bar says when Belay let go.** One sentence under the section about
letting go, for the paused mark.

**No network at all.** The privacy section now says outright that this build
cannot reach the network in either direction. It is the strongest claim in the
listing and it is now literally true: there is no network entitlement of any
kind in the App Store build.

The languages line is corrected everywhere. Two of them were wrong before: the
German one said "SECHS SPRACHEN" and then listed one language in English, and
none of them mentioned Chinese.

---

## What changed in the descriptions for 1.3.2

Two edits, applied to every language on 2026-08-20, on top of whatever the
store held that day:

**What changed for 1.5.0.** The agents sentence in every language now names
three built-in agents — Claude Code, Codex and Cline — and Cline left the
preset list accordingly. Nothing else moved; the privacy claims are untouched
and still true.

**The agents paragraph tells the 1.3.2 truth.** Claude Code and Codex are both
detected precisely now — Codex graduated from a preset to a first-class
provider — and the preset list grew to six: Copilot CLI, Gemini CLI, OpenCode,
Cline, Aider and Pi.

**One sentence about the network.** Every hold now carries a network-client
assertion, so the copy says remote sessions survive. The privacy section's
"no network access of any kind" stays: a power assertion asks macOS not to
park the network stack, it neither connects out nor listens, and the build
still has no network entitlement.

---

## English (U.S.)

**Promotional text** (170)
```
Leave your agents running. Belay keeps your Mac awake while they work, then gets out of the way when they're done. No account. No telemetry.
```

**Keywords** (100, comma separated, no spaces)
```
ai,claude,codex,gemini,cline,caffeine,insomnia,sleep,menubar,coding,cli,terminal,developer
```

**Description** (4000)
```
Your Mac goes to sleep. The coding agent you left running stops making progress.

Belay keeps your Mac awake while coding agents work. When they're done, Belay gets out of the way and your Mac can sleep normally again.

No timer to start. No caffeine switch to remember. Just leave your agent running.

While Belay holds, it also asks macOS to keep the network active, so SSH sessions and streaming replies keep going.

WORKS WITH

Claude Code, Codex and Cline are detected precisely, out of the box: Belay reads their own session files, so it knows exactly when a turn starts and ends. Copilot CLI, Gemini CLI, OpenCode, Aider and Pi have ready-made presets.

For anything else, point Belay at a folder your tool writes to and it will use activity in that folder as the signal. The folders you choose are remembered, so you pick them once.

THREE MODES

• Auto: keeps your Mac awake while an agent is working.
• Always On: keeps it awake until you turn it off.
• Off: Belay stays out of the way.

KNOWS WHEN TO LET GO

Belay can wait a little after an agent goes quiet, stop after a maximum awake time, and stop on low battery. It never changes your macOS sleep settings.

When Belay stops on purpose, the menu bar icon shows it, so a Mac that went quiet is never a mystery.

NOTIFICATIONS, IF YOU WANT THEM

Belay can let you know when an agent needs you, a long run finishes, or it stops keeping your Mac awake for safety. Each notification can be turned off.

STAYS ON YOUR MAC

Belay uses local activity to determine whether an agent is working. It doesn't upload your prompts or code. There is no account, no analytics and no telemetry.

This version has no network access of any kind. It cannot connect out and it does not listen for anything.

Your statistics stay on your Mac unless you choose to share them.

STATISTICS THAT MEAN SOMETHING

See how long Belay kept your Mac awake while you were away, plus runs watched, runs saved and your longest run.

Time at the keyboard doesn't count, because your Mac wasn't going to sleep anyway.

LANGUAGES

English, Russian, German, Spanish, French, Italian and Simplified Chinese.
```

---

## Русский

**Promotional text** (170)
```
Belay не даст Mac уснуть, пока ваши AI агенты работают. Приложение само разрешит Mac заснуть, как только все процессы будут завершены.
```

**Keywords** (100)
```
ai,claude,codex,gemini,cline,caffeine,insomnia,sleep,menubar,coding,cli,terminal,developer,код
```

**Description** (4000)
```
Belay не даёт вашему Mac уснуть, пока работают AI coding-агенты. Как только агенты закончат работу, Mac автоматически перейдет в обычный режим засыпания.

Никаких таймеров. Никаких переключателей, о которых нужно помнить. Запустите Belay, настройте один раз - все остальное он сделает за вас.

Пока Belay держит Mac, он просит macOS сохранять активной и сеть: SSH-сессии и потоковые ответы не обрываются.

ПОДДЕРЖИВАЕМЫЕ АГЕНТЫ

Claude Code, Codex и Cline определяются точно и сразу: Belay читает их собственные файлы сессий и точно знает, когда работа началась и закончилась. Для Copilot CLI, Gemini CLI, OpenCode, Aider и Pi есть готовые пресеты.

Для остальных инструментов можно выбрать папку, и Belay будет определять работу по активности в ней. Выбранные папки запоминаются, так что указать их достаточно один раз.

ТРИ РЕЖИМА

• Авто: Mac не засыпает, пока работает агент.
• Всегда включено: Mac остаётся активным, пока вы сами не выключите режим.
• Выкл.: Belay ничего не меняет.

УМНОЕ УПРАВЛЕНИЕ

Belay может немного подождать после завершения работы, ограничить максимальное время без сна и остановиться при низком заряде батареи. Системные настройки сна macOS при этом не меняются.

Когда Belay останавливается намеренно, значок в строке меню это показывает. Затихший Mac больше не загадка.

УВЕДОМЛЕНИЯ

Belay может сообщить, когда агенту нужны вы, когда длительная задача завершилась или когда приложение перестало удерживать Mac от сна в целях безопасности. Каждое уведомление можно отключить.

ВСЁ ОСТАЁТСЯ НА MAC

Belay определяет активность локально. Ваши промпты и код никуда не загружаются. Никаких аккаунтов, аналитики или телеметрии.

У этой версии нет доступа к сети ни в какую сторону: она не может ничего отправить и ничего не слушает.

Статистика тоже остаётся на вашем Mac, пока вы сами не решите ею поделиться.

СТАТИСТИКА СО СМЫСЛОМ

Посмотрите, сколько времени Belay действительно не давал Mac уснуть, пока вас не было рядом, сколько запусков он видел, сколько сохранил и какой был самым долгим.

Время за клавиатурой не считается: в этот момент Mac и так не собирался засыпать.

ЛОКАЛИЗАЦИЯ

English, Русский, Deutsch, Español, Français, Italiano и 简体中文.
```

---

## Deutsch

**Promotional text** (170)
```
Lass deine Agents weiterarbeiten. Belay hält deinen Mac wach, solange sie arbeiten, und gibt ihn wieder frei, sobald sie fertig sind. Kein Account. Keine Telemetrie.
```

**Keywords** (100)
```
ruhezustand,terminal,cli,sitzung,hintergrund,automatisierung,aufgabe,energie,leerlauf,llm
```

**Description** (4000)
```
Dein Mac schläft ein. Der Coding-Agent, den du weiterarbeiten lassen wolltest, kommt nicht mehr voran.

Belay hält deinen Mac wach, solange Coding-Agents arbeiten. Sobald sie fertig sind, gibt Belay wieder frei und dein Mac kann ganz normal schlafen.

Kein Timer. Kein Schalter, an den du später denken musst. Lass deinen Agent einfach arbeiten.

Während Belay den Mac wach hält, bittet es macOS auch, das Netzwerk aktiv zu lassen: SSH-Sitzungen und Streaming-Antworten laufen weiter.

UNTERSTÜTZTE AGENTS

Claude Code, Codex und Cline werden präzise erkannt, direkt ab Werk: Belay liest ihre eigenen Sitzungsdateien und weiß genau, wann ein Turn beginnt und endet. Für Copilot CLI, Gemini CLI, OpenCode, Aider und Pi gibt es fertige Presets.

Für alles andere kannst du einen Ordner auswählen. Belay erkennt dann anhand der Aktivität in diesem Ordner, ob gerade gearbeitet wird. Die gewählten Ordner werden gemerkt, du wählst sie also nur einmal aus.

DREI MODI

• Auto: hält deinen Mac wach, solange ein Agent arbeitet.
• Immer an: hält ihn wach, bis du den Modus ausschaltest.
• Aus: Belay greift nicht ein.

WEISS, WANN ES LOSLASSEN KANN

Belay kann nach dem Ende einer Aufgabe noch kurz warten, die maximale Wachzeit begrenzen und bei niedrigem Akkustand aufhören.

Deine macOS-Einstellungen für den Ruhezustand bleiben unverändert.

Wenn Belay absichtlich aufhört, zeigt das Symbol in der Menüleiste es an. Ein Mac, der still wird, ist nie ein Rätsel.

BENACHRICHTIGUNGEN, WENN DU SIE WILLST

Belay kann dich informieren, wenn ein Agent dich braucht, ein längerer Lauf fertig ist oder Belay aus Sicherheitsgründen aufhört, deinen Mac wach zu halten.

Jede Benachrichtigung lässt sich einzeln ausschalten.

BLEIBT AUF DEINEM MAC

Belay erkennt Aktivität lokal. Deine Prompts und dein Code werden nicht hochgeladen. Kein Account, keine Analytics, keine Telemetrie.

Diese Version hat überhaupt keinen Netzwerkzugriff: Sie kann nichts senden und lauscht auf nichts.

Auch deine Statistiken bleiben auf deinem Mac, bis du sie selbst teilst.

STATISTIKEN, DIE ETWAS AUSSAGEN

Sieh, wie lange Belay deinen Mac tatsächlich wach gehalten hat, während du weg warst, wie viele Läufe erkannt und gerettet wurden und welcher am längsten dauerte.

Zeit an der Tastatur zählt nicht. Dann wäre dein Mac ohnehin nicht eingeschlafen.

SPRACHEN

English, Deutsch, Русский, Español, Français, Italiano und 简体中文.
```

---

## Español

**Promotional text** (170)
```
Deja a tus agentes trabajando. Belay mantiene tu Mac despierto mientras trabajan y se aparta cuando terminan. Sin cuenta. Sin telemetría.
```

**Keywords** (100)
```
reposo,terminal,cli,sesión,segundo plano,automatización,tarea,energía,inactivo,llm
```

**Description** (4000)
```
Tu Mac entra en reposo. El agente que dejaste trabajando deja de avanzar.

Belay mantiene tu Mac despierto mientras trabajan tus agentes de código. Cuando terminan, se aparta y tu Mac vuelve a dormir con normalidad.

Sin temporizadores. Sin interruptores que tengas que recordar después. Deja al agente trabajando y listo.

Mientras Belay mantiene tu Mac despierto, también pide a macOS que mantenga activa la red: las sesiones SSH y las respuestas en streaming no se cortan.

AGENTES COMPATIBLES

Claude Code, Codex y Cline se detectan con precisión desde el primer momento: Belay lee sus propios archivos de sesión y sabe exactamente cuándo empieza y termina un turno. Copilot CLI, Gemini CLI, OpenCode, Aider y Pi cuentan con ajustes predefinidos.

Para cualquier otra herramienta, puedes elegir una carpeta y Belay usará la actividad de esa carpeta para saber si hay trabajo en curso. Las carpetas que elijas se recuerdan, así que solo las eliges una vez.

TRES MODOS

• Auto: mantiene el Mac despierto mientras trabaja un agente.
• Siempre activo: lo mantiene despierto hasta que lo desactives.
• Desactivado: Belay no interviene.

SABE CUÁNDO SOLTAR

Belay puede esperar un poco cuando el agente termina, limitar el tiempo máximo que el Mac permanece despierto y detenerse si queda poca batería.

Tus ajustes de reposo de macOS no se modifican.

Cuando Belay se detiene a propósito, el icono de la barra de menús lo muestra. Un Mac que se queda en silencio nunca es un misterio.

NOTIFICACIONES, SI LAS QUIERES

Belay puede avisarte cuando un agente te necesita, cuando termina una tarea larga o cuando deja de mantener el Mac despierto por seguridad.

Puedes desactivar cada aviso por separado.

TODO SE QUEDA EN TU MAC

Belay detecta la actividad de forma local. Tus prompts y tu código no se suben a ningún sitio. Sin cuenta, sin analíticas y sin telemetría.

Esta versión no tiene ningún acceso a la red: no puede conectarse a nada ni escucha nada.

Tus estadísticas también permanecen en tu Mac hasta que decidas compartirlas.

ESTADÍSTICAS QUE SÍ CUENTAN

Consulta cuánto tiempo mantuvo Belay tu Mac despierto mientras estabas fuera, cuántas ejecuciones detectó, cuántas salvó y cuál fue la más larga.

El tiempo frente al teclado no cuenta. En ese momento, tu Mac tampoco iba a entrar en reposo.

IDIOMAS

English, Español, Deutsch, Français, Italiano, Русский y 简体中文.
```

---

## Français

**Promotional text** (170)
```
Laissez vos agents travailler. Belay garde votre Mac éveillé pendant leur travail, puis s’efface une fois qu’ils ont fini. Aucun compte. Aucune télémétrie.
```

**Keywords** (100)
```
veille,terminal,cli,session,arrière-plan,automatisation,tâche,énergie,inactif,llm
```

**Description** (4000)
```
Votre Mac se met en veille. L’agent que vous aviez laissé travailler n’avance plus.

Belay garde votre Mac éveillé tant que vos agents de code travaillent. Une fois leur tâche terminée, Belay s’efface et votre Mac peut de nouveau se mettre en veille normalement.

Pas de minuteur. Pas d’interrupteur à penser à désactiver plus tard. Laissez simplement votre agent travailler.

Pendant que Belay garde votre Mac éveillé, il demande aussi à macOS de maintenir le réseau actif : les sessions SSH et les réponses en streaming continuent.

AGENTS PRIS EN CHARGE

Claude Code, Codex et Cline sont détectés avec précision, sans aucune configuration : Belay lit leurs propres fichiers de session et sait exactement quand un tour commence et se termine. Copilot CLI, Gemini CLI, OpenCode, Aider et Pi disposent de préréglages prêts à l’emploi.

Pour les autres outils, choisissez simplement un dossier. Belay utilisera son activité pour savoir si un travail est en cours. Les dossiers choisis sont mémorisés, vous ne les indiquez donc qu’une fois.

TROIS MODES

• Auto : garde votre Mac éveillé pendant qu’un agent travaille.
• Toujours actif : le garde éveillé jusqu’à ce que vous désactiviez le mode.
• Désactivé : Belay n’intervient pas.

SAIT QUAND S’ARRÊTER

Belay peut attendre quelques instants après la fin du travail, limiter la durée maximale d’éveil et s’arrêter lorsque la batterie devient faible.

Vos réglages de veille macOS ne sont pas modifiés.

Quand Belay s’arrête volontairement, l’icône de la barre des menus l’indique. Un Mac devenu silencieux n’est jamais une énigme.

NOTIFICATIONS, SI VOUS LES VOULEZ

Belay peut vous prévenir quand un agent a besoin de vous, quand une longue tâche se termine ou quand il cesse de garder votre Mac éveillé par sécurité.

Chaque notification peut être désactivée séparément.

TOUT RESTE SUR VOTRE MAC

Belay détecte l’activité en local. Vos invites et votre code ne sont envoyés nulle part. Aucun compte, aucune analyse, aucune télémétrie.

Cette version n’a aucun accès au réseau : elle ne peut rien envoyer et n’écoute rien.

Vos statistiques restent également sur votre Mac jusqu’à ce que vous décidiez de les partager.

DES STATISTIQUES QUI ONT DU SENS

Voyez combien de temps Belay a gardé votre Mac éveillé pendant votre absence, combien d’exécutions il a suivies, combien il en a sauvées et quelle a été la plus longue.

Le temps passé au clavier ne compte pas : à ce moment-là, votre Mac n’allait de toute façon pas s’endormir.

LANGUES

English, Français, Deutsch, Español, Italiano, Русский et 简体中文.
```

---

## Italiano

**Promotional text** (170)
```
Lascia lavorare i tuoi agenti. Belay tiene sveglio il Mac mentre lavorano e si fa da parte quando hanno finito. Nessun account. Nessuna telemetria.
```

**Keywords** (100)
```
sospensione,stop,terminale,cli,sessione,background,automazione,attività,energia,inattivo,llm
```

**Description** (4000)
```
Il Mac va in stop. L’agente che avevi lasciato al lavoro smette di fare progressi.

Belay tiene sveglio il Mac mentre i tuoi coding agent lavorano. Quando hanno finito, si fa da parte e il Mac può tornare a dormire normalmente.

Niente timer. Niente interruttori da ricordarsi di spegnere. Lascia lavorare l’agente e basta.

Mentre Belay tiene sveglio il Mac, chiede a macOS di mantenere attiva anche la rete: le sessioni SSH e le risposte in streaming non si interrompono.

AGENTI SUPPORTATI

Claude Code, Codex e Cline vengono rilevati con precisione, senza alcuna configurazione: Belay legge i loro file di sessione e sa esattamente quando un turno inizia e finisce. Copilot CLI, Gemini CLI, OpenCode, Aider e Pi hanno preset già pronti.

Per qualsiasi altro strumento puoi scegliere una cartella. Belay userà l’attività di quella cartella per capire se c’è del lavoro in corso. Le cartelle scelte vengono ricordate, quindi le indichi una volta sola.

TRE MODALITÀ

• Auto: tiene sveglio il Mac mentre un agente lavora.
• Sempre attivo: lo tiene sveglio finché non disattivi la modalità.
• Disattivato: Belay non interviene.

SA QUANDO MOLLARE LA PRESA

Belay può aspettare un po’ dopo la fine del lavoro, limitare il tempo massimo di attività e fermarsi quando la batteria è quasi scarica.

Le impostazioni di stop di macOS non vengono modificate.

Quando Belay si ferma di proposito, l’icona nella barra dei menu lo mostra. Un Mac che tace non è mai un mistero.

NOTIFICHE, SE LE VUOI

Belay può avvisarti quando un agente ha bisogno di te, quando termina un’attività lunga o quando smette di tenere sveglio il Mac per sicurezza.

Ogni notifica può essere disattivata separatamente.

RESTA TUTTO SUL TUO MAC

Belay rileva l’attività in locale. I tuoi prompt e il tuo codice non vengono caricati da nessuna parte. Nessun account, nessuna analisi e nessuna telemetria.

Questa versione non ha alcun accesso alla rete: non può inviare nulla e non è in ascolto su nulla.

Anche le statistiche restano sul tuo Mac finché non decidi di condividerle.

STATISTICHE CHE CONTANO DAVVERO

Scopri per quanto tempo Belay ha tenuto sveglio il Mac mentre eri lontano, quante esecuzioni ha rilevato, quante ne ha salvate e quale è durata di più.

Il tempo passato alla tastiera non conta. In quel momento il Mac non sarebbe comunque andato in stop.

LINGUE

English, Italiano, Deutsch, Español, Français, Русский e 简体中文.
```

---

## 简体中文

New in 1.3, and **already created in App Store Connect** on 2026-08-16 through
the API, along with the name, the subtitle and the Chinese privacy policy URL.
Creating the version localisation makes App Store Connect create the matching
App Information localisation on its own, seeded from the primary language, which
is why that half was a `PATCH` rather than a `POST`.

**Screenshots are the one thing left.** A new localisation starts with none, and
Apple will not accept a submission without them. Ours carry no English text, so
the same six files go up again. Support points at the English contacts page,
because `/zh/contacts/` returns 404 and Apple loads these at review.

Every term here comes from [`../Localization/zh-Hans-glossary.md`](../Localization/zh-Hans-glossary.md),
which is the file that kept three separate translation passes saying the same
thing. The three that matter: agent is 智能体 and never 代理, keeping awake is
保持唤醒, and letting go is 让 Mac 进入睡眠 rather than anything with 释放.

**Promotional text** (170)
```
让你的智能体继续跑。它们工作时 Belay 让 Mac 保持唤醒，工作结束后就退到一边。无需账户，没有遥测。
```

**Keywords** (100)
```
ai,claude,codex,gemini,cline,唤醒,睡眠,防止睡眠,菜单栏,智能体,终端,编程,开发者
```

**Description** (4000)
```
Mac 进入了睡眠。你留着继续跑的编程智能体也就停在了那里。

智能体工作时，Belay 让你的 Mac 保持唤醒；它们完成后，Belay 退到一边，Mac 照常进入睡眠。

不用定时器，也不用记着去关掉某个开关。让智能体跑就行了。

在 Belay 保持唤醒期间，它也会请求 macOS 保持网络活跃：SSH 会话和流式回复不会中断。

支持的智能体

Claude Code、Codex 和 Cline 开箱即可精确检测：Belay 读取它们自己的会话文件，准确知道轮次何时开始、何时结束。Copilot CLI、Gemini CLI、OpenCode、Aider 和 Pi 都有现成的预设。

其他工具可以指定一个文件夹，Belay 会用该文件夹的活动来判断是否有工作在进行。你选择的文件夹会被记住，只需指定一次。

三种模式

• 自动：智能体工作时让 Mac 保持唤醒。
• 常开：一直保持唤醒，直到你关闭为止。
• 关闭：Belay 不做任何干预。

知道什么时候该放手

智能体安静下来之后，Belay 可以再等一会儿；也可以设置最长唤醒时间，或在电量偏低时停止。macOS 的睡眠设置不会被修改。

当 Belay 有意停止时，菜单栏图标会显示出来。安静下来的 Mac 不再是谜。

通知，如果你想要的话

智能体需要你、长任务结束、或者 Belay 出于安全考虑停止保持唤醒时，都可以收到通知。每一项都能单独关闭。

一切都留在你的 Mac 上

Belay 在本地判断活动。你的提示词和代码不会被上传到任何地方。没有账户，没有分析，没有遥测。

此版本完全没有网络访问权限：既不能对外连接，也不监听任何东西。

统计数据同样留在你的 Mac 上，除非你自己选择分享。

有意义的统计

看看你不在的时候 Belay 实际让 Mac 保持唤醒了多久，监视了多少次运行、保住了多少次，以及最长的一次有多久。

在键盘前的时间不计入其中，因为那时 Mac 本来也不会进入睡眠。

语言

English、简体中文、Русский、Deutsch、Español、Français、Italiano。
```


---

## Two things the description deliberately does not say

**It does not name a competitor.** Amphetamine, Caffeine and KeepingYouAwake
are the apps people compare this to, and naming them in metadata is both a
2.3.10 risk and free advertising for them.

**It does not promise the App Store build checks for updates.** That build
cannot: the channel ships its own updater and rejects a second one, so the
direct build's daily check is absent rather than disabled there. The
description says nothing about updates for that reason, and the privacy label
for the App Store build is therefore "no data collected" with no exceptions to
explain.

**It no longer promises Precise Detection.** It did until 2026-08-16, and that
was inaccurate metadata: the hook listener needs an entitlement that build no
longer has, and the feature could not have worked in a sandbox in any case
because the installer writes into `~/.claude/settings.json` and the sandbox home
is the container. Anything the App Store build cannot do belongs in neither the
description nor the promotional text; the direct build's README is where those
features are described.
