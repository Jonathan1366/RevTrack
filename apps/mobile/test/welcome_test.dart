import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revtrack/main.dart';
import 'package:revtrack/widgets/welcome.dart';
import 'package:revtrack/widgets/vehicle_card.dart';

void main() {
  Future<void> start(WidgetTester tester, Size size, {double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true, highContrast: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(const RevTrackApp(enableWelcomeVideo: false));
    await tester.pumpAndSettle();
  }

  testWidgets('unconfigured Google sign-in never grants fleet access', (
    tester,
  ) async {
    await start(tester, const Size(390, 844));
    expect(find.byType(FleetHome), findsNothing);
    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pumpAndSettle();
    expect(find.text('Masuk ke RevTrack'), findsOneWidget);
    await tester.tap(find.text('Lanjutkan dengan Google'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Login Google belum diaktifkan'),
      findsOneWidget,
    );
    expect(find.byType(FleetHome), findsNothing);
    await tester.tap(find.text('Coba demo dulu'));
    await tester.pumpAndSettle();
    expect(find.byType(FleetHome), findsOneWidget);
    expect(find.text('DEMO'), findsOneWidget);
    await tester.tap(find.byTooltip('Kembali ke halaman awal'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.byType(FleetHome), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in [
    (const Size(320, 568), 1.0),
    (const Size(844, 390), 1.0),
    (const Size(390, 844), 1.6),
  ]) {
    testWidgets(
      'welcome and registration remain usable at ${viewport.$1} / ${viewport.$2}',
      (tester) async {
        await start(tester, viewport.$1, scale: viewport.$2);
        final register = find.text('Baru di RevTrack? Daftar');
        await tester.ensureVisible(register);
        await tester.tap(register);
        await tester.pumpAndSettle();
        expect(find.text('Daftar di RevTrack'), findsOneWidget);
        await tester.ensureVisible(find.text('Coba demo dulu'));
        await tester.tap(find.text('Coba demo dulu'));
        await tester.pumpAndSettle();
        expect(find.byType(FleetHome), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('missing energy is distinct from an empty battery', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [EnergyDial(value: null), EnergyDial(value: 0)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
