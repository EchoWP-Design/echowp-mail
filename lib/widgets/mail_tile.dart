import 'package:flutter/material.dart';

import '../models.dart';
import 'common.dart';

class MailTile extends StatelessWidget {
  final MailItem item;
  final bool selected;
  final bool opened;
  final Color? accountColor;
  /// Hintergrundfarbe des Postfachs (Ansicht „Aktuell“), leicht hinterlegt.
  final Color? tint;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAvatarTap;
  final VoidCallback? onStarTap;

  const MailTile({
    super.key,
    required this.item,
    required this.selected,
    required this.opened,
    required this.accountColor,
    this.tint,
    required this.onTap,
    required this.onLongPress,
    required this.onAvatarTap,
    this.onStarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unread = !item.seen;
    final bg = selected
        ? cs.primaryContainer
        : opened
            ? cs.surfaceContainerHighest
            : tint != null
                ? accountTint(tint!, theme)
                : theme.scaffoldBackgroundColor;
    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
          child: Row(
            children: [
              Container(width: 4, height: 44, color: accountColor ?? Colors.transparent),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onAvatarTap,
                child: selected
                    ? CircleAvatar(
                        radius: 20,
                        backgroundColor: cs.primary,
                        child: Icon(Icons.check, color: cs.onPrimary),
                      )
                    : SenderAvatar(name: item.sender),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (unread)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: CircleAvatar(radius: 4, backgroundColor: cs.primary),
                        ),
                      Expanded(
                        child: Text(
                          item.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: unread ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatListDate(item.date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: unread ? cs.primary : cs.onSurfaceVariant,
                          fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      Expanded(
                        child: Text(
                          item.subject,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                            color: unread ? cs.onSurface : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (item.hasAttachments)
                        Icon(Icons.attach_file, size: 16, color: cs.onSurfaceVariant),
                      StarButton(starred: item.flagged, onTap: onStarTap),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stern-Farbe (EchoWP-Gelb, im hellen Design etwas dunkler für Kontrast).
Color starColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFD400) : const Color(0xFFE0B000);

/// Anklickbarer Stern in der Mailliste.
class StarButton extends StatelessWidget {
  final bool starred;
  final VoidCallback? onTap;
  const StarButton({super.key, required this.starred, this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      starred ? Icons.star : Icons.star_border,
      size: 20,
      color: starred ? starColor(context) : Theme.of(context).colorScheme.outline,
    );
    if (onTap == null) return starred ? icon : const SizedBox.shrink();
    return Tooltip(
      message: starred ? 'Stern entfernen' : 'Mit Stern markieren',
      child: InkResponse(
        key: const ValueKey('star'),
        onTap: onTap,
        radius: 18,
        child: Padding(padding: const EdgeInsets.only(left: 6), child: icon),
      ),
    );
  }
}

/// Postfachfarbe dezent über den Hintergrund gelegt (Text bleibt gut lesbar).
Color accountTint(Color c, ThemeData theme) => Color.alphaBlend(
    c.withValues(alpha: theme.brightness == Brightness.dark ? 0.22 : 0.14), theme.scaffoldBackgroundColor);

class SwipeBackground extends StatelessWidget {
  final SwipeAction action;
  final bool alignLeft;
  const SwipeBackground({super.key, required this.action, required this.alignLeft});

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(action.icon, color: Colors.white),
      const SizedBox(width: 8),
      Text(action.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    ];
    return Container(
      color: action.color,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignLeft ? children : children.reversed.toList(),
      ),
    );
  }
}
