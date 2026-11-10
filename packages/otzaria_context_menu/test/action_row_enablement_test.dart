import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart';

void main() {
  test('disabled action rows cannot enable a parent submenu', () {
    final inactiveIcon = AppContextMenuEntry.iconRow(const [
      AppContextMenuIconAction(icon: Icons.copy, label: 'No action'),
      AppContextMenuIconAction(
        icon: Icons.share,
        label: 'Disabled callback',
        enabled: false,
        onTap: _noop,
      ),
    ]);
    final inactiveColor = AppContextMenuEntry.colorRow(const [
      AppContextMenuColorAction(
        id: 'gray',
        color: Colors.grey,
        label: 'Unavailable',
      ),
    ]);
    expect(
      hasEnabledAppContextMenuEntries([
        const AppContextMenuEntry.divider(),
        inactiveIcon,
        inactiveColor,
      ]),
      isFalse,
    );
  });

  test('active icon callbacks or nested icon submenus enable rows', () {
    final callback = AppContextMenuEntry.iconRow([
      const AppContextMenuIconAction(icon: Icons.copy, onTap: _noop),
    ]);
    final submenu = AppContextMenuEntry.iconRow([
      AppContextMenuIconAction(
        icon: Icons.link,
        submenuBuilder: () => [
          const AppContextMenuSubAction(label: 'Link', onTap: _noop),
        ],
      ),
    ]);
    expect(hasEnabledAppContextMenuEntries([callback]), isTrue);
    expect(hasEnabledAppContextMenuEntries([submenu]), isTrue);
  });

  test('color rows require at least one active color', () {
    final colors = AppContextMenuEntry.colorRow([
      const AppContextMenuColorAction(
        id: 'inactive',
        color: Colors.blue,
        label: 'Blue',
      ),
      const AppContextMenuColorAction(
        id: 'active',
        color: Colors.red,
        label: 'Red',
        onTap: _noop,
      ),
    ]);
    expect(hasEnabledAppContextMenuEntries([colors]), isTrue);
  });

  test('normal entries preserve their existing enabled semantics', () {
    expect(
      hasEnabledAppContextMenuEntries([
        const AppContextMenuEntry(label: 'Placeholder'),
      ]),
      isTrue,
    );
    expect(
      hasEnabledAppContextMenuEntries([
        const AppContextMenuEntry(label: 'Disabled', enabled: false),
      ]),
      isFalse,
    );
  });
}

void _noop() {}
