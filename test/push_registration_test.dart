import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/services/push_device_registration.dart';

void main() {
  test(
    'registration serializes account switches and uses increasing device sequences',
    () async {
      String? uid = 'resident';
      Map<String, dynamic>? stored;
      final sent = <Map<String, dynamic>>[];
      final first = Completer<void>();
      final service = PushDeviceRegistration(
        currentUid: () => uid,
        read: () async => stored,
        write: (value) async {
          stored = Map.of(value);
        },
        send: (value) async {
          sent.add(Map.of(value));
          if (sent.length == 1) await first.future;
        },
      );
      final old = service.update(
        uid: 'resident',
        token: 'token',
        enabled: true,
      );
      await Future<void>.delayed(Duration.zero);
      uid = 'other';
      final current = service.update(
        uid: 'other',
        token: 'token',
        enabled: true,
      );
      first.complete();
      await Future.wait([old, current]);
      expect(sent.map((v) => v['sequence']), [1, 2]);
      expect(sent[0]['installation'], sent[1]['installation']);
      expect(stored!.keys, unorderedEquals(['installation', 'sequence']));
    },
  );
  test(
    'account changes during preference IO prevent a stale registration',
    () async {
      String? uid = 'resident';
      final ready = Completer<void>();
      var calls = 0;
      final service = PushDeviceRegistration(
        currentUid: () => uid,
        read: () async {
          await ready.future;
          return null;
        },
        write: (value) async {},
        send: (value) async {
          calls++;
        },
      );
      final result = service.update(
        uid: 'resident',
        token: 'old',
        enabled: true,
      );
      await Future<void>.delayed(Duration.zero);
      uid = 'other';
      ready.complete();
      await result;
      expect(calls, 0);
    },
  );
  test('a failed registration does not block a later unregister', () async {
    Map<String, dynamic>? stored;
    final sent = <Map<String, dynamic>>[];
    final service = PushDeviceRegistration(
      currentUid: () => 'resident',
      read: () async => stored,
      write: (value) async {
        stored = value;
      },
      send: (value) async {
        sent.add(value);
        if (sent.length == 1) throw StateError('offline');
      },
    );
    await expectLater(
      service.update(uid: 'resident', token: 'token', enabled: true),
      throwsStateError,
    );
    await service.update(uid: 'resident', enabled: false);
    expect(sent.last['sequence'], 2);
    expect(sent.last['mode'], 'unregister');
    expect(sent.last.containsKey('token'), false);
  });
}
