const assert = require("node:assert/strict");
const test = require("node:test");

const projectId = process.env.GCLOUD_PROJECT || "";
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST || "";

if (!projectId.startsWith("zelia-security-test-")) {
  throw new Error("SECURITY_TEST_PROJECT_REQUIRED");
}
if (!functionsHost) {
  throw new Error("FUNCTIONS_EMULATOR_HOST_REQUIRED");
}

const endpoint = `http://${functionsHost}/${projectId}` +
  "/us-central1/chatWithZeliaCallable";

test("the callable emulator rejects a completely unauthenticated request",
    async () => {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({data: {message: "Bonjour"}}),
      });
      const body = await response.json();

      assert.notEqual(response.status, 200);
      assert.equal(body.error.status, "UNAUTHENTICATED");
      assert.equal(JSON.stringify(body).includes("Bonjour"), false);
    });
