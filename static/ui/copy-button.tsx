// A Copy button for copy.js (the web kit), as chrome::copy_button writes it.

import { lang, type Code } from "../../web/js/lang/lang.ts";

const LABEL: Record<Code, string> = { en: "Copy", ko: "복사", "zh-Hans": "复制", "zh-Hant": "複製" };

export function CopyButton({ text }: { text: string }) {
  const label = LABEL[lang()];
  return (
    <button type="button" class="btn-2 btn-sm copy" data-copy={text} aria-label={label}>
      {label}
    </button>
  );
}
