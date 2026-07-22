/* eslint-disable require-jsdoc */

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

function productionFiles(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap((entry) => {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) return productionFiles(target);
    return entry.isFile() && target.endsWith(".js") ? [target] : [];
  });
}

test("Functions production code has no direct console output", () => {
  const files = productionFiles(path.resolve(__dirname, "../../services"));
  const violations = files.flatMap((file) => {
    const source = fs.readFileSync(file, "utf8");
    return /console\.(?:log|info|warn|error)\s*\(/.test(source) ? [file] : [];
  });
  assert.deepEqual(violations, []);
});

test("diagnostics never serialize raw errors, requests or responses", () => {
  const files = productionFiles(path.resolve(__dirname, "../../services"));
  const violations = files.flatMap((file) => {
    if (file.endsWith("diagnostics.js")) return [];
    const source = fs.readFileSync(file, "utf8");
    const unsafeMetadata =
      /metadata\s*:\s*(?:error|request|response|payload)\b/;
    const unsafeSerialization =
      /JSON\.stringify\s*\(\s*(?:error|request|response|payload)\s*\)/;
    return unsafeMetadata.test(source) || unsafeSerialization.test(source) ?
      [file] : [];
  });
  assert.deepEqual(violations, []);
});
