import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/services/active_audio.dart';

void main() {
  // Isolate ActiveAudio state between tests. Since it's a static singleton we
  // reset it by having a dummy stop take the slot and then releasing it.
  tearDown(() async {
    final dummy = () {};
    await ActiveAudio.claim(dummy);
    ActiveAudio.release(dummy);
  });

  group('ActiveAudio', () {
    test('first claim does not invoke any stop', () async {
      var stopCalls = 0;
      Future<void> stop() async {
        stopCalls++;
      }

      await ActiveAudio.claim(stop);
      expect(stopCalls, 0);
      ActiveAudio.release(stop);
    });

    test('second claim stops the previous source', () async {
      var aStopped = 0;
      var bStopped = 0;
      Future<void> stopA() async {
        aStopped++;
      }

      Future<void> stopB() async {
        bStopped++;
      }

      await ActiveAudio.claim(stopA);
      await ActiveAudio.claim(stopB);

      expect(aStopped, 1, reason: 'A should have been stopped when B claimed');
      expect(bStopped, 0, reason: 'B is now active; it should not be stopped');
      ActiveAudio.release(stopB);
    });

    test('claiming the same stop twice does not stop itself', () async {
      var stopCalls = 0;
      Future<void> stop() async {
        stopCalls++;
      }

      await ActiveAudio.claim(stop);
      await ActiveAudio.claim(stop);
      expect(stopCalls, 0);
      ActiveAudio.release(stop);
    });

    test('release clears active source only when called by the active one',
        () async {
      var aStopped = 0;
      Future<void> stopA() async {
        aStopped++;
      }

      Future<void> stopB() async {}

      await ActiveAudio.claim(stopA);
      // stopB is not active — release should be a no-op for it.
      ActiveAudio.release(stopB);
      // Active source is still A; a new claim should stop A.
      await ActiveAudio.claim(stopB);
      expect(aStopped, 1);
      ActiveAudio.release(stopB);
    });

    test('release by active source clears the slot (no-op on next release)',
        () async {
      var aStopped = 0;
      Future<void> stopA() async {
        aStopped++;
      }

      await ActiveAudio.claim(stopA);
      ActiveAudio.release(stopA);
      // Subsequent claim by a different source should NOT invoke stopA.
      Future<void> stopB() async {}
      await ActiveAudio.claim(stopB);
      expect(aStopped, 0);
      ActiveAudio.release(stopB);
    });

    test('chain of claims stops each predecessor once', () async {
      var aStopped = 0;
      var bStopped = 0;
      var cStopped = 0;
      Future<void> stopA() async {
        aStopped++;
      }

      Future<void> stopB() async {
        bStopped++;
      }

      Future<void> stopC() async {
        cStopped++;
      }

      await ActiveAudio.claim(stopA);
      await ActiveAudio.claim(stopB);
      await ActiveAudio.claim(stopC);

      expect(aStopped, 1);
      expect(bStopped, 1);
      expect(cStopped, 0);
      ActiveAudio.release(stopC);
    });

    test('claim swallows a throwing stop so the new source still becomes active',
        () async {
      Future<void> badStop() async {
        throw StateError('boom');
      }

      var goodStopped = 0;
      Future<void> goodStop() async {
        goodStopped++;
      }

      await ActiveAudio.claim(badStop);
      await ActiveAudio.claim(goodStop);
      // goodStop is now active; claiming something else stops it.
      Future<void> another() async {}
      await ActiveAudio.claim(another);
      expect(goodStopped, 1);
      ActiveAudio.release(another);
    });
  });

  group('ActiveAudio background layer', () {
    // Pump the microtask queue a few times so fire-and-forget resume calls
    // queued by `release` have a chance to run before we assert.
    Future<void> flushMicrotasks() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('isForegroundActive reflects current slot', () async {
      Future<void> stop() async {}
      expect(ActiveAudio.isForegroundActive, isFalse);
      await ActiveAudio.claim(stop);
      expect(ActiveAudio.isForegroundActive, isTrue);
      ActiveAudio.release(stop);
      expect(ActiveAudio.isForegroundActive, isFalse);
    });

    test('foreground claim pauses background; release resumes it', () async {
      var pauseCalls = 0;
      var resumeCalls = 0;
      final handle = BackgroundAudioHandle(
        pause: () async => pauseCalls++,
        resume: () async => resumeCalls++,
      );
      ActiveAudio.registerBackground(handle);

      Future<void> stop() async {}
      await ActiveAudio.claim(stop);
      expect(pauseCalls, 1, reason: 'claim should pause the background');
      expect(resumeCalls, 0);

      ActiveAudio.release(stop);
      await flushMicrotasks();
      expect(resumeCalls, 1, reason: 'release should resume the background');
      expect(pauseCalls, 1);

      ActiveAudio.unregisterBackground(handle);
    });

    test('baton-pass between foreground sources does not re-pause background',
        () async {
      var pauseCalls = 0;
      final handle = BackgroundAudioHandle(
        pause: () async => pauseCalls++,
        resume: () async {},
      );
      ActiveAudio.registerBackground(handle);

      Future<void> stopA() async {}
      Future<void> stopB() async {}
      await ActiveAudio.claim(stopA); // 0 → 1 active — pause fires
      await ActiveAudio.claim(stopB); // baton pass — no extra pause
      expect(pauseCalls, 1);

      ActiveAudio.release(stopB);
      ActiveAudio.unregisterBackground(handle);
    });

    test('release resumes only once even if called multiple times', () async {
      var resumeCalls = 0;
      final handle = BackgroundAudioHandle(
        pause: () async {},
        resume: () async => resumeCalls++,
      );
      ActiveAudio.registerBackground(handle);

      Future<void> stop() async {}
      await ActiveAudio.claim(stop);
      ActiveAudio.release(stop);
      ActiveAudio.release(stop); // second call: identity no longer matches
      await flushMicrotasks();
      expect(resumeCalls, 1);

      ActiveAudio.unregisterBackground(handle);
    });

    test('unregistering the background stops further pause/resume callbacks',
        () async {
      var pauseCalls = 0;
      var resumeCalls = 0;
      final handle = BackgroundAudioHandle(
        pause: () async => pauseCalls++,
        resume: () async => resumeCalls++,
      );
      ActiveAudio.registerBackground(handle);
      ActiveAudio.unregisterBackground(handle);

      Future<void> stop() async {}
      await ActiveAudio.claim(stop);
      ActiveAudio.release(stop);
      await flushMicrotasks();
      expect(pauseCalls, 0);
      expect(resumeCalls, 0);
    });

    test('registering a second background replaces the first', () async {
      var oldPauseCalls = 0;
      var newPauseCalls = 0;
      final oldHandle = BackgroundAudioHandle(
        pause: () async => oldPauseCalls++,
        resume: () async {},
      );
      final newHandle = BackgroundAudioHandle(
        pause: () async => newPauseCalls++,
        resume: () async {},
      );
      ActiveAudio.registerBackground(oldHandle);
      ActiveAudio.registerBackground(newHandle);

      Future<void> stop() async {}
      await ActiveAudio.claim(stop);
      expect(oldPauseCalls, 0);
      expect(newPauseCalls, 1);

      ActiveAudio.release(stop);
      ActiveAudio.unregisterBackground(newHandle);
    });

    test('release swallows exceptions thrown by the resume callback',
        () async {
      final handle = BackgroundAudioHandle(
        pause: () async {},
        resume: () async => throw StateError('resume boom'),
      );
      ActiveAudio.registerBackground(handle);

      Future<void> stop() async {}
      await ActiveAudio.claim(stop);
      // Should not throw even though resume throws.
      expect(() => ActiveAudio.release(stop), returnsNormally);
      await flushMicrotasks();

      ActiveAudio.unregisterBackground(handle);
    });

    // ====================================================================
    // Regression: method tear-offs passed to claim() and release() are
    // not `identical()` to one another, they just compare equal. Using
    // `identical` in the arbiter caused release() to no-op, which left
    // the slot stuck and the background music paused forever.
    // ====================================================================

    test(
        'release matches a previously-claimed method tear-off (== semantics, '
        'not identical)', () async {
      // Sanity check the Dart semantics this test depends on.
      final source = _TearOffSource();
      expect(identical(source.stop, source.stop), isFalse,
          reason: 'tear-offs produce new Function objects on each access');
      expect(source.stop == source.stop, isTrue,
          reason: 'tear-offs from the same (receiver, method) compare ==');

      var resumeCalls = 0;
      final bg = BackgroundAudioHandle(
        pause: () async {},
        resume: () async => resumeCalls++,
      );
      ActiveAudio.registerBackground(bg);

      // Claim with a fresh tear-off.
      await ActiveAudio.claim(source.stop);
      // Release with another fresh tear-off from the same instance —
      // NOT `identical`, but `==`. Must still clear the slot and trigger
      // the background resume.
      ActiveAudio.release(source.stop);
      await flushMicrotasks();

      expect(resumeCalls, 1, reason: 'resume must fire after tear-off release');
      expect(ActiveAudio.isForegroundActive, isFalse,
          reason: 'release must actually clear the slot');

      ActiveAudio.unregisterBackground(bg);
    });

    test('claim baton-pass works when prev was passed as a tear-off',
        () async {
      // Verifies `prev == stop` check in claim() uses `==` correctly so
      // that subsequent claims still invoke the previous stop callback.
      final alice = _TearOffSource();
      await ActiveAudio.claim(alice.stop);

      Future<void> bobStop() async {}
      await ActiveAudio.claim(bobStop);

      expect(alice.stopCalls, 1,
          reason: 'new claim must call previous stop even across tear-offs');

      ActiveAudio.release(bobStop);
    });

    test(
        'stopForeground fires the current stop callback, clears the slot, '
        'and does NOT trigger the background resume callback', () async {
      var foregroundStops = 0;
      var bgResumes = 0;
      final bg = BackgroundAudioHandle(
        pause: () async {},
        resume: () async => bgResumes++,
      );
      ActiveAudio.registerBackground(bg);

      Future<void> stop() async {
        foregroundStops++;
      }

      await ActiveAudio.claim(stop);
      await ActiveAudio.stopForeground();

      expect(foregroundStops, 1, reason: 'current stop must be invoked');
      expect(ActiveAudio.isForegroundActive, isFalse,
          reason: 'slot must be cleared');
      expect(bgResumes, 0,
          reason: 'callers of stopForeground are leaving the scope — '
              'background should NOT be told to resume');

      ActiveAudio.unregisterBackground(bg);
    });

    test('stopForeground on an empty slot is a harmless no-op', () async {
      expect(() => ActiveAudio.stopForeground(), returnsNormally);
      await ActiveAudio.stopForeground();
      expect(ActiveAudio.isForegroundActive, isFalse);
    });

    test('release with a different source (not the active one) is a no-op',
        () async {
      var resumeCalls = 0;
      final bg = BackgroundAudioHandle(
        pause: () async {},
        resume: () async => resumeCalls++,
      );
      ActiveAudio.registerBackground(bg);

      final alice = _TearOffSource();
      final bob = _TearOffSource();
      await ActiveAudio.claim(alice.stop);

      // Bob never claimed; a stale release call from Bob shouldn't clear
      // Alice's slot or trigger background resume.
      ActiveAudio.release(bob.stop);
      await flushMicrotasks();

      expect(resumeCalls, 0);
      expect(ActiveAudio.isForegroundActive, isTrue,
          reason: "Alice's slot must remain active");

      ActiveAudio.release(alice.stop);
      ActiveAudio.unregisterBackground(bg);
    });
  });
}

/// A simple object whose `stop` method is captured as a tear-off by the
/// tests. Mirrors the real-world pattern used by `_TtsButtonState._stop`
/// where each `widget._stop` access produces a new `Function` object but
/// callers pass the tear-off to both [ActiveAudio.claim] and
/// [ActiveAudio.release].
class _TearOffSource {
  int stopCalls = 0;

  Future<void> stop() async {
    stopCalls++;
  }
}
