const {defineBoolean} = require("firebase-functions/params");

const ZELIA_ENFORCE_APP_CHECK_NAME = "ZELIA_ENFORCE_APP_CHECK";
const zeliaEnforceAppCheck = defineBoolean(
    ZELIA_ENFORCE_APP_CHECK_NAME,
    {
      default: true,
      description: "Exige un jeton Firebase App Check valide pour le chat.",
    },
);

const SECURITY_ENVIRONMENTS = Object.freeze({
  emulator: "emulator",
  development: "development",
  staging: "staging",
  production: "production",
});

/**
 * Résout l'environnement de sécurité sans permettre à une valeur inconnue
 * d'affaiblir la production.
 *
 * @param {Object} env variables d'environnement
 * @return {string} environnement fermé
 */
function resolveSecurityEnvironment(env = process.env) {
  if (env.FUNCTIONS_EMULATOR === "true") {
    return SECURITY_ENVIRONMENTS.emulator;
  }

  const configured = String(env.ZELIA_ENVIRONMENT || "")
      .trim()
      .toLowerCase();
  if (configured === SECURITY_ENVIRONMENTS.development ||
      configured === SECURITY_ENVIRONMENTS.staging ||
      configured === SECURITY_ENVIRONMENTS.production) {
    return configured;
  }

  return SECURITY_ENVIRONMENTS.production;
}

/**
 * Résout la décision App Check depuis le paramètre Firebase officiel.
 *
 * @param {Object} enforcementParam paramètre booléen injectable
 * @return {boolean} App Check requis
 */
function requiresAppCheck(enforcementParam = zeliaEnforceAppCheck) {
  return enforcementParam.value();
}

module.exports = {
  SECURITY_ENVIRONMENTS,
  ZELIA_ENFORCE_APP_CHECK_NAME,
  requiresAppCheck,
  resolveSecurityEnvironment,
  zeliaEnforceAppCheck,
};
