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
 * Seul l'émulateur local Firebase peut omettre App Check. Les builds debug
 * qui appellent un backend distant utilisent un jeton debug enregistré.
 *
 * @param {Object} env variables d'environnement
 * @return {boolean} App Check requis
 */
function requiresAppCheck(env = process.env) {
  return resolveSecurityEnvironment(env) !== SECURITY_ENVIRONMENTS.emulator;
}

module.exports = {
  SECURITY_ENVIRONMENTS,
  requiresAppCheck,
  resolveSecurityEnvironment,
};
