import 'package:flutter/material.dart';

import 'app_mode.dart';

/// Two-segment toggle between 阅 (bookshelf) and 搜 (agent chat).
///
/// Lives in the bookshelf rail (vertical) and in the chat shell's top bar
/// (horizontal). The reader page deliberately has none: it is a route on top of
/// the root, so switching there would leave the reader covering the other shell.
class ModeSwitch extends StatelessWidget {
  const ModeSwitch({
    super.key,
    required this.mode,
    required this.onChanged,
    this.axis = Axis.vertical,
    this.keyPrefix = 'mode',
  });

  final AppMode mode;
  final ValueChanged<AppMode> onChanged;
  final Axis axis;

  /// Distinguishes the rail copy from the chat copy; both can be in the tree at
  /// once because the shells are kept alive inside an [IndexedStack].
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _chip(context, AppMode.read, '阅'),
      _chip(context, AppMode.search, '搜'),
    ];
    final vertical = axis == Axis.vertical;
    final children = <Widget>[];
    for (var i = 0; i < chips.length; i++) {
      if (i > 0) {
        children.add(
          SizedBox(width: vertical ? 0 : 6, height: vertical ? 6 : 0),
        );
      }
      children.add(chips[i]);
    }
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _chip(BuildContext context, AppMode value, String label) {
    final theme = Theme.of(context);
    final active = mode == value;
    return Tooltip(
      message: value == AppMode.read ? '阅：书架' : '搜：对话',
      child: InkWell(
        key: Key('$keyPrefix-mode-${value.name}'),
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? theme.colorScheme.secondaryContainer : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
