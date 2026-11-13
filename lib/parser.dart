// 纯 Dart：编号解析、截图行聚合、分组排序。不依赖 Flutter / ML Kit，后续接爬取功能可直接复用。

class OcrLine {
  final String text;
  final double y; // 在整张图中的绝对纵坐标（行中心）
  final double leftFrac; // 行左边缘 / 图宽
  final double centerFrac; // 行中心 / 图宽
  OcrLine(this.text, this.y, this.leftFrac, this.centerFrac);
}

class Item {
  final String? prefix; // HSJ
  final String? series; // 26
  final String? number; // 435
  final String name;
  int qty;
  bool qtyGuess; // 没识别到数量，默认按 1 计

  Item({
    this.prefix,
    this.series,
    this.number,
    this.name = '',
    this.qty = 1,
    this.qtyGuess = false,
  });

  bool get hasCode => prefix != null;
  String get group => prefix ?? '';
  String get code => hasCode ? 'No.$prefix$series-$number' : '';
  String get key => hasCode ? code : 'N:$name';
  int get seriesInt => int.tryParse(series ?? '') ?? 0;
  int get numberInt => int.tryParse(number ?? '') ?? 0;

  /// 导出用的一行文字：数量大于 1 时带 ×N
  String get line {
    final base = hasCode ? code : name;
    return qty > 1 ? '$base ×$qty' : base;
  }

  bool get isUnknown => !hasCode && name == '（未识别商品）';

  Item copy() => Item(
        prefix: prefix,
        series: series,
        number: number,
        name: name,
        qty: qty,
        qtyGuess: qtyGuess,
      );

  Map<String, dynamic> toJson() =>
      {'p': prefix, 's': series, 'n': number, 'name': name, 'qty': qty, 'g': qtyGuess};

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        prefix: j['p'] as String?,
        series: j['s'] as String?,
        number: j['n'] as String?,
        name: (j['name'] as String?) ?? '',
        qty: (j['qty'] as int?) ?? 1,
        qtyGuess: (j['g'] as bool?) ?? false,
      );
}

/// 把 src 并入 target（复制条目）。同编号/同名商品已存在时：sumQty 为 true 数量相加，否则跳过。
void mergeInto(List<Item> target, Iterable<Item> src, {bool sumQty = false}) {
  for (final it in src) {
    if (it.isUnknown) {
      target.add(it.copy());
      continue;
    }
    final i = target.indexWhere((e) => e.key == it.key);
    if (i < 0) {
      target.add(it.copy());
    } else if (sumQty) {
      target[i].qty += it.qty;
      if (!it.qtyGuess) target[i].qtyGuess = false;
    }
  }
}

class CartResult {
  final List<Item> items;
  final int? expected; // 截图底部"商品合計数量"
  CartResult(this.items, this.expected);
  int get sumQty => items.fold(0, (a, b) => a + b.qty);
  int get qtyGuessed => items.where((e) => e.qtyGuess).length;
}

class Group {
  final String prefix;
  final List<Item> items;
  Group(this.prefix, this.items);
  int get sumQty => items.fold(0, (a, b) => a + b.qty);
}

String toHalfWidth(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xFF01 && r <= 0xFF5E) {
      b.writeCharCode(r - 0xFEE0);
    } else if (r == 0x3000) {
      b.write(' ');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

// 仅用于识别的规范化副本（不改原文）：全角转半角，各种横线统一为 -
String normalizeForId(String s) =>
    toHalfWidth(s).replaceAll(RegExp('[\u2010-\u2015\u2212\u30FC\uFF70\u2500]'), '-');

String _fixDigits(String s) => s
    .replaceAll(RegExp('[Oo]'), '0')
    .replaceAll(RegExp('[IilL|]'), '1');

final _idRe = RegExp(
  r'N[oO0]\s*[.,]?\s*([A-Za-z]{2,6})\s*([0-9OoIilL|]{1,3})\s*-\s*([0-9OoIilL|]{1,5})',
);
final _codeOnlyRe = RegExp(
  r'(?:N[oO0]\s*[.,]?\s*)?([A-Za-z]{2,6})\s*(\d{1,3})\s*-\s*(\d{1,5})',
);

Item _fromMatch(RegExpMatch m, String name, int qty, bool guess) => Item(
      prefix: m.group(1)!.toUpperCase(),
      series: _fixDigits(m.group(2)!),
      number: _fixDigits(m.group(3)!),
      name: name,
      qty: qty,
      qtyGuess: guess,
    );

/// 手动输入编号，如 "HSJ26-435" 或 "No.HSJ26-435"
Item? parseCodeOnly(String input, {String name = '', int qty = 1}) {
  final m = _codeOnlyRe.firstMatch(normalizeForId(input.trim()));
  return m == null ? null : _fromMatch(m, name, qty, false);
}

String _key(String s) => normalizeForId(s).toLowerCase().replaceAll(RegExp(r'\s+'), '');

bool _isJunk(String t) {
  const kws = ['¥', '￥', '税込', 'お届け', '順次発送', '商品合計', '注文内容', '削除'];
  if (kws.any(t.contains)) return true;
  return RegExp(r'^[\d\s:+\-%]*$').hasMatch(normalizeForId(t));
}

/// 数量框在行的中间偏右（约 58% 处），是 1~2 位纯数字（可能和 −、+ 连在一起）
int? _findQty(List<OcrLine> buf) {
  int? best;
  var bestDist = 9.0;
  for (final l in buf) {
    if (l.centerFrac < 0.46 || l.centerFrac > 0.72) continue;
    final t = normalizeForId(l.text).replaceAll(RegExp(r'[\s+\-]'), '');
    if (!RegExp(r'^[0-9OoIl|]{1,2}$').hasMatch(t)) continue;
    final v = int.tryParse(_fixDigits(t));
    if (v == null || v < 1) continue;
    final d = (l.centerFrac - 0.58).abs();
    if (d < bestDist) {
      bestDist = d;
      best = v;
    }
  }
  return best;
}

List<Item> _itemsFrom(List<OcrLine> buf) {
  final joined = normalizeForId(buf.map((e) => e.text).join(' '));
  final ms = _idRe.allMatches(joined).toList();
  final nameParts = <String>[];
  for (final l in buf) {
    if (l.leftFrac < 0.33) continue; // 左侧是缩略图和价格
    if (_isJunk(l.text)) continue;
    if (_idRe.hasMatch(normalizeForId(l.text))) continue;
    nameParts.add(l.text.trim());
  }
  final name = nameParts.join('');
  final q = _findQty(buf);
  final qty = q ?? 1;
  final guess = q == null || ms.length > 1;
  if (ms.isEmpty) {
    return [Item(name: name.isEmpty ? '（未识别商品）' : name, qty: qty, qtyGuess: guess)];
  }
  return ms
      .map((m) => _fromMatch(m, ms.length == 1 ? name : '', ms.length == 1 ? qty : 1, guess))
      .toList();
}

/// 把 OCR 得到的所有行（来自重叠切片）合并为商品列表
CartResult parseCart(List<OcrLine> raw) {
  final sorted = [...raw]..sort((a, b) => a.y.compareTo(b.y));
  final lines = <OcrLine>[];
  for (final l in sorted) {
    final k = _key(l.text);
    var dup = false;
    for (var i = lines.length - 1; i >= 0 && l.y - lines[i].y <= 12; i--) {
      if (_key(lines[i].text) == k) {
        dup = true;
        break;
      }
    }
    if (!dup) lines.add(l);
  }

  final hi = lines.indexWhere((l) => l.text.contains('注文内容'));
  if (hi >= 0) lines.removeRange(0, hi + 1);

  final items = <Item>[];
  var buf = <OcrLine>[];
  for (final l in lines) {
    if (l.text.contains('削除')) {
      items.addAll(_itemsFrom(buf));
      buf = [];
    } else {
      buf.add(l);
    }
  }
  if (items.isEmpty) {
    // 没找到任何"削除"分隔标记（例如只用英文识别）时，直接从全部文字里捞编号
    final all = normalizeForId(lines.map((e) => e.text).join(' '));
    final found = _idRe.allMatches(all).map((m) => _fromMatch(m, '', 1, true)).toList();
    return CartResult(found, null);
  }
  final footer = normalizeForId(buf.map((e) => e.text).join(' '));
  final m = RegExp(r'合計数量\D{0,6}(\d+)').firstMatch(footer);
  return CartResult(items, m == null ? null : int.tryParse(m.group(1)!));
}

/// 按团体分组，组内按 系列→序号 排序
List<Group> groupAndSort(List<Item> items, {required bool ascending}) {
  final map = <String, List<Item>>{};
  for (final it in items.where((e) => e.hasCode)) {
    map.putIfAbsent(it.group, () => []).add(it);
  }
  final keys = map.keys.toList()..sort();
  return keys.map((k) {
    final list = map[k]!
      ..sort((a, b) {
        var c = a.seriesInt.compareTo(b.seriesInt);
        if (c == 0) c = a.numberInt.compareTo(b.numberInt);
        return ascending ? c : -c;
      });
    return Group(k, list);
  }).toList();
}
