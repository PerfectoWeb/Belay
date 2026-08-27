/* The character field behind the hero.

   A grid of monospace glyphs on a canvas, at rest until a pointer disturbs it.
   The disturbance is a wave: it spreads outward from where the pointer is,
   reflects off nothing, and dies down. Which glyph a cell draws depends on how
   much energy it holds, so the ripple reads as a change in density rather than
   a change in colour, the way a printed halftone does.

   Belay's mark is a star, so the brightest cells are stars and everything below
   them is a dot fading into the page. Nothing here is decoration for its own
   sake: the hero is otherwise a flat rectangle of dark, and the field is what
   makes moving the pointer across it feel like touching something.

   Switched off entirely under `prefers-reduced-motion`, while the tab is
   hidden, and while the hero is scrolled out of view. It draws nothing that
   carries meaning, so losing it costs a reader nothing at all. */

window.BelayField = function () {
    "use strict";

    var host = document.querySelector("[data-field]");
    if (!host || !window.requestAnimationFrame) { return; }
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) { return; }
    /* No pointer, no point: a touch screen has nothing to move across the
       field, and the canvas would be a battery cost for a still picture. */
    if (window.matchMedia("(hover: none)").matches) { return; }

    var canvas = document.createElement("canvas");
    canvas.className = "field";
    canvas.setAttribute("aria-hidden", "true");
    host.insertBefore(canvas, host.firstChild);
    var ctx = canvas.getContext("2d", { alpha: true });
    if (!ctx) { return; }

    /* Sparse to dense. The last two are the brand's stars, which is what the
       crest of a ripple lands on; below them it is punctuation thinning out to
       nothing. All monospace-safe: the canvas places every glyph at its own
       cell centre, so a character of a different width cannot shift the grid. */
    var RAMP = [".", ".", ":", "+", "*", "✦", "✦"];
    var CELL = 15;
    var FONT_SIZE = 12;
    /* How far the pointer reaches, in pixels. Wide enough that the hand feels
       ahead of the ripple rather than poking it. */
    var REACH = 150;
    /* How hard a still pointer pushes, per frame. Movement adds to this. */
    var PUSH = 0.055;
    /* The wave: `SPREAD` is how fast a disturbance travels between cells and
       `KEEP` is how much of it survives each frame. Tuned by eye — below 0.96
       the ripple dies before it is seen, above 0.99 the field never settles. */
    var SPREAD = 0.16;
    var KEEP = 0.978;
    /* The pointer's own inertia: the wave is made at a point that chases the
       cursor rather than at the cursor itself, which is what gives the trail
       its lag on a fast swipe. */
    var CHASE = 0.14;

    var cols = 0;
    var rows = 0;
    var cur = null;
    var prev = null;
    var rest = null;
    var dpr = 1;

    var pointerX = -1e4;
    var pointerY = -1e4;
    var ghostX = -1e4;
    var ghostY = -1e4;
    var lastX = -1e4;
    var lastY = -1e4;
    var pointerIn = false;
    var running = false;
    var visible = true;

    function measure() {
        var box = host.getBoundingClientRect();
        dpr = Math.min(window.devicePixelRatio || 1, 2);
        canvas.width = Math.max(1, Math.round(box.width * dpr));
        canvas.height = Math.max(1, Math.round(box.height * dpr));
        canvas.style.width = box.width + "px";
        canvas.style.height = box.height + "px";
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.font = FONT_SIZE + "px ui-monospace, SFMono-Regular, Menlo, monospace";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";

        cols = Math.ceil(box.width / CELL) + 1;
        rows = Math.ceil(box.height / CELL) + 1;
        var size = cols * rows;
        cur = new Float32Array(size);
        prev = new Float32Array(size);
        /* A little standing texture so the field is not a blank rectangle
           before anybody touches it. Fixed per cell rather than random per
           frame: a grid that fizzes on its own is noise, not texture. */
        rest = new Float32Array(size);
        for (var i = 0; i < size; i++) {
            var x = i % cols;
            var y = (i / cols) | 0;
            rest[i] = 0.10 + 0.06 * Math.sin(x * 0.7 + y * 0.9) * Math.cos(x * 0.31 - y * 0.17);
        }
    }

    function disturb() {
        if (!pointerIn) { return; }
        ghostX += (pointerX - ghostX) * CHASE;
        ghostY += (pointerY - ghostY) * CHASE;
        var moved = Math.hypot(pointerX - lastX, pointerY - lastY);
        lastX = pointerX;
        lastY = pointerY;
        /* A fast hand leaves a brighter wake, up to a ceiling: without the cap
           a flick across the hero whites the whole thing out. */
        var strength = PUSH * (1 + Math.min(moved / 18, 2.2));

        var cx = ghostX / CELL;
        var cy = ghostY / CELL;
        var span = Math.ceil(REACH / CELL);
        var x0 = Math.max(0, Math.floor(cx - span));
        var x1 = Math.min(cols - 1, Math.ceil(cx + span));
        var y0 = Math.max(0, Math.floor(cy - span));
        var y1 = Math.min(rows - 1, Math.ceil(cy + span));

        for (var y = y0; y <= y1; y++) {
            for (var x = x0; x <= x1; x++) {
                var dx = (x - cx) * CELL;
                var dy = (y - cy) * CELL;
                var d = Math.hypot(dx, dy);
                if (d > REACH) { continue; }
                /* Smooth to zero at the rim, so the reach has no visible edge. */
                var fall = 1 - d / REACH;
                cur[y * cols + x] += strength * fall * fall;
            }
        }
    }

    function step() {
        var next = prev;
        for (var y = 0; y < rows; y++) {
            var up = y > 0 ? y - 1 : y;
            var down = y < rows - 1 ? y + 1 : y;
            for (var x = 0; x < cols; x++) {
                var i = y * cols + x;
                var left = x > 0 ? i - 1 : i;
                var right = x < cols - 1 ? i + 1 : i;
                /* The wave equation, discretised: where a cell sits relative to
                   its neighbours is the force on it, and its previous value is
                   its momentum. */
                var pull = (cur[left] + cur[right] + cur[up * cols + x] + cur[down * cols + x]) * 0.25 - cur[i];
                var value = cur[i] + (cur[i] - next[i]) * 0.92 + pull * SPREAD;
                next[i] = value * KEEP;
            }
        }
        prev = cur;
        cur = next;
    }

    function draw() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        var half = CELL / 2;
        for (var y = 0; y < rows; y++) {
            for (var x = 0; x < cols; x++) {
                var i = y * cols + x;
                var level = rest[i] + Math.abs(cur[i]) * 2.6;
                if (level < 0.06) { continue; }
                var capped = Math.min(level, 1);
                var glyph = RAMP[Math.min(RAMP.length - 1, Math.floor(capped * RAMP.length))];
                /* Rest is a grey barely off the page; energy pulls it towards
                   the accent, so a ripple arrives as colour and density at once. */
                var lift = Math.min(1, Math.max(0, (capped - 0.12) / 0.7));
                var r = Math.round(64 + (91 - 64) * lift);
                var g = Math.round(72 + (147 - 72) * lift);
                var b = Math.round(88 + (255 - 88) * lift);
                ctx.fillStyle = "rgba(" + r + "," + g + "," + b + "," + (0.16 + capped * 0.72).toFixed(3) + ")";
                ctx.fillText(glyph, x * CELL + half, y * CELL + half);
            }
        }
    }

    function frame() {
        if (!running) { return; }
        disturb();
        step();
        draw();
        requestAnimationFrame(frame);
    }

    function start() {
        if (running || !visible) { return; }
        running = true;
        requestAnimationFrame(frame);
    }

    function stop() { running = false; }

    host.addEventListener("pointermove", function (event) {
        var box = host.getBoundingClientRect();
        pointerX = event.clientX - box.left;
        pointerY = event.clientY - box.top;
        if (!pointerIn) {
            /* Arriving: the ghost starts where the pointer is, or the first
               move drags a ripple in from wherever it was left. */
            ghostX = pointerX;
            ghostY = pointerY;
            lastX = pointerX;
            lastY = pointerY;
            pointerIn = true;
        }
    }, { passive: true });

    host.addEventListener("pointerleave", function () { pointerIn = false; });

    var resizing = null;
    window.addEventListener("resize", function () {
        clearTimeout(resizing);
        resizing = setTimeout(measure, 150);
    }, { passive: true });

    document.addEventListener("visibilitychange", function () {
        if (document.hidden) { stop(); } else { start(); }
    });

    if ("IntersectionObserver" in window) {
        new IntersectionObserver(function (entries) {
            visible = entries[0].isIntersecting;
            if (visible) { start(); } else { stop(); }
        }, { threshold: 0 }).observe(host);
    }

    measure();
    start();
};
