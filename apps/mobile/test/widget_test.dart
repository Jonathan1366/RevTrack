import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revtrack/main.dart';
import 'package:revtrack/widgets/map_experience.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await font.load();
  });
  Future<void> start(
    WidgetTester tester, {
    Size size = const Size(1440, 1100),
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RevTrackApp());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'dashboard clearly labels demo telemetry and missing Mapbox configuration',
    (tester) async {
      await start(tester);
      expect(find.text('DEMO'), findsOneWidget);
      expect(find.text('Peta skematik · DEMO'), findsOneWidget);
      expect(find.textContaining('Mapbox belum aktif'), findsOneWidget);
      expect(
        find.text('Semua bergerak. Anda memegang kendali.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fleet search filters units and detail opens for the matching vehicle',
    (tester) async {
      await start(tester);
      await tester.tap(find.text('Armada').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fleet-search')),
        '2086',
      );
      await tester.pumpAndSettle();
      expect(find.text('Toyota Avanza'), findsOneWidget);
      expect(find.text('Hyundai IONIQ 5'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('vehicle-veh-002')));
      await tester.pumpAndSettle();
      expect(find.text('Profil bahan bakar'), findsOneWidget);
      expect(find.text('Linimasa perjalanan · ilustrasi'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(VehicleDetail),
          matching: find.text('64%'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('alert acknowledgment is local and updates its action', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.text('Peringatan').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Tandai ditinjau').first,
    );
    await tester.pumpAndSettle();
    expect(find.text('✓ Ditinjau · sesi lokal'), findsOneWidget);
    expect(find.textContaining('2 peringatan perlu ditinjau.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone navigation and EV filter remain usable without overflow', (
    tester,
  ) async {
    await start(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Armada').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'EV'));
    await tester.pumpAndSettle();
    expect(find.text('Hyundai IONIQ 5'), findsOneWidget);
    expect(find.text('Toyota Avanza'), findsNothing);
    await tester.tap(find.text('Rev AI').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Analisis aturan · bukan model generatif'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('map marker selection changes vehicle energy details', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byKey(const ValueKey('map-veh-003')));
    await tester.pumpAndSettle();
    expect(find.text('26%'), findsWidgets);
    expect(find.text('BYD Atto 3'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone map controls and route errors remain usable', (
    tester,
  ) async {
    await start(tester, size: const Size(390, 844));
    await tester.ensureVisible(find.byKey(const ValueKey('open-map')));
    await tester.tap(find.byKey(const ValueKey('open-map')));
    await tester.pumpAndSettle();
    expect(find.byType(MapExperience), findsOneWidget);
    expect(find.text('RevTrack Maps'), findsOneWidget);
    await tester.tap(find.text('Monas'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mapbox'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline operations explain API setup without fake mutations', (
    tester,
  ) async {
    await start(tester, size: const Size(390, 844));
    await tester.tap(find.text('Operasi').last);
    await tester.pumpAndSettle();
    expect(find.text('Hubungkan workspace ke API'), findsOneWidget);
    expect(find.text('Booking baru'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
