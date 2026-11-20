// Header menu, package search, code block bars, install tabs. The theme
// is theme.js, the search shortcut keys.js and Copy copy.js, from the
// web kit. The markup it builds is ui/*.tsx (Preact).

import { render } from "preact";
import { CodeBlock } from "./ui/code-block.tsx";
import { MAX, Results, type Entry } from "./ui/results.tsx";

(() => {
  let index: Entry[] | null = null;
  const load = (): Promise<Entry[]> =>
    index ? Promise.resolve(index)
      : fetch("/search-index.json").then((r) => r.json() as Promise<Entry[]>).then((d) => (index = d));

  // Run f and ease el's size to the result (copy.js, the web kit).
  const resize = (el: HTMLElement, f: () => void): void => (window.nabiResize ? window.nabiResize(el, f) : f());

  // Narrow header: the menu button shows the nav below.
  const hdr = document.querySelector<HTMLElement>(".hdr");
  const menu = document.querySelector<HTMLButtonElement>(".hdr .menu");
  if (hdr && menu) {
    const set = (open: boolean): void => {
      hdr.classList.toggle("open", open);
      menu.setAttribute("aria-expanded", open ? "true" : "false");
    };
    menu.addEventListener("click", () => set(!hdr.classList.contains("open")));
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && hdr.classList.contains("open")) { set(false); menu.focus(); }
    });
  }

  // Code blocks in readmes and the guide: a bar with the language and Copy.
  for (const pre of document.querySelectorAll<HTMLPreElement>(".md pre")) {
    const lang = pre.querySelector("code")?.className.match(/language-(\w+)/)?.[1] ?? "";
    const host = document.createDocumentFragment();
    render(<CodeBlock lang={lang} text={(pre.textContent ?? "").replace(/\n$/, "")} />, host);
    const fig = host.firstChild;
    if (!(fig instanceof HTMLElement)) continue;
    pre.replaceWith(fig);
    fig.append(pre);
  }

  // Install boxes: tabs (their Copy buttons are the page's own).
  for (const box of document.querySelectorAll<HTMLElement>(".inst")) {
    const tabs = [...box.querySelectorAll<HTMLElement>(".itabs [role=tab]")];
    const pick = (t: HTMLElement, focus: boolean): void => {
      // The panels differ in height: the box eases to the new one.
      resize(box, () => {
        for (const x of tabs) {
          const on = x === t;
          x.setAttribute("aria-selected", on ? "true" : "false");
          x.tabIndex = on ? 0 : -1;
          document.getElementById(x.getAttribute("aria-controls") ?? "")?.classList.toggle("on", on);
        }
        // The `use` line is the library's: not under `nabi install`.
        box.querySelector(".iuse")?.toggleAttribute("hidden", t.dataset["bin"] === "1");
      });
      if (focus) t.focus();
    };
    tabs.forEach((t, k) => {
      t.addEventListener("click", () => pick(t, false));
      t.addEventListener("keydown", (e) => {
        const d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
        const next = tabs[(k + d + tabs.length) % tabs.length];
        if (d && next) { e.preventDefault(); pick(next, true); }
      });
    });
  }

  // Package tabs: keep the current one in view, fade an edge with more beyond.
  const bar = document.querySelector<HTMLElement>(".package-head .tabs");
  if (bar) {
    const cur = bar.querySelector("[aria-current]");
    if (cur) {
      // 40px: clear of the fade.
      const a = cur.getBoundingClientRect(), b = bar.getBoundingClientRect();
      if (a.right > b.right - 40) bar.scrollLeft += a.right - b.right + 40;
    }
    const edges = (): void => {
      const max = bar.scrollWidth - bar.clientWidth;
      bar.classList.toggle("more-l", bar.scrollLeft > 1);
      bar.classList.toggle("more-r", bar.scrollLeft < max - 1);
    };
    bar.addEventListener("scroll", edges, { passive: true });
    addEventListener("resize", edges);
    edges();
  }

  // 404.html: name the missing path.
  const lost = document.getElementById("lost-path");
  if (lost) lost.textContent = location.pathname;

  // Every term must be in the name, the description or a keyword, and
  // `official:yes` / `official:no` filters; `why` says where they were
  // found. Official packages come first among equals. layout.nabi's
  // search ranks the same way.
  const match = (data: Entry[], query: string): [Entry[], string[]] => {
    const words = query.toLowerCase().split(/\s+/).filter(Boolean);
    let only = "";
    for (const w of words) {
      if (!w.startsWith("official:")) continue;
      const v = w.slice(9);
      only = v === "yes" || v === "true" ? "yes" : v === "no" || v === "false" ? "no" : only;
    }
    const terms = words.filter((w) => !w.startsWith("official:"));
    const q = terms.join(" ");
    const hits: [number, Entry][] = [];
    for (const e of data) {
      if ((only === "yes" && !e.o) || (only === "no" && e.o)) continue;
      const t = e.t.toLowerCase();
      const p = e.p.toLowerCase();
      const ks = (e.k ?? []).map((k) => k.toLowerCase());
      const inKw = (w: string): boolean => ks.some((k) => k.includes(w));
      if (!terms.every((w) => t.includes(w) || p.includes(w) || inKw(w))) continue;
      const where: string[] = [];
      if (terms.some((w) => t.includes(w))) where.push("name");
      if (terms.some((w) => p.includes(w))) where.push("description");
      if (terms.some(inKw)) where.push("keywords");
      e.why = where.length === 3 ? "name, description and keywords" : where.join(" and ");
      hits.push([t === q ? 0 : t.startsWith(q) ? 1 : t.includes(q) ? 2 : ks.includes(q) ? 3 : 4, e]);
    }
    hits.sort((a, b) => a[0] - b[0] || (b[1].o ?? 0) - (a[1].o ?? 0) || a[1].t.localeCompare(b[1].t));
    return [hits.map((h) => h[1]), terms];
  };

  // Header search: a combobox over the index; Enter without a pick opens
  // the full list filtered (packages/?q=).
  const form = document.querySelector<HTMLFormElement>(".hdr .search");
  const q = form?.querySelector<HTMLInputElement>(".q");
  const box = form?.querySelector<HTMLUListElement>(".results");
  const status = form?.querySelector<HTMLElement>("[role=status]");
  if (form && q && box && status) {
    let sel = -1;
    const opts = (): HTMLAnchorElement[] => [...box.querySelectorAll<HTMLAnchorElement>("[role=option]")];
    const mark = (i: number): void => {
      const as = opts();
      as.forEach((a, k) => a.setAttribute("aria-selected", k === i ? "true" : "false"));
      sel = i;
      const a = as[i];
      if (a) {
        q.setAttribute("aria-activedescendant", a.id);
        a.scrollIntoView({ block: "nearest" });
      } else {
        q.removeAttribute("aria-activedescendant");
      }
    };
    const show = (on: boolean): void => {
      box.hidden = !on;
      q.setAttribute("aria-expanded", on ? "true" : "false");
      if (!on) { q.removeAttribute("aria-activedescendant"); sel = -1; }
    };
    const fill = (hits: Entry[], terms: string[], data: Entry[]): void =>
      render(<Results hits={hits} terms={terms} published={data.length > 0} />, box);
    const search = async (): Promise<void> => {
      const query = q.value.trim();
      if (!query) { show(false); status.textContent = ""; return; }
      const data = await load();
      const [hits, terms] = match(data, query);
      // An open list eases to its new length; a closed one fades in (.appear).
      if (box.hidden) fill(hits, terms, data);
      else resize(box, () => fill(hits, terms, data));
      show(true);
      status.textContent = !hits.length ? "No packages match" : hits.length === 1 ? "1 package" : `${hits.length} packages`;
      mark(-1);
    };
    q.addEventListener("focus", () => void load(), { once: true });
    q.addEventListener("input", () => void search());
    q.addEventListener("keydown", (ev) => {
      const n = opts().length;
      const picked = opts()[sel];
      if (ev.key === "ArrowDown" && n) { ev.preventDefault(); mark((sel + 1) % n); }
      else if (ev.key === "ArrowUp" && n) { ev.preventDefault(); mark((sel - 1 + n) % n); }
      else if (ev.key === "Enter" && picked) { ev.preventDefault(); location.href = picked.href; }
      else if (ev.key === "Escape") { if (!box.hidden) show(false); else q.blur(); }
    });
    document.addEventListener("click", (ev) => {
      if (!(ev.target instanceof Node) || !form.contains(ev.target)) show(false);
    });

    // The full list is filtered and sorted by the server (?q=, ?sort=);
    // a new order applies as soon as it is picked.
    const sort = document.getElementById("list-sort");
    if (sort instanceof HTMLSelectElement) sort.addEventListener("change", () => sort.form?.submit());
  }
})();
