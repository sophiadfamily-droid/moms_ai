import '../models/memory_lifecycle.dart';

final class MemoryConfirmationCopy {
  const MemoryConfirmationCopy();

  String proposal(MemoryConfirmationRequest request) {
    final value = request.newValue?.trim() ?? '';
    return value.isEmpty
        ? 'Souhaites-tu que je retienne cette information ?'
        : 'Souhaites-tu que je retienne cette information : « $value » ?';
  }

  String get clarification =>
      'Souhaites-tu que je retienne cette information, oui ou non ?';

  String get confirmed => 'C’est noté, cette information est mémorisée.';

  String get rejected => 'D’accord, je ne retiendrai pas cette information.';

  String get alreadyActive => 'Cette information est déjà mémorisée.';

  String get unavailable =>
      'Cette proposition n’est plus disponible ou a déjà été traitée.';

  String get persistenceFailure =>
      'Je n’ai pas pu enregistrer ce choix. Tu peux réessayer.';
}
