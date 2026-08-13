#!/usr/bin/env python3
"""Generates the privacy policy in six languages from one structure.

The pages share their skeleton, their stylesheet and their section order, so a
change to the policy is a change in one place per language rather than six
files drifting apart. The English page is the authoritative one and every
translation says so at the top.
"""

import io
import os
import sys

LANGUAGES = [
    ("en", "English", "en"),
    ("ru", "Русский", "ru"),
    ("de", "Deutsch", "de"),
    ("es", "Español", "es"),
    ("fr", "Français", "fr"),
    ("it", "Italiano", "it"),
]

# Section keys in the order they appear on the page.
ORDER = [
    "lede", "reads_head", "reads_1", "reads_2", "reads_3", "reads_4",
    "leaves_head", "leaves_mas", "leaves_direct",
    "stores_head", "stores_1", "stores_2",
    "changes_head", "changes_1", "changes_2",
    "sharing_head", "sharing_1", "sharing_2",
    "policy_head", "policy_1",
    "contact_head", "contact_1",
]

T = {}

T["en"] = {
    "title": "Privacy policy: Belay",
    "meta": "Belay has no accounts, analytics, advertising or crash reporting. What it reads, what it stores, and the one request it can make.",
    "h1": "Privacy policy",
    "stamp": "Belay for macOS. Last updated 13 August 2026.",
    "lede": "Belay doesn't have accounts, analytics, advertising or crash reporting. It doesn't build a profile of you or send your work to us. Most of what Belay needs never leaves your Mac.",
    "reads_head": "What Belay reads",
    "reads_1": "Belay needs to know one thing: is an agent working right now?",
    "reads_2": "For Claude Code, Belay watches the session files Claude Code already writes on your Mac. It looks at how large a file is, whether it grew, when it was last written, and, in the part that grew, two fields of each record: what kind of record it is, and whether the turn ended. Your prompts, your replies and your code are not read out of those files and no copy of them is kept.",
    "reads_3": "For other agents, Belay can watch a folder you choose. macOS tells Belay which files changed and when, and that is all Belay uses: it does not open those files or read what is in them. The folder stays yours, and nothing in it is uploaded.",
    "reads_4": "Which folders Belay looks at is up to you. <code>~/.claude</code> for Claude Code, and for anything else only what you point it at.",
    "leaves_head": "What leaves your Mac",
    "leaves_mas": "<strong>Mac App Store.</strong> Belay makes no outbound network connections. That build ships without the entitlement macOS requires for them. Precise detection, if you turn it on, uses a connection that begins and ends on your own Mac and sends nothing over the internet.",
    "leaves_direct": "<strong>Direct download.</strong> The version downloaded from GitHub can check for updates once a day. It sends an ordinary HTTPS request to the GitHub releases API with no account, no query and no Belay identifier; GitHub sees the request's IP address and a user agent, as it would for any web request. You can turn automatic checks off in Settings, under General, and Belay never installs an update without you asking.",
    "stores_head": "What Belay stores",
    "stores_1": "Belay stores its settings and simple usage counters in your Mac user preferences. The counters hold durations, run counts and days. They don't hold project names, prompts or code.",
    "stores_2": "You can reset your statistics at any time in Settings, under Statistics.",
    "changes_head": "What Belay changes on your Mac",
    "changes_1": "To keep your Mac awake, Belay uses the power assertion API macOS provides for it. It doesn't rewrite your Energy Saver settings, and it can't: an assertion sits alongside those settings rather than editing them.",
    "changes_2": "If you turn on precise detection for Claude Code, Belay shows you the exact configuration it would add before anything is written, and only writes after you confirm. It takes a timestamped backup first, adds only its own entry, and \"Remove\" on the same screen puts the file back.",
    "sharing_head": "Sharing",
    "sharing_1": "Belay doesn't send your usage statistics, your settings or your work to us. There are no analytics or advertising services in the app.",
    "sharing_2": "The Statistics pane can make an image of your own numbers. If you share one, macOS asks you where it goes, and nothing is shared until you do that yourself.",
    "policy_head": "Changes to this policy",
    "policy_1": "If this policy changes, we'll update the date above. Any meaningful privacy change will also be mentioned in the release notes.",
    "contact_head": "Contact",
    "contact_1": 'Questions about this policy: <a href="https://github.com/PerfectoWeb/Belay/issues">the issue tracker</a>, or the address on <a href="https://perfecto-web.com">perfecto-web.com</a>.',
    "fine": "Claude Code, Codex CLI, Gemini CLI and Cline are made by other people. Belay works alongside them and is not affiliated with or endorsed by any of them.",
    "authoritative": None,
    "source": "Source on GitHub",
}

T["ru"] = {
    "title": "Политика приватности: Belay",
    "meta": "У Belay нет аккаунтов, аналитики, рекламы и сбора отчётов о сбоях. Что приложение читает, что хранит и какой единственный запрос может сделать.",
    "h1": "Политика приватности",
    "stamp": "Belay для macOS. Обновлено 13 августа 2026 года.",
    "lede": "У Belay нет аккаунтов, аналитики, рекламы и сбора отчётов о сбоях. Он не составляет ваш профиль и не отправляет нам вашу работу. Почти всё, что нужно Belay, не покидает ваш Mac.",
    "reads_head": "Что Belay читает",
    "reads_1": "Belay нужно знать одно: работает ли агент прямо сейчас?",
    "reads_2": "Для Claude Code он смотрит на файлы сессий, которые Claude Code и так пишет на вашем Mac. Его интересует размер файла, вырос ли он, когда в него писали в последний раз, и в той части, что выросла, два поля каждой записи: её тип и завершился ли ход. Ваши промпты, ответы и код из этих файлов не извлекаются, и их копии нигде не остаются.",
    "reads_3": "Для других агентов Belay может следить за папкой, которую вы сами выберете. macOS сообщает ему, какие файлы изменились и когда, и этим Belay и ограничивается: он не открывает эти файлы и не читает их содержимое. Папка остаётся вашей, и ничего из неё никуда не загружается.",
    "reads_4": "За какими папками следить, решаете вы. <code>~/.claude</code> для Claude Code, а для остального только то, на что вы укажете сами.",
    "leaves_head": "Что уходит с вашего Mac",
    "leaves_mas": "<strong>Mac App Store.</strong> Belay не делает исходящих сетевых соединений. У этой сборки нет права, которое macOS для них требует. Точное определение, если вы его включите, использует соединение, которое начинается и заканчивается на вашем же Mac, и в интернет ничего не отправляет.",
    "leaves_direct": "<strong>Прямая загрузка.</strong> Версия, скачанная с GitHub, может раз в сутки проверять обновления. Это обычный HTTPS-запрос к API релизов GitHub, без аккаунта, без параметров запроса и без идентификатора Belay; GitHub видит IP-адрес запроса и строку user agent, как при любом обращении к сайту. Автоматическую проверку можно выключить в Настройках, в разделе «Общие», и Belay никогда не устанавливает обновление без вашего участия.",
    "stores_head": "Что Belay хранит",
    "stores_1": "Настройки и простые счётчики использования, в пользовательских настройках вашего Mac. Счётчики содержат длительности, число запусков и даты. В них нет ни названий проектов, ни промптов, ни кода.",
    "stores_2": "Сбросить статистику можно в любой момент в Настройках, в разделе «Статистика».",
    "changes_head": "Что Belay меняет на вашем Mac",
    "changes_1": "Чтобы не давать Mac уснуть, Belay использует предусмотренный для этого механизм macOS, power assertion. Ваши настройки энергосбережения он не переписывает и не может: ассертион существует рядом с ними, а не правит их.",
    "changes_2": "Если вы включаете точное определение для Claude Code, Belay сначала показывает точный текст, который добавит, и пишет только после вашего подтверждения. Перед записью делается резервная копия с отметкой времени, добавляется только собственная запись Belay, а кнопка «Удалить» на том же экране возвращает файл как было.",
    "sharing_head": "Передача данных",
    "sharing_1": "Belay не отправляет нам ни вашу статистику, ни настройки, ни вашу работу. Никаких аналитических и рекламных сервисов в приложении нет.",
    "sharing_2": "В разделе «Статистика» можно сделать картинку с вашими же числами. Если вы решите ею поделиться, macOS спросит куда, и до этого момента никуда ничего не уходит.",
    "policy_head": "Изменения этой политики",
    "policy_1": "Если политика изменится, мы обновим дату выше. Любое значимое изменение, касающееся приватности, будет упомянуто и в описании выпуска.",
    "contact_head": "Связь",
    "contact_1": 'Вопросы по этой политике: <a href="https://github.com/PerfectoWeb/Belay/issues">трекер задач</a> или адрес на <a href="https://perfecto-web.com">perfecto-web.com</a>.',
    "fine": "Claude Code, Codex CLI, Gemini CLI и Cline сделаны другими людьми. Belay работает рядом с ними и не связан с ними и не одобрен ими.",
    "authoritative": 'Это перевод. Основной текст политики <a href="../">на английском</a>.',
    "source": "Исходный код на GitHub",
}

T["de"] = {
    "title": "Datenschutzerklärung: Belay",
    "meta": "Belay hat keine Konten, keine Analytik, keine Werbung und keine Absturzberichte. Was es liest, was es speichert und die eine Anfrage, die es stellen kann.",
    "h1": "Datenschutzerklärung",
    "stamp": "Belay für macOS. Zuletzt aktualisiert am 13. August 2026.",
    "lede": "Belay hat keine Konten, keine Analytik, keine Werbung und keine Absturzberichte. Es legt kein Profil von dir an und schickt uns deine Arbeit nicht. Das meiste, was Belay braucht, verlässt deinen Mac nie.",
    "reads_head": "Was Belay liest",
    "reads_1": "Belay muss eines wissen: Arbeitet gerade ein Agent?",
    "reads_2": "Für Claude Code schaut Belay auf die Sitzungsdateien, die Claude Code ohnehin auf deinem Mac schreibt. Es sieht, wie groß eine Datei ist, ob sie gewachsen ist, wann zuletzt geschrieben wurde, und im gewachsenen Teil zwei Felder je Eintrag: um welche Art Eintrag es sich handelt und ob der Zug beendet wurde. Deine Prompts, deine Antworten und dein Code werden aus diesen Dateien nicht ausgelesen, und es wird keine Kopie davon aufbewahrt.",
    "reads_3": "Für andere Agenten kann Belay einen Ordner beobachten, den du auswählst. macOS teilt Belay mit, welche Dateien sich wann geändert haben, und mehr nutzt Belay nicht: Es öffnet diese Dateien nicht und liest ihren Inhalt nicht. Der Ordner bleibt deiner, und nichts daraus wird hochgeladen.",
    "reads_4": "Welche Ordner Belay ansieht, entscheidest du. <code>~/.claude</code> für Claude Code, und sonst nur das, worauf du es selbst richtest.",
    "leaves_head": "Was deinen Mac verlässt",
    "leaves_mas": "<strong>Mac App Store.</strong> Belay stellt keine ausgehenden Netzwerkverbindungen her. Dieser Build wird ohne die Berechtigung ausgeliefert, die macOS dafür verlangt. Die präzise Erkennung nutzt, wenn du sie einschaltest, eine Verbindung, die auf deinem eigenen Mac beginnt und endet, und sendet nichts ins Internet.",
    "leaves_direct": "<strong>Direkter Download.</strong> Die von GitHub geladene Version kann einmal täglich nach Updates sehen. Das ist eine gewöhnliche HTTPS-Anfrage an die GitHub-Releases-API, ohne Konto, ohne Abfrageparameter und ohne Belay-Kennung; GitHub sieht die IP-Adresse der Anfrage und einen User Agent, wie bei jedem Web-Aufruf. Die automatische Prüfung lässt sich in den Einstellungen unter „Allgemein“ abschalten, und Belay installiert nie ein Update, ohne dass du es verlangst.",
    "stores_head": "Was Belay speichert",
    "stores_1": "Seine Einstellungen und einfache Nutzungszähler, in den Benutzereinstellungen deines Macs. Die Zähler enthalten Dauern, Anzahl der Läufe und Tage. Sie enthalten keine Projektnamen, keine Prompts und keinen Code.",
    "stores_2": "Du kannst deine Statistik jederzeit in den Einstellungen unter „Statistik“ zurücksetzen.",
    "changes_head": "Was Belay auf deinem Mac verändert",
    "changes_1": "Um deinen Mac wach zu halten, nutzt Belay die dafür vorgesehene Power-Assertion-API von macOS. Deine Energiespar-Einstellungen schreibt es nicht um, und es kann es auch nicht: Eine Assertion steht neben ihnen, statt sie zu ändern.",
    "changes_2": "Wenn du die präzise Erkennung für Claude Code einschaltest, zeigt Belay zuerst genau die Konfiguration, die es hinzufügen würde, und schreibt erst nach deiner Bestätigung. Vorher wird eine Sicherung mit Zeitstempel angelegt, es wird nur der eigene Eintrag hinzugefügt, und „Entfernen“ im selben Fenster stellt die Datei wieder her.",
    "sharing_head": "Weitergabe",
    "sharing_1": "Belay schickt uns weder deine Nutzungsstatistik noch deine Einstellungen noch deine Arbeit. Es gibt keine Analyse- oder Werbedienste in der App.",
    "sharing_2": "Der Statistik-Bereich kann ein Bild deiner eigenen Zahlen erzeugen. Wenn du es teilst, fragt macOS dich wohin, und vorher wird nichts geteilt.",
    "policy_head": "Änderungen an dieser Erklärung",
    "policy_1": "Ändert sich diese Erklärung, aktualisieren wir das Datum oben. Jede bedeutsame Änderung beim Datenschutz wird auch in den Versionshinweisen genannt.",
    "contact_head": "Kontakt",
    "contact_1": 'Fragen zu dieser Erklärung: <a href="https://github.com/PerfectoWeb/Belay/issues">der Issue-Tracker</a> oder die Adresse auf <a href="https://perfecto-web.com">perfecto-web.com</a>.',
    "fine": "Claude Code, Codex CLI, Gemini CLI und Cline stammen von anderen. Belay arbeitet neben ihnen und steht mit keinem von ihnen in Verbindung und wird von keinem unterstützt.",
    "authoritative": 'Dies ist eine Übersetzung. Maßgeblich ist die <a href="../">englische Fassung</a>.',
    "source": "Quellcode auf GitHub",
}

T["es"] = {
    "title": "Política de privacidad: Belay",
    "meta": "Belay no tiene cuentas, analítica, publicidad ni informes de fallos. Qué lee, qué guarda y la única petición que puede hacer.",
    "h1": "Política de privacidad",
    "stamp": "Belay para macOS. Última actualización: 13 de agosto de 2026.",
    "lede": "Belay no tiene cuentas, analítica, publicidad ni informes de fallos. No crea un perfil tuyo ni nos envía tu trabajo. Casi todo lo que Belay necesita nunca sale de tu Mac.",
    "reads_head": "Qué lee Belay",
    "reads_1": "Belay necesita saber una cosa: ¿hay un agente trabajando ahora mismo?",
    "reads_2": "Para Claude Code, Belay mira los archivos de sesión que Claude Code ya escribe en tu Mac. Se fija en el tamaño del archivo, en si ha crecido, en cuándo se escribió por última vez y, en la parte que ha crecido, en dos campos de cada registro: de qué tipo es y si el turno ha terminado. Tus prompts, tus respuestas y tu código no se extraen de esos archivos y no se guarda ninguna copia.",
    "reads_3": "Para otros agentes, Belay puede vigilar una carpeta que elijas tú. macOS le dice qué archivos han cambiado y cuándo, y eso es todo lo que Belay usa: no abre esos archivos ni lee lo que contienen. La carpeta sigue siendo tuya y nada de ella se sube a ninguna parte.",
    "reads_4": "Qué carpetas mira Belay lo decides tú. <code>~/.claude</code> para Claude Code y, para lo demás, solo aquello que le indiques.",
    "leaves_head": "Qué sale de tu Mac",
    "leaves_mas": "<strong>Mac App Store.</strong> Belay no realiza conexiones de red salientes. Esa versión se publica sin el permiso que macOS exige para ellas. La detección precisa, si la activas, usa una conexión que empieza y termina en tu propio Mac y no envía nada por internet.",
    "leaves_direct": "<strong>Descarga directa.</strong> La versión descargada de GitHub puede comprobar si hay actualizaciones una vez al día. Es una petición HTTPS normal a la API de versiones de GitHub, sin cuenta, sin parámetros de consulta y sin identificador de Belay; GitHub ve la dirección IP de la petición y un user agent, como en cualquier visita web. La comprobación automática se puede desactivar en Ajustes, en «General», y Belay nunca instala una actualización sin que tú se lo pidas.",
    "stores_head": "Qué guarda Belay",
    "stores_1": "Sus ajustes y unos contadores de uso sencillos, en las preferencias de tu usuario. Los contadores guardan duraciones, número de ejecuciones y días. No guardan nombres de proyectos, ni prompts, ni código.",
    "stores_2": "Puedes restablecer tus estadísticas cuando quieras en Ajustes, en «Estadísticas».",
    "changes_head": "Qué cambia Belay en tu Mac",
    "changes_1": "Para mantener el Mac despierto, Belay usa la API de aserciones de energía que macOS ofrece para eso. No reescribe tus ajustes de ahorro de energía, y no puede hacerlo: una aserción convive con ellos en vez de editarlos.",
    "changes_2": "Si activas la detección precisa para Claude Code, Belay te enseña primero la configuración exacta que añadiría y solo escribe después de que lo confirmes. Antes hace una copia de seguridad con marca de tiempo, añade únicamente su propia entrada y «Eliminar», en esa misma pantalla, deja el archivo como estaba.",
    "sharing_head": "Compartir",
    "sharing_1": "Belay no nos envía tus estadísticas de uso, ni tus ajustes, ni tu trabajo. En la app no hay servicios de analítica ni de publicidad.",
    "sharing_2": "El panel de Estadísticas puede crear una imagen con tus propios números. Si decides compartirla, macOS te pregunta a dónde, y hasta entonces no se comparte nada.",
    "policy_head": "Cambios en esta política",
    "policy_1": "Si esta política cambia, actualizaremos la fecha de arriba. Cualquier cambio relevante para la privacidad se mencionará también en las notas de la versión.",
    "contact_head": "Contacto",
    "contact_1": 'Dudas sobre esta política: <a href="https://github.com/PerfectoWeb/Belay/issues">el gestor de incidencias</a> o la dirección que aparece en <a href="https://perfecto-web.com">perfecto-web.com</a>.',
    "fine": "Claude Code, Codex CLI, Gemini CLI y Cline son de otras personas. Belay funciona junto a ellos y no está afiliado ni respaldado por ninguno.",
    "authoritative": 'Esto es una traducción. La versión de referencia está <a href="../">en inglés</a>.',
    "source": "Código en GitHub",
}

T["fr"] = {
    "title": "Politique de confidentialité : Belay",
    "meta": "Belay n'a ni comptes, ni analytique, ni publicité, ni rapports de plantage. Ce qu'il lit, ce qu'il conserve et la seule requête qu'il peut faire.",
    "h1": "Politique de confidentialité",
    "stamp": "Belay pour macOS. Dernière mise à jour : 13 août 2026.",
    "lede": "Belay n'a ni comptes, ni analytique, ni publicité, ni rapports de plantage. Il ne constitue pas de profil vous concernant et ne nous envoie pas votre travail. L'essentiel de ce dont Belay a besoin ne quitte jamais votre Mac.",
    "reads_head": "Ce que Belay lit",
    "reads_1": "Belay a besoin de savoir une seule chose : un agent travaille-t-il en ce moment ?",
    "reads_2": "Pour Claude Code, Belay regarde les fichiers de session que Claude Code écrit déjà sur votre Mac. Il observe la taille du fichier, s'il a grandi, la date de dernière écriture et, dans la partie ajoutée, deux champs de chaque enregistrement : son type et si le tour est terminé. Vos prompts, vos réponses et votre code ne sont pas extraits de ces fichiers et aucune copie n'en est conservée.",
    "reads_3": "Pour les autres agents, Belay peut surveiller un dossier que vous choisissez. macOS lui indique quels fichiers ont changé et quand, et c'est tout ce que Belay utilise : il n'ouvre pas ces fichiers et n'en lit pas le contenu. Le dossier reste le vôtre et rien n'en est téléversé.",
    "reads_4": "Les dossiers que Belay regarde, c'est vous qui les choisissez. <code>~/.claude</code> pour Claude Code, et pour le reste uniquement ce que vous lui désignez.",
    "leaves_head": "Ce qui quitte votre Mac",
    "leaves_mas": "<strong>Mac App Store.</strong> Belay n'établit aucune connexion réseau sortante. Cette version est livrée sans l'autorisation que macOS exige pour cela. La détection précise, si vous l'activez, utilise une connexion qui commence et se termine sur votre propre Mac et n'envoie rien sur internet.",
    "leaves_direct": "<strong>Téléchargement direct.</strong> La version téléchargée depuis GitHub peut vérifier une fois par jour s'il existe une mise à jour. C'est une requête HTTPS ordinaire vers l'API des versions de GitHub, sans compte, sans paramètre de requête et sans identifiant Belay ; GitHub voit l'adresse IP de la requête et un user agent, comme pour n'importe quelle visite web. La vérification automatique se désactive dans Réglages, sous « Général », et Belay n'installe jamais de mise à jour sans que vous le demandiez.",
    "stores_head": "Ce que Belay conserve",
    "stores_1": "Ses réglages et de simples compteurs d'utilisation, dans les préférences de votre compte. Les compteurs contiennent des durées, des nombres d'exécutions et des jours. Ils ne contiennent ni noms de projets, ni prompts, ni code.",
    "stores_2": "Vous pouvez réinitialiser vos statistiques à tout moment dans Réglages, sous « Statistiques ».",
    "changes_head": "Ce que Belay modifie sur votre Mac",
    "changes_1": "Pour garder votre Mac éveillé, Belay utilise l'API d'assertion d'alimentation que macOS prévoit pour cela. Il ne réécrit pas vos réglages d'économie d'énergie, et il ne le peut pas : une assertion coexiste avec eux au lieu de les modifier.",
    "changes_2": "Si vous activez la détection précise pour Claude Code, Belay vous montre d'abord la configuration exacte qu'il ajouterait et n'écrit qu'après votre confirmation. Il fait au préalable une sauvegarde horodatée, n'ajoute que sa propre entrée, et « Supprimer », sur le même écran, remet le fichier en l'état.",
    "sharing_head": "Partage",
    "sharing_1": "Belay ne nous envoie ni vos statistiques d'utilisation, ni vos réglages, ni votre travail. Il n'y a dans l'app aucun service d'analytique ou de publicité.",
    "sharing_2": "Le volet Statistiques peut créer une image de vos propres chiffres. Si vous la partagez, macOS vous demande où, et rien n'est partagé avant cela.",
    "policy_head": "Modifications de cette politique",
    "policy_1": "Si cette politique change, nous mettrons à jour la date ci-dessus. Tout changement notable en matière de confidentialité sera également signalé dans les notes de version.",
    "contact_head": "Contact",
    "contact_1": 'Questions sur cette politique : <a href="https://github.com/PerfectoWeb/Belay/issues">le suivi des tickets</a>, ou l\'adresse indiquée sur <a href="https://perfecto-web.com">perfecto-web.com</a>.',
    "fine": "Claude Code, Codex CLI, Gemini CLI et Cline sont l'œuvre d'autres personnes. Belay fonctionne à leurs côtés et n'est ni affilié ni approuvé par aucun d'eux.",
    "authoritative": 'Ceci est une traduction. La version de référence est <a href="../">en anglais</a>.',
    "source": "Code source sur GitHub",
}

T["it"] = {
    "title": "Informativa sulla privacy: Belay",
    "meta": "Belay non ha account, analitiche, pubblicità né segnalazioni di errori. Cosa legge, cosa conserva e l'unica richiesta che può fare.",
    "h1": "Informativa sulla privacy",
    "stamp": "Belay per macOS. Ultimo aggiornamento: 13 agosto 2026.",
    "lede": "Belay non ha account, analitiche, pubblicità né segnalazioni di errori. Non costruisce un profilo di te e non ci manda il tuo lavoro. Quasi tutto ciò che serve a Belay non lascia mai il tuo Mac.",
    "reads_head": "Cosa legge Belay",
    "reads_1": "A Belay serve sapere una cosa: c'è un agente al lavoro in questo momento?",
    "reads_2": "Per Claude Code, Belay guarda i file di sessione che Claude Code già scrive sul tuo Mac. Osserva quanto è grande un file, se è cresciuto, quando è stato scritto l'ultima volta e, nella parte cresciuta, due campi di ogni voce: di che tipo è e se il turno è finito. I tuoi prompt, le tue risposte e il tuo codice non vengono estratti da quei file e non ne resta alcuna copia.",
    "reads_3": "Per gli altri agenti, Belay può sorvegliare una cartella scelta da te. macOS gli dice quali file sono cambiati e quando, e Belay usa soltanto questo: non apre quei file e non ne legge il contenuto. La cartella resta tua e nulla di ciò che contiene viene caricato altrove.",
    "reads_4": "Quali cartelle guardare lo decidi tu. <code>~/.claude</code> per Claude Code e, per il resto, solo ciò che gli indichi.",
    "leaves_head": "Cosa lascia il tuo Mac",
    "leaves_mas": "<strong>Mac App Store.</strong> Belay non effettua connessioni di rete in uscita. Quella versione viene distribuita senza il permesso che macOS richiede per farlo. Il rilevamento preciso, se lo attivi, usa una connessione che inizia e finisce sul tuo stesso Mac e non manda nulla su internet.",
    "leaves_direct": "<strong>Download diretto.</strong> La versione scaricata da GitHub può controllare una volta al giorno se esiste una versione nuova. È una normale richiesta HTTPS all'API delle release di GitHub, senza account, senza parametri e senza identificatori di Belay; GitHub vede l'indirizzo IP della richiesta e uno user agent, come per qualsiasi visita web. Il controllo automatico si disattiva in Impostazioni, alla voce «Generali», e Belay non installa mai un aggiornamento senza che tu lo chieda.",
    "stores_head": "Cosa conserva Belay",
    "stores_1": "Le sue impostazioni e semplici contatori d'uso, nelle preferenze del tuo utente. I contatori contengono durate, numero di esecuzioni e giorni. Non contengono nomi di progetti, prompt o codice.",
    "stores_2": "Puoi azzerare le statistiche quando vuoi in Impostazioni, alla voce «Statistiche».",
    "changes_head": "Cosa cambia Belay sul tuo Mac",
    "changes_1": "Per tenere sveglio il Mac, Belay usa l'API di asserzione di alimentazione che macOS mette a disposizione. Non riscrive le tue impostazioni di risparmio energetico, e non potrebbe: un'asserzione convive con esse invece di modificarle.",
    "changes_2": "Se attivi il rilevamento preciso per Claude Code, Belay ti mostra prima la configurazione esatta che aggiungerebbe e scrive solo dopo la tua conferma. Prima crea una copia di sicurezza con data e ora, aggiunge soltanto la propria voce e «Rimuovi», nella stessa schermata, riporta il file com'era.",
    "sharing_head": "Condivisione",
    "sharing_1": "Belay non ci manda le tue statistiche d'uso, le tue impostazioni o il tuo lavoro. Nell'app non ci sono servizi di analitica o pubblicitari.",
    "sharing_2": "Il pannello Statistiche può creare un'immagine dei tuoi numeri. Se decidi di condividerla, macOS ti chiede dove, e prima di allora non viene condiviso nulla.",
    "policy_head": "Modifiche a questa informativa",
    "policy_1": "Se questa informativa cambia, aggiorneremo la data qui sopra. Ogni cambiamento rilevante per la privacy sarà indicato anche nelle note di versione.",
    "contact_head": "Contatti",
    "contact_1": 'Domande su questa informativa: <a href="https://github.com/PerfectoWeb/Belay/issues">il tracker delle segnalazioni</a> o l\'indirizzo su <a href="https://perfecto-web.com">perfecto-web.com</a>.',
    "fine": "Claude Code, Codex CLI, Gemini CLI e Cline sono di altri. Belay funziona accanto a loro e non è affiliato né sostenuto da nessuno di essi.",
    "authoritative": 'Questa è una traduzione. La versione di riferimento è <a href="../">in inglese</a>.',
    "source": "Codice su GitHub",
}

MARK = '''<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <path d="M32 6 L38.5 25.5 L58 32 L38.5 38.5 L32 58 L25.5 38.5 L6 32 L25.5 25.5 Z" fill="#1f6bff"/>
        <path d="M50 8 L52.5 15.5 L60 18 L52.5 20.5 L50 28 L47.5 20.5 L40 18 L47.5 15.5 Z" fill="#5b93ff"/>
    </svg>'''


def switcher(current, depth):
    up = "../" * depth
    items = []
    for code, name, _ in LANGUAGES:
        href = up if code == "en" else f"{up}{code}/"
        if code == current:
            items.append(f'<span class="here">{name}</span>')
        else:
            items.append(f'<a href="{href}">{name}</a>')
    return '<nav class="languages">' + " ".join(items) + "</nav>"


def page(code):
    t = T[code]
    depth = 0 if code == "en" else 1
    up = "../" * depth
    lines = [
        "<!doctype html>",
        f'<html lang="{code}">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>{t['title']}</title>",
        f'<meta name="description" content="{t["meta"]}">',
        f'<link rel="stylesheet" href="{up}../style.css">',
    ]
    for other, _, lang in LANGUAGES:
        href = "../privacy/" if other == "en" else f"../privacy/{other}/"
        lines.append(f'<link rel="alternate" hreflang="{lang}" href="https://perfectoweb.github.io/Belay{href[2:]}">')
    lines += [
        "</head>",
        "<body>",
        '<div class="wrap">',
        "",
        "<header>",
        f"    {MARK}",
        f'    <a href="{up}../">belay</a>',
        "</header>",
        "",
        f"<h1>{t['h1']}</h1>",
        f'<p class="stamp">{t["stamp"]}</p>',
        "",
        switcher(code, depth),
        "",
    ]
    if t["authoritative"]:
        lines += [f'<p class="stamp translated">{t["authoritative"]}</p>', ""]
    lines += [f'<p class="lede">{t["lede"]}</p>', ""]

    sections = [
        ("reads_head", ["reads_1", "reads_2", "reads_3", "reads_4"], False),
        ("leaves_head", ["leaves_mas", "leaves_direct"], True),
        ("stores_head", ["stores_1", "stores_2"], False),
        ("changes_head", ["changes_1", "changes_2"], False),
        ("sharing_head", ["sharing_1", "sharing_2"], False),
        ("policy_head", ["policy_1"], False),
        ("contact_head", ["contact_1"], False),
    ]
    for head, bodies, boxed in sections:
        lines.append(f"<h2>{t[head]}</h2>")
        lines.append("")
        if boxed:
            lines.append('<div class="note">')
            for key in bodies:
                lines.append(f"    <p>{t[key]}</p>")
            lines.append("</div>")
        else:
            for key in bodies:
                lines.append(f"<p>{t[key]}</p>")
                lines.append("")
        if not boxed and lines[-1] == "":
            lines.pop()
        lines.append("")

    lines += [
        "<footer>",
        f'    <a href="{up}../">Belay</a> &middot;',
        f'    <a href="https://github.com/PerfectoWeb/Belay">{t["source"]}</a>',
        f'    <p class="fine">{t["fine"]}</p>',
        "</footer>",
        "",
        "</div>",
        "</body>",
        "</html>",
        "",
    ]
    return "\n".join(lines)


def main(root):
    for code, _, _ in LANGUAGES:
        folder = os.path.join(root, "privacy") if code == "en" else os.path.join(root, "privacy", code)
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, "index.html")
        io.open(path, "w", encoding="utf-8").write(page(code))
        print(f"wrote {path}")


if __name__ == "__main__":
    main(sys.argv[1])
