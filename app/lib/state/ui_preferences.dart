import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Presentation choices for screens that have no Phase 1–4 service.
///
/// Handwriting recognition and mobile-data sync are stored here so the
/// settings screen can show them. They do not start ML Kit or change sync.
class UiPreferences {
  const UiPreferences({
    this.inLibrary = false,
    this.themeMode = ThemeMode.system,
    this.displayName = '',
    this.email = '',
    this.handwritingOn = true,
    this.syncOverMobile = true,
    this.exportPdf = true,
  });

  final bool inLibrary;
  final ThemeMode themeMode;
  final String displayName;
  final String email;

  /// UI-only. Search still uses text already saved on a page.
  final bool handwritingOn;

  /// UI-only. The sync service has no mobile-data switch.
  final bool syncOverMobile;
  final bool exportPdf;

  String get appearanceLabel => switch (themeMode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  String get exportLabel => exportPdf ? 'PDF' : 'Image';

  String get handwritingLabel => handwritingOn ? 'On' : 'Off';

  String get mobileDataLabel => syncOverMobile ? 'On' : 'Off';

  String get initial {
    final name = displayName.trim();
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  UiPreferences copyWith({
    bool? inLibrary,
    ThemeMode? themeMode,
    String? displayName,
    String? email,
    bool? handwritingOn,
    bool? syncOverMobile,
    bool? exportPdf,
  }) {
    return UiPreferences(
      inLibrary: inLibrary ?? this.inLibrary,
      themeMode: themeMode ?? this.themeMode,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      handwritingOn: handwritingOn ?? this.handwritingOn,
      syncOverMobile: syncOverMobile ?? this.syncOverMobile,
      exportPdf: exportPdf ?? this.exportPdf,
    );
  }
}

final uiPreferencesProvider =
    NotifierProvider<UiPreferencesController, UiPreferences>(
      UiPreferencesController.new,
    );

class UiPreferencesController extends Notifier<UiPreferences> {
  @override
  UiPreferences build() => const UiPreferences();

  void enterLibrary() {
    state = state.copyWith(inLibrary: true);
  }

  void cycleAppearance() {
    final next = switch (state.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    state = state.copyWith(themeMode: next);
  }

  void toggleHandwriting() {
    state = state.copyWith(handwritingOn: !state.handwritingOn);
  }

  void toggleMobileData() {
    state = state.copyWith(syncOverMobile: !state.syncOverMobile);
  }

  void cycleExport() {
    state = state.copyWith(exportPdf: !state.exportPdf);
  }

  void rememberProfile({required String name, required String email}) {
    state = state.copyWith(displayName: name, email: email);
  }

  void clearProfile() {
    state = state.copyWith(displayName: '', email: '');
  }
}
