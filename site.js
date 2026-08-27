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

    /* ------------------------------------------------------------- startup */

    function begin() {
        retellTheDays();
        watchTheFigures();
        rotateTheMiddleFigure();
        tooltips();
        if (window.BelayField) { window.BelayField(); }
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", begin);
    } else {
        begin();
    }
})();
