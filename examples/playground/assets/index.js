import { Popcorn } from "@swmansion/popcorn";
import * as monaco from "monaco-editor";
// 0.56 ships language definitions in the default entry but keeps the TypeScript
// language service in a separate contribution, exposed as named exports rather
// than hung off `monaco.languages.typescript`.
import * as ts from "monaco-editor/language/typescript/monaco.contribution.js";
import { createTour } from "./tour.js";

// esbuild has no `?worker` import, so the workers are separate bundles served
// from the same origin (COEP require-corp forbids cross-origin ones). They are
// ESM output, so they must be module workers or the import statements throw.
self.MonacoEnvironment = {
  getWorker(_id, label) {
    const isTs = label === "typescript" || label === "javascript";
    return new Worker(isTs ? "/ts.worker.js" : "/editor.worker.js", { type: "module" });
  },
};

const ELIXIR_SOURCE = `defmodule Playground.Users do
  use RpcElixir.Handler

  @spec get(%{id: String.t()}, %{}) ::
          {:ok, %{id: String.t(), email: String.t(), tags: [String.t()]}}
          | {:error, :not_found}
  def get(%{id: id}, _ctx), do: {:ok, %{id: id, email: "ada@example.com", tags: []}}

  @spec list(%{optional(:limit) => integer()}, %{}) ::
          {:ok, %{users: [%{id: String.t(), created_at: DateTime.t()}], total: integer()}}
  def list(_input, _ctx), do: {:ok, %{users: [], total: 0}}
end

defmodule Playground.Router do
  use RpcElixir.Router

  scope "users" do
    expose Playground.Users
  end
end
`;

const RENAMED_SOURCE = ELIXIR_SOURCE.replace(
  "email: String.t()",
  "email_address: String.t()",
).replace('email: "ada@example.com"', 'email_address: "ada@example.com"');

const CONSUMER_SOURCE = `import { createRpcClient } from "./rpc.gen";

const rpc = createRpcClient({ url: "/rpc" });

const res = await rpc.users.get({ id: "u_1" });
if (res.ok) {
  // Hover res.data — this shape came from the @spec on the left.
  console.log(res.data.email, res.data.tags);
}
`;

// The generated client imports the runtime package. Stub its types so the
// consumer pane type-checks without shipping the real @elixir-ts-rpc/client.
const CLIENT_STUB = `declare module "@elixir-ts-rpc/client" {
  export type DomainError<C extends string> = { code: C; message: string };
  export type MiddlewareError<C extends string> = { code: C; message: string };
  export type Client = { call(name: string, input: unknown): Promise<unknown> };
  export type RpcMethod<I, O, E> = (input: I) =>
    Promise<{ ok: true; data: O } | { ok: false; error: E }>;
  export function createClient(opts: { url: string }): Client;
  export function rpcMethod<I, O, E>(c: Client, n: string, codes: string[]): RpcMethod<I, O, E>;
}`;

const COMPILER_OPTIONS = {
  target: ts.ScriptTarget.ESNext,
  module: ts.ModuleKind.ESNext,
  moduleResolution: ts.ModuleResolutionKind.NodeJs,
  strict: true,
  allowNonTsExtensions: true,
};

ts.typescriptDefaults.setCompilerOptions(COMPILER_OPTIONS);
ts.typescriptDefaults.setEagerModelSync(true);
ts.typescriptDefaults.addExtraLib(CLIENT_STUB, "file:///client.d.ts");

// Monaco revalidates a model when that model changes, not when something it
// imports changes. Rewriting rpc.gen.ts therefore leaves stale errors in the
// consumer pane until the defaults change and force a full re-check.
const revalidateDependents = () => ts.typescriptDefaults.setCompilerOptions(COMPILER_OPTIONS);

// The tour scripts the Elixir pane and reads TypeScript diagnostics out of the
// consumer pane, so a reader typing mid-step is editing against the script. Both
// go read-only while it runs, and the first attempted keystroke hands them back.
const TOUR_LOCK_MESSAGE = {
  value: "The guided tour is driving this pane. It just stopped — type again to edit.",
};

const GENERATED_MESSAGE = { value: "Generated output. Edit the Elixir spec on the left." };

const editorOpts = {
  theme: "vs-dark",
  fontSize: 12.5,
  minimap: { enabled: false },
  scrollBeyondLastLine: false,
  automaticLayout: true,
  tabSize: 2,
  renderLineHighlight: "none",
  wordWrap: "on",
  fixedOverflowWidgets: true,
  overflowWidgetsDomNode: document.getElementById("overflow-widgets"),
};

const elixirEditor = monaco.editor.create(document.getElementById("ed-elixir"), {
  ...editorOpts,
  value: ELIXIR_SOURCE,
  language: "elixir",
  readOnlyMessage: TOUR_LOCK_MESSAGE,
});

// A real file URI so the consumer pane's `./rpc.gen` import resolves to it.
const generatedModel = monaco.editor.createModel(
  "// waiting for the first generate…",
  "typescript",
  monaco.Uri.parse("file:///rpc.gen.ts"),
);

const tsEditor = monaco.editor.create(document.getElementById("ed-ts"), {
  ...editorOpts,
  model: generatedModel,
  readOnly: true,
  readOnlyMessage: GENERATED_MESSAGE,
});

const useEditor = monaco.editor.create(document.getElementById("ed-use"), {
  ...editorOpts,
  model: monaco.editor.createModel(
    CONSUMER_SOURCE,
    "typescript",
    monaco.Uri.parse("file:///main.ts"),
  ),
  readOnlyMessage: TOUR_LOCK_MESSAGE,
});

// Each generated method carries a JSDoc link back to the handler that produced
// it. In a real project that href is a file:// URI the editor opens; here the
// "file" is the pane on the left, so the link is intercepted and revealed there.
// Monaco's markdown sanitizer only keeps a short list of link schemes, and
// file: is on it, which is why the playground reuses that scheme.
//
// The name in the href is whatever the generator called the buffer, so it
// arrives with each generation rather than being spelled out again here.
let sourceFile = null;

const revealHandler = (line) => {
  const model = elixirEditor.getModel();
  if (line < 1 || line > model.getLineCount()) return false;
  elixirEditor.revealLineInCenter(line);
  elixirEditor.setSelection(
    new monaco.Range(
      line,
      model.getLineFirstNonWhitespaceColumn(line),
      line,
      model.getLineMaxColumn(line),
    ),
  );
  elixirEditor.focus();
  return true;
};

const followSourceLink = (url) => {
  const line = Number(monaco.Uri.parse(url).fragment.slice(1));
  return Number.isInteger(line) && revealHandler(line);
};

monaco.editor.registerLinkOpener({
  open(resource) {
    if (!sourceFile || resource.path !== `/${sourceFile}`) return false;
    return followSourceLink(resource.toString());
  },
});

// Inside the generated pane that link is only markdown in a comment, so nothing
// makes it clickable on its own.
const SOURCE_LINK = /\[([^\]]+)\]\((file:\/\/\/[^\s)]+)\)/g;

// Ranges cover the `[label]` part, so the href stays plain text and only the
// human-readable half of the markdown behaves like a link.
const sourceLinksOnLine = (model, line) =>
  [...model.getLineContent(line).matchAll(SOURCE_LINK)].map((match) => {
    const [, label, url] = match;
    const start = match.index + 1;
    return { range: new monaco.Range(line, start, line, start + label.length + 2), url };
  });

monaco.languages.registerLinkProvider("typescript", {
  provideLinks(model) {
    if (model.uri.toString() !== generatedModel.uri.toString()) return { links: [] };

    const links = [];
    for (let line = 1; line <= model.getLineCount(); line++) {
      links.push(...sourceLinksOnLine(model, line));
    }
    return { links };
  },
});

// Monaco gates links inside a document behind a modifier, cmd on a Mac and ctrl
// everywhere else, and announces which in its own tooltip. That is right for an
// editor and wrong for a demo: a visitor should not have to know the convention,
// or which platform they are being asked about. This pane is read-only, so a bare
// click has no other job, and following the link on one costs nothing. The
// modifier keeps working for anyone who reaches for it out of habit.
tsEditor.onMouseUp((event) => {
  if (event.target.type !== monaco.editor.MouseTargetType.CONTENT_TEXT) return;
  const position = event.target.position;
  if (!position || !tsEditor.getSelection().isEmpty()) return;

  const hit = sourceLinksOnLine(generatedModel, position.lineNumber).find((link) =>
    link.range.containsPosition(position),
  );
  if (hit) followSourceLink(hit.url);
});

// The tour demonstrates the link without a mouse: it shows where the link lives
// in the generated file and follows it, both panes at once.
const jumpToSource = () => {
  const [hit] = generatedModel.findMatches(SOURCE_LINK.source, false, true, true, null, true);
  if (!hit) return false;
  tsEditor.revealRangeInCenter(hit.range);
  tsEditor.setSelection(hit.range);
  return followSourceLink(hit.matches[2]);
};

// A regeneration usually rewrites a line or two somewhere down a file that does
// not fit on screen, so without this the pane looks untouched and you have to
// go hunting for what your edit did. The changed lines are marked for a moment
// and the first of them is centered.
const CHANGE_FLASH_MS = 1600;
const changeFlash = tsEditor.createDecorationsCollection();
let changeFlashTimer = null;

const changedLines = (before, after) => {
  const previous = before.split("\n");
  const next = after.split("\n");
  const lines = [];
  for (let i = 0; i < Math.max(previous.length, next.length); i++) {
    if (previous[i] !== next[i] && i < next.length) lines.push(i + 1);
  }
  return lines;
};

const revealChanges = (before, after) => {
  if (!before || before === after) return;
  const lines = changedLines(before, after);
  if (lines.length === 0) return;

  tsEditor.revealLineInCenter(lines[0]);
  changeFlash.set(
    lines.map((line) => ({
      range: new monaco.Range(line, 1, line, 1),
      options: { isWholeLine: true, className: "changed-line" },
    })),
  );

  clearTimeout(changeFlashTimer);
  changeFlashTimer = setTimeout(() => changeFlash.clear(), CHANGE_FLASH_MS);
};

const setTourLock = (locked) => {
  for (const editor of [elixirEditor, useEditor]) editor.updateOptions({ readOnly: locked });
  document.body.classList.toggle("tour-locked", locked);
};

const caveatsBtn = document.getElementById("caveats-btn");
const caveatsPanel = document.getElementById("caveats");

caveatsBtn.addEventListener("click", () => {
  const open = caveatsPanel.classList.toggle("open");
  caveatsBtn.setAttribute("aria-expanded", String(open));
});

const statusEl = document.getElementById("status");
const errorEl = document.getElementById("error");
const tourBtn = document.getElementById("tour-btn");

let statusOverride = null;
let lastStatus = { text: "booting…", cls: "" };

const setStatus = (text, cls) => {
  // Only remember settled results. Remembering the transient "generating…" means
  // closing the tour mid-generation would restore it and look permanently stuck.
  if (cls !== "busy") lastStatus = { text, cls: cls ?? "" };
  if (statusOverride) return;
  statusEl.textContent = text;
  statusEl.className = cls ?? "";
};

const showError = (stage, message) => {
  errorEl.style.display = "block";
  errorEl.textContent = `${stage}: ${message}`;
};

const clearError = () => {
  errorEl.style.display = "none";
};

setStatus("booting Popcorn…", "busy");

const popcorn = await Popcorn.init({
  bundlePaths: ["/wasm/bundle.avm"],
  onStderr: (m) => console.warn(m),
}).catch((e) => {
  setStatus("boot failed", "err");
  // Missing COOP/COEP is the likeliest deploy failure, and its raw error says
  // nothing useful. Cross-origin isolation is what tells the two apart.
  showError(
    "boot",
    self.crossOriginIsolated
      ? String(e)
      : "page is not cross-origin isolated, so SharedArrayBuffer is unavailable — check the COOP/COEP headers",
  );
  throw e;
});

async function runGeneration() {
  setStatus("generating…", "busy");
  try {
    const result = await popcorn.call(elixirEditor.getValue(), {
      process: "playground",
      timeoutMs: 30_000,
    });

    if (!result.ok) throw result.error;
    const data = result.data;

    if (data.ok) {
      clearError();
      sourceFile = data.source_file;
      const previous = generatedModel.getValue();
      generatedModel.setValue(data.typescript);
      revealChanges(previous, data.typescript);
      revalidateDependents();
      setStatus(`${data.procedures.length} procedures · ${Math.round(result.durationMs)}ms`, "ok");
    } else {
      showError(data.stage, data.error);
      setStatus(`${data.stage} error`, "err");
    }
  } catch (e) {
    showError("call", String(e));
    setStatus("call failed", "err");
  }
}

// A generation takes seconds, so runs are serialized (two never race on the
// generated model) and calls that arrive mid-run collapse into a single
// follow-up instead of queueing a backlog that drains long after the typing
// stopped. Every intermediate run would be reading superseded text anyway.
// The returned promise still covers the editor content as of the call, since
// the follow-up reads the editor when it starts. The catch keeps one failure
// from wedging every later generation.
let inFlight = null;
let queued = null;

const deferred = () => {
  let resolve;
  const promise = new Promise((r) => (resolve = r));
  return { promise, resolve };
};

function runNow() {
  inFlight = runGeneration()
    .catch(() => {})
    .finally(() => {
      inFlight = null;
      if (!queued) return;
      const { resolve } = queued;
      queued = null;
      resolve(runNow());
    });
  return inFlight;
}

function generate() {
  if (!inFlight) return runNow();
  queued ??= deferred();
  return queued.promise;
}

let typingProgrammatically = false;
let debounce;

// Long enough that an ordinary mid-word or mid-line pause does not spend a
// generation, short enough to still feel like it reacts to what you typed.
const DEBOUNCE_MS = 700;

elixirEditor.onDidChangeModelContent(() => {
  if (typingProgrammatically) return;
  clearTimeout(debounce);
  debounce = setTimeout(generate, DEBOUNCE_MS);
});

const tour = createTour({
  monaco,
  jumpToSource,
  editors: { elixir: elixirEditor, ts: tsEditor, use: useEditor },
  panes: {
    elixir: document.getElementById("pane-elixir"),
    ts: document.getElementById("pane-ts"),
    use: document.getElementById("pane-use"),
  },
  ui: {
    bar: document.getElementById("caption-bar"),
    caption: document.getElementById("caption"),
    step: document.getElementById("tour-step"),
    prev: document.getElementById("tour-prev"),
    next: document.getElementById("tour-next"),
    play: document.getElementById("tour-play"),
  },
  sources: { base: ELIXIR_SOURCE, renamed: RENAMED_SOURCE, consumer: CONSUMER_SOURCE },
  generate,
  onOpenChange: (open) => {
    setTourLock(open);
    syncTourButton();
  },
  setTyping: (v) => {
    typingProgrammatically = v;
  },
  onStatus: (text) => {
    statusOverride = null;
    if (text) {
      statusEl.textContent = text;
      statusEl.className = "busy";
      statusOverride = text;
    } else {
      // Tour over: put back whatever the last real generation reported.
      setStatus(lastStatus.text, lastStatus.cls);
    }
  },
});

const syncTourButton = () => {
  tourBtn.textContent = tour.open ? "\u25a0 Stop tour" : "\u25b6 Guided tour";
  tourBtn.classList.toggle("running", tour.open);
};

// Typing into a locked pane is how a reader says they are done watching.
for (const editor of [elixirEditor, useEditor]) {
  editor.onDidAttemptReadOnlyEdit(() => tour.stop());
}

tourBtn.addEventListener("click", () => {
  if (tour.open) tour.stop();
  else tour.start();
});

document.getElementById("tour-prev").addEventListener("click", () => tour.prev());
document.getElementById("tour-next").addEventListener("click", () => tour.next());
document.getElementById("tour-play").addEventListener("click", () => tour.toggleAuto());
document.getElementById("tour-close").addEventListener("click", () => tour.stop());

// Arrow keys are Monaco's while an editor has focus, so only claim them outside.
document.addEventListener("keydown", (e) => {
  if (!tour.open) return;
  if (e.target instanceof Element && e.target.closest(".monaco-editor")) return;
  if (e.key === "ArrowLeft") tour.prev();
  else if (e.key === "ArrowRight") tour.next();
  else if (e.key === "Escape") tour.stop();
});

await generate();

Object.assign(window, { monaco, ts, elixirEditor, generatedModel, useEditor, generate, tour });
