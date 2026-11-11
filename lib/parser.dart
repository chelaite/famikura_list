// 纯 Dart：编号解析、截图行聚合、分组排序。不依赖 Flutter / ML Kit，后续接爬取功能可直接复用。

class OcrLine {
  final String text;
  final double y; // 在整张图中的绝对纵坐标（行中心）
  final double leftFrac; // 行左边缘 / 图宽
  OcrLine(this.text, this.y, this.leftFrac);
}

class Item {
  final String? prefix; // HSJ
  final String? series; // 26
  final String? number; // 435
  final String name;
  Item({this.prefix, this.series, this.number, this.name = ''});

  bool get hasCode => prefix != null;
  String get group => prefix ?? '';
  String get code => hasCode ? 'No.$prefix$series-$number' : '';
  String get key => hasCode ? code : 'N:$name';
  int get seriesInt => int.tryParse(series ?? '') ?? 0;
  int get numberInt => int.tryParse(number ?? '') ?? 0;
}

class CartResult {
  final List<Item> items;
  final int? expected; // 截图底部"商品合計数量"
  CartResult(this.items, this.expected);
}

class Group {
  final String prefix;
  final List<Item> items;
  Group(this.prefix, this.items);
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

// 仅用于识别编号的规范化副本（不改原文）：全角转半角，各种横线统一为 -
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

Item _fromMatch(RegExpMatch m, String name) => Item(
      prefix: m.group(1)!.toUpperCase(),
      series: _fixDigits(m.group(2)!),
      number: _fixDigits(m.group(3)!),
      name: name,
    );

/// 手动输入编号，如 "HSJ26-435" 或 "No.HSJ26-435"
Item? parseCodeOnly(String input, {String name = ''}) {
  final m = _codeOnlyRe.firstMatch(normalizeForId(input.trim()));
  return m == null ? null : _fromMatch(m, name);
}

String _key(String s) => normalizeForId(s).toLowerCase().replaceAll(RegExp(r'\s+'), '');

bool _isJunk(String t) {
  const kws = ['¥', '￥', '税込', 'お届け', '順次発送', '商品合計', '注文内容', '削除'];
  if (kws.any(t.contains)) return true;
  return RegExp(r'^[\d\s:+\-%]*$').hasMatch(normalizeForId(t));
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
  if (ms.isEmpty) {
    return [Item(name: name.isEmpty ? '（未识别商品）' : name)];
  }
  return ms.map((m) => _fromMatch(m, ms.length == 1 ? name : '')).toList();
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
