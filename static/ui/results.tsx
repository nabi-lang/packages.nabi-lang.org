// The header search's list: a row per hit, then a note when none match
// or more match than are shown.

import type { ComponentChildren } from "preact";
import { dir, lang, type Code } from "../../web/js/lang/lang.ts";

/** One line of search-index.json. */
export interface Entry {
  /** name */
  t: string;
  /** canonical path */
  u: string;
  /** latest version */
  v: string;
  /** description */
  p: string;
  /** keywords */
  k?: string[];
  /** 1: an official package */
  o?: 1;
  /** 1: it has an executable */
  b?: 1;
  /** where the terms matched (`name`, `description`, `keywords`), set by match() */
  why?: string[];
}

/** The page's language (`<html lang>`, web/js/lang). */
export const LANG: Code = lang();

/** `p` (root-relative) on the pages in the page's language: `/ko/..`, `/zh-hans/..`. */
export const at = (p: string): string => (LANG === "en" ? p : "/" + dir(LANG).slice(0, -1) + p);

/** The page's words, by language. */
export const SAY: Record<Code, {
  where: Record<string, string>;
  why: (words: string[]) => string;
  official: string;
  fixed: (q: string) => ComponentChildren;
  none: string;
  empty: string;
  more: (n: number) => string;
  status: (n: number, fixed: string) => string;
}> = {
  en: {
    where: { name: "name", description: "description", keywords: "keywords" },
    why: (w) => "in " + (w.length === 3 ? "name, description and keywords" : w.join(" and ")),
    official: "Official",
    fixed: (q) => <>Showing results for <q>{q}</q></>,
    none: "No packages match.",
    empty: "No packages published yet.",
    more: (n) => `${n} packages match. Press Enter to see all.`,
    status: (n, f) => {
      const t = !n ? "No packages match" : n === 1 ? "1 package" : `${n} packages`;
      return f && n ? `${t} for ${f}` : t;
    },
  },
  ko: {
    where: { name: "이름", description: "설명", keywords: "키워드" },
    why: (w) => w.join(", ") + "에서",
    official: "공식",
    fixed: (q) => <><q>{q}</q>의 결과입니다</>,
    none: "맞는 패키지가 없습니다.",
    empty: "아직 공개된 패키지가 없습니다.",
    more: (n) => `패키지 ${n}개가 맞습니다. Enter를 누르면 모두 봅니다.`,
    status: (n, f) => {
      const t = !n ? "맞는 패키지가 없습니다" : `패키지 ${n}개`;
      return f && n ? `${f}: ${t}` : t;
    },
  },
  "zh-Hans": {
    where: { name: "名称", description: "描述", keywords: "关键词" },
    why: (w) => "匹配" + w.join("、"),
    official: "官方",
    fixed: (q) => <>以下是 <q>{q}</q> 的结果</>,
    none: "没有匹配的包。",
    empty: "还没有发布任何包。",
    more: (n) => `${n} 个包匹配。按 Enter 查看全部。`,
    status: (n, f) => {
      const t = !n ? "没有匹配的包" : `${n} 个包`;
      return f && n ? `${f}：${t}` : t;
    },
  },
  "zh-Hant": {
    where: { name: "名稱", description: "描述", keywords: "關鍵字" },
    why: (w) => "符合" + w.join("、"),
    official: "官方",
    fixed: (q) => <>以下是 <q>{q}</q> 的結果</>,
    none: "沒有符合的套件。",
    empty: "還沒有發布任何套件。",
    more: (n) => `${n} 個套件符合。按 Enter 查看全部。`,
    status: (n, f) => {
      const t = !n ? "沒有符合的套件" : `${n} 個套件`;
      return f && n ? `${f}：${t}` : t;
    },
  },
};

const T = SAY[LANG];

/** Where the terms matched, in words: "in name and keywords", "이름, 키워드에서". */
export const whyText = (why: string[]): string => T.why(why.map((w) => T.where[w] ?? w));

/** Rows shown; the rest are behind Enter (packages/?q=). */
export const MAX = 8;

// The part of a description worth showing in one line: from a little
// before the first matched term when it would be cut off.
const snippet = (text: string, terms: string[]): string => {
  const lo = text.toLowerCase();
  let at = -1;
  for (const w of terms) {
    const k = lo.indexOf(w);
    if (k >= 0 && (at < 0 || k < at)) at = k;
  }
  if (at < 48) return text;
  const from = text.lastIndexOf(" ", at - 20);
  return "..." + text.slice(from < 0 ? at - 20 : from + 1);
};

// `text` with each term wrapped in <mark>.
function Marked({ text, terms }: { text: string; terms: string[] }) {
  const words = terms.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  if (!words.length) return <>{text}</>;
  const re = new RegExp(`(${words.join("|")})`, "gi");
  return <>{text.split(re).map((part, k) => (k % 2 === 0 ? part : <mark>{part}</mark>))}</>;
}

function Row({ e, k, terms }: { e: Entry; k: number; terms: string[] }) {
  return (
    <li role="none">
      <a id={"results-" + k} role="option" tabIndex={-1} href={at(e.u)}>
        <span class="n"><Marked text={e.t} terms={terms} />{e.o ? <span class="official">{T.official}</span> : null}{e.b ? <span class="tag bin">bin</span> : null}</span>
        <span class="vw">
          <span class="why">{whyText(e.why ?? [])}</span>
          <span class="v">{e.v}</span>
        </span>
        {e.p ? <small><Marked text={snippet(e.p, terms)} terms={terms} /></small> : null}
      </a>
    </li>
  );
}

/** `published`: the index has any packages at all; `fixed`: the
 * corrected query the hits are for, when the typed one matched nothing. */
export function Results({ hits, terms, published, fixed = "" }: { hits: Entry[]; terms: string[]; published: boolean; fixed?: string }) {
  return (
    <>
      {fixed && hits.length ? <li role="none" class="fixed">{T.fixed(fixed)}</li> : null}
      {hits.slice(0, MAX).map((e, k) => <Row e={e} k={k} terms={terms} />)}
      {!hits.length ? (
        <li role="none" class="empty">{published ? T.none : T.empty}</li>
      ) : hits.length > MAX ? (
        <li role="none" class="all">{T.more(hits.length)}</li>
      ) : null}
    </>
  );
}
