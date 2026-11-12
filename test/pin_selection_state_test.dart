import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/services/pin_selection_state.dart';
import 'package:safepaths_app/utils/geo_utils.dart';

void main() {
  testWidgets(
    'camera quiet time enables selection without any native idle event',
    (tester) async {
      var reads = 0;
      final state = PinSelectionState(
        readPoint: () async {
          reads++;
          return GeoCoord(14.67, 120.98);
        },
        quietPeriod: const Duration(milliseconds: 100),
      );
      state.cameraChanged('position-a');
      expect(state.moving, isTrue);
      await tester.pump(const Duration(milliseconds: 101));
      await tester.pump();
      expect(state.canConfirm, isTrue);
      expect(reads, 1);
      final revision = state.revision;
      state.cameraChanged('position-a');
      expect(state.moving, isFalse);
      expect(state.revision, revision);
      state.dispose();
    },
  );
  test(
    'an old asynchronous read cannot replace the newer selected pin',
    () async {
      final old = Completer<GeoCoord>(), latest = Completer<GeoCoord>();
      var count = 0;
      final state = PinSelectionState(
        readPoint: () => count++ == 0 ? old.future : latest.future,
      );
      state.cameraChanged('old');
      final first = state.refresh();
      state.cameraChanged('latest');
      final second = state.refresh();
      latest.complete(GeoCoord(14.68, 120.99));
      await second;
      old.complete(GeoCoord(14.67, 120.98));
      await first;
      expect(state.point!.lat, 14.68);
      expect(state.point!.lng, 120.99);
      expect(state.canConfirm, isTrue);
      state.dispose();
    },
  );
  test(
    'failed or invalid native reads explain failure and allow retry',
    () async {
      var fail = true;
      final state = PinSelectionState(
        readPoint: () async =>
            fail ? GeoCoord(double.nan, 0) : GeoCoord(14.67, 120.98),
      );
      await state.refresh();
      expect(state.failed, isTrue);
      expect(state.moving, isFalse);
      expect(state.canConfirm, isFalse);
      fail = false;
      await state.refresh();
      expect(state.failed, isFalse);
      expect(state.canConfirm, isTrue);
      state.dispose();
    },
  );
  test(
    'late reads after closing the picker do not notify or revive it',
    () async {
      final pending = Completer<GeoCoord>();
      final state = PinSelectionState(readPoint: () => pending.future);
      var notifications = 0;
      state.addListener(() => notifications++);
      final read = state.refresh();
      state.dispose();
      pending.complete(GeoCoord(14.67, 120.98));
      await read;
      expect(notifications, 0);
      expect(state.point, isNull);
    },
  );
}
