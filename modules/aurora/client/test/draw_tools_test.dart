import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_client/games/drawguess/canvas.dart';
import 'package:aurora_client/games/drawguess/toolbar.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drawing tools: fill tap, colour wheel, Ctrl+Z / Ctrl+Y.
/// SHOTS=1 also writes build/shots/_draw_tools.png.
void main() {
  testWidgets('fill, colour wheel and undo / redo shortcuts', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <Map<String, dynamic>>[];
    final sketch = Sketch();
    final tool = DgTool();
    void send(Map<String, dynamic> a) {
      sent.add(a);
      switch (a['type']) {
        case 'stroke':
          sketch.stroke(a);
        case 'undo':
          sketch.undo();
        case 'redo':
          sketch.redo();
        case 'clear':
          sketch.clear();
      }
    }

    // a closed outline to fill
    sketch.stroke({'id': 1, 'color': 0xFF212121, 'width': 8, 'pts': [200, 200, 800, 200, 800, 800, 200, 800, 200, 200]});
    final key = GlobalKey();
    Widget app() => MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: StatefulBuilder(builder: (context, setState) {
                tool.addListener(() => setState(() {}));
                return Column(children: [
                  const TextField(key: Key('text')),
                  SizedBox(
                    height: 600,
                    child: DgCanvas(
                      strokes: DgStroke.parse(sketch.toJson()),
                      enabled: true,
                      color: tool.canvasColor,
                      width: tool.canvasWidth,
                      fill: tool.fill,
                      send: (a) => setState(() => send(a)),
                    ),
                  ),
                  DgToolbar(
                    tool: tool,
                    send: (a) => setState(() => send(a)),
                    points: sketch.points,
                    maxPoints: sketch.maxPoints,
                    canUndo: sketch.canUndo,
                    canRedo: sketch.canRedo,
                  ),
                ]);
              }),
            ),
          ),
        );
    await tester.pumpWidget(app());

    // pick a custom colour from the wheel
    await tester.tap(find.byTooltip('色盘：自选颜色'));
    await tester.pumpAndSettle();
    expect(find.text('色盘'), findsOneWidget);
    await tester.tap(find.text('使用此颜色'));
    await tester.pumpAndSettle();

    // fill inside the square
    await tester.tap(find.byTooltip('填充'));
    await tester.pump();
    expect(tool.fill, isTrue);
    tool.color = 0xFFFDD835;
    await tester.pump();
    final canvas = tester.getRect(find.byType(DgCanvas));
    await tester.tapAt(canvas.center);
    await tester.pump();
    expect(sent.last['type'], 'stroke');
    expect(sent.last['width'], kFillWidth);
    expect(sent.last['pts'], hasLength(2));
    expect(sketch.strokes.last['w'], kFillWidth);

    if (Platform.environment['SHOTS'] == '1') {
      await tester.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('build/shots/_draw_tools.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    // Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z
    sent.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect([for (final a in sent) a['type']], ['undo', 'redo', 'redo']);

    // shortcuts are left to a focused text field
    sent.clear();
    await tester.tap(find.byKey(const Key('text')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(sent, isEmpty);
  });
}
