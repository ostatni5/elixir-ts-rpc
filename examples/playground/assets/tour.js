// A scripted walkthrough. The point it has to land: a change on the Elixir side
// turns into a TypeScript error, without anyone running a build.
//
// Steps are indexed and each one declares which *source variant* it belongs to
// rather than an incremental edit, so navigating backwards is just re-applying a
// known state. Typing is animated only when you walk forward into the step that
// owns the change.

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const KEYSTROKE_MS = 34;

const RENAME_EDITS = [
  ["email: String\\.t\\(\\)", "email_address: String.t()"],
  ['email: "ada@example\\.com"', 'email_address: "ada@example.com"'],
];

const REVERT_EDITS = RENAME_EDITS.map(([from, to]) => [
  to.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
  from.replace(/\\/g, ""),
]);

export function createTour({
  monaco,
  jumpToSource,
  editors,
  panes,
  ui,
  sources,
  generate,
  setTyping,
  onStatus,
  onOpenChange,
}) {
  const steps = [
    {
      pane: "elixir",
      variant: "base",
      say: "This <code>@spec</code> is the only place these types are written down. No schema file, no duplicate definitions.",
      hold: 3600,
    },
    {
      pane: "ts",
      variant: "base",
      say: "This client was generated from it — by Elixir itself, compiled to WebAssembly, running in this tab. No server.",
      hold: 3800,
    },
    {
      pane: "ts",
      variant: "base",
      jump: true,
      say: "Every method also points back at the line that produced it. Click that link in the generated file, or hover the call below, and you land on the handler.",
      hold: 5000,
    },
    {
      pane: "use",
      variant: "base",
      say: "Your application code type-checks against those generated types.",
      hold: 3200,
    },
    {
      pane: "elixir",
      variant: "renamed",
      owns: "rename",
      say: "Now watch what a backend change does. Renaming <code>email</code> to <code>email_address</code> in the spec…",
      hold: 2000,
    },
    {
      pane: "ts",
      variant: "renamed",
      say: "Codegen reran. <code>UsersGetOutput</code> now has <code>email_address</code> — the old field is gone.",
      hold: 3600,
    },
    {
      pane: "use",
      variant: "renamed",
      expect: "error",
      say: "And your TypeScript is broken — the break surfaces here, at edit time:",
      hold: 4600,
    },
    {
      pane: "elixir",
      variant: "base",
      owns: "revert",
      say: "Change it back, and the error clears on its own.",
      hold: 2200,
    },
    {
      pane: null,
      variant: "base",
      expect: "clean",
      say: "Green again. Close the tour and it is your buffer — edit anything on the left and the client follows.",
      hold: 4000,
    },
  ];

  let index = -1;
  let variant = "base";
  let open = false;
  let auto = false;
  // True from the click until the first step is on screen. The opening
  // regeneration takes seconds, and without this the UI looks dead and a second
  // click would quietly cancel the tour.
  let starting = false;
  // Bumped on every navigation so a pending auto-advance abandons its sleep.
  let token = 0;

  const highlight = (name) => {
    for (const [key, el] of Object.entries(panes)) el.classList.toggle("active", key === name);
  };

  // "typed", "missing" (the reader edited the text the script expects) or
  // "aborted" (a newer navigation superseded this one mid-keystroke).
  async function typeReplace(find, replacement) {
    const editor = editors.elixir;
    const model = editor.getModel();
    const match = model.findMatches(find, false, true, true, null, false)[0];
    if (!match) return "missing";

    const { range } = match;
    editor.revealRangeInCenterIfOutsideViewport(range);
    // Edits go through the model, not the editor: the pane is read-only while the
    // tour drives it, and `editor.executeEdits` is a silent no-op when it is.
    const edit = (at, text) => model.pushEditOperations(null, [{ range: at, text }], () => null);
    edit(range, "");

    let column = range.startColumn;
    const mine = token;
    for (const char of replacement) {
      if (token !== mine) return "aborted";
      const at = new monaco.Range(range.startLineNumber, column, range.startLineNumber, column);
      edit(at, char);
      column += 1;
      editor.setPosition({ lineNumber: range.startLineNumber, column });
      await sleep(KEYSTROKE_MS);
    }
    return "typed";
  }

  const markers = () =>
    monaco.editor
      .getModelMarkers({ resource: editors.use.getModel().uri })
      .filter((m) => m.severity === monaco.MarkerSeverity.Error)
      .map((m) => m.message);

  // Diagnostics arrive from the TS worker a beat after the model settles.
  async function waitForMarkers(want, timeoutMs = 9000) {
    const deadline = Date.now() + timeoutMs;
    const mine = token;
    while (Date.now() < deadline) {
      if (token !== mine) return [];
      const found = markers();
      if (want === "error" ? found.length > 0 : found.length === 0) return found;
      await sleep(150);
    }
    return markers();
  }

  async function applyVariant(target, { animate }) {
    if (variant === target) return;
    const mine = token;
    setTyping(true);
    try {
      if (animate) {
        const edits = target === "renamed" ? RENAME_EDITS : REVERT_EDITS;
        for (const [find, replacement] of edits) {
          const outcome = await typeReplace(find, replacement);
          if (outcome === "aborted") return;
          if (outcome === "missing") {
            editors.elixir.setValue(sources[target]);
            break;
          }
        }
      } else {
        editors.elixir.setValue(sources[target]);
      }
    } finally {
      setTyping(false);
    }
    // Leave `variant` alone when superseded, or the half-typed buffer counts as
    // applied and the early return above stops it ever being restored.
    if (token !== mine) return;
    variant = target;
    await generate();
  }

  function renderNav() {
    ui.step.textContent = starting ? "…" : `${index + 1} / ${steps.length}`;
    ui.prev.disabled = starting || index <= 0;
    ui.next.disabled = starting || index >= steps.length - 1;
    ui.play.disabled = starting;
    ui.play.textContent = auto ? "⏸" : "▶";
    ui.play.title = auto ? "Pause" : "Resume";
  }

  async function goTo(target, { animate = false } = {}) {
    if (!open || target < 0 || target >= steps.length) return;
    token += 1;
    const mine = token;

    index = target;
    const step = steps[index];
    renderNav();
    highlight(step.pane);
    ui.caption.innerHTML = step.say;
    onStatus(`tour ${index + 1}/${steps.length}`);

    await applyVariant(step.variant, { animate: animate && Boolean(step.owns) });
    if (token !== mine) return;

    if (step.jump) jumpToSource();

    if (step.expect) {
      const found = await waitForMarkers(step.expect);
      if (token !== mine) return;
      if (step.expect === "error" && found.length) {
        ui.caption.innerHTML = `${step.say}<br><span class="tour-err"></span>`;
        // Not interpolated: a diagnostic mentioning a generic would parse as markup.
        ui.caption.querySelector(".tour-err").textContent = found[0];
      }
    }
  }

  async function autoAdvance() {
    while (auto && open && index < steps.length - 1) {
      const mine = token;
      await sleep(steps[index].hold ?? 2800);
      if (token !== mine || !auto || !open) return;
      await goTo(index + 1, { animate: true });
    }
    if (auto && open && index === steps.length - 1) {
      await sleep(steps[index].hold ?? 2800);
      if (auto && open) stop();
    }
  }

  function stop() {
    if (!open) return;
    open = false;
    auto = false;
    starting = false;
    token += 1;
    for (const el of Object.values(panes)) el.classList.remove("active");
    ui.bar.classList.remove("visible");
    setTyping(false);
    onStatus(null);
    onOpenChange(false);
  }

  return {
    async start() {
      if (open) return;
      // Everything up to the first await is synchronous on purpose, so the click
      // produces visible feedback in the same frame.
      open = true;
      starting = true;
      auto = true;
      variant = "base";
      index = -1;
      token += 1;
      ui.bar.classList.add("visible");
      ui.caption.innerHTML = "Starting the tour — regenerating the client in the browser…";
      renderNav();
      onOpenChange(true);

      setTyping(true);
      editors.elixir.setValue(sources.base);
      editors.use.getModel().setValue(sources.consumer);
      setTyping(false);

      const mine = token;
      await generate();
      if (token !== mine || !open) {
        starting = false;
        return;
      }
      starting = false;
      await goTo(0);
      autoAdvance();
    },
    stop,
    // Any manual navigation drops out of auto-advance so the reader sets the pace.
    async prev() {
      if (starting) return;
      auto = false;
      await goTo(index - 1);
      renderNav();
    },
    async next() {
      if (starting) return;
      auto = false;
      await goTo(index + 1, { animate: true });
      renderNav();
    },
    toggleAuto() {
      if (starting) return;
      auto = !auto;
      renderNav();
      if (auto) autoAdvance();
      else token += 1;
    },
    get open() {
      return open;
    },
  };
}
