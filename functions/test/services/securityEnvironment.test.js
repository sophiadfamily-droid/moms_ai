const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ZELIA_ENFORCE_APP_CHECK_NAME,
  requiresAppCheck,
  resolveSecurityEnvironment,
  resolveSecurityPolicy,
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

test("unknown environments fail closed and release tiers require App Check",
    () => {
      assert.equal(resolveSecurityEnvironment({ZELIA_ENVIRONMENT: "unknown"}),
          "production");
      assert.deepEqual(
          resolveSecurityPolicy(booleanParam(false), {
            ZELIA_ENVIRONMENT: "development",
          }),
          {environment: "development", appCheckRequired: false},
      );
      for (const environment of ["staging", "production"]) {
        assert.throws(
            () => resolveSecurityPolicy(booleanParam(false), {
              ZELIA_ENVIRONMENT: environment,
            }),
            /APP_CHECK_ENFORCEMENT_REQUIRED/,
        );
        assert.deepEqual(
            resolveSecurityPolicy(booleanParam(true), {
              ZELIA_ENVIRONMENT: environment,
            }),
            {environment, appCheckRequired: true},
        );
      }
    });
