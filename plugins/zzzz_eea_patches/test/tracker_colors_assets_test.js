"use strict";

// node --test plugins/zzzz_eea_patches/test/tracker_colors_assets_test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { execFileSync } = require("node:child_process");

const source = fs.readFileSync(path.join(__dirname, "../assets/javascripts/tracker_colors.js"), "utf8");
const samples = process.env.TASKMAN_COLOR_RULES_FILE ?
  JSON.parse(fs.readFileSync(process.env.TASKMAN_COLOR_RULES_FILE, "utf8")) : JSON.parse(execFileSync("ruby", [
  "-rjson", "-r" + path.join(__dirname, "../lib/eea_patches/tracker_colors.rb"), "-e",
  "c = EeaPatches::TrackerColors; colors = c::NAMED_COLORS.values + c::LEGACY_NAMES.values + (14..100).map { |id| c.generated(id) }; puts JSON.generate(colors.to_h { |color| [color.delete_prefix('#'), c.css_rule(color)] })"
], { encoding: "utf8" }));

function element(tokens = [], children = []) {
  return { nodeType: 1, classList: tokens, querySelectorAll: () => children };
}

function setup({ text = "", nodes = [], readyState = "complete" } = {}) {
  const rules = [];
  let onMutation;
  let onReady;
  const style = { textContent: text, sheet: { cssRules: rules, insertRule: rule => rules.push(rule) } };
  const context = {
    document: {
      readyState, body: element([], nodes), getElementById: () => style,
      addEventListener: (_name, callback) => { onReady = callback; }
    },
    MutationObserver: class {
      constructor(callback) { onMutation = callback; }
      observe() {}
    }
  };
  vm.runInNewContext(source, context);
  return {
    rules,
    ready: () => onReady(),
    mutate: records => onMutation(records)
  };
}

test("late AJAX colors match the server palette, including text and hover contrast", () => {
  const audit = setup();
  for (const [hex, rule] of Object.entries(samples)) {
    const node = element(["issue-card", "taskman-tracker-color-" + hex]);
    audit.mutate([{ type: "childList", addedNodes: [element([], [node])] }]);
    assert.equal(audit.rules.at(-1), rule);
    assert.match(rule, /--taskman-tracker-text:#ffffff;/);
    assert.match(rule, /--taskman-tracker-hover-text:#ffffff;/);
  }
  assert.equal(audit.rules.length, Object.keys(samples).length);
});

test("server rules and repeated cards do not create duplicate CSS", () => {
  const audit = setup({ text: samples["0000ff"] });
  const node = element(["taskman-tracker-color-0000ff", "taskman-tracker-color-abcdef"]);
  audit.mutate([{ type: "childList", addedNodes: [node, node] }]);
  audit.mutate([{ type: "attributes", target: node }]);
  assert.equal(audit.rules.length, 1);
  assert.match(audit.rules[0], /^\.taskman-tracker-color-abcdef /);
});

test("changing a card's tracker installs its new color", () => {
  const audit = setup();
  audit.mutate([{ type: "attributes", target: element(["taskman-tracker-color-ffa500"]) }]);
  assert.equal(audit.rules[0], samples.ffa500);
});

test("text nodes, unrelated classes and malformed color tokens are ignored", () => {
  const audit = setup();
  audit.mutate([{ type: "childList", addedNodes: [
    { nodeType: 3 }, element(["taskman-tracker-color-ffffff-injected", "bk-blue", "taskman-tracker-color-</style>"])
  ] }]);
  assert.equal(audit.rules.length, 0);
});

test("initialization waits for the document when needed", () => {
  const audit = setup({ readyState: "loading", nodes: [element(["taskman-tracker-color-0000ff"])] });
  assert.equal(audit.rules.length, 0);
  audit.ready();
  assert.equal(audit.rules[0], samples["0000ff"]);
});
