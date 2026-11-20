import { CopyButton } from "./copy-button.tsx";

// The frame of a code block in readmes and the guide: a bar with the
// language and Copy. The caller moves the <pre> in after the bar.
export function CodeBlock({ lang, text }: { lang: string; text: string }) {
  return (
    <figure class="cb">
      <div class="cb-h">
        <span class="t-label">{lang && lang !== "text" ? lang : ""}</span>
        <CopyButton text={text} />
      </div>
    </figure>
  );
}
