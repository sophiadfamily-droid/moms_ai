import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpInformationScreen extends StatefulWidget {
  const HelpInformationScreen({super.key});

  @override
  State<HelpInformationScreen> createState() => _HelpInformationScreenState();
}

class _HelpInformationScreenState extends State<HelpInformationScreen> {
  static const _background = Color(0xFFF8EFEA);
  static const _accent = Color(0xFFE95D5D);
  static const _soft = Color(0xFF8B6F67);
  final _searchController = TextEditingController();
  String _query = '';
  String _selectedCategory = 'Tout';
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_FaqItem> get _visibleQuestions {
    final words = _query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    return _faq.where((item) {
      if (_selectedCategory != 'Tout' && item.category != _selectedCategory) {
        return false;
      }
      if (words.isEmpty) return true;
      final text =
          '${item.category} ${item.question} ${item.answer}'.toLowerCase();
      return words.every(text.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleQuestions = _visibleQuestions;
    final categories = <String>[];
    for (final item in visibleQuestions) {
      if (!categories.contains(item.category)) categories.add(item.category);
    }

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        title: const Text('Aide'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const Text(
            'Comment puis-je t’aider ?',
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Rechercher une question…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _allCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = _allCategories[index];
                return ChoiceChip(
                  label: Text(category),
                  selected: category == _selectedCategory,
                  showCheckmark: false,
                  selectedColor: _accent.withValues(alpha: 0.14),
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                  side: BorderSide(color: _soft.withValues(alpha: 0.12)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (_) =>
                      setState(() => _selectedCategory = category),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle(_query.isNotEmpty
              ? '${visibleQuestions.length} RÉSULTAT${visibleQuestions.length > 1 ? 'S' : ''}'
              : 'FOIRE AUX QUESTIONS'),
          const SizedBox(height: 4),
          if (visibleQuestions.isEmpty)
            _emptySearch()
          else
            for (final category in categories) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 7),
                child: Text(
                  category,
                  style: const TextStyle(
                    color: _soft,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _card(
                children: [
                  for (final item
                      in visibleQuestions.where((q) => q.category == category))
                    _Question(title: item.question, answer: item.answer),
                ],
              ),
            ],
          const SizedBox(height: 28),
          _sectionTitle('BESOIN D’AIDE ?'),
          const SizedBox(height: 8),
          _card(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.support_agent, color: _accent),
                title: const Text(
                  'Contacter l’équipe Zelia',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Une question, un problème ou une idée'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showContactChoices,
              ),
            ],
          ),
          const SizedBox(height: 28),
          _sectionTitle('À PROPOS'),
          const SizedBox(height: 8),
          _card(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined, color: _accent),
                title: const Text('Conditions d’utilisation'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showInformation(
                  'Conditions d’utilisation',
                  'Le document juridique définitif sera ajouté avant la publication de Zelia. Cette page restera accessible ici.',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined, color: _accent),
                title: const Text('Politique de confidentialité'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showInformation(
                  'Politique de confidentialité',
                  'La politique définitive expliquera précisément quelles données sont utilisées, pourquoi elles le sont et comment demander leur suppression.',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline, color: _accent),
                title: const Text('Version de Zelia'),
                trailing: Text(_version.isEmpty ? '…' : _version),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptySearch() => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Column(
          children: [
            Icon(Icons.search_off, color: _accent, size: 38),
            SizedBox(height: 12),
            Text('Je n’ai pas trouvé cette question.',
                style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Essaie avec des mots plus simples.',
                style: TextStyle(color: _soft)),
          ],
        ),
      );

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Text(
          title,
          style: const TextStyle(
            color: _soft,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
      );

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _soft.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: _soft.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(children: children),
      );

  Future<void> _showContactChoices() => showModalBottomSheet<void>(
        context: context,
        backgroundColor: _background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _soft.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Contacter l’équipe Zelia',
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _contactChoice(
                  icon: Icons.help_outline,
                  label: 'Poser une question',
                  subject: 'Question sur Zelia',
                ),
                _contactChoice(
                  icon: Icons.report_problem_outlined,
                  label: 'Signaler un problème',
                  subject: 'Problème rencontré dans Zelia',
                ),
                _contactChoice(
                  icon: Icons.lightbulb_outline,
                  label: 'Partager une suggestion',
                  subject: 'Suggestion pour Zelia',
                ),
              ],
            ),
          ),
        ),
      );

  Widget _contactChoice({
    required IconData icon,
    required String label,
    required String subject,
  }) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: _accent),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          Navigator.pop(context);
          final uri = Uri(
            scheme: 'mailto',
            path: 'sophiadfamily@gmail.com',
            queryParameters: {
              'subject': subject,
              'body':
                  '\n\n—\nVersion Zelia : ${_version.isEmpty ? 'inconnue' : _version}',
            },
          );
          final opened = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!opened && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Impossible d’ouvrir l’application Mail pour le moment.',
                ),
              ),
            );
          }
        },
      );

  Future<void> _showInformation(String title, String text) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: _background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 28,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                Text(text, style: const TextStyle(color: _soft, height: 1.5)),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Question extends StatelessWidget {
  const _Question({required this.title, required this.answer});
  final String title;
  final String answer;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 16),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(answer,
                style: const TextStyle(color: Color(0xFF8B6F67), height: 1.45)),
          ),
        ],
      );
}

class _FaqItem {
  const _FaqItem(this.category, this.question, this.answer);
  final String category;
  final String question;
  final String answer;
}

const _allCategories = <String>[
  'Tout',
  'Découvrir Zelia',
  'Compte et profil',
  'Agenda et conflits',
  'Tâches, courses et routines',
  'Mémoire Zelia',
  'Notifications',
  'Voix et autorisations',
  'Sécurité et contrôle',
  'En cas de problème',
];

const _faq = <_FaqItem>[
  _FaqItem('Découvrir Zelia', 'À quoi sert Zelia ?',
      'Zelia t’aide à organiser ton agenda, tes tâches, tes courses, tes routines et les informations utiles à ton quotidien. Tu peux lui parler naturellement ou lui écrire.'),
  _FaqItem('Découvrir Zelia', 'Comment parler à Zelia ?',
      'Appuie sur le micro et parle comme à une assistante. Tu peux aussi écrire ton message. Donne simplement ce que tu sais : Zelia te demandera les informations manquantes.'),
  _FaqItem('Découvrir Zelia', 'Puis-je utiliser Zelia sans Internet ?',
      'Certaines pages restent accessibles, mais une connexion est nécessaire pour converser avec Zelia et synchroniser certaines informations.'),
  _FaqItem('Compte et profil', 'Pourquoi créer un compte Zelia ?',
      'Ton compte permet de retrouver tes informations lorsque tu te déconnectes, changes de téléphone ou te reconnectes.'),
  _FaqItem(
      'Compte et profil',
      'Comment modifier mes informations personnelles ?',
      'Ouvre Profil, puis appuie sur ta fiche. Tu peux y modifier tes informations, tes activités, tes lieux et ce que Zelia doit savoir sur toi.'),
  _FaqItem('Compte et profil', 'Comment ajouter une personne à mon foyer ?',
      'Dans Profil, appuie sur Ajouter un profil. Choisis le lien avec cette personne, complète sa fiche, puis enregistre.'),
  _FaqItem('Compte et profil', 'Puis-je supprimer un profil familial ?',
      'Oui. Ouvre la fiche de la personne puis choisis Supprimer ce profil. Une confirmation est toujours demandée.'),
  _FaqItem('Compte et profil', 'Comment ajouter ou changer une photo ?',
      'Ouvre la fiche concernée, appuie sur l’appareil photo placé sur l’avatar, puis choisis une image dans ta photothèque.'),
  _FaqItem('Agenda et conflits', 'Comment créer un rendez-vous ?',
      'Dis par exemple « rendez-vous dentiste demain à 15 heures ». Zelia complètera avec toi le motif, la durée, les trajets et la marge si nécessaire.'),
  _FaqItem(
      'Agenda et conflits',
      'Pourquoi Zelia demande la durée et les trajets ?',
      'Ces informations lui permettent de réserver le bon temps et de détecter les chevauchements avant qu’ils ne compliquent ta journée.'),
  _FaqItem(
      'Agenda et conflits',
      'Que se passe-t-il si deux choses se chevauchent ?',
      'Zelia t’indique précisément les deux éléments concernés et peut proposer une solution. Rien n’est déplacé sans ton accord.'),
  _FaqItem(
      'Agenda et conflits',
      'Puis-je modifier ou supprimer un rendez-vous ?',
      'Oui. Ouvre le rendez-vous dans Agenda ou demande à Zelia de le modifier ou de le supprimer. Elle te fera confirmer le changement.'),
  _FaqItem('Tâches, courses et routines', 'Comment créer une tâche ?',
      'Demande simplement à Zelia, par exemple « rappelle-moi d’appeler le médecin demain », ou utilise le bouton d’ajout dans Tâches.'),
  _FaqItem(
      'Tâches, courses et routines',
      'À quoi servent les priorités des tâches ?',
      'Elles aident Zelia à faire ressortir ce qui mérite ton attention en premier, sans cacher le reste.'),
  _FaqItem(
      'Tâches, courses et routines',
      'Comment ajouter un produit à ma liste de courses ?',
      'Dis « ajoute du lait à mes courses » ou ouvre Courses et ajoute le produit directement.'),
  _FaqItem('Tâches, courses et routines', 'Qu’est-ce qu’une routine ?',
      'Une routine est une habitude qui revient régulièrement, par exemple l’école, un traitement ou une activité. Zelia peut en tenir compte dans ton organisation.'),
  _FaqItem('Mémoire Zelia', 'Qu’est-ce que Mémoire Zelia ?',
      'C’est l’espace prévu pour voir les informations utiles retenues au fil des conversations. Le raccordement complet à toutes les conversations sera réalisé dans une prochaine étape du projet.'),
  _FaqItem('Mémoire Zelia', 'Puis-je corriger ou supprimer un souvenir ?',
      'Oui. Lorsqu’un souvenir apparaît dans Mémoire Zelia, tu peux l’ouvrir pour le modifier, l’archiver ou le supprimer.'),
  _FaqItem(
      'Mémoire Zelia',
      'Quelle différence entre mon profil et la mémoire ?',
      'Le profil contient les informations structurées que tu remplis toi-même. La mémoire regroupe les éléments utiles appris pendant tes conversations avec Zelia.'),
  _FaqItem('Notifications', 'Comment activer ou désactiver les notifications ?',
      'Ouvre Profil, puis Notifications pour choisir celles que tu souhaites. Les autorisations générales se modifient dans les réglages de l’iPhone.'),
  _FaqItem('Notifications', 'Pourquoi je ne reçois pas une notification ?',
      'Vérifie que les notifications sont autorisées dans les réglages de l’iPhone et qu’elles sont activées dans Zelia. Vérifie aussi les modes Concentration ou Ne pas déranger.'),
  _FaqItem(
      'Notifications',
      'Que se passe-t-il quand je touche une notification ?',
      'Zelia ouvre directement l’endroit concerné lorsque le lien est disponible, par exemple le bon jour dans l’Agenda.'),
  _FaqItem(
      'Voix et autorisations',
      'Pourquoi Zelia demande l’accès au microphone ?',
      'Uniquement pour écouter ta demande lorsque tu utilises le bouton micro. Tu peux continuer à écrire sans cet accès.'),
  _FaqItem('Voix et autorisations', 'Pourquoi Zelia demande ma localisation ?',
      'La localisation sert à afficher ta ville, adapter ton pays et préparer des fonctions utiles comme les trajets. Tu peux retirer cet accès dans les réglages de l’iPhone.'),
  _FaqItem('Voix et autorisations', 'Où modifier les accès au téléphone ?',
      'Ouvre Profil, Confidentialité et mes données, puis Réglages de l’iPhone. Tu y trouveras la localisation, les photos, le microphone et les notifications.'),
  _FaqItem(
      'Sécurité et contrôle',
      'Est-ce que Zelia change quelque chose sans mon accord ?',
      'Non. Zelia peut préparer et proposer une action, mais elle attend toujours ton accord avant de modifier ton organisation.'),
  _FaqItem('Sécurité et contrôle', 'Où sont stockées mes informations ?',
      'Les informations liées à ton profil sont rattachées à ton compte Zelia. Les détails complets seront présentés dans la politique de confidentialité avant la publication.'),
  _FaqItem('En cas de problème', 'Que faire si Zelia ne répond pas ?',
      'Vérifie ta connexion Internet, attends un instant puis réessaie. Si le problème continue, ferme et rouvre l’application.'),
  _FaqItem(
      'En cas de problème',
      'Que faire si une modification n’apparaît pas ?',
      'Reviens sur la page concernée ou actualise-la. Si nécessaire, ferme puis rouvre Zelia afin de relancer l’affichage.'),
  _FaqItem(
      'En cas de problème',
      'Que faire si l’application reste sur un écran vide ?',
      'Ferme complètement Zelia puis rouvre-la. Si cela se reproduit, note l’action faite juste avant afin que le problème puisse être corrigé précisément.'),
];
