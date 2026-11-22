// A Copy button for copy.js (the web kit), as chrome::copy_button writes it.
export function CopyButton({ text }: { text: string }) {
  const label = document.documentElement.lang === "ko" ? "복사" : "Copy";
  return (
    <button type="button" class="btn-2 btn-sm copy" data-copy={text} aria-label={label}>
      {label}
    </button>
  );
}
