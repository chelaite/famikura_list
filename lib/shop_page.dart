import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'catalog.dart';
import 'dialogs.dart';
import 'parser.dart';

typedef CreateListFn = Future<void> Function(String name, List<Item> items);

// ───────────────────────── 图片磁盘缓存 ─────────────────────────

class DiskCache {
  static Directory? _dir;
  static final Map<String, Future<File>> _inflight = {};

  static Future<File> fileFor(String url) {
    return _inflight.putIfAbsent(url, () {
      return _get(url).whenComplete(() {
        _inflight.remove(url);
      });
    });
  }

  static Future<File> _get(String url) async {
    if (_dir == null) {
      final base = await getApplicationSupportDirectory();
      _dir = await Directory('${base.path}/img').create(recursive: true);
    }
    final name = Uri.parse(url).pathSegments.join('_');
    final f = File('${_dir!.path}/$name');
    if (await f.exists() && await f.length() > 0) return f;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final bytes = await consolidateHttpClientResponseBytes(res);
      await f.writeAsBytes(bytes);
      return f;
    } finally {
      client.close();
    }
  }
}

class ProductImage extends StatefulWidget {
  final String url;
  final double? width, height;
  final BoxFit fit;
  const ProductImage({super.key, required this.url, this.width, this.height, this.fit = BoxFit.contain});
  @override
  State<ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<ProductImage> {
  File? _file;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProductImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _file = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.url.isEmpty) {
      _failed = true;
      return;
    }
    try {
      final f = await DiskCache.fileFor(widget.url);
      if (mounted) setState(() => _file = f);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f != null) {
      return Image.file(
        f,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Center(
        child: _failed
            ? const Icon(Icons.broken_image, color: Colors.grey)
            : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

/// 商品大图 + 信息
Future<void> showProductDialog(BuildContext context, Product p, {bool showAdd = true}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ProductImage(url: p.img, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            if (p.no != null) Text(p.no!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(p.displayName),
            const SizedBox(height: 4),
            Text('¥${p.price}${p.soldOut ? '（缺货）' : ''}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
                if (showAdd)
                  FilledButton.icon(
                    onPressed: () {
                      cart.add(p);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('加入购物车'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ───────────────────────── 商品库 ─────────────────────────

class ShopPage extends StatefulWidget {
  final CreateListFn onCreate;
  const ShopPage({super.key, required this.onCreate});
  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final _q = TextEditingController();
  String _query = '';
  String _cat = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _openSync() async {
    List<Artist> artists;
    try {
      artists = await catalog.fetchArtists();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取团体列表失败：$e')));
      }
      return;
    }
    if (!mounted) return;
    final sel = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          void toggle(String n, bool? v) => setS(() {
                if (v == true) {
                  sel.add(n);
                } else {
                  sel.remove(n);
                }
              });
          return AlertDialog(
            title: const Text('选择要同步的团体或个人'),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: ListView(
                children: [
                  for (final a in artists)
                    if (a.members.isEmpty)
                      CheckboxListTile(
                        dense: true,
                        value: sel.contains(a.name),
                        title: Text(a.name),
                        onChanged: (v) => toggle(a.name, v),
                      )
                    else
                      ExpansionTile(
                        tilePadding: const EdgeInsets.only(left: 4, right: 12),
                        leading: Checkbox(
                          value: sel.contains(a.name),
                          onChanged: (v) => toggle(a.name, v),
                        ),
                        title: Text(a.name),
                        subtitle: Text('${a.members.length} 位成员', style: const TextStyle(fontSize: 12)),
                        children: [
                          for (final m in a.members)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.only(left: 40, right: 12),
                              value: sel.contains(m),
                              title: Text(m),
                              onChanged: (v) => toggle(m, v),
                            ),
                        ],
                      ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              FilledButton(
                onPressed: sel.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text(sel.isEmpty ? '开始同步' : '开始同步（${sel.length}）'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    catalog.sync(sel.toList());
  }

  Future<void> _online(String v) async {
    final q = v.trim();
    if (q.isEmpty || catalog.syncing) return;
    FocusScope.of(context).unfocus();
    setState(() => _query = q);
    await catalog.searchOnline(q, _cat);
  }

  Future<void> _openCart() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CartPage(onCreate: widget.onCreate)),
    );
  }

  Widget _card(Product p) {
    final n = cart.qty[p.code] ?? 0;
    const small = TextStyle(fontSize: 12);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => showProductDialog(context, p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.white,
                child: ProductImage(url: p.img, fit: BoxFit.contain),
              ),
            ),
            if (p.no != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Text(p.no!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
              child: Text(p.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                children: [
                  Text('¥${p.price}', style: small),
                  const Spacer(),
                  if (n > 0)
                    Text('×$n', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.pink)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '加入购物车',
                    icon: const Icon(Icons.add_shopping_cart, size: 20),
                    onPressed: () => cart.add(p),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([catalog, cart]),
      builder: (context, _) {
        final items = catalog.query(_query, _cat);
        return Scaffold(
          appBar: AppBar(
            title: const Text('商品库'),
            actions: [
              IconButton(
                tooltip: '更新商品库',
                icon: const Icon(Icons.sync),
                onPressed: catalog.syncing ? null : _openSync,
              ),
            ],
          ),
          body: Column(
            children: [
              if (catalog.syncing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    children: [
                      const LinearProgressIndicator(),
                      Row(
                        children: [
                          Expanded(child: Text(catalog.status, style: const TextStyle(fontSize: 12))),
                          TextButton(onPressed: catalog.cancelSync, child: const Text('取消')),
                        ],
                      ),
                    ],
                  ),
                )
              else if (catalog.status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(catalog.status, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _q,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '搜商品名、编号或标签（回车联网搜索）',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _q.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                        onSubmitted: _online,
                      ),
                    ),
                    IconButton(
                      tooltip: '联网搜索（含标签）',
                      icon: const Icon(Icons.travel_explore),
                      onPressed: catalog.syncing ? null : () => _online(_q.text),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('全部'),
                        selected: _cat.isEmpty,
                        onSelected: (_) => setState(() => _cat = ''),
                      ),
                    ),
                    for (final e in kCategories.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: _cat == e.key,
                          onSelected: (_) => setState(() => _cat = e.key),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    catalog.products.isEmpty
                        ? ''
                        : '${items.length} 件 / 商品库共 ${catalog.products.length} 件',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            catalog.products.isEmpty
                                ? '商品库是空的\n点右上角的同步按钮，选择团体后开始拉取'
                                : '没有符合条件的商品',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.62,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _card(items[i]),
                      ),
              ),
            ],
          ),
          bottomNavigationBar: cart.kinds == 0
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: FilledButton.icon(
                      onPressed: _openCart,
                      icon: const Icon(Icons.shopping_cart),
                      label: Text('购物车 ${cart.kinds} 种 / ${cart.total} 件'),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

// ───────────────────────── 购物车 ─────────────────────────

class CartPage extends StatelessWidget {
  final CreateListFn onCreate;
  const CartPage({super.key, required this.onCreate});

  static String _defaultName() {
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    return '商店清单 ${t(n.month)}-${t(n.day)} ${t(n.hour)}:${t(n.minute)}';
  }

  Future<void> _make(BuildContext context) async {
    final name = await askText(context, title: '给新清单命名', initial: _defaultName(), hint: '列表名称');
    if (name == null) return;
    final items = <Item>[];
    for (final e in cart.qty.entries) {
      final p = catalog.products[e.key];
      if (p != null) items.add(productToItem(p, e.value));
    }
    cart.clear();
    await onCreate(name, items);
  }

  Widget _row(Product p, int q) => Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
          child: Row(
            children: [
              ProductImage(url: p.img, width: 48, height: 64, fit: BoxFit.cover),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.no ?? p.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (p.no != null)
                      Text(p.displayName,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: q > 1 ? () => cart.setQty(p.code, q - 1) : null,
              ),
              Text('$q', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline),
                onPressed: q < 99 ? () => cart.setQty(p.code, q + 1) : null,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                onPressed: () => cart.remove(p.code),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final rows = <Widget>[];
        for (final e in cart.qty.entries) {
          final p = catalog.products[e.key];
          if (p != null) rows.add(_row(p, e.value));
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('购物车'),
            actions: [
              if (cart.kinds > 0)
                IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: () async {
                    if (await confirm(context, '清空购物车？')) cart.clear();
                  },
                ),
            ],
          ),
          body: rows.isEmpty
              ? const Center(child: Text('购物车是空的', style: TextStyle(color: Colors.grey)))
              : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), children: rows),
          bottomNavigationBar: rows.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: FilledButton.icon(
                      onPressed: () => _make(context),
                      icon: const Icon(Icons.playlist_add_check),
                      label: Text('生成清单（${cart.kinds} 种 / ${cart.total} 件）'),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
