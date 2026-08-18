import 'package:flutter/material.dart';

import '../services/contextual_support_card_service.dart';

/// Shared visual contract for the short support card on Tasks and Shopping.
/// Longer actionable suggestions deliberately use their own expanding card.
final class CompactContextualSupportCard extends StatelessWidget {
  const CompactContextualSupportCard({
    required this.supportMessage,
    required this.accent,
    required this.textColor,
    required this.secondaryTextColor,
    this.contentKey,
    super.key,
  });

  static const double visualHeight = 96;

  final ContextualSupportCardMessage supportMessage;
  final Color accent;
  final Color textColor;
  final Color secondaryTextColor;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: visualHeight,
      margin: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.90),
            accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              key: contentKey,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supportMessage.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  supportMessage.message,
                  key: Key(supportMessage.semanticKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
