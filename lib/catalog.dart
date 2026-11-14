import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'parser.dart';

const kHost = 'famikura-store.jp';

/// 网站上的 5 个商品类别：接口参数 ct → 显示名
const kCategories = <String, String>{
  'photo': '写真',
  'mini-photo': 'ミニフォト',
  'square-photo': 'ましかくフォト',
  'goods': 'グッズ',
  'cd-video': 'CD/映像/その他',
};

/// 从商品名里取出编号，如 "【No.HSJ26-435】…" → "No.HSJ26-435"（和 Item.code 同一格式）
String? _extractNo(String name) {
  final m = RegExp(r'No\.?\s*([A-Za-z]{2,6})(\d{1,3})-(\d{1,5})').firstMatch(normalizeForId(name));
  if (m == null) return null;
  return 'No.${m.group(1)!.toUpperCase()}${m.group(2)}-${m.group(3)}';
}

Set<String> _readTags(Map<String, dynamic> j) {
  final out = <String>{};
  final g = j['g'];
  if (g is List) out.addAll(g.map((e) => e.toString()));
  final t = (j['t'] ?? '').toString(); // 旧版本只存了同步用的团体名
  if (t.isNotEmpty) out.add(t);
  return out;
}

class Product {
  final String code; // 网站内部代码 SSXJ-90996
  final String name; // 完整商品名（含 【No.xxx】）
  final String cat; // photo / goods ...
  final String img;
  final String url; // 详情页路径
  final Set<String> tags; // 话题标签（同步 / 联网搜索时记录）
  final int price;
  final String? no; // No.HSJ26-435
  final bool soldOut;

  Product({
    required this.code,
    required this.name,
    required this.cat,
    required this.img,
    required this.url,
    required this.price,
    required this.no,
    required this.soldOut,
    Set<String>? tags,
  }) : tags = tags ?? <String>{};

  String? _search;

  /// 本地搜索用的文字：商品名 + 编号 + 所有标签
  String get search =>
      _search ??= toHalfWidth('$name ${no ?? ''} ${tags.join(' ')}').toLowerCase();

  bool addTag(String t) {
    final v = t.trim();
    if (v.isEmpty) return false;
    final added = tags.add(v);
    if (added) _search = null;
    return added;
  }

  /// 去掉开头的【No.xxx】
  String get displayName => name.replaceFirst(RegExp(r'^【[^】]*】\s*'), '');

  /// 内部代码里的数字，越大越新
  int get seq => int.tryParse(code.split('-').last) ?? 0;

  factory Product.fromApi(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString();
    final name = s('item_name');
    return Product(
      code: s('item_code'),
      name: name,
      cat: s('item_category_code'),
      img: s('item_img_url'),
      url: s('item_detail_url'),
      price: int.tryParse(s('min_price')) ?? 0,
      no: _extractNo(name),
      soldOut: s('out_of_stock_code').isNotEmpty,
    );
  }

  Map<String, dynamic> toJson() => {
        'c': code,
        'n': name,
        'k': cat,
        'i': img,
        'u': url,
        'g': tags.toList(),
        'p': price,
        's': soldOut,
      };

  factory Product.fromJson(Map<String, dynamic> j) {
    final name = (j['n'] ?? '').toString();
    return Product(
      code: (j['c'] ?? '').toString(),
      name: name,
      cat: (j['k'] ?? '').toString(),
      img: (j['i'] ?? '').toString(),
      url: (j['u'] ?? '').toString(),
      tags: _readTags(j),
      price: (j['p'] as int?) ?? 0,
      no: _extractNo(name),
      soldOut: (j['s'] as bool?) ?? false,
    );
  }
}

class Artist {
  final String name;
  final List<String> members;
  Artist(this.name, this.members);
}

class _PageResult {
  final int count, pages;
  final List<Product> items;
  _PageResult(this.count, this.pages, this.items);
}

Future<Map<String, dynamic>> _getJson(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
    );
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final body = await res.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<_PageResult> _fetchPage(String ct, int page, {String tag = '', String word = ''}) async {
  final uri = Uri.https(kHost, '/s/j/api_common/list/item_list_v3', {
    'rw': '60',
    'page': '$page',
    'ct': ct,
    'gr': '',
    'so': 'DATE',
    'word': word,
    'hashtag': tag,
    'ignore': '',
    'label': '',
    'OPDATE': '',
    'OPSTAT': '',
  });
  final map = await _getJson(uri);
  final pg = map['pages'];
  final total = pg is Map ? (int.tryParse('${pg['total']}') ?? 0) : 0;
  final count = int.tryParse('${map['count']}') ?? 0;
  final list = (map['list'] as List?) ?? [];
  final items = list
      .map((e) => Product.fromApi(Map<String, dynamic>.from(e as Map)))
      .where((p) => p.code.isNotEmpty)
      .toList();
  return _PageResult(count, total, items);
}

/// 本地商品库：从网站同步下来，搜索/分类浏览都在本地完成
class Catalog extends ChangeNotifier {
  final Map<String, Product> products = {};
  final Map<String, Product> _byNo = {};
  List<String> tags = [];
  DateTime? lastSync;
  bool syncing = false;
  String status = '';
  bool _cancel = false;
  File? _file;

  Product? findByNo(String code) => _byNo[code];

  void _index() {
    _byNo.clear();
    for (final p in products.values) {
      final n = p.no;
      if (n != null) _byNo[n] = p;
    }
  }

  Future<void> load() async {
    try {
      final d = await getApplicationDocumentsDirectory();
      _file = File('${d.path}/catalog.json');
      if (await _file!.exists()) {
        final m = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        final t = (m['tags'] as List?)?.map((e) => e.toString()).toList();
        if (t != null && t.isNotEmpty) tags = t;
        lastSync = DateTime.tryParse((m['last'] ?? '').toString());
        products.clear();
        for (final e in ((m['items'] as List?) ?? [])) {
          final p = Product.fromJson(Map<String, dynamic>.from(e as Map));
          if (p.code.isNotEmpty) products[p.code] = p;
        }
      }
    } catch (_) {}
    _index();
    notifyListeners();
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString(jsonEncode({
        'tags': tags,
        'last': lastSync?.toIso8601String(),
        'items': products.values.map((e) => e.toJson()).toList(),
      }));
    } catch (_) {}
  }

  /// 网站上所有团体和个人（团体带成员名单）。名字同时就是话题标签
  Future<List<Artist>> fetchArtists() async {
    final uri = Uri.https(kHost, '/s/j/api/list/arti_list_with_actor', {'OPDATE': '', 'OPSTAT': ''});
    final map = await _getJson(uri);
    final list = (map['list'] as List?) ?? [];
    final out = <Artist>[];
    for (final e in list) {
      final m = e as Map;
      final name = (m['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final members = <String>[];
      final pl = m['player'];
      if (pl is List) {
        for (final x in pl) {
          final n = ((x as Map)['name'] ?? '').toString();
          if (n.isNotEmpty && n != name && !members.contains(n)) members.add(n);
        }
      }
      out.add(Artist(name, members));
    }
    return out;
  }

  void cancelSync() => _cancel = true;

  /// 按"团体 × 类别"逐页拉取，请求之间间隔 1.2 秒
  Future<void> sync(List<String> list) async {
    if (syncing) return;
    syncing = true;
    _cancel = false;
    status = '准备同步…';
    notifyListeners();
    var added = 0;
    var cancelled = false;
    try {
      outer:
      for (final tag in list) {
        for (final ct in kCategories.keys) {
          var page = 0;
          var total = 1;
          while (page < total) {
            if (_cancel) {
              cancelled = true;
              break outer;
            }
            final r = await _fetchPage(ct, page, tag: tag);
            total = r.pages;
            for (final p in r.items) {
              final ex = products[p.code];
              if (ex == null) {
                added++;
                products[p.code] = p;
                p.addTag(tag);
              } else {
                ex.addTag(tag);
              }
            }
            status = '$tag · ${kCategories[ct]} ${page + 1}/${total < 1 ? 1 : total}（该类别共 ${r.count} 件）';
            notifyListeners();
            page++;
            await Future.delayed(const Duration(milliseconds: 1200));
          }
        }
      }
      if (!cancelled) lastSync = DateTime.now();
      tags = <String>{...tags, ...list}.toList();
      status = cancelled
          ? '已取消（已保存已拉取的，商品库共 ${products.length} 件）'
          : '同步完成：新增 $added 件，商品库共 ${products.length} 件';
    } catch (e) {
      status = '同步失败：$e（已拉取的部分已保存）';
    } finally {
      syncing = false;
      _index();
      await _save();
      notifyListeners();
    }
  }

  /// 联网搜索：用网站自己的关键词搜索（会匹配商品名和标签），结果并入商品库，
  /// 并给结果记上这个搜索词作为标签，以后在本地也能搜到
  Future<int> searchOnline(String q, String cat) async {
    final term = q.trim();
    if (term.isEmpty || syncing) return 0;
    syncing = true;
    _cancel = false;
    status = '联网搜索“$term”…';
    notifyListeners();
    var found = 0;
    try {
      final cts = cat.isEmpty ? kCategories.keys.toList() : [cat];
      outer:
      for (final ct in cts) {
        var page = 0;
        var total = 1;
        while (page < total) {
          if (_cancel) break outer;
          final r = await _fetchPage(ct, page, word: term);
          total = r.pages;
          for (final p in r.items) {
            final ex = products[p.code];
            if (ex == null) {
              products[p.code] = p;
              p.addTag(term);
            } else {
              ex.addTag(term);
            }
            found++;
          }
          status = '联网搜索“$term” · ${kCategories[ct]} ${page + 1}/${total < 1 ? 1 : total}';
          notifyListeners();
          page++;
          if (!(page >= total && ct == cts.last)) {
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        }
      }
      status = _cancel ? '已取消联网搜索' : '联网搜索完成：“$term” 共 $found 件';
    } catch (e) {
      status = '联网搜索失败：$e';
    } finally {
      syncing = false;
      _index();
      await _save();
      notifyListeners();
    }
    return found;
  }

  List<Product> query(String q, String cat) {
    final terms = toHalfWidth(q)
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final out = products.values
        .where((p) => (cat.isEmpty || p.cat == cat) && terms.every(p.search.contains))
        .toList();
    out.sort((a, b) => b.seq.compareTo(a.seq));
    return out;
  }

  /// 截图识别出的商品：商品库里有对应编号时，用官方商品名替换识别出的（可能有错字的）名称
  Item enrich(Item it) {
    if (!it.hasCode) return it;
    final p = _byNo[it.code];
    if (p == null) return it;
    return Item(
      prefix: it.prefix,
      series: it.series,
      number: it.number,
      name: p.displayName,
      qty: it.qty,
      qtyGuess: it.qtyGuess,
    );
  }
}

final catalog = Catalog();

/// 商店里的购物车：商品内部代码 → 数量
class CartModel extends ChangeNotifier {
  final Map<String, int> qty = {};
  int get kinds => qty.length;
  int get total => qty.values.fold(0, (a, b) => a + b);

  void add(Product p) {
    final n = (qty[p.code] ?? 0) + 1;
    qty[p.code] = n > 99 ? 99 : n;
    notifyListeners();
  }

  void setQty(String code, int v) {
    qty[code] = v < 1 ? 1 : (v > 99 ? 99 : v);
    notifyListeners();
  }

  void remove(String code) {
    qty.remove(code);
    notifyListeners();
  }

  void clear() {
    qty.clear();
    notifyListeners();
  }
}

final cart = CartModel();

/// 商店商品 → 清单里的条目
Item productToItem(Product p, int q) {
  final it = p.no == null ? null : parseCodeOnly(p.no!, name: p.displayName, qty: q);
  return it ?? Item(name: p.name, qty: q);
}
