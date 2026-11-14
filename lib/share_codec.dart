import 'dart:convert';
import 'dart:io';
import 'parser.dart';
import 'store.dart';

/// 分享出去的整条消息：前面是人能直接看的清单，最后一行是给 App 导入用的代码
const _prefix = 'FKLIST1:';

class SharedList {
  final String name;
  final List<Item> items;
  SharedList(this.name, this.items);
}

String buildShareText(List<ShopList> lists) {
  final b = StringBuffer();
  for (final l in lists) {
    b.writeln('【${l.name}】${l.items.length} 种 / ${l.totalQty} 件');
    for (final it in l.items) {
      b.writeln('${it.hasCode ? it.code : it.name} ×${it.qty}');
    }
    b.writeln();
  }
  b.writeln('（用「购物清单」App 导入：复制整条消息，在首页点右上角的导入按钮）');
  b.write(_prefix);
  b.write(_encode(lists));
  b.write('.');
  return b.toString();
}

String _encode(List<ShopList> lists) {
  final data = {
    'v': 1,
    'lists': [
      for (final l in lists) {'name': l.name, 'items': l.items.map((e) => e.toJson()).toList()},
    ],
  };
  final bytes = gzip.encode(utf8.encode(jsonEncode(data)));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// 从收到的消息里找出代码并还原；找不到或损坏时返回 null
List<SharedList>? decodeShareText(String text) {
  final m = RegExp('$_prefix([A-Za-z0-9_\\-\\s]+)\\.').firstMatch(text);
  if (m == null) return null;
  try {
    final code = m.group(1)!.replaceAll(RegExp(r'\s+'), '');
    if (code.length > 400000) return null;
    final bytes = gzip.decode(base64Url.decode(base64Url.normalize(code)));
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final out = <SharedList>[];
    for (final e in (data['lists'] as List)) {
      final mm = e as Map;
      final items = <Item>[
        for (final x in (mm['items'] as List)) Item.fromJson(Map<String, dynamic>.from(x as Map)),
      ];
      out.add(SharedList((mm['name'] ?? '导入的列表').toString(), items));
    }
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}
