import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';

void main() {
  group('SelectionSyncController', () {
    test('מעביר בעלות בחירה לאזור האחרון שהופעל', () {
      final controller = SelectionSyncController();
      final firstOwner = Object();
      final secondOwner = Object();
      var notifications = 0;

      controller.addListener(() {
        notifications++;
      });

      controller.activate(firstOwner);

      expect(controller.activeOwner, same(firstOwner));
      expect(controller.revision, 1);
      expect(notifications, 1);

      controller.activate(secondOwner);

      expect(controller.activeOwner, same(secondOwner));
      expect(controller.revision, 2);
      expect(notifications, 2);
    });

    test('לא שולח notify נוסף כשאותו אזור מופעל שוב', () {
      final controller = SelectionSyncController();
      final owner = Object();
      var notifications = 0;

      controller.addListener(() {
        notifications++;
      });

      controller.activate(owner);
      controller.activate(owner);

      expect(controller.activeOwner, same(owner));
      expect(controller.revision, 1);
      expect(notifications, 1);
    });

    test('מתעלם מניקוי של אזור שכבר איבד בעלות', () {
      final controller = SelectionSyncController();
      final firstOwner = Object();
      final secondOwner = Object();
      var notifications = 0;

      controller.addListener(() {
        notifications++;
      });

      controller.activate(firstOwner);
      controller.activate(secondOwner);
      controller.clear(firstOwner);

      expect(controller.activeOwner, same(secondOwner));
      expect(controller.revision, 2);
      expect(notifications, 2);
    });

    test('מאפשר רק לאזור הפעיל לנקות את הבחירה', () {
      final controller = SelectionSyncController();
      final owner = Object();
      var notifications = 0;

      controller.addListener(() {
        notifications++;
      });

      controller.activate(owner);
      controller.clear(owner);

      expect(controller.activeOwner, isNull);
      expect(controller.revision, 2);
      expect(notifications, 2);
    });
  });
}
