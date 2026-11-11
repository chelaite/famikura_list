import 'dart:io';
import 'dart:ui' as ui;
import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'parser.dart';

Future<String> _path(String name) async {
  final d = await getTemporaryDirectory();
  return '${d.path}/$name';
}

String _stamp() {
  final n = DateTime.now();
  String t(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${t(n.month)}${t(n.day)}_${t(n.hour)}${t(n.minute)}';
}

Future<String> exportTxt(List<Group> groups, List<Item> noCode) async {
  final b = StringBuffer();
  for (final g in groups) {
    b.writeln('【${g.prefix}】');
    for (final it in g.items) {
      b.writeln(it.code);
    }
    b.writeln();
  }
  if (noCode.isNotEmpty) {
    b.writeln('【无编号商品】');
    for (final it in noCode) {
      b.writeln(it.name);
    }
  }
  final p = await _path('list_${_stamp()}.txt');
  await File(p).writeAsString(b.toString());
  return p;
}

Future<String> exportXlsx(List<Group> groups, List<Item> noCode) async {
  final ex = Excel.createExcel();
  ex.rename('Sheet1', '编号清单');
  final s1 = ex['编号清单'];
  s1.appendRow([TextCellValue('团体'), TextCellValue('编号'), TextCellValue('商品名')]);
  for (final g in groups) {
    for (final it in g.items) {
      s1.appendRow([TextCellValue(g.prefix), TextCellValue(it.code), TextCellValue(it.name)]);
    }
  }
  if (noCode.isNotEmpty) {
    final s2 = ex['无编号商品'];
    s2.appendRow([TextCellValue('商品名')]);
    for (final it in noCode) {
      s2.appendRow([TextCellValue(it.name)]);
    }
  }
  final bytes = ex.encode();
  final p = await _path('list_${_stamp()}.xlsx');
  await File(p).writeAsBytes(bytes!);
  return p;
}

class _Row {
  final String text;
  final double size;
  final bool bold;
  final Color color;
  _Row(this.text, this.size, this.bold, this.color);
}

Future<String> exportPng(List<Group> groups, List<Item> noCode) async {
  const w = 1080.0, pad = 48.0;
  final rows = <_Row>[];
  for (final g in groups) {
    rows.add(_Row('【${g.prefix}】', 40, true, const Color(0xFFC2185B)));
    for (final it in g.items) {
      rows.add(_Row(it.name.isEmpty ? it.code : '${it.code}  ${it.name}', 32, false, Colors.black87));
    }
    rows.add(_Row(' ', 20, false, Colors.black));
  }
  if (noCode.isNotEmpty) {
    rows.add(_Row('【无编号商品】', 40, true, const Color(0xFFC2185B)));
    for (final it in noCode) {
      rows.add(_Row(it.name, 32, false, Colors.black87));
    }
  }
  final painters = <TextPainter>[];
  var h = pad * 2;
  for (final r in rows) {
    final tp = TextPainter(
      text: TextSpan(
        text: r.text,
        style: TextStyle(
          fontSize: r.size,
          color: r.color,
          fontWeight: r.bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - pad * 2);
    painters.add(tp);
    h += tp.height + 10;
  }
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
  c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
  var y = pad;
  for (final tp in painters) {
    tp.paint(c, Offset(pad, y));
    y += tp.height + 10;
  }
  final image = await rec.endRecording().toImage(w.toInt(), h.ceil());
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  final p = await _path('list_${_stamp()}.png');
  await File(p).writeAsBytes(bd!.buffer.asUint8List());
  return p;
}
