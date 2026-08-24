"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  canonicalItemFromDocument,
  loadCanonicalShoppingItems,
  withCanonicalShoppingContext,
} = require("../../services/canonicalShoppingRepository");

/**
 * Builds a Firestore document fixture.
 * @param {Object} data Firestore document data.
 * @return {Object} Document fixture.
 */
function document(data) {
  return {data: () => data};
}

test("reads revisioned and legacy active shopping documents", () => {
  assert.deepEqual(canonicalItemFromDocument(document({
    payload: {
      title: " Fraises ",
      quantity: "2 barquettes",
      isUrgent: true,
      isBought: false,
      createdAt: "2026-08-24T08:00:00.000Z",
    },
  })), {
    title: "Fraises",
    quantity: "2 barquettes",
    isUrgent: true,
    createdAt: "2026-08-24T08:00:00.000Z",
  });
  assert.equal(canonicalItemFromDocument(document({
    title: "Lait", isBought: true,
  })), null);
  assert.equal(canonicalItemFromDocument(document({
    isTombstone: true, payload: {title: "Pain"},
  })), null);
});

test("loads shopping only below the authenticated user path", async () => {
  const calls = [];
  const firestore = {
    collection(name) {
      calls.push(["root", name]);
      return {doc(uid) {
        calls.push(["uid", uid]);
        return {collection(child) {
          calls.push(["child", child]);
          return {orderBy(field, direction) {
            calls.push(["orderBy", field, direction]);
            return {limit(value) {
              calls.push(["limit", value]);
              return {get: async () => ({docs: [
                document({title: "Kiwis", isBought: false}),
              ]})};
            }};
          }};
        }};
      }};
    },
  };
  const result = await loadCanonicalShoppingItems({
    firestore, uid: "verified-user", limit: 100,
  });
  assert.deepEqual(calls, [
    ["root", "users"], ["uid", "verified-user"],
    ["child", "shopping_items"],
    ["orderBy", "updatedAt", "desc"], ["limit", 100],
  ]);
  assert.equal(result[0].title, "Kiwis");
});

test("a newer deletion hides older product copies", async () => {
  const firestore = {
    collection() {
      return {doc() {
        return {collection() {
          return {orderBy() {
            return {limit() {
              return {get: async () => ({docs: [
                document({
                  payload: {title: "Lait", isBought: false},
                  updatedAt: "2026-08-20T08:00:00.000Z",
                }),
                document({
                  payload: {title: " lait ", isBought: false},
                  isTombstone: true,
                  updatedAt: "2026-08-24T08:00:00.000Z",
                }),
                document({
                  payload: {title: "Pain", isBought: false},
                  updatedAt: "2026-08-23T08:00:00.000Z",
                }),
              ]})};
            }};
          }};
        }};
      }};
    },
  };
  const result = await loadCanonicalShoppingItems({
    firestore, uid: "verified-user", limit: 100,
  });
  assert.deepEqual(result.map((item) => item.title), ["Pain"]);
});

test("a newer bought state hides an older active copy", async () => {
  const firestore = {
    collection() {
      return {doc() {
        return {collection() {
          return {orderBy() {
            return {limit() {
              return {get: async () => ({docs: [
                document({
                  title: "Fraises", isBought: false,
                  updatedAt: "2026-08-20T08:00:00.000Z",
                }),
                document({
                  title: "Fraises", isBought: true,
                  updatedAt: "2026-08-24T08:00:00.000Z",
                }),
              ]})};
            }};
          }};
        }};
      }};
    },
  };
  const result = await loadCanonicalShoppingItems({
    firestore, uid: "verified-user", limit: 100,
  });
  assert.deepEqual(result, []);
});

test(
    "fourteen bought products never appear beside two current products",
    async () => {
      const active = ["Kiwis", "Fraises"].map((title, index) => document({
        title,
        isBought: false,
        updatedAt: `2026-08-24T08:0${index}:00.000Z`,
      }));
      const bought = Array.from({length: 14}, (_, index) => document({
        title: `Ancien produit ${index}`,
        isBought: true,
        updatedAt: `2026-08-23T${String(index).padStart(2, "0")}:00:00.000Z`,
      }));
      const firestore = {
        collection() {
          return {doc() {
            return {collection() {
              return {orderBy() {
                return {limit() {
                  return {get: async () => ({docs: [...active, ...bought]})};
                }};
              }};
            }};
          }};
        },
      };

      const result = await loadCanonicalShoppingItems({
        firestore, uid: "verified-user", limit: 100,
      });
      assert.deepEqual(
          result.map((item) => item.title),
          ["Kiwis", "Fraises"],
      );
    },
);

test("adds bounded shopping context without mutating source", () => {
  const source = {
    conversationContext: {sections: [], projectionVersion: 4},
  };
  const enriched = withCanonicalShoppingContext(source, [{
    title: "Lait", quantity: "", isUrgent: false, createdAt: null,
  }]);
  assert.deepEqual(source.conversationContext.sections, []);
  assert.equal(enriched.conversationContext.sections[0].type, "shopping");
  assert.equal(enriched.conversationContext.sections[0].items[0].facts.title,
      "Lait");
});
