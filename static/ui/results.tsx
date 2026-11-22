// The header search's list: a row per hit, then a note when none match
// or more match than are shown.

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
  /** where the terms matched, set by match() */
  why?: string;
}

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
      <a id={"results-" + k} role="option" tabIndex={-1} href={e.u}>
        <span class="n"><Marked text={e.t} terms={terms} />{e.o ? <span class="official">Official</span> : null}{e.b ? <span class="tag bin">bin</span> : null}</span>
        <span class="vw">
          <span class="why">{"in " + (e.why ?? "")}</span>
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
      {fixed && hits.length ? <li role="none" class="fixed">Showing results for <q>{fixed}</q></li> : null}
      {hits.slice(0, MAX).map((e, k) => <Row e={e} k={k} terms={terms} />)}
      {!hits.length ? (
        <li role="none" class="empty">{published ? "No packages match." : "No packages published yet."}</li>
      ) : hits.length > MAX ? (
        <li role="none" class="all">{`${hits.length} packages match. Press Enter to see all.`}</li>
      ) : null}
    </>
  );
}
