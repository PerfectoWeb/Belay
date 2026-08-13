# App Store listing copy

Every text field App Store Connect asks for, in the six languages Belay ships,
ready to paste. Nothing here is written from imagination: every claim maps to
something the app does, because a claim the binary does not support is
inaccurate metadata under guideline 2.3 and is refused at review.

Character limits are Apple's and are counted below each field. Cyrillic counts
the same as Latin, so the Russian lines were written to the same budget rather
than translated and hoped over.

Two rules the copy follows throughout. No superlatives, because a utility that
shouts is a utility nobody believes. And no price words anywhere: 2.3.7 forbids
them in metadata other than the price field, which is also why "Free" appears on
no screenshot.

---

## Fields that are the same in every language

**Bundle ID** `com.perfectoweb.belay`
**SKU** `belay-mac-1`
**Apple ID** `6801207644`, issued when the record was created
**Primary category** Developer Tools
**Secondary category** Utilities
**Age rating** 4+
**Price** Free
**Copyright** `2026 PerfectoWeb`
**Support URL** `https://perfecto-web.com/en/contacts/`
**Marketing URL** `https://perfectoweb.github.io/Belay/`

Both were `perfecto-web.com/belay` addresses and both returned 404 on the day
of the first release. Apple requires these to load without a login and checks
them at review, so they point at pages that exist. Move them back to the
product's own domain whenever those pages are built.
**Privacy policy URL**, one per App Store Connect localisation:

| Localisation | URL |
|---|---|
| English (U.S.) | `https://perfectoweb.github.io/Belay/privacy/` |
| Russian | `https://perfectoweb.github.io/Belay/privacy/ru/` |
| German | `https://perfectoweb.github.io/Belay/privacy/de/` |
| Spanish (Spain) | `https://perfectoweb.github.io/Belay/privacy/es/` |
| French | `https://perfectoweb.github.io/Belay/privacy/fr/` |
| Italian | `https://perfectoweb.github.io/Belay/privacy/it/` |

Apple would have accepted the English address in all six boxes. It is a real
policy in each language instead, because this is the one document where a
reader needs to understand exactly what is read off their disk, and the app
already speaks all six. Each translation says it is a translation and links to
the English, which governs.

The capital B is not optional. GitHub Pages paths are case-sensitive even
though github.com URLs are not, and the lowercase spelling of this address
returns 404. It was written lowercase here until the page went up and the
two were compared.

---

## English

**Name** (30)
`Belay - Keep Mac Awake` — 22

**Chosen on 2026-08-13.** The two lines finish each other's sentence, which is
worth more than the keyword arithmetic that favoured the alternative below.
"AI" is bought back out of the keyword budget, where it costs three characters
and ranks the same: Apple pools the name, the subtitle and the keywords.

Plain `Belay` is taken on the Mac App Store, by an SSH client and by an
assistant, so the name carries a description the way theirs do. "Mac" is left
out on purpose: every app in this store is a Mac app, and the word buys nothing
in a search that is already restricted to Macs. What it buys instead is room
for "AI", which is what people are typing this year.

**Subtitle** (30)
`While your coding agents work` — 29

Changed when "AI Agents" moved into the name. Apple searches the name, the
subtitle and the keywords as one pool, so a word in two of them is a word
wasted: the old subtitle repeated "awake" and "agents", and this one spends
those characters on "Mac" and "sleeps" instead.

### The candidate that was not chosen

```
Name      Belay - Awake for AI Agents     27
Subtitle  Your Mac sleeps when they do    28
```

It reads better than the one above, and the two lines finish each other's
sentence, which no amount of keyword arithmetic is worth ignoring.

What it costs: "AI" appears in neither field, so it has to be bought back out
of the keyword budget, where it is three characters and ranks the same as it
would anywhere else — Apple pools all three fields, so a term in the keywords
is not worth less than a term in the name. "Mac" costs four characters in a
store where every app is a Mac app.

So the real trade is: this pair spends 7 characters on `Mac` and on reading
well, and the other spends them on `Awake for AI Agents` reading like a label.
Both fit. Neither is a mistake. Left here undecided on purpose, because it is a
judgement about the shop window rather than about the software, and the person
whose shop it is should make it.

**Promotional text** (170)
`Belay watches your local coding agent and holds sleep off only while it is
actually working. When the run ends, your Mac sleeps the way it always did.` — 150

**Keywords** (100, comma separated, no spaces)
`ai,claude,codex,gemini,cline,caffeine,insomnia,sleep,menubar,coding,cli,terminal,developer` — 90

`ai` is here rather than in the name, which is the trade the chosen name makes.
`power` came out to pay for it: it is the vaguest term on the list.

`agent` and `awake` came out for the same reason: both are in the name now,
and repeating a term in the keyword field does not rank it twice. The freed
characters went to `cli` and `terminal`.

**Description** (4000)

```
Your Mac goes to sleep. The agent you left running does not survive it.

Belay sits in the menu bar and watches for a local AI coding agent doing
actual work. While one is working it holds sleep off. The moment everything
goes quiet it lets go, and your Mac sleeps exactly as it did before.

It is not a caffeine switch you have to remember. There is nothing to turn on
before a long run and nothing to turn off afterwards.

WHAT IT WATCHES

Claude Code needs no configuration at all. Codex, Gemini CLI and Cline each
have a one-tap preset. Anything else that writes files while it works can be
covered by pointing Belay at a folder.

Belay can also be told exactly when a turn starts and ends, rather than
inferring it from files, by installing a small hook into Claude Code's own
settings. That is one button, it is reversible, and it is what makes "an agent
is waiting for you" reliable.

THREE MODES

Auto holds only while an agent is working. Always on holds until you say
otherwise. Off does nothing at all.

IT LETS GO

A hold is never open ended. Belay releases after the work stops, after a
ceiling you set, when the battery falls below a level you set, and when it
quits for any reason including being killed. Your energy settings are never
changed: a power assertion sits alongside them rather than editing them.

WHAT IT READS

Only enough of your agent's session files to tell whether it is running: file
sizes, timestamps and whether a turn ended. Never your prompts. Never your
code. Nothing about you or your work leaves this Mac, and there is no account
and no telemetry.

NOTIFICATIONS, IF YOU WANT THEM

When an agent is blocked on a question. When a long run has finished. When
Belay let go to protect the battery. All three can be switched off.

WHAT IT COUNTS

How long your Mac was held awake while you were away from it, and how many
runs would otherwise have ended in a dead session. Time held while you were at
the keyboard is not counted, because the Mac was not going to sleep anyway.

Six languages: English, Russian, German, Spanish, French, Italian.
```

**What's New** (4000), first release
```
First release.
```

---

## Русский

**Subtitle** (30)
`Mac не спит, пока агент занят` — 29

**Promotional text** (170)
`Belay следит за локальным агентом и не даёт Mac уснуть, только пока тот
действительно работает. Работа закончилась, и Mac засыпает как обычно.` — 142

**Keywords** (100)
`claude,codex,gemini,cline,агент,сон,бодрствование,кофеин,меню,разработка,питание` — 80

**Description**

```
Mac уходит в сон. Агент, которого вы оставили работать, этого не переживает.

Belay живёт в строке меню и следит, работает ли прямо сейчас локальный
ИИ-агент. Пока работает, сон отложен. Как только всё затихло, Belay отпускает,
и Mac засыпает ровно так же, как раньше.

Это не переключатель, который надо не забыть нажать. Перед долгим запуском
включать нечего, и после него выключать нечего.

ЗА ЧЕМ ОН СЛЕДИТ

Claude Code не требует никакой настройки. Для Codex, Gemini CLI и Cline есть
готовые пресеты в одно нажатие. Всё остальное, что пишет файлы во время
работы, покрывается указанием папки.

Belay также может узнавать о начале и конце хода точно, а не по косвенным
признакам, если установить небольшой хук в собственные настройки Claude Code.
Это одна кнопка, она обратима, и именно она делает надёжным уведомление
«агент ждёт вас».

ТРИ РЕЖИМА

Авто удерживает, только пока агент работает. Всегда удерживает, пока вы не
скажете иначе. Выключен не делает ничего.

ОН ОТПУСКАЕТ

Удержание никогда не бесконечно. Belay отпускает после того, как работа
закончилась, по достижении заданного вами предела, при падении заряда ниже
выбранного уровня и при завершении работы приложения, в том числе аварийном.
Ваши настройки энергосбережения не меняются: ассертион существует рядом с
ними, а не правит их.

ЧТО ОН ЧИТАЕТ

Только то, что нужно, чтобы понять, идёт ли работа: размеры файлов, отметки
времени и признак завершения хода. Никогда ваши промпты. Никогда ваш код.
Ничего о вас и о вашей работе не покидает этот Mac, аккаунта нет, телеметрии
нет.

УВЕДОМЛЕНИЯ, ЕСЛИ НУЖНЫ

Когда агент ждёт вашего ответа. Когда длинная работа закончилась. Когда Belay
отпустил, чтобы сберечь батарею. Все три отключаются.

ЧТО ОН СЧИТАЕТ

Сколько времени Mac не спал, пока вас не было рядом, и сколько запусков иначе
оборвались бы. Время, когда вы были за клавиатурой, не учитывается: Mac и так
не собирался засыпать.

Шесть языков: английский, русский, немецкий, испанский, французский,
итальянский.
```

---

## Deutsch

**Subtitle** (30)
`Wach, solange der Agent läuft` — 29

**Promotional text** (170)
`Belay beobachtet deinen lokalen Agenten und hält den Ruhezustand nur so lange
auf, wie wirklich gearbeitet wird. Danach schläft dein Mac wie immer.` — 147

**Keywords** (100)
`claude,codex,gemini,cline,agent,wach,schlaf,koffein,menuleiste,entwickler,energie` — 81

**Description**

```
Dein Mac geht in den Ruhezustand. Der Agent, den du laufen lassen hast,
übersteht das nicht.

Belay sitzt in der Menüleiste und beobachtet, ob gerade ein lokaler
KI-Coding-Agent arbeitet. Solange einer arbeitet, bleibt der Mac wach. Sobald
alles ruhig ist, lässt Belay los, und dein Mac schläft genau wie vorher.

Es ist kein Schalter, an den du denken musst. Vor einem langen Lauf ist nichts
einzuschalten und danach nichts auszuschalten.

WAS ES BEOBACHTET

Claude Code braucht keinerlei Konfiguration. Für Codex, Gemini CLI und Cline
gibt es je eine Vorlage mit einem Tipp. Alles andere, das beim Arbeiten Dateien
schreibt, deckst du ab, indem du Belay einen Ordner nennst.

Belay kann auch exakt erfahren, wann ein Zug beginnt und endet, statt es aus
Dateien zu schließen: dafür wird ein kleiner Hook in die Einstellungen von
Claude Code eingetragen. Ein Knopf, umkehrbar, und genau das macht "ein Agent
wartet auf dich" verlässlich.

DREI MODI

Automatisch hält nur, solange ein Agent arbeitet. Immer hält, bis du etwas
anderes sagst. Aus tut gar nichts.

ES LÄSST LOS

Kein Halten ist unbegrenzt. Belay lässt los, wenn die Arbeit endet, bei einer
von dir gesetzten Obergrenze, wenn der Akku unter einen von dir gesetzten Stand
fällt, und wenn die App beendet wird, auch unsanft. Deine Energieeinstellungen
werden nie verändert: eine Assertion steht neben ihnen, statt sie zu ändern.

WAS ES LIEST

Nur so viel aus den Sitzungsdateien deines Agenten, wie nötig ist, um zu
erkennen, ob er läuft: Dateigrößen, Zeitstempel und ob ein Zug beendet wurde.
Nie deine Prompts. Nie deinen Code. Nichts über dich verlässt diesen Mac, es
gibt kein Konto und keine Telemetrie.

MITTEILUNGEN, WENN DU WILLST

Wenn ein Agent auf eine Antwort wartet. Wenn ein langer Lauf fertig ist. Wenn
Belay losgelassen hat, um den Akku zu schonen. Alle drei abschaltbar.

WAS ES ZÄHLT

Wie lange dein Mac wach gehalten wurde, während du weg warst, und wie viele
Läufe sonst gestorben wären. Zeit am Schreibtisch zählt nicht mit: da wäre der
Mac ohnehin nicht eingeschlafen.

Sechs Sprachen: Englisch, Russisch, Deutsch, Spanisch, Französisch,
Italienisch.
```

---

## Español

**Subtitle** (30)
`Despierto mientras el agente` — 28

**Promotional text** (170)
`Belay vigila tu agente local y evita la suspensión solo mientras trabaja de
verdad. Cuando la ejecución termina, tu Mac duerme como siempre lo hizo.` — 148

**Keywords** (100)
`claude,codex,gemini,cline,agente,despierto,suspension,cafeina,menu,desarrollo,energia` — 85

**Description**

```
Tu Mac se suspende. El agente que dejaste trabajando no sobrevive a eso.

Belay vive en la barra de menús y vigila si hay un agente de programación local
trabajando ahora mismo. Mientras lo haya, la suspensión espera. En cuanto todo
queda en silencio, Belay suelta y tu Mac duerme igual que antes.

No es un interruptor que haya que recordar. Antes de una ejecución larga no hay
nada que activar, y después no hay nada que desactivar.

QUÉ VIGILA

Claude Code no necesita configuración alguna. Codex, Gemini CLI y Cline tienen
un ajuste preparado, a un toque. Cualquier otra cosa que escriba archivos
mientras trabaja se cubre indicándole una carpeta.

Belay también puede saber con exactitud cuándo empieza y termina un turno, en
lugar de deducirlo de los archivos, instalando un pequeño enlace en los propios
ajustes de Claude Code. Es un botón, es reversible, y es lo que hace fiable el
aviso de que un agente te está esperando.

TRES MODOS

Automático mantiene solo mientras un agente trabaja. Siempre mantiene hasta que
digas otra cosa. Desactivado no hace nada.

SUELTA

Ninguna retención es indefinida. Belay suelta cuando el trabajo termina, al
llegar al límite que fijes, cuando la batería baja del nivel que fijes, y
cuando la app termina, incluso de forma abrupta. Tus ajustes de energía nunca
se modifican: una aserción convive con ellos en vez de editarlos.

QUÉ LEE

Solo lo justo de los archivos de sesión de tu agente para saber si está en
marcha: tamaños, marcas de tiempo y si un turno terminó. Nunca tus prompts.
Nunca tu código. Nada sobre ti sale de este Mac, no hay cuenta ni telemetría.

NOTIFICACIONES, SI LAS QUIERES

Cuando un agente espera una respuesta. Cuando termina una ejecución larga.
Cuando Belay soltó para cuidar la batería. Las tres se pueden desactivar.

QUÉ CUENTA

Cuánto tiempo estuvo tu Mac despierto mientras no estabas, y cuántas
ejecuciones habrían muerto. El tiempo con las manos en el teclado no cuenta:
el Mac no iba a dormirse de todos modos.

Seis idiomas: inglés, ruso, alemán, español, francés e italiano.
```

---

## Français

**Subtitle** (30)
`Éveillé pendant que l'agent` — 27

**Promotional text** (170)
`Belay surveille votre agent local et retient la veille seulement pendant qu'il
travaille vraiment. Une fois l'exécution finie, votre Mac dort comme avant.` — 154

**Keywords** (100)
`claude,codex,gemini,cline,agent,eveil,veille,cafeine,menu,developpeur,energie` — 77

**Description**

```
Votre Mac se met en veille. L'agent que vous avez laissé tourner n'y survit
pas.

Belay se tient dans la barre des menus et surveille si un agent de code local
travaille en ce moment. Tant qu'il y en a un, la veille attend. Dès que tout se
tait, Belay lâche, et votre Mac dort exactement comme avant.

Ce n'est pas un interrupteur qu'il faut penser à activer. Avant une longue
exécution il n'y a rien à allumer, et après il n'y a rien à éteindre.

CE QU'IL SURVEILLE

Claude Code ne demande aucune configuration. Codex, Gemini CLI et Cline ont
chacun un réglage prêt, en une touche. Tout le reste qui écrit des fichiers en
travaillant se couvre en désignant un dossier.

Belay peut aussi savoir précisément quand un tour commence et finit, au lieu de
le déduire des fichiers, en installant un petit hook dans les réglages de
Claude Code. C'est un bouton, c'est réversible, et c'est ce qui rend fiable
l'avertissement qu'un agent vous attend.

TROIS MODES

Auto retient seulement pendant qu'un agent travaille. Toujours retient jusqu'à
ce que vous disiez autre chose. Désactivé ne fait rien.

IL LÂCHE

Aucune retenue n'est illimitée. Belay lâche quand le travail s'arrête, à la
limite que vous fixez, quand la batterie passe sous le niveau que vous fixez,
et quand l'app se termine, même brutalement. Vos réglages d'énergie ne sont
jamais modifiés : une assertion coexiste avec eux au lieu de les changer.

CE QU'IL LIT

Seulement ce qu'il faut des fichiers de session de votre agent pour savoir s'il
tourne : tailles, horodatages et fin de tour. Jamais vos prompts. Jamais votre
code. Rien vous concernant ne quitte ce Mac, il n'y a ni compte ni télémétrie.

NOTIFICATIONS, SI VOUS EN VOULEZ

Quand un agent attend une réponse. Quand une longue exécution est finie. Quand
Belay a lâché pour ménager la batterie. Les trois se désactivent.

CE QU'IL COMPTE

Combien de temps votre Mac est resté éveillé pendant votre absence, et combien
d'exécutions seraient mortes autrement. Le temps passé au clavier ne compte
pas : le Mac n'allait de toute façon pas s'endormir.

Six langues : anglais, russe, allemand, espagnol, français, italien.
```

---

## Italiano

**Subtitle** (30)
`Sveglio mentre l'agente lavora` — 30

**Promotional text** (170)
`Belay osserva il tuo agente locale e trattiene lo stop solo mentre sta davvero
lavorando. Finita l'esecuzione, il Mac va in stop come ha sempre fatto.` — 150

**Keywords** (100)
`claude,codex,gemini,cline,agente,sveglio,stop,caffeina,menu,sviluppo,energia` — 76

**Description**

```
Il Mac va in stop. L'agente che hai lasciato al lavoro non ci sopravvive.

Belay sta nella barra dei menu e osserva se un agente di programmazione locale
sta lavorando adesso. Finché c'è, lo stop aspetta. Appena tutto tace, Belay
lascia andare e il Mac va in stop esattamente come prima.

Non è un interruttore da ricordare. Prima di una lunga esecuzione non c'è nulla
da accendere, e dopo non c'è nulla da spegnere.

COSA OSSERVA

Claude Code non richiede alcuna configurazione. Codex, Gemini CLI e Cline hanno
un'impostazione pronta, con un tocco. Tutto il resto che scrive file mentre
lavora si copre indicando una cartella.

Belay può anche sapere con esattezza quando un turno inizia e finisce, invece
di dedurlo dai file, installando un piccolo hook nelle impostazioni di Claude
Code. È un pulsante, è reversibile, ed è ciò che rende affidabile l'avviso che
un agente ti sta aspettando.

TRE MODI

Auto trattiene solo mentre un agente lavora. Sempre trattiene finché non dici
altro. Spento non fa nulla.

LASCIA ANDARE

Nessuna trattenuta è illimitata. Belay lascia andare quando il lavoro finisce,
al limite che imposti, quando la batteria scende sotto il livello che imposti,
e quando l'app termina, anche bruscamente. Le tue impostazioni di energia non
vengono mai cambiate: un'asserzione convive con esse invece di modificarle.

COSA LEGGE

Solo quanto basta dei file di sessione del tuo agente per capire se è in
esecuzione: dimensioni, orari e fine turno. Mai i tuoi prompt. Mai il tuo
codice. Nulla che ti riguardi lascia questo Mac, non c'è account e non c'è
telemetria.

NOTIFICHE, SE LE VUOI

Quando un agente aspetta una risposta. Quando una lunga esecuzione è finita.
Quando Belay ha lasciato andare per risparmiare la batteria. Tutte e tre si
possono spegnere.

COSA CONTA

Per quanto tempo il Mac è rimasto sveglio mentre non c'eri, e quante esecuzioni
sarebbero morte altrimenti. Il tempo passato alla tastiera non conta: il Mac
non sarebbe andato in stop comunque.

Sei lingue: inglese, russo, tedesco, spagnolo, francese, italiano.
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
