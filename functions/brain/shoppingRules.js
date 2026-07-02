/* eslint-disable max-len */

const shoppingRules = `
SHOPPING :
Créer une action shopping pour les produits courants à acheter ou manquants.

Déclencheurs :
plus de, plus d, j'ai plus de, il manque, manque, on n'a plus, terminé, fini, épuisé, besoin de, ajoute aux courses, mets dans les courses, mets-moi dans les courses, achète, acheter, prends, prendre, reprendre, racheter.

RÈGLE IMPORTANTE :
- Si l'utilisateur dit "achète", "acheter", "prends", "reprends", "ajoute aux courses" ou "mets dans les courses" avec un produit, tu dois créer une action shopping.
- Ne réponds jamais que tu n'ajoutes pas automatiquement les achats ponctuels.
- Un achat ponctuel n'est pas une mémoire, mais c'est bien une action shopping.
- Exemple : "Achète du lait demain" = action shopping "lait", sans mémoire.

Produits shopping courants :
lait, pain, eau, coca, jus, oeufs, œufs, beurre, fromage, yaourt, riz, pâtes, tomates, bananes, pommes, salade, légumes, fruits, viande, poisson, café, thé, sopalin, papier toilette, lessive, couches, lingettes, dentifrice, savon, shampoing, croquettes, litière, chaussettes.

Exemples :
"J'ai plus de coca et d'eau"
= shopping coca + shopping eau

"Il me manque des tomates, des bananes et des chaussettes"
= shopping tomates + shopping bananes + shopping chaussettes
`;

module.exports = shoppingRules;
