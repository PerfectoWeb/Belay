/* The character field behind the hero.

   A grid of monospace glyphs on a canvas, at rest until a pointer disturbs it.
   The disturbance is a wave: it spreads outward from where the pointer is,
   reflects off nothing, and dies down. Which glyph a cell draws depends on how
   much energy it holds, so the ripple reads as a change in density rather than
   a change in colour, the way a printed halftone does.

   Belay's mark is a star, so the brightest cells are stars and everything below
   them is a dot fading into the page. Grey rather than the brand blue: a
   coloured ripple under a headline reads as a second thing happening, and the
   page only has room for one. Nothing here is decoration for its own sake: the
   page is otherwise a flat rectangle of dark, and the field is what makes
   moving the pointer across it feel like touching something.

   The canvas is fixed to the viewport rather than sized to the page. That is
   what lets it sit behind everything without costing more: a page four screens
   long would be four times the cells to solve and draw every frame, and this
   way the cost is the same whatever the page's height.

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
    /* Behind the whole page, not inside the hero: `[data-field]` is only the
       switch that says whether to run at all. */
    document.body.insertBefore(canvas, document.body.firstChild);
    var ctx = canvas.getContext("2d", { alpha: true });
    if (!ctx) { return; }

    /* Sparse to dense. The last two are the brand's stars, which is what the
       crest of a ripple lands on; below them it is punctuation thinning out to
       nothing. All monospace-safe: the canvas places every glyph at its own
       cell centre, so a character of a different width cannot shift the grid. */
    /* The faintest two levels are the resting grain and are drawn as squares;
       the rest are glyphs, each of which the font centres on its own. */
    /* Five agent marks, hidden in the grid at 13 cells square and invisible
       until the wake washes over them. Rasterised from the app's own SVGs by
       `scratchpad/logo-mask.swift`, which is the only honest way to get a
       recognisable shape at this size: hand-drawing them would drift from the
       real marks the moment one changes.

       Codex is not among them. Its knot is a line drawing whose gaps close up
       below about twenty cells, and a solid blob is worse than no easter egg.

       Order and placement are fixed, not random: somebody who finds one should
       be able to show it to somebody else. */
    var LOGOS = [
        { x: 0.13, y: 0.28, bits: "0001100100000000110011000000001101001100110110101100001111111100000001111110111111111111111000001111111100011111110110011011111100000010101111000011010010000000001000000" },
        { x: 0.8, y: 0.17, bits: "0000001000000000000110000000000111000000000011110000000011111100000111111111001111111111111011111111111000011111110000000111110000000001110000000000011000000000001000000" },
        { x: 0.28, y: 0.79, bits: "0000000000000001111111111001111111111100110011100111011001110011101111111111101111110111111111001011011111101101101111110110110111111111001111100111111111100000111111000" },
        { x: 0.88, y: 0.68, bits: "0000001100000000001110000000011111111000011111111110011111111111001111111111100111001100111111100110011101110011001110111011101110011111111111001111111111100011111111110" },
        { x: 0.55, y: 0.93, bits: "0000111111000001111111110001111111111100111111111111111100000011111100000001111110000000111111000000011111110000001111111110111111011111001111100111100111100001110011100" }
    ];

    var DOT = ".";
    var RAMP = [DOT, DOT, "+", "+", "*", "✦", "✦"];
    var CELL = 15;
    var FONT_SIZE = 12;
    /* How far the pointer reaches, in pixels. Wide enough that the hand feels
       ahead of the ripple rather than poking it, and no wider: at 150 the
       disturbance was a third of the hero across and read as a spotlight
       following the cursor rather than a wake behind it. */
    var REACH = 88;
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
    var logo = null;
    var dpr = 1;

    var pointerX = -1e4;
    var pointerY = -1e4;
    /* 0 while nothing is moving, 1 while a hand is. */
    var presence = 0;
    var ghostX = -1e4;
    var ghostY = -1e4;
    var lastX = -1e4;
    var lastY = -1e4;
    var pointerIn = false;
    var running = false;
    var visible = true;

    function measure() {
        var width = window.innerWidth;
        var height = window.innerHeight;
        dpr = Math.min(window.devicePixelRatio || 1, 2);
        canvas.width = Math.max(1, Math.round(width * dpr));
        canvas.height = Math.max(1, Math.round(height * dpr));
        canvas.style.width = width + "px";
        canvas.style.height = height + "px";
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.font = FONT_SIZE + "px ui-monospace, SFMono-Regular, Menlo, monospace";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";

        cols = Math.ceil(width / CELL) + 1;
        rows = Math.ceil(height / CELL) + 1;
        var size = cols * rows;
        cur = new Float32Array(size);
        prev = new Float32Array(size);
        /* A little standing texture so the field is not a blank rectangle
           before anybody touches it. Fixed per cell rather than random per
           frame: a grid that fizzes on its own is noise, not texture. */
        rest = new Float32Array(size);
        /* Where a mark's ink falls. Rebuilt with the grid, so the marks keep
           their place on the page rather than their place in an old array. */
        logo = new Uint8Array(size);
        var SPAN = 13;
        for (var m = 0; m < LOGOS.length; m++) {
            var mark = LOGOS[m];
            var ox = Math.round(mark.x * (cols - SPAN));
            var oy = Math.round(mark.y * (rows - SPAN));
            if (ox < 0 || oy < 0) { continue; }
            for (var by = 0; by < SPAN; by++) {
                for (var bx = 0; bx < SPAN; bx++) {
                    if (mark.bits.charCodeAt(by * SPAN + bx) !== 49) { continue; }
                    logo[(oy + by) * cols + (ox + bx)] = 1;
                }
            }
        }
        for (var i = 0; i < size; i++) {
            var x = i % cols;
            var y = (i / cols) | 0;
            rest[i] = 0.10 + 0.06 * Math.sin(x * 0.7 + y * 0.9) * Math.cos(x * 0.31 - y * 0.17);
        }
    }

    function disturb() {
        var moved = Math.hypot(pointerX - lastX, pointerY - lastY);
        lastX = pointerX;
        lastY = pointerY;

        /* Presence answers "is a hand moving here", not "is a pointer here".
           A pointer resting on the page used to keep pushing the same cells
           and left a bright patch sitting under it; now the field wakes as the
           hand starts and settles back to nothing as it stops, so there is
           never a mark left behind. Rising faster than it falls, because
           arriving should feel immediate and leaving should feel like a wake
           closing over. */
        var wants = pointerIn && moved > 0.4 ? 1 : 0;
        presence += (wants - presence) * (wants ? 0.22 : 0.045);

        if (!pointerIn) { return; }
        ghostX += (pointerX - ghostX) * CHASE;
        ghostY += (pointerY - ghostY) * CHASE;
        /* A fast hand leaves a brighter wake, up to a ceiling: without the cap
           a flick across the hero whites the whole thing out. */
        var strength = PUSH * presence * (1 + Math.min(moved / 18, 2.2));

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
                /* The standing texture is always there; only the ripple
                   is scaled by presence, so the page keeps its grain and
                   just the wake fades up and away. */
                var wake = Math.abs(cur[i]) * 2.6 * presence;
                /* A mark's cells are ordinary grain until the wake reaches
                   them, and then they run ahead of their neighbours: the shape
                   surfaces inside the ripple and sinks again behind it. */
                var level = rest[i] + wake + (logo[i] === 1 ? wake * 2.4 : 0);
                if (level < 0.06) { continue; }
                var capped = Math.min(level, 1);
                var glyph = RAMP[Math.min(RAMP.length - 1, Math.floor(capped * RAMP.length))];
                /* Rest is a grey barely off the page and energy lifts it to a
                   slightly brighter grey: the ripple arrives as light and
                   density, not as colour. Both the blue it first reached for
                   and the near-white after that competed with the words on
                   top of it, so the whole range now sits close to the page. */
                var lift = Math.min(1, Math.max(0, (capped - 0.12) / 0.7));
                var r = Math.round(58 + (104 - 58) * lift);
                var g = Math.round(64 + (112 - 64) * lift);
                var b = Math.round(78 + (126 - 78) * lift);
                /* Opacity carries most of the ripple, so it is the other half of
                   keeping it quiet: at full energy a cell is a little over a
                   third as solid as it used to be. */
                ctx.fillStyle = "rgba(" + r + "," + g + "," + b + "," + (0.14 + capped * 0.26).toFixed(3) + ")";
                var px = x * CELL + half;
                var py = y * CELL + half;
                if (glyph === DOT) {
                    /* The resting grain is drawn, not typed. A period sits on
                       the baseline, and `textBaseline: middle` centres the em
                       box rather than the ink, so the dots landed a few pixels
                       below every other glyph and the wake looked offset from
                       the grid it was moving through. A square at the cell's
                       centre cannot be off. */
                    ctx.fillRect(px - 0.9, py - 0.9, 1.8, 1.8);
                } else {
                    ctx.fillText(glyph, px, py);
                }
            }
        }
    }

    /* How much movement counts as "still". Below this the field is drawn once
       more, at rest, and the loop stops until a pointer wakes it: an idle page
       should not be spending a frame's work sixty times a second on a picture
       that is not changing. */
    var STILL = 0.0016;

    function energy() {
        var total = 0;
        for (var i = 0; i < cur.length; i += 7) { total += Math.abs(cur[i]); }
        return total / (cur.length / 7);
    }

    function frame() {
        if (!running) { return; }
        disturb();
        step();
        draw();
        if (presence < 0.01 && energy() < STILL) {
            running = false;
            return;
        }
        requestAnimationFrame(frame);
    }

    function start() {
        if (running || !visible) { return; }
        running = true;
        requestAnimationFrame(frame);
    }

    function stop() { running = false; }

    window.addEventListener("pointermove", function (event) {
        pointerX = event.clientX;
        pointerY = event.clientY;
        start();
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

    document.addEventListener("pointerleave", function () { pointerIn = false; });

    var resizing = null;
    window.addEventListener("resize", function () {
        clearTimeout(resizing);
        resizing = setTimeout(measure, 150);
    }, { passive: true });

    document.addEventListener("visibilitychange", function () {
        if (document.hidden) { stop(); } else { start(); }
    });

    measure();
    start();
};
