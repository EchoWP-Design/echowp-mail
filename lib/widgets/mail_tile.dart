import 'package:flutter/material.dart';

import '../models.dart';
import 'common.dart';

class MailTile extends StatelessWidget {
  final MailItem item;
  final bool selected;
  final bool opened;
  final Color? accountColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAvatarTap;

  const MailTile({
    super.key,
    required this.item,
    required this.selected,
    required this.opened,
    required this.accountColor,
    required this.onTap,
    required this.onLongPress,
    required this.onAvatarTap,
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
                      if (item.flagged) const Icon(Icons.flag, size: 16, color: Color(0xFFFB8C00)),
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
