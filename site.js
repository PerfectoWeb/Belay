/* Belay landing page behaviour.

   A plain file, like the stylesheet: no build step, no bundler, no imports.
   Everything here is an enhancement — the page is complete and readable with
   this file blocked, which is why nothing below creates content that matters.

   Five pieces: the day counter, the numbers counting up when they scroll into
   view, the middle figure rotating between three facts, tooltips, and the
   character field behind the hero. Each one checks for its own markup and does
   nothing when it is absent, so removing a block from template.html cannot
   throw. */

(function () {
    "use strict";

    var still = window.matchMedia("(prefers-reduced-motion: reduce)");

    /* ---------------------------------------------------------------- days */

    /* Built pages sit on a CDN for hours. The day count is the one number that
       goes stale on its own, so the page works it out again from a fixed date. */
    function retellTheDays() {
        var el = document.querySelector(".figure[data-since]");
        if (!el) { return; }
        var start = new Date(el.dataset.since + "T00:00:00");
        var days = Math.floor((Date.now() - start.getTime()) / 86400000);
        if (days > 0) { el.dataset.count = String(days); el.textContent = String(days); }
    }

    /* ------------------------------------------------------------ counting */

    /* Numbers count up the first time they are seen, and only then. A number
       that re-counts every time it scrolls past is a fidget, not a flourish. */
    function countUp(el, to, ms) {
        if (still.matches) { el.textContent = String(to); return; }
        var from = 0;
        var started = null;
        function step(now) {
            if (started === null) { started = now; }
            var t = Math.min(1, (now - started) / ms);
            /* Fast at first, then settling: the last few numbers are the ones
               worth reading, so they get most of the time. */
            var eased = 1 - Math.pow(1 - t, 3);
            el.textContent = String(Math.round(from + (to - from) * eased));
            if (t < 1) { requestAnimationFrame(step); }
        }
        requestAnimationFrame(step);
    }

    function watchTheFigures() {
        var figures = [].slice.call(document.querySelectorAll(".figure[data-count]"));
        if (!figures.length) { return; }
        if (!("IntersectionObserver" in window)) { return; }
        var seen = new WeakSet();
        var watcher = new IntersectionObserver(function (entries) {
            entries.forEach(function (entry) {
                if (!entry.isIntersecting || seen.has(entry.target)) { return; }
                seen.add(entry.target);
                var to = parseInt(entry.target.dataset.count, 10);
                if (!isNaN(to)) { countUp(entry.target, to, 1100); }
            });
        }, { threshold: 0.6 });
        figures.forEach(function (el) { watcher.observe(el); });
    }

    /* ------------------------------------------------------------ rotating */

    /* The middle figure holds three facts about the same repository, and shows
       them in turn. The scramble between them is short on purpose: it is there
       to say "this changed", not to be looked at. */
    var SCRAMBLE = "0123456789/\\|<>_-=+*#%$";

    function scrambleTo(el, text, ms) {
        if (still.matches) { el.textContent = text; return; }
        var started = null;
        function frame(now) {
            if (started === null) { started = now; }
            var t = Math.min(1, (now - started) / ms);
            var settled = Math.floor(text.length * t);
            var out = text.slice(0, settled);
            for (var i = settled; i < text.length; i++) {
                out += SCRAMBLE[Math.floor(Math.random() * SCRAMBLE.length)];
            }
            el.textContent = out;
            if (t < 1) { requestAnimationFrame(frame); } else { el.textContent = text; }
        }
        requestAnimationFrame(frame);
    }

    function rotateTheMiddleFigure() {
        var card = document.querySelector("[data-rotate]");
        if (!card) { return; }
        var figure = card.querySelector(".figure");
        var caption = card.querySelector(".caption");
        var glyphs = [].slice.call(card.querySelectorAll(".glyph"));
        var origins = [].slice.call(card.querySelectorAll(".origin .face"));
        if (!figure || !caption) { return; }
        var numbers = (figure.dataset.faces || "").split("|");
        var words = (caption.dataset.faces || "").split("|");
        if (numbers.length < 2) { return; }

        var face = 0;
        /* The first turn waits, so the count-up on the number below has
           finished before anything else moves. */
        function turn() {
            face = (face + 1) % numbers.length;
            card.classList.add("turning");
            scrambleTo(figure, numbers[face], 420);
            scrambleTo(caption, words[face], 420);
            glyphs.forEach(function (glyph, index) {
                glyph.classList.toggle("is-on", index === face);
            });
            origins.forEach(function (origin, index) {
                origin.classList.toggle("is-on", index === face);
            });
            setTimeout(function () { card.classList.remove("turning"); }, 480);
        }

        /* Long enough to read, short enough that somebody scrolling past sees
           it happen once. Paused while the tab is in the background: an
           animation nobody is watching is only a battery cost. */
        var timer = null;
        function start() {
            if (timer || still.matches) { return; }
            /* No `document.hidden` test inside the tick: some embedded views
               report a visible page as hidden, and the card then never turned
               at all. Leaving and returning is handled by the event below,
               which is the thing that actually knows. */
            timer = setInterval(turn, 5200);
        }
        function stop() { clearInterval(timer); timer = null; }

        document.addEventListener("visibilitychange", function () {
            if (document.hidden) { stop(); } else { start(); }
        });
        /* Belt and braces. Some embedded browsers report a page nobody has
           hidden as hidden, which stops the rotation for good; a pointer moving
           over the page is proof somebody is looking at it, so it starts again.
           Costs one listener and one guarded call. */
        window.addEventListener("pointermove", function () {
            if (!document.hidden) { start(); }
        }, { passive: true });
        /* Hovering holds the current face, so a fact can be read and its link
           followed without it changing under the pointer. */
        card.addEventListener("mouseenter", stop);
        card.addEventListener("mouseleave", start);
        card.addEventListener("focusin", stop);
        card.addEventListener("focusout", start);
        setTimeout(start, 2600);
    }

    /* ------------------------------------------------------------- tooltip */

    /* One tooltip for the whole page, moved to whatever needs it. Anything with
       `data-tip` gets one, on hover and on keyboard focus alike, which is the
       only reason this is script rather than a `title` attribute: `title` never
       appears for somebody tabbing through, and never appears on a phone. */
    function tooltips() {
        var tip = null;

        function ensure() {
            if (tip) { return tip; }
            tip = document.createElement("div");
            tip.className = "tip";
            tip.setAttribute("role", "tooltip");
            document.body.appendChild(tip);
            return tip;
        }

        function show(host) {
            var text = host.getAttribute("data-tip");
            if (!text) { return; }
            var el = ensure();
            el.textContent = text;
            /* Measured while it is already laid out and merely transparent.
               Hiding it with `hidden` and revealing it a frame later was a race
               nothing won: every pointer event took the class off again before
               the frame that would have put it back. */
            var box = host.getBoundingClientRect();
            var mine = el.getBoundingClientRect();
            var left = box.left + box.width / 2 - mine.width / 2;
            /* Kept inside the window: a tooltip half off the edge is a bug the
               reader blames on themselves for hovering too far right. */
            left = Math.max(8, Math.min(left, window.innerWidth - mine.width - 8));
            var top = box.top - mine.height - 8;
            var below = top < 4;
            if (below) { top = box.bottom + 8; }
            el.classList.toggle("below", below);
            el.style.left = Math.round(left + window.scrollX) + "px";
            el.style.top = Math.round(top + window.scrollY) + "px";
            el.classList.add("is-on");
        }

        function hide() {
            if (!tip) { return; }
            tip.classList.remove("is-on");
        }

        document.addEventListener("mouseover", function (event) {
            var host = event.target.closest("[data-tip]");
            if (host) { show(host); }
        });
        document.addEventListener("mouseout", function (event) {
            if (event.target.closest("[data-tip]")) { hide(); }
        });
        document.addEventListener("focusin", function (event) {
            var host = event.target.closest("[data-tip]");
            if (host) { show(host); }
        });
        document.addEventListener("focusout", hide);
        window.addEventListener("scroll", hide, { passive: true });
    }

    /* ---------------------------------------------------------------- film */

    /* The demo video, which is not on the page until somebody asks for it.

       An `<iframe>` in the markup would fetch YouTube for every visitor,
       including the ones who never press play, and this page tells people it
       has no telemetry: quietly handing their address to Google on arrival
       would make that a half-truth. So the player is built on the first click,
       from `youtube-nocookie.com`, and torn out again when the dialog closes so
       the sound stops with it.

       `<dialog>` rather than a hand-made overlay: the modal state, the focus
       trap, the Escape key and the inert page behind it are all the browser's
       already, and every hand-made version of that misses one of them. */
    function film() {
        var dialog = document.querySelector("[data-film]");
        var slot = dialog && dialog.querySelector("[data-film-slot]");
        var openers = [].slice.call(document.querySelectorAll("[data-demo]"));
        if (!dialog || !slot || !openers.length || !dialog.showModal) { return; }

        function open(id) {
            var frame = document.createElement("iframe");
            /* No controls at all, and looping. The demo is a short cut that
               joins back to its own beginning, so it plays as a loop rather
               than as a video somebody has to operate; without `controls=0`
               YouTube also flashes its bar over the first second before
               fading it, which is the thing that looked broken. `loop` needs
               `playlist` naming the same video: on its own it is ignored. */
            frame.src = "https://www.youtube-nocookie.com/embed/" + id
                + "?autoplay=1&controls=0&loop=1&playlist=" + id
                + "&rel=0&modestbranding=1&playsinline=1&iv_load_policy=3";
            frame.title = dialog.getAttribute("aria-label") || "";
            frame.allow = "autoplay; fullscreen; picture-in-picture";
            frame.setAttribute("allowfullscreen", "");
            frame.setAttribute("referrerpolicy", "strict-origin-when-cross-origin");
            slot.replaceChildren(frame);
            dialog.showModal();
        }

        /* Emptied first, then closed. Emptying is the part that matters: a
           player left in the page keeps its connection and, on some builds,
           keeps making noise behind a dialog nobody can see.

           Not hung off the `close` event, which is where this started: some
           engines — the one embedded in this project's own tooling among them —
           toggle `open` without ever dispatching it, and the video played on
           under a closed dialog. The event is still listened for, because an
           engine that does fire it can close the dialog by routes this code
           never sees. */
        function shut() { slot.replaceChildren(); }

        function dismiss() {
            shut();
            if (dialog.open) { dialog.close(); }
        }

        openers.forEach(function (button) {
            button.addEventListener("click", function () {
                open(button.getAttribute("data-demo"));
            });
        });
        dialog.addEventListener("close", shut);
        dialog.addEventListener("cancel", shut);
        dialog.querySelectorAll("[data-film-close]").forEach(function (button) {
            button.addEventListener("click", dismiss);
        });
        /* Escape, taken by hand for the same reason. */
        dialog.addEventListener("keydown", function (event) {
            if (event.key === "Escape") {
                event.preventDefault();
                dismiss();
            }
        });
        /* Clicking the darkness closes it. The dialog element covers the whole
           screen, so a click that lands on the element itself and not on its
           children is a click outside the video. */
        dialog.addEventListener("click", function (event) {
            if (event.target === dialog) { dismiss(); }
        });
    }


    /* ------------------------------------------------------------- star bar */

    /* The one ask on the page, and when it is allowed to happen.

       Not on arrival: a visitor who has just landed owes nothing and knows
       nothing, and a bar in their face is the first thing they learn about us.
       It waits for two signs that the page has actually been read, both
       required: the numbers under the hero have scrolled into view (they sit
       past the pitch, so seeing them means the pitch was seen), and about
       twenty seconds have passed with the tab in front. Then it slides in,
       once, and any answer ends it: a star is remembered for good, "not now"
       and the cross for two months. Somebody arriving from the repository
       itself is already where the bar would send them, so it stays quiet.

       Nothing is fetched to show the count: the number is the one baked into
       the page by the scheduled job, so the ask costs the visitor no request
       to a third party. Honest as "as of the last build", like the figures. */
    function starbar() {
        var bar = document.querySelector("[data-starbar]");
        if (!bar) { return; }
        var KEY = "belay.starbar";
        var DWELL_MS = 18000;
        var SNOOZE_MS = 60 * 86400000;

        var memory = {};
        try { memory = JSON.parse(localStorage.getItem(KEY) || "{}") || {}; } catch (e) { memory = {}; }
        function remember(patch) {
            Object.keys(patch).forEach(function (k) { memory[k] = patch[k]; });
            try { localStorage.setItem(KEY, JSON.stringify(memory)); } catch (e) { /* private mode */ }
        }

        var forced = location.hash === "#starbar";
        if (!forced) {
            if (memory.starred) { return; }
            if (memory.dismissedAt && Date.now() - memory.dismissedAt < SNOOZE_MS) { return; }
            if (/(^|\.)github\.com$/.test((document.referrer.split("/")[2] || "").toLowerCase())) { return; }
        }

        var shown = false;
        var sawTheNumbers = forced;
        var dwelt = forced;
        var timer = null;
        var dwellLeft = DWELL_MS;
        var dwellStarted = null;

        /* The dwell counts only while the tab is in front: a page left open
           in a background tab has not been read. */
        function startDwell() {
            if (dwelt || timer !== null) { return; }
            dwellStarted = Date.now();
            timer = setTimeout(function () { timer = null; dwelt = true; maybeShow(); }, dwellLeft);
        }
        function pauseDwell() {
            if (timer === null) { return; }
            clearTimeout(timer); timer = null;
            dwellLeft = Math.max(0, dwellLeft - (Date.now() - dwellStarted));
        }
        document.addEventListener("visibilitychange", function () {
            if (document.hidden) { pauseDwell(); } else { startDwell(); }
        });
        if (!document.hidden) { startDwell(); }

        var numbers = document.querySelector(".figures");
        if (numbers && "IntersectionObserver" in window && !sawTheNumbers) {
            var watcher = new IntersectionObserver(function (entries) {
                if (entries.some(function (e) { return e.isIntersecting; })) {
                    sawTheNumbers = true;
                    watcher.disconnect();
                    maybeShow();
                }
            }, { threshold: 0.4 });
            watcher.observe(numbers);
        } else if (!numbers) {
            sawTheNumbers = true;
        }

        /* Never over the demo or the lightbox: someone watching is busy. */
        function somethingIsOpen() {
            var box = document.querySelector("[data-lightbox]");
            return (box && !box.hidden) || !!document.querySelector("dialog[open]");
        }

        function maybeShow() {
            if (shown || !sawTheNumbers || !dwelt) { return; }
            /* Embedded views can report a visible page as hidden; the forced
               preview ignores that, real visits wait for a tab in front. */
            if (document.hidden && !forced) { return; }
            if (somethingIsOpen()) { setTimeout(maybeShow, 4000); return; }
            shown = true;
            bar.hidden = false;
            /* Two frames, so the transition has a "from" to leave. */
            requestAnimationFrame(function () {
                requestAnimationFrame(function () { bar.classList.add("is-in"); });
            });
            document.addEventListener("keydown", onKey);
            /* The count arrives after the bar has: it starts at nothing and
               settles on the real number with the same easing as the figures
               below, which is what makes it read as a live count rather than
               a label somebody typed. */
            var count = bar.querySelector("[data-starbar-count]");
            var total = count ? parseInt(count.textContent, 10) : NaN;
            if (count && !isNaN(total) && !still.matches) {
                count.textContent = "0";
                setTimeout(function () { countUp(count, total, 1100); }, 700);
            }
        }

        function hide(patch) {
            if (patch) { remember(patch); }
            document.removeEventListener("keydown", onKey);
            bar.classList.remove("is-in");
            bar.classList.add("is-out");
            var done = function () { bar.hidden = true; bar.classList.remove("is-out"); };
            if (still.matches) { done(); } else { setTimeout(done, 340); }
        }
        function onKey(event) {
            if (event.key === "Escape") { hide({ dismissedAt: Date.now() }); }
        }

        var go = bar.querySelector("[data-starbar-go]");
        var later = bar.querySelector("[data-starbar-later]");
        if (go) {
            /* The link opens in its own tab (the build adds that); the bar
               goes on its way here and is never seen again. */
            go.addEventListener("click", function () { hide({ starred: true }); });
        }
        if (later) { later.addEventListener("click", function () { hide({ dismissedAt: Date.now() }); }); }

        if (forced) { maybeShow(); }
    }

    /* ------------------------------------------------------------- startup */

    function begin() {
        retellTheDays();
        watchTheFigures();
        rotateTheMiddleFigure();
        tooltips();
        film();
        starbar();
        if (window.BelayField) { window.BelayField(); }
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", begin);
    } else {
        begin();
    }
})();
