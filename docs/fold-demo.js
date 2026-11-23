// Interactive folding demo: a tiny read-only "editor" whose fold ribbon collapses headings and bracket blocks.
(() => {
  const SOURCE = `#set page(paper: "a4", margin: 2.2cm)
#set heading(numbering: "1.")

= Write without friction <write>
Completion comes from the Typst engine itself:
variables, imported functions and labels
that are actually in scope.

$ sum_(k=1)^n k = (n (n + 1)) / 2 $ <gauss>

== Spelling
Checked in the language of #text(lang: "en")[..],
and never inside math.

= Tables like Numbers <tables>
#figure(
  table(
    columns: 3,
    table.header([*Action*], [*Menu*], [*Key*]),
    [Open Quickly], [Navigate], [⇧⌘O],
    [Go to Line], [Navigate], [⌘L],
  ),
  caption: [Made in the table editor.],
) <shortcuts>

= Ship it <ship>
Export to PDF, PDF/A, PDF/UA-1, PNG or SVG.`;

  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  function highlight(line) {
    const h = line.match(/^(=+)\s/);
    if (h) {
      return `<span class="t-head">${esc(line).replace(/(&lt;[\w:-]+&gt;)/, '<span class="t-lbl">$1</span>')}</span>`;
    }
    const rules = [
      [/^"[^"]*"/, "t-str"],
      [/^<[\w:-]+>/, "t-lbl"],
      [/^\$[^$]*\$/, "t-math"],
      [/^#(set|show|let|import|include)\b/, "t-kw"],
      [/^#?[a-z][\w.-]*(?=\()/, "t-fn"],
      [/^\d+(\.\d+)?/, "t-num"],
      [/^\*[^*\]]+\*/, "t-strong"],
      [/^[\[\](),:]/, "t-punct"],
    ];
    let out = "", rest = line;
    while (rest.length) {
      let hit = null;
      for (const [re, cls] of rules) {
        const m = rest.match(re);
        if (m && m[0].length) { hit = [m[0], cls]; break; }
      }
      if (hit) {
        out += `<span class="${hit[1]}">${esc(hit[0])}</span>`;
        rest = rest.slice(hit[0].length);
        const unit = hit[1] === "t-num" && rest.match(/^(cm|mm|pt|em|fr|deg|%)/);
        if (unit) { out += `<span class="t-unit">${unit[0]}</span>`; rest = rest.slice(unit[0].length); }
      }
      else { out += esc(rest[0]); rest = rest.slice(1); }
    }
    return out;
  }

  // Fold regions: a heading runs to the next heading of its level or higher (trailing blank lines stay outside);
  // a line ending in "(" runs to the ")" line at its indentation, which stays visible.
  function regions(lines) {
    const out = [];
    lines.forEach((l, i) => {
      const h = l.match(/^(=+)\s/);
      if (h) {
        let end = lines.length - 1;
        for (let j = i + 1; j < lines.length; j++) {
          const k = lines[j].match(/^(=+)\s/);
          if (k && k[1].length <= h[1].length) { end = j - 1; break; }
        }
        while (end > i && !lines[end].trim()) end--;
        if (end > i) out.push({ start: i, end, kind: "heading" });
      } else if (/\($/.test(l)) {
        const indent = l.match(/^\s*/)[0].length;
        for (let j = i + 1; j < lines.length; j++) {
          if (lines[j].match(/^\s*/)[0].length === indent && /^\s*\)/.test(lines[j])) {
            if (j - 1 > i) out.push({ start: i, end: j - 1, kind: "bracket" });
            break;
          }
        }
      }
    });
    return out;
  }

  function build(root) {
    const lines = SOURCE.split("\n");
    const regs = regions(lines);
    const innermost = (i) => regs.filter((r) => i >= r.start && i <= r.end)
      .sort((a, b) => (a.end - a.start) - (b.end - b.start))[0];
    const depth = (i) => regs.filter((r) => i >= r.start && i <= r.end).length;

    const code = document.createElement("div");
    code.className = "fd-code";
    code.setAttribute("role", "group");
    code.setAttribute("aria-label", "Typst source with foldable sections");

    const lineEls = [];
    function lineEl(i) {
      const el = document.createElement("div");
      el.className = "fd-line";
      el.dataset.i = i;
      const r = innermost(i);
      const d = depth(i);
      const rib = document.createElement("span");
      rib.className = "fd-rib";
      if (r) {
        rib.style.setProperty("--a", (0.06 + 0.07 * d).toFixed(2));
        if (r.start === i) rib.classList.add("top");
        if (r.end === i) rib.classList.add("bottom");
      }
      el.innerHTML = `<span class="fd-num">${i + 1}</span>`;
      if (i === 0) el.classList.add("current");
      el.appendChild(rib);
      const txt = document.createElement("span");
      txt.className = "fd-text";
      txt.innerHTML = (i === 0 ? '<span class="fd-caret" aria-hidden="true"></span>' : "") + (highlight(lines[i]) || "&#8203;");
      el.appendChild(txt);
      lineEls[i] = el;
      return el;
    }

    function render(from, to, parent) {
      for (let i = from; i <= to; i++) {
        const r = regs.find((x) => x.start === i && x.end <= to && x !== parent);
        if (!r) { code.__target.appendChild(lineEl(i)); continue; }
        const head = lineEl(i);
        head.classList.add("fd-head");
        const toggle = document.createElement("button");
        toggle.className = "fd-toggle";
        toggle.type = "button";
        toggle.setAttribute("aria-expanded", "true");
        toggle.setAttribute("aria-label", `Fold lines ${r.start + 2} to ${r.end + 1}`);
        toggle.innerHTML = '<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M3.5 1.8 6.7 5 3.5 8.2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        const badge = document.createElement("span");
        badge.className = "fd-badge";
        const n = r.end - r.start;
        badge.textContent = r.kind === "heading" ? `⋯ ${n} ${n === 1 ? "line" : "lines"}` : "···";
        if (r.kind === "bracket") badge.classList.add("block");
        head.querySelector(".fd-text").appendChild(badge);
        head.prepend(toggle);
        code.__target.appendChild(head);

        const body = document.createElement("div");
        body.className = "fd-body";
        const inner = document.createElement("div");
        inner.className = "fd-inner";
        body.appendChild(inner);
        code.__target.appendChild(body);
        const saved = code.__target;
        code.__target = inner;
        render(i + 1, r.end, r);
        code.__target = saved;

        r.head = head; r.body = body; r.toggle = toggle; r.badge = badge;
        const flip = () => setFolded(r, !r.folded);
        toggle.addEventListener("click", flip);
        badge.addEventListener("click", flip);
        i = r.end;
      }
    }
    code.__target = code;
    render(0, lines.length - 1, null);
    delete code.__target;

    function setFolded(r, folded) {
      r.folded = folded;
      r.head.classList.toggle("folded", folded);
      r.body.classList.toggle("folded", folded);
      r.toggle.setAttribute("aria-expanded", String(!folded));
      r.toggle.setAttribute("aria-label", `${folded ? "Unfold" : "Fold"} lines ${r.start + 2} to ${r.end + 1}`);
    }

    // The ribbon: hovering a line lights up its innermost region; clicking folds it.
    function regionAt(target) {
      const line = target.closest(".fd-line");
      return line ? innermost(Number(line.dataset.i)) : null;
    }
    let hot = null;
    function setHot(r) {
      if (hot === r) return;
      if (hot) for (let i = hot.start; i <= hot.end; i++) lineEls[i].classList.remove("hot");
      hot = r;
      if (hot) for (let i = hot.start; i <= hot.end; i++) lineEls[i].classList.add("hot");
    }
    code.addEventListener("mousemove", (e) => setHot(e.target.closest(".fd-rib") ? regionAt(e.target) : null));
    code.addEventListener("mouseleave", () => setHot(null));
    code.addEventListener("click", (e) => {
      if (!e.target.closest(".fd-rib")) return;
      const r = regionAt(e.target);
      if (r && r.head) { setFolded(r, !r.folded); interacted = true; }
    });
    let interacted = false;
    code.addEventListener("pointerdown", () => { interacted = true; });

    root.querySelector(".fd-window").appendChild(code);

    const all = (folded) => regs.filter((r) => r.kind === "heading" && r.head).forEach((r) => setFolded(r, folded));
    root.querySelector("[data-fold-all]")?.addEventListener("click", () => { interacted = true; all(true); });
    root.querySelector("[data-unfold-all]")?.addEventListener("click", () => { interacted = true; all(false); });

    // One unprompted fold and unfold when the demo first scrolls into view, so it is clear what it does.
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
    const fig = regs.find((r) => r.kind === "bracket" && r.head);
    if (!reduce && fig && "IntersectionObserver" in window) {
      const io = new IntersectionObserver((entries) => {
        if (!entries.some((e) => e.isIntersecting)) return;
        io.disconnect();
        setTimeout(() => { if (!interacted) setFolded(fig, true); }, 900);
        setTimeout(() => { if (!interacted) setFolded(fig, false); }, 2600);
      }, { threshold: 0.6 });
      io.observe(root);
    }
  }

  document.querySelectorAll(".fold-demo").forEach(build);
})();
