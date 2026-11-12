import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/utils/closure_exit_recovery.dart';

void main() {
  late ClosureExitRecovery recovery;
  final start = DateTime(2026, 11, 11);
  bool fix(
    int seconds, {
    bool near = false,
    bool reliable = true,
    bool pending = false,
    bool paused = true,
  }) => recovery.observe(
    paused: paused,
    reliable: reliable,
    calculationPending: pending,
    nearClosure: near,
    fixTime: start.add(Duration(seconds: seconds)),
  );
  setUp(() => recovery = ClosureExitRecovery());
  test(
    'rechecks once only after three distinct clear fixes spanning six seconds',
    () {
      recovery.arm();
      expect(fix(0), isFalse);
      expect(fix(3), isFalse);
      expect(fix(6), isTrue);
      expect(fix(9), isFalse);
    },
  );
  test(
    'duplicate and older timestamps do not count as sustained clearance',
    () {
      recovery.arm();
      expect(fix(0), isFalse);
      expect(fix(0), isFalse);
      expect(fix(-1), isFalse);
      expect(fix(6), isFalse);
      expect(fix(7), isTrue);
    },
  );
  test('unreliable GPS interrupts the clear streak', () {
    recovery.arm();
    fix(0);
    fix(3);
    expect(fix(6, reliable: false), isFalse);
    expect(fix(7), isFalse);
    expect(fix(10), isFalse);
    expect(fix(13), isTrue);
  });
  test('returning near any closed road restarts clearance', () {
    recovery.arm();
    fix(0);
    fix(3);
    expect(fix(6, near: true), isFalse);
    expect(fix(7), isFalse);
    expect(fix(10), isFalse);
    expect(fix(13), isTrue);
  });
  test(
    'does not overlap a pending calculation or forget the near-closure history',
    () {
      recovery.arm();
      fix(0);
      fix(3);
      expect(fix(6, pending: true), isFalse);
      expect(fix(7), isFalse);
      expect(fix(10), isFalse);
      expect(fix(13), isTrue);
    },
  );
  test('normal navigation or adoption cancels an armed recovery', () {
    recovery.arm();
    expect(fix(0, paused: false), isFalse);
    fix(3);
    fix(6);
    expect(fix(9), isFalse);
    recovery.arm();
    recovery.reset();
    expect(fix(12), isFalse);
  });
  test('never rechecks a no-clear search without a near-closure origin', () {
    expect(fix(0), isFalse);
    expect(fix(3), isFalse);
    expect(fix(6), isFalse);
  });
  test('a long gap between fixes cannot count as continuous clearance', () {
    recovery.arm();
    fix(0);
    fix(3);
    expect(fix(40), isFalse);
    expect(fix(43), isFalse);
    expect(fix(46), isTrue);
  });
}
