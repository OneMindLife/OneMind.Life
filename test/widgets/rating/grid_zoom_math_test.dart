import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/rating/rating_widget.dart';

void main() {
  group('GridZoomMath', () {
    // Standard viewport: 600px tall, zoom 1x
    // gridHeight = 600, stackHeight = 600 - 150 = 450
    // Position 100 → gridY = 75 (top)
    // Position 0 → gridY = 525 (bottom)
    // Position 50 → gridY = 300 (middle)

    group('positionToGridY', () {
      test('position 100 maps to top buffer', () {
        final y = GridZoomMath.positionToGridY(100, 600, 1.0);
        expect(y, 75.0); // buffer
      });

      test('position 0 maps to bottom buffer', () {
        final y = GridZoomMath.positionToGridY(0, 600, 1.0);
        expect(y, 525.0); // gridHeight - buffer
      });

      test('position 50 maps to center', () {
        final y = GridZoomMath.positionToGridY(50, 600, 1.0);
        expect(y, 300.0); // (600 / 2)
      });

      test('zoom 2x doubles the stack height', () {
        // gridHeight = 1200, stackHeight = 1050
        final y100 = GridZoomMath.positionToGridY(100, 600, 2.0);
        final y0 = GridZoomMath.positionToGridY(0, 600, 2.0);
        expect(y100, 75.0); // buffer stays the same
        expect(y0, 1125.0); // 1200 - 75
        expect(y0 - y100, 1050.0); // stackHeight
      });
    });

    group('screenYToPosition', () {
      test('no scroll, top of viewport → position 100', () {
        // screenY = 75 (where position 100 is), scroll = 0
        final pos = GridZoomMath.screenYToPosition(75, 0, 600, 1.0);
        expect(pos, closeTo(100, 0.01));
      });

      test('no scroll, bottom of viewport → position 0', () {
        // screenY = 525, scroll = 0
        final pos = GridZoomMath.screenYToPosition(525, 0, 600, 1.0);
        expect(pos, closeTo(0, 0.01));
      });

      test('no scroll, center of viewport → position 50', () {
        final pos = GridZoomMath.screenYToPosition(300, 0, 600, 1.0);
        expect(pos, closeTo(50, 0.01));
      });

      test('with scroll offset', () {
        // zoom 2x: gridHeight=1200, stackHeight=1050
        // scrolled down 300px, finger at screenY=100
        // gridY = 300 + 100 = 400
        // position = 100 * (1 - (400 - 75) / 1050) = 100 * (1 - 325/1050) ≈ 69.05
        final pos = GridZoomMath.screenYToPosition(100, 300, 600, 2.0);
        expect(pos, closeTo(69.05, 0.1));
      });
    });

    group('screenYToPosition and positionToGridY are inverses', () {
      test('roundtrip at zoom 1x', () {
        const availableHeight = 600.0;
        const zoom = 1.0;
        const scrollOffset = 0.0;

        for (final screenY in [75.0, 150.0, 300.0, 450.0, 525.0]) {
          final position = GridZoomMath.screenYToPosition(
              screenY, scrollOffset, availableHeight, zoom);
          final gridY = GridZoomMath.positionToGridY(position, availableHeight, zoom);
          // gridY should equal scrollOffset + screenY
          expect(gridY, closeTo(scrollOffset + screenY, 0.01),
              reason: 'screenY=$screenY position=$position gridY=$gridY');
        }
      });

      test('roundtrip at zoom 3x with scroll', () {
        const availableHeight = 600.0;
        const zoom = 3.0;
        const scrollOffset = 500.0;

        for (final screenY in [0.0, 100.0, 300.0, 500.0, 600.0]) {
          final position = GridZoomMath.screenYToPosition(
              screenY, scrollOffset, availableHeight, zoom);
          final gridY = GridZoomMath.positionToGridY(position, availableHeight, zoom);
          expect(gridY, closeTo(scrollOffset + screenY, 0.01),
              reason: 'screenY=$screenY position=$position gridY=$gridY');
        }
      });
    });

    group('scrollForFocalPoint', () {
      test('zoom in from 1x to 2x, focal at center', () {
        const availableHeight = 600.0;
        const screenY = 300.0; // center of screen
        const oldScroll = 0.0;
        const oldZoom = 1.0;
        const newZoom = 2.0;

        final newScroll = GridZoomMath.scrollForFocalPoint(
            screenY, oldScroll, availableHeight, oldZoom, newZoom);

        // Position at center: 50
        // Old gridY for pos 50: 300 (center)
        // New gridY for pos 50: (1 - 0.5) * (1200-150) + 75 = 525 + 75 = 600
        // newScroll = 600 - 300 = 300
        expect(newScroll, closeTo(300, 0.01));
      });

      test('zoom in keeps focal position stable', () {
        const availableHeight = 600.0;
        const screenY = 200.0;
        const oldScroll = 0.0;
        const oldZoom = 1.0;
        const newZoom = 3.0;

        final newScroll = GridZoomMath.scrollForFocalPoint(
            screenY, oldScroll, availableHeight, oldZoom, newZoom);

        // Verify: the position at screenY before zoom should be at screenY after zoom
        final posBefore = GridZoomMath.screenYToPosition(
            screenY, oldScroll, availableHeight, oldZoom);
        final posAfter = GridZoomMath.screenYToPosition(
            screenY, newScroll, availableHeight, newZoom);

        expect(posAfter, closeTo(posBefore, 0.01),
            reason: 'Position at focal point should be stable: before=$posBefore after=$posAfter');
      });

      test('zoom out keeps focal position stable', () {
        const availableHeight = 600.0;
        const screenY = 400.0;
        const oldScroll = 500.0;
        const oldZoom = 3.0;
        const newZoom = 1.5;

        final newScroll = GridZoomMath.scrollForFocalPoint(
            screenY, oldScroll, availableHeight, oldZoom, newZoom);

        final posBefore = GridZoomMath.screenYToPosition(
            screenY, oldScroll, availableHeight, oldZoom);
        final posAfter = GridZoomMath.screenYToPosition(
            screenY, newScroll, availableHeight, newZoom);

        expect(posAfter, closeTo(posBefore, 0.01));
      });

      test('focal point stability across many zoom levels', () {
        const availableHeight = 700.0;
        const screenY = 350.0;
        var scroll = 0.0;
        var zoom = 1.0;

        final initialPos = GridZoomMath.screenYToPosition(
            screenY, scroll, availableHeight, zoom);

        // Zoom in incrementally
        for (var i = 0; i < 10; i++) {
          final newZoom = (zoom * 1.25).clamp(1.0, 15.0);
          scroll = GridZoomMath.scrollForFocalPoint(
              screenY, scroll, availableHeight, zoom, newZoom);
          zoom = newZoom;

          final currentPos = GridZoomMath.screenYToPosition(
              screenY, scroll, availableHeight, zoom);
          expect(currentPos, closeTo(initialPos, 0.1),
              reason: 'Zoom $zoom: position drifted from $initialPos to $currentPos');
        }
      });

      test('zoom at top of screen (position ~100)', () {
        const availableHeight = 600.0;
        const screenY = 75.0; // position 100
        const oldScroll = 0.0;
        const oldZoom = 1.0;
        const newZoom = 2.0;

        final newScroll = GridZoomMath.scrollForFocalPoint(
            screenY, oldScroll, availableHeight, oldZoom, newZoom);

        final posBefore = GridZoomMath.screenYToPosition(
            screenY, oldScroll, availableHeight, oldZoom);
        final posAfter = GridZoomMath.screenYToPosition(
            screenY, newScroll, availableHeight, newZoom);

        expect(posAfter, closeTo(posBefore, 0.01));
      });

      test('zoom at bottom of screen (position ~0)', () {
        const availableHeight = 600.0;
        const screenY = 525.0; // position 0
        const oldScroll = 0.0;
        const oldZoom = 1.0;
        const newZoom = 2.0;

        final newScroll = GridZoomMath.scrollForFocalPoint(
            screenY, oldScroll, availableHeight, oldZoom, newZoom);

        final posBefore = GridZoomMath.screenYToPosition(
            screenY, oldScroll, availableHeight, oldZoom);
        final posAfter = GridZoomMath.screenYToPosition(
            screenY, newScroll, availableHeight, newZoom);

        expect(posAfter, closeTo(posBefore, 0.01));
      });

      test('no zoom change returns same scroll', () {
        const availableHeight = 600.0;
        const screenY = 300.0;
        const oldScroll = 100.0;
        const zoom = 2.0;

        final newScroll = GridZoomMath.scrollForFocalPoint(
            screenY, oldScroll, availableHeight, zoom, zoom);

        expect(newScroll, closeTo(oldScroll, 0.01));
      });
    });
  });
}
