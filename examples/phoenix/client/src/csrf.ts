// Phoenix renders the HTML shell with `<meta name="csrf-token">` (the same
// mechanism LiveView's app.js uses). This is the single place the SPA reads it.
export const csrfToken =
  document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? "";
