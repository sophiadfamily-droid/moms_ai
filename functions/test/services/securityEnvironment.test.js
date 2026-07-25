const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ZELIA_ENFORCE_APP_CHECK_NAME,
  requiresAppCheck,
  resolveSecurityEnvironment,
  zeliaEnforceAppCheck,
} = require("../../services/securityEnvironment");

/**
 * Construit un paramètre booléen déterministe.
 *
 * @param {boolean} value valeur du paramètre
 * @return {Object} paramètre injectable
 */
function booleanParam(value) {
  return {value: () => value};
}

test("App Check parameter is explicit and fails closed by default", () => {
  assert.equal(ZELIA_ENFORCE_APP_CHECK_NAME, "ZELIA_ENFORCE_APP_CHECK");
  assert.equal(zeliaEnforceAppCheck.name, ZELIA_ENFORCE_APP_CHECK_NAME);
  assert.equal(zeliaEnforceAppCheck.options.default, true);
  assert.equal(requiresAppCheck(booleanParam(true)), true);
});

test("false bypasses App Check without changing environment labels", () => {
  assert.equal(requiresAppCheck(booleanParam(false)), false);
  assert.equal(resolveSecurityEnvironment({FUNCTIONS_EMULATOR: "true"}),
      "emulator");
  assert.equal(resolveSecurityEnvironment({ZELIA_ENVIRONMENT: "production"}),
      "production");
});
