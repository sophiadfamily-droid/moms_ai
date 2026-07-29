"use strict";

const {
  normalizeNaturalLanguage,
} = require("../../brain/engines/naturalLanguageNormalizer");

const definitions = Object.freeze([
  ["task", 40, [
    "Crée une tâche appeler l'école lundi",
    "Rappelle-moi de payer les impôts vendredi",
    "Faut que j'appelle la mutuelle",
    "Documents mutuelle demain",
    "Appeler école lundi",
    "Reporte la tâche à mardi",
    "Termine la tâche assurance",
    "Mets la tâche dossier en priorité",
    "Pense à me rappeler le passeport",
    "Préparer les sacs pour demain",
  ]],
  ["event", 40, [
    "J'ai rendez-vous chez le médecin demain à 15h",
    "Médecin demain 15h",
    "Rdv dentiste 30 min",
    "Trouve-moi un moment lundi prochain",
    "Cale-moi ça mardi à neuf heures",
    "Décale le rendez-vous à vendredi",
    "Annule le rendez-vous du quinze août",
    "Quelles sont mes disponibilités demain",
    "Planifie le rendez-vous avec trajet et marge",
    "Réunion après l'école",
  ]],
  ["shopping", 35, [
    "Ajoute du lait aux courses",
    "Il manque des œufs",
    "On a fini les couches",
    "Faut acheter du pain",
    "Mets deux litres de lait dans les courses",
    "Ajoute pommes et bananes aux courses",
    "Y a plus de couches",
  ]],
  ["routine", 25, [
    "Crée une routine tous les lundis à neuf heures",
    "Tous les jours rappelle-moi les vitamines",
    "Une semaine sur deux le mardi à 18h",
    "Du lundi au vendredi à 7h30",
    "Modifie ma routine du mercredi",
  ]],
  ["memory", 25, [
    "Retiens que je préfère le matin",
    "Oublie ma préférence pour le vendredi",
    "Corrige ma contrainte du mardi",
    "Souviens-toi que Léa est ma sœur",
    "Je préfère les rendez-vous après l'école",
  ]],
  ["priority", 20, [
    "Quelles sont mes priorités aujourd'hui",
    "Que dois-je faire en premier",
    "Qu'est-ce qui est urgent cette semaine",
    "Montre-moi ce qui est important",
    "Sur quoi je dois me concentrer aujourd'hui",
  ]],
  ["ambiguous", 15, [
    "Je veux plus de bananes",
    "Je ne veux plus de bananes",
    "J'ai plus de bananes",
    "Ajoute plus de bananes",
    "Annule pas le rendez-vous",
    "Ne crée pas de tâche",
    "Je veux pas le supprimer",
    "Pas demain après-demain",
    "Plutôt mardi que lundi",
    "Mets-le demain",
    "Décale le rendez-vous",
    "Oui mais demain",
    "Non plutôt mardi",
    "Peut-être",
    "Achète du lait et décale le rendez-vous",
  ]],
]);

const variants = Object.freeze([
  (text) => text.toLowerCase(),
  (text) => text.toUpperCase(),
  (text) => `euh ${text.replace(/[’']/g, "")}`,
  (text) => text.normalize("NFD").replace(/[\u0300-\u036f]/g, ""),
  (text) => `bon alors ${text} stp`,
]);

const corpus = [];
for (const [intent, count, phrases] of definitions) {
  for (let index = 0; index < count; index += 1) {
    const variantIndex = Math.floor(index / phrases.length);
    const rawText = variants[variantIndex](
        phrases[index % phrases.length],
    );
    const normalization = normalizeNaturalLanguage(rawText);
    corpus.push(Object.freeze({
      id: `${intent}-${String(index + 1).padStart(3, "0")}`,
      rawText,
      normalizedText: normalization.normalizedText,
      expectedIntent: intent,
      expectedEntities: Object.freeze([]),
      understandingLevel: intent === "ambiguous" ?
        "ambiguous" : normalization.normalizationCodes.length === 0 ?
          "exactMatch" : "normalizedMatch",
      disposition: intent === "ambiguous" ?
        "clarification" : "confirmation",
      synthetic: true,
    }));
  }
}

module.exports = Object.freeze(corpus);
