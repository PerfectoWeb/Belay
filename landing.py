"""The landing page, in the six languages the app speaks.

VERSION is written here by the release workflow rather than fetched by the
page. A visitor should not have to wait on api.github.com, and a version
number that only appears when a request succeeds is worse than one that is
simply true at build time.
"""

VERSION = "1.0.0"

L = {}

L["en"] = {
    "title": "Belay: stays awake while your agents work",
    "meta": "A small macOS menu bar app that keeps your Mac awake while coding agents work, then lets it sleep when they're done.",
    "h1": "Stays awake while your agents work.",
    "lede": "Belay keeps your Mac awake while a coding agent is working. When the work stops, Belay gets out of the way and your Mac can sleep normally again.",
    "body": "Built-in detection for Claude Code, plus presets for Codex CLI, Gemini CLI and Cline. You can also point Belay at a folder for anything else. Detection stays on your Mac. No account. No telemetry. Belay never sends your prompts or code anywhere.",
    "download": "Download for macOS",
    "source": "Source on GitHub",
    "requires": "Requires macOS 14 or later. Apple silicon and Intel.",
    "version": "Version {version}, free and open source.",
    "notes": "Release notes",
    "privacy": "Privacy policy",
    "bug": "Report a bug",
    "language": "Language",
}

L["ru"] = {
    "title": "Belay: не даёт Mac уснуть, пока агенты работают",
    "meta": "Небольшое приложение в строке меню macOS: не даёт Mac уснуть, пока работают агенты, и отпускает, когда они закончили.",
    "h1": "Не спит, пока работают ваши агенты.",
    "lede": "Belay не даёт Mac уснуть, пока агент работает. Работа закончилась, Belay уходит с дороги, и Mac засыпает как обычно.",
    "body": "Встроенное определение для Claude Code, плюс пресеты для Codex CLI, Gemini CLI и Cline. Для всего остального можно указать папку. Определение остаётся на вашем Mac. Ни аккаунта, ни телеметрии. Ваши промпты и код Belay никуда не отправляет.",
    "download": "Скачать для macOS",
    "source": "Исходный код на GitHub",
    "requires": "Нужна macOS 14 или новее. Apple silicon и Intel.",
    "version": "Версия {version}, бесплатно и с открытым кодом.",
    "notes": "Описание выпуска",
    "privacy": "Политика приватности",
    "bug": "Сообщить об ошибке",
    "language": "Язык",
}

L["de"] = {
    "title": "Belay: bleibt wach, solange deine Agenten arbeiten",
    "meta": "Eine kleine macOS-Menüleisten-App, die deinen Mac wach hält, solange Coding-Agenten arbeiten, und ihn danach schlafen lässt.",
    "h1": "Bleibt wach, solange deine Agenten arbeiten.",
    "lede": "Belay hält deinen Mac wach, solange ein Coding-Agent arbeitet. Hört die Arbeit auf, geht Belay aus dem Weg und dein Mac kann wieder normal schlafen.",
    "body": "Eingebaute Erkennung für Claude Code, dazu Vorlagen für Codex CLI, Gemini CLI und Cline. Für alles andere kannst du Belay auf einen Ordner richten. Die Erkennung bleibt auf deinem Mac. Kein Konto. Keine Telemetrie. Belay schickt deine Prompts und deinen Code nirgendwohin.",
    "download": "Für macOS laden",
    "source": "Quellcode auf GitHub",
    "requires": "Benötigt macOS 14 oder neuer. Apple Silicon und Intel.",
    "version": "Version {version}, kostenlos und quelloffen.",
    "notes": "Versionshinweise",
    "privacy": "Datenschutz",
    "bug": "Fehler melden",
    "language": "Sprache",
}

L["es"] = {
    "title": "Belay: se mantiene despierto mientras trabajan tus agentes",
    "meta": "Una pequeña app de la barra de menús de macOS que mantiene el Mac despierto mientras trabajan los agentes y lo deja dormir cuando terminan.",
    "h1": "Despierto mientras trabajan tus agentes.",
    "lede": "Belay mantiene tu Mac despierto mientras un agente está trabajando. Cuando el trabajo termina, Belay se aparta y tu Mac vuelve a dormir con normalidad.",
    "body": "Detección integrada para Claude Code, más ajustes preparados para Codex CLI, Gemini CLI y Cline. Para lo demás, puedes indicarle una carpeta. La detección se queda en tu Mac. Sin cuenta. Sin telemetría. Belay no envía tus prompts ni tu código a ninguna parte.",
    "download": "Descargar para macOS",
    "source": "Código en GitHub",
    "requires": "Requiere macOS 14 o posterior. Apple silicon e Intel.",
    "version": "Versión {version}, gratis y de código abierto.",
    "notes": "Notas de la versión",
    "privacy": "Privacidad",
    "bug": "Informar de un error",
    "language": "Idioma",
}

L["fr"] = {
    "title": "Belay : reste éveillé pendant que vos agents travaillent",
    "meta": "Une petite app de la barre des menus macOS qui garde votre Mac éveillé pendant que les agents travaillent, puis le laisse dormir une fois terminé.",
    "h1": "Éveillé pendant que vos agents travaillent.",
    "lede": "Belay garde votre Mac éveillé pendant qu'un agent travaille. Quand le travail s'arrête, Belay s'efface et votre Mac peut de nouveau dormir normalement.",
    "body": "Détection intégrée pour Claude Code, plus des préréglages pour Codex CLI, Gemini CLI et Cline. Pour le reste, vous pouvez désigner un dossier. La détection reste sur votre Mac. Pas de compte. Pas de télémétrie. Belay n'envoie vos prompts et votre code nulle part.",
    "download": "Télécharger pour macOS",
    "source": "Code source sur GitHub",
    "requires": "Nécessite macOS 14 ou plus récent. Apple silicon et Intel.",
    "version": "Version {version}, gratuit et open source.",
    "notes": "Notes de version",
    "privacy": "Confidentialité",
    "bug": "Signaler un bug",
    "language": "Langue",
}

L["it"] = {
    "title": "Belay: resta sveglio mentre i tuoi agenti lavorano",
    "meta": "Una piccola app nella barra dei menu di macOS che tiene sveglio il Mac mentre gli agenti lavorano e lo lascia dormire quando hanno finito.",
    "h1": "Sveglio mentre i tuoi agenti lavorano.",
    "lede": "Belay tiene sveglio il Mac mentre un agente sta lavorando. Quando il lavoro finisce, Belay si toglie di mezzo e il Mac può tornare a dormire normalmente.",
    "body": "Rilevamento integrato per Claude Code, più preset per Codex CLI, Gemini CLI e Cline. Per tutto il resto puoi indicargli una cartella. Il rilevamento resta sul tuo Mac. Nessun account. Nessuna telemetria. Belay non manda da nessuna parte i tuoi prompt o il tuo codice.",
    "download": "Scarica per macOS",
    "source": "Codice su GitHub",
    "requires": "Richiede macOS 14 o successivo. Apple silicon e Intel.",
    "version": "Versione {version}, gratis e open source.",
    "notes": "Note di versione",
    "privacy": "Privacy",
    "bug": "Segnala un bug",
    "language": "Lingua",
}
