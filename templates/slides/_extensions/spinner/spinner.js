/*!
 * spinner — fruit-machine style random draw plugin for Quarto revealjs.
 *
 * The Lua filter turns a `.spinner` div into
 *   <div class="spinner-machine" data-options='[...]' data-groups="9" ...></div>
 * and this plugin builds and drives the machine.
 *
 * Fairness model: the option list is shuffled once, with crypto randomness,
 * when the deck loads. Each spin takes the next card off that fixed deck, so
 * an option can never come up twice — the animation reveals a draw that has
 * already been made.
 */
window.RevealSpinner = function () {

  /* ---------------------------------------------------------------- utils */

  function parseBool(v, dflt) {
    if (v === undefined || v === null || v === "") return dflt;
    return !/^(false|no|off|0)$/i.test(String(v).trim());
  }

  function parseMs(v, dflt) {
    if (v === undefined || v === null || v === "") return dflt;
    var s = String(v).trim(), m;
    if ((m = s.match(/^([\d.]+)\s*ms$/i))) return parseFloat(m[1]);
    if ((m = s.match(/^([\d.]+)\s*s$/i))) return parseFloat(m[1]) * 1000;
    var n = parseFloat(s);
    if (isNaN(n)) return dflt;
    return n < 100 ? n * 1000 : n;   // bare small numbers read as seconds
  }

  function parseNum(v, dflt) {
    var n = parseFloat(v);
    return isNaN(n) ? dflt : n;
  }

  function csv(s) {
    return String(s).split(/\s*[,;|]\s*/).map(function (x) { return x.trim(); })
      .filter(function (x) { return x.length; });
  }

  function withUnit(v, unit) {
    if (v === undefined || v === null || v === "") return null;
    var s = String(v).trim();
    return /^[\d.]+$/.test(s) ? s + (unit || "px") : s;
  }

  /* unbiased random integer, crypto-backed where available */
  function randInt(n) {
    if (window.crypto && window.crypto.getRandomValues) {
      var limit = Math.floor(0xFFFFFFFF / n) * n, buf = new Uint32Array(1), v;
      do { window.crypto.getRandomValues(buf); v = buf[0]; } while (v >= limit);
      return v % n;
    }
    return Math.floor(Math.random() * n);
  }

  function shuffle(arr) {
    var a = arr.slice();
    for (var i = a.length - 1; i > 0; i--) {
      var j = randInt(i + 1), t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  }

  /* ---------------------------------------------------------------- audio */

  var audioCtx = null;
  function ctx() {
    if (!audioCtx) {
      var C = window.AudioContext || window.webkitAudioContext;
      if (!C) return null;
      audioCtx = new C();
    }
    if (audioCtx.state === "suspended") audioCtx.resume();
    return audioCtx;
  }

  function beep(freq, dur, vol, type) {
    var c = ctx(); if (!c) return;
    var t = c.currentTime, o = c.createOscillator(), g = c.createGain();
    o.type = type || "square";
    o.frequency.setValueAtTime(freq, t);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + 0.004);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(c.destination);
    o.start(t); o.stop(t + dur + 0.02);
  }

  /* --------------------------------------------------------------- engine */

  /* Speed profile: hold a constant speed for the first CRUISE of the spin so
     every option is legibly seen going past, then decelerate smoothly to rest.
       v(t) = v0                            t <= p
       v(t) = v0 * (1 - u)^2, u=(t-p)/(1-p) t >  p
     Integrated and normalised so s(0)=0, s(1)=1. */
  var CRUISE = 0.45;
  var V0 = 1 / (CRUISE + (1 - CRUISE) / 3);

  function progress(t) {
    if (t <= CRUISE) return V0 * t;
    var u = (t - CRUISE) / (1 - CRUISE);
    return V0 * CRUISE + V0 * (1 - CRUISE) * (u - u * u + (u * u * u) / 3);
  }

  function createSpinner(root) {
    var d = root.dataset;

    var options = [];
    try { options = JSON.parse(d.options || "[]"); } catch (e) { options = []; }

    if (!options.length) {
      root.appendChild(el("p", "sp-error",
        "spinner: this div has no list items, so there is nothing to draw from."));
      return;
    }

    var cfg = {
      duration:   parseMs(d.duration, 6000),
      cycles:     Math.max(1, Math.round(parseNum(d.cycles, 3))),
      rows:       Math.max(1, Math.round(parseNum(d.rows, 3))) | 1,  // keep odd
      blur:       Math.max(0, parseNum(d.blur, 2)),
      sound:      parseBool(d.sound, true),
      keepDrawn:  parseBool(d.keepDrawn, true),
      shuffleReel: parseBool(d.shuffleReel, false),
      results:    (d.results || "right").toLowerCase(),
      resultsTitle: d.resultsTitle || "Assignments",
      buttonLabel: d.buttonLabel || "SPIN",
      groupLabel: d.groupLabel || "Group"
    };

    /* who the draws are for: a count ("9") or explicit labels ("Ana, Ben") */
    var groups;
    if (d.groups && /^\d+$/.test(d.groups.trim())) {
      groups = [];
      for (var i = 1; i <= parseInt(d.groups, 10); i++) groups.push(cfg.groupLabel + " " + i);
    } else if (d.groups) {
      groups = csv(d.groups);
    } else {
      groups = options.map(function (_, i) { return cfg.groupLabel + " " + (i + 1); });
    }

    /* ---- theming: presets are CSS classes, fine-tuning is CSS variables ---- */
    root.classList.add("sp-theme-" + (d.theme || "classic"));
    root.classList.add("sp-results-" + cfg.results);
    if (d.accent) root.style.setProperty("--sp-accent", d.accent);
    if (d.rowHeight) root.style.setProperty("--sp-row-h", withUnit(d.rowHeight));
    if (d.fontSize) root.style.setProperty("--sp-font", withUnit(d.fontSize));
    root.style.setProperty("--sp-rows", cfg.rows);

    /* ------------------------------- markup ------------------------------- */
    var layout  = el("div", "sp-layout");
    var main    = el("div", "sp-main");
    var label   = el("div", "sp-label");
    var machine = el("div", "sp-machine");
    var win     = el("div", "sp-window");
    var strip   = el("div", "sp-strip");
    var band    = el("div", "sp-band");
    var ptrL    = el("i", "sp-ptr sp-ptr-l");
    var ptrR    = el("i", "sp-ptr sp-ptr-r");
    var ctrls   = el("div", "sp-controls");
    var bSpin   = el("button", "sp-btn sp-spin", cfg.buttonLabel);
    var bReset  = el("button", "sp-btn sp-ghost sp-reset", "Reset");
    var bMute   = el("button", "sp-btn sp-ghost sp-mute", "🔊");
    var status  = el("div", "sp-status");
    var side    = el("div", "sp-side");
    var list    = el("ol", "sp-list");

    win.appendChild(strip);
    machine.appendChild(win); machine.appendChild(band);
    machine.appendChild(ptrL); machine.appendChild(ptrR);
    ctrls.appendChild(bSpin); ctrls.appendChild(bReset); ctrls.appendChild(bMute);
    main.appendChild(label); main.appendChild(machine);
    main.appendChild(ctrls); main.appendChild(status);
    side.appendChild(el("h3", "sp-side-title", cfg.resultsTitle));
    side.appendChild(list);
    layout.appendChild(main);
    if (cfg.results !== "none") layout.appendChild(side);

    root.innerHTML = "";
    root.appendChild(layout);

    bReset.title = "Re-shuffle and start again";
    bMute.title  = "Sound on/off";
    bSpin.setAttribute("aria-label", "Draw the next option");

    /* ------------------------------- state -------------------------------- */
    var deckOrder = [];   // the shuffled draw order, fixed before the first spin
    var drawn = 0;
    var spinning = false;
    var soundOn = cfg.sound;
    var summaries = root.id
      ? document.querySelectorAll('.spinner-summary[data-for="' + root.id + '"]')
      : [];

    function rowH() {
      var v = parseFloat(getComputedStyle(root).getPropertyValue("--sp-row-h"));
      return v || 110;
    }
    var HALF = Math.floor(cfg.rows / 2);

    function tick()    { if (soundOn) beep(1150, 0.045, 0.05, "square"); }
    function fanfare() {
      if (!soundOn) return;
      [[523, 0], [659, 110], [784, 220], [1047, 330]].forEach(function (p) {
        setTimeout(function () { beep(p[0], 0.22, 0.09, "triangle"); }, p[1]);
      });
    }

    function assignedSet() {
      var s = {};
      for (var i = 0; i < drawn; i++) s[deckOrder[i]] = true;
      return s;
    }

    /* The reel is the whole option list, repeated. Every option therefore
       passes the window on every cycle — nothing is hidden from the audience.
       Already-drawn options stay on the reel but are struck through, unless
       keep-drawn="false", in which case they leave the reel entirely. */
    function reelOrder() {
      var base = cfg.keepDrawn
        ? options
        : options.filter(function (t) { return !assignedSet()[t]; });
      if (!base.length) base = options;
      return cfg.shuffleReel ? shuffle(base) : base.slice();
    }

    function buildStrip(winner, cycles) {
      var order = reelOrder();
      var L = order.length;
      var pos = order.indexOf(winner);
      if (pos < 0) { order = order.concat([winner]); pos = order.length - 1; L = order.length; }

      var items = [];
      for (var h = 0; h < HALF; h++) items.push(order[(L - HALF + h + L) % L]);  // headroom
      for (var c = 0; c < cycles; c++) items = items.concat(order);
      for (var i = 0; i <= pos; i++) items.push(order[i]);
      for (var j = 1; j <= HALF + 1; j++) items.push(order[(pos + j) % L]);

      var winnerIdx = HALF + cycles * L + pos;
      var taken = assignedSet();

      strip.innerHTML = "";
      var winnerEl = null;
      items.forEach(function (t, k) {
        var node = el("div", "sp-item", t);
        if (taken[t]) node.classList.add("sp-taken");
        if (k === winnerIdx) { node.classList.remove("sp-taken"); winnerEl = node; }
        strip.appendChild(node);
      });

      return { winnerEl: winnerEl, distance: (winnerIdx - HALF) * rowH() };
    }

    function setY(y) { strip.style.transform = "translateY(" + (-y) + "px)"; }

    /* Resting state. Deliberately centres a *random* option rather than the
       next card off the deck — parking the upcoming winner under the band
       would give the answer away before the spin. */
    function idle() {
      machine.classList.remove("sp-landed");
      strip.style.filter = "none";
      var built = buildStrip(options[randInt(options.length)], 0);
      setY(built.distance);
    }

    /* -------------------------------- spin -------------------------------- */
    function spin() {
      if (spinning) return;
      if (drawn >= groups.length || drawn >= deckOrder.length) return;

      spinning = true;
      bSpin.disabled = true;
      bReset.disabled = true;
      machine.classList.remove("sp-landed");
      machine.classList.add("sp-spinning");

      var winner = deckOrder[drawn];
      var built = buildStrip(winner, cfg.cycles);
      var target = built.distance;
      var h = rowH();
      var t0 = performance.now(), lastY = 0, lastRow = -1;

      function frame(now) {
        var t = Math.min(1, (now - t0) / cfg.duration);
        var y = target * progress(t);
        setY(y);

        if (cfg.blur > 0) {
          var speed = y - lastY;                  // px this frame
          strip.style.filter = "blur(" + Math.min(cfg.blur, speed * 0.2).toFixed(2) + "px)";
        }
        lastY = y;

        var row = Math.round(y / h);
        if (row !== lastRow) { lastRow = row; tick(); }

        if (t < 1) requestAnimationFrame(frame);
        else land(built.winnerEl, target, winner);
      }
      requestAnimationFrame(frame);
    }

    function land(winnerEl, target, winner) {
      strip.style.filter = "none";
      machine.classList.remove("sp-spinning");
      // settle like a real reel: a hair past the stop, then spring back
      strip.style.transition = "transform .1s ease-out";
      setY(target + 13);
      setTimeout(function () {
        strip.style.transition = "transform .26s cubic-bezier(.34,1.4,.64,1)";
        setY(target);
        setTimeout(function () {
          strip.style.transition = "";
          if (winnerEl) winnerEl.classList.add("sp-won");
          machine.classList.add("sp-landed");
          fanfare();
          record(groups[drawn], winner);
          drawn++;
          spinning = false;
          bReset.disabled = false;
          refresh();
          root.dispatchEvent(new CustomEvent("spinner:drawn", {
            bubbles: true, detail: { group: groups[drawn - 1], option: winner, index: drawn - 1 }
          }));
        }, 270);
      }, 100);
    }

    /* ------------------------------ results ------------------------------- */
    function record(group, option) {
      var li = el("li", "sp-row");
      li.appendChild(el("span", "sp-g", group + ":"));
      li.appendChild(el("span", "sp-t", option));
      list.appendChild(li);

      Array.prototype.forEach.call(summaries, function (s) {
        var row = el("div", "sp-row");
        row.appendChild(el("span", "sp-g", group + ":"));
        row.appendChild(el("span", "sp-t", option));
        s.querySelector(".sp-summary-body").appendChild(row);
        s.classList.add("sp-has-rows");
      });
    }

    function refresh() {
      var groupsLeft = groups.length - drawn;
      var optionsLeft = deckOrder.length - drawn;
      var done = groupsLeft <= 0 || optionsLeft <= 0;

      bSpin.disabled = done || spinning;
      label.textContent = done ? "All done" : groups[drawn];

      if (groupsLeft <= 0) {
        status.textContent = "Every draw has been made.";
      } else if (optionsLeft <= 0) {
        status.textContent = "Out of options — add more to the list.";
      } else {
        status.textContent = "Shuffled at load · " + optionsLeft +
          (optionsLeft === 1 ? " option" : " options") + " left";
      }
    }

    function reset() {
      if (spinning) return;
      deckOrder = shuffle(options);
      drawn = 0;
      list.innerHTML = "";
      Array.prototype.forEach.call(summaries, function (s) {
        s.querySelector(".sp-summary-body").innerHTML = "";
        s.classList.remove("sp-has-rows");
      });
      idle();
      refresh();
    }

    bSpin.addEventListener("click", spin);
    machine.addEventListener("click", function () { if (!bSpin.disabled) spin(); });
    bReset.addEventListener("click", reset);
    bMute.addEventListener("click", function () {
      soundOn = !soundOn;
      bMute.textContent = soundOn ? "🔊" : "🔇";
      bMute.classList.toggle("sp-off", !soundOn);
    });

    if (!soundOn) { bMute.textContent = "🔇"; bMute.classList.add("sp-off"); }
    reset();
  }

  function prepareSummary(node) {
    var title = node.dataset.title;
    node.innerHTML = "";
    if (title) node.appendChild(el("h3", "sp-side-title", title));
    var body = el("div", "sp-summary-body");
    if (node.dataset.columns) {
      body.style.gridTemplateColumns = "repeat(" + parseNum(node.dataset.columns, 2) + ", 1fr)";
    }
    node.appendChild(body);
  }

  return {
    id: "spinner",
    init: function (deck) {
      var scope = deck.getRevealElement() || document;
      Array.prototype.forEach.call(
        scope.querySelectorAll(".spinner-summary"), prepareSummary);
      Array.prototype.forEach.call(
        scope.querySelectorAll(".spinner-machine"), createSpinner);
    }
  };
};
