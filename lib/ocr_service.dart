import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'parser.dart';

class _SliceReq {
  final String path, dir;
  final int tileH, overlap;
  _SliceReq(this.path, this.dir, this.tileH, this.overlap);
}

class _SliceRes {
  final List<String> paths;
  final List<int> tops;
  final int width;
  _SliceRes(this.paths, this.tops, this.width);
}

_SliceRes _slice(_SliceReq r) {
  final decoded = img.decodeImage(File(r.path).readAsBytesSync());
  if (decoded == null) throw Exception('无法读取图片');
  final w = decoded.width, hAll = decoded.height;
  final paths = <String>[], tops = <int>[];
  for (var top = 0;; top += r.tileH - r.overlap) {
    final h = min(r.tileH, hAll - top);
    final crop = img.copyCrop(decoded, x: 0, y: top, width: w, height: h);
    final p = '${r.dir}/tile_$top.png';
    File(p).writeAsBytesSync(img.encodePng(crop));
    paths.add(p);
    tops.add(top);
    if (top + h >= hAll) break;
  }
  return _SliceRes(paths, tops, w);
}

Future<CartResult> recognizeCart(String path, {void Function(double)? onProgress}) async {
  final tmp = await getTemporaryDirectory();
  final dir = await tmp.createTemp('ocr_');
  final recognizer = TextRecognizer(script: TextRecognitionScript.japanese);
  try {
    final s = await compute(_slice, _SliceReq(path, dir.path, 1600, 300));
    final all = <OcrLine>[];
    for (var i = 0; i < s.paths.length; i++) {
      final res = await recognizer.processImage(InputImage.fromFilePath(s.paths[i]));
      for (final block in res.blocks) {
        for (final line in block.lines) {
          final b = line.boundingBox;
          all.add(OcrLine(line.text, s.tops[i] + b.center.dy, b.left / s.width));
        }
      }
      onProgress?.call((i + 1) / s.paths.length);
    }
    return parseCart(all);
  } finally {
    await recognizer.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
