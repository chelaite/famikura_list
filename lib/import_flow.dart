import 'package:image_picker/image_picker.dart';
import 'catalog.dart';
import 'ocr_service.dart';
import 'parser.dart';

/// 选图 → 识别 → 把商品直接加进 target，返回提示信息。用户取消选图时返回 null。
Future<List<String>?> importScreenshots(
  ImagePicker picker,
  List<Item> target,
  void Function(String) onStatus,
) async {
  final files = await picker.pickMultiImage();
  if (files.isEmpty) return null;
  final notes = <String>[];
  for (var i = 0; i < files.length; i++) {
    final tag = '第${i + 1}张';
    onStatus('识别$tag / 共${files.length}张…');
    try {
      final r = await recognizeCart(files[i].path, onProgress: (p) {
        onStatus('识别$tag / 共${files.length}张 ${(p * 100).round()}%');
      });
      for (final it in r.items) {
        if (it.isUnknown) {
          target.add(it);
          continue;
        }
        final ex = target.where((e) => e.key == it.key).toList();
        if (ex.isEmpty) {
          target.add(catalog.enrich(it));
        } else if (it.hasCode && !it.qtyGuess && ex.first.qty != it.qty) {
          notes.add('$tag：${it.code} 与之前的截图重复且数量不同（已有 ${ex.first.qty}，这张 ${it.qty}），保留已有数量，请自行核对');
        }
      }
      final n = r.items.length, sum = r.sumQty;
      String msg;
      if (r.expected == null) {
        msg = '$tag：$n 种，数量合计 $sum（没找到底部合计数量，无法校验）';
      } else if (r.expected == sum) {
        msg = '$tag：$n 种 / 共 $sum 件，与合计数量一致 ✓';
      } else if (r.expected == n) {
        msg = '$tag：种类数 $n 与截图合计 ${r.expected} 相符，但数量合计是 $sum（若截图合计按种类计可忽略，否则请核对数量）';
      } else {
        msg = '$tag：识别到 $n 种 / $sum 件，但截图显示共 ${r.expected} 件，请检查！';
      }
      if (r.qtyGuessed > 0) {
        msg += '（${r.qtyGuessed} 种没识别到数量，已按 1 计，数量显示为橙色）';
      }
      notes.add(msg);
    } catch (e) {
      notes.add('$tag识别失败：$e');
    }
  }
  return notes;
}
