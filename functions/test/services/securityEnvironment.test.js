const assert = require("node:assert/strict");
const test = require("node:test");

const {
  requiresAppCheck,
  resolveSecurityEnvironment,
} = require("../../services/securityEnvironment");

test("production and staging fail closed on App Check", () => {
  assert.equal(requiresAppCheck({ZELIA_ENVIRONMENT: "production"}), true);
  assert.equal(requiresAppCheck({ZELIA_ENVIRONMENT: "staging"}), true);
  assert.equal(requiresAppCheck({ZELIA_ENVIRONMENT: "unknown"}), true);
  assert.equal(requiresAppCheck({}), true);
});

test("only Functions emulator bypasses App Check enforcement", () => {
  assert.equal(resolveSecurityEnvironment({FUNCTIONS_EMULATOR: "true"}),
      "emulator");
  assert.equal(requiresAppCheck({FUNCTIONS_EMULATOR: "true"}), false);
  assert.equal(requiresAppCheck({
    FUNCTIONS_EMULATOR: "false",
    ZELIA_ENVIRONMENT: "development",
  }), true);
});
