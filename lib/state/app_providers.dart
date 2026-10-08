import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/integration_models.dart';
import 'core_providers.dart';

/// null means "follow the device language" (Arabic or English, otherwise English).
class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    final code = ref.watch(prefsProvider).locale;
    return code == 'ar' || code == 'en' ? Locale(code) : null;
  }

  Future<void> set(String code) async {
    await ref.read(prefsProvider).setLocale(code);
    state = code == 'ar' || code == 'en' ? Locale(code) : null;
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

class NotificationsNotifier extends Notifier<List<AppNotification>> {
  @override
  List<AppNotification> build() => const <AppNotification>[];

  void push(String title, String body, {bool isError = false}) {
    final entry = AppNotification(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      body: body,
      createdAt: DateTime.now(),
      isError: isError,
    );
    state = [entry, ...state].take(50).toList();
  }

  void clear() => state = const <AppNotification>[];
}

final notificationsProvider = NotifierProvider<NotificationsNotifier, List<AppNotification>>(NotificationsNotifier.new);
