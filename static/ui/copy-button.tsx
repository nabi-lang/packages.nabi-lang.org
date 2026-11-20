// A Copy button for copy.js (the web kit), as chrome::copy_button writes it.
export function CopyButton({ text }: { text: string }) {
  return (
    <button type="button" class="btn-2 btn-sm copy" data-copy={text} aria-label="Copy">
      Copy
    </button>
  );
}
