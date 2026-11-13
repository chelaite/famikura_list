import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'parser.dart';

/// 若装了新 APK 仍然闪退，把 true 改成 false（只识别英文数字，编号照样能提取）
const bool kUseJapanese = true;

const int _tileH = 1600, _overlap = 300;

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
  final recognizer = TextRecognizer(
    script: kUseJapanese ? TextRecognitionScript.japanese : TextRecognitionScript.latin,
  );
  try {
    final s = await compute(_slice, _SliceReq(path, dir.path, _tileH, _overlap));
    final all = <OcrLine>[];
    final n = s.paths.length;
    for (var i = 0; i < n; i++) {
      // 每个切片只"负责"自己的区间（重叠区在中线分界），避免同一行被两个切片各识别一次
      final lo = i == 0 ? double.negativeInfinity : s.tops[i] + _overlap / 2;
      final hi = i == n - 1 ? double.infinity : s.tops[i + 1] + _overlap / 2;
      final res = await recognizer.processImage(InputImage.fromFilePath(s.paths[i]));
      for (final block in res.blocks) {
        for (final line in block.lines) {
          final b = line.boundingBox;
          final y = s.tops[i] + b.center.dy;
          if (y < lo || y >= hi) continue;
          all.add(OcrLine(line.text, y, b.left / s.width, b.center.dx / s.width));
        }
      }
      onProgress?.call((i + 1) / n);
    }
    return parseCart(all, imageWidth: s.width.toDouble());
  } finally {
    await recognizer.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
