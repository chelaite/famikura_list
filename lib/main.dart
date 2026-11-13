import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dialogs.dart';
import 'exporter.dart';
import 'import_flow.dart';
import 'parser.dart';
import 'store.dart';

void main() => runApp(const App());

int _cq(int v) => v < 1 ? 1 : (v > 99 ? 99 : v);

String _date(DateTime d) {
  String t(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}';
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '购物清单',
        theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
        home: const ListsPage(),
      );
}

// ───────────────────────── 列表总览 ─────────────────────────

class ListsPage extends StatefulWidget {
  const ListsPage({super.key});
  @override
  State<ListsPage> createState() => _ListsPageState();
}

class _ListsPageState extends State<ListsPage> {
  final _picker = ImagePicker();
  List<ShopList> _lists = [];
  final Set<String> _sel = {};
  bool _loading = true;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    Store.load().then((v) {
      if (!mounted) return;
      setState(() {
        _lists = v;
        _loading = false;
      });
    });
  }

  Future<void> _save() => Store.save(_lists);

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _open(ShopList l, {List<String> notes = const []}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ListPage(list: l, onChanged: _save, initialNotes: notes)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final name = await askText(context, title: '新建列表', initial: '列表 ${_lists.length + 1}', hint: '列表名称');
    if (name == null) return;
    final l = ShopList(id: ShopList.newId(), name: name, created: DateTime.now());
    setState(() => _lists.insert(0, l));
    await _save();
    if (!mounted) return;
    await _open(l);
  }

  Future<void> _importNew() async {
    setState(() {
      _busy = true;
      _status = '';
    });
    final items = <Item>[];
    List<String>? notes;
    try {
      notes = await importScreenshots(_picker, items, (s) {
        if (mounted) setState(() => _status = s);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (notes == null || !mounted) return;
    if (items.isEmpty) {
      _toast('没有识别到商品');
      return;
    }
    final name = await askText(context, title: '给新列表命名', initial: '列表 ${_lists.length + 1}', hint: '列表名称');
    if (name == null) {
      _toast('已取消，识别结果未保存');
      return;
    }
    final l = ShopList(id: ShopList.newId(), name: name, created: DateTime.now(), items: items);
    setState(() => _lists.insert(0, l));
    await _save();
    if (!mounted) return;
    await _open(l, notes: notes);
  }

  Future<void> _merge() async {
    final chosen = _lists.where((e) => _sel.contains(e.id)).toList();
    if (chosen.length < 2) return;
    final name = await askText(context, title: '合并后的新列表名称', initial: '合并列表', hint: '列表名称');
    if (name == null) return;
    final items = <Item>[];
    for (final l in chosen) {
      mergeInto(items, l.items, sumQty: true);
    }
    final nl = ShopList(id: ShopList.newId(), name: name, created: DateTime.now(), items: items);
    setState(() {
      _lists.insert(0, nl);
      _sel.clear();
    });
    await _save();
    _toast('已合并为「$name」，原列表保留（相同商品数量已相加）');
  }

  Future<void> _deleteSel() async {
    final ok = await confirm(context, '删除选中的 ${_sel.length} 个列表？此操作不能撤销。');
    if (!ok) return;
    setState(() {
      _lists.removeWhere((e) => _sel.contains(e.id));
      _sel.clear();
    });
    await _save();
  }

  void _toggle(ShopList l) => setState(() {
        if (!_sel.remove(l.id)) _sel.add(l.id);
      });

  @override
  Widget build(BuildContext context) {
    final selecting = _sel.isNotEmpty;
    return Scaffold(
      appBar: selecting
          ? AppBar(
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_sel.clear)),
              title: Text('已选 ${_sel.length}'),
              actions: [
                if (_sel.length >= 2)
                  IconButton(tooltip: '合并', icon: const Icon(Icons.merge_type), onPressed: _merge),
                IconButton(tooltip: '删除', icon: const Icon(Icons.delete), onPressed: _deleteSel),
              ],
            )
          : AppBar(
              title: const Text('我的列表'),
              actions: [
                IconButton(
                  tooltip: '新建列表',
                  icon: const Icon(Icons.add),
                  onPressed: _busy ? null : _create,
                ),
              ],
            ),
      floatingActionButton: selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _importNew,
              icon: const Icon(Icons.photo_library),
              label: const Text('导入截图'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  Padding(padding: const EdgeInsets.all(6), child: Text(_status)),
                ],
                if (_lists.isEmpty && !_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Text(
                      '还没有列表\n点右上角 + 新建，或点下方"导入截图"直接生成',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                for (final l in _lists)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      selected: _sel.contains(l.id),
                      leading: selecting
                          ? Checkbox(value: _sel.contains(l.id), onChanged: (_) => _toggle(l))
                          : const Icon(Icons.list_alt),
                      title: Text(l.name),
                      subtitle: Text('${l.items.length} 种 / ${l.totalQty} 件 · ${_date(l.created)}'),
                      onTap: selecting ? () => _toggle(l) : () => _open(l),
                      onLongPress: () => _toggle(l),
                    ),
                  ),
                if (_lists.isNotEmpty && !selecting)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('长按列表可多选，进行合并或删除',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ],
            ),
    );
  }
}

// ───────────────────────── 单个列表 ─────────────────────────

class _EditResult {
  final String code, name;
  final int qty;
  final bool delete;
  _EditResult(this.code, this.name, this.qty, {this.delete = false});
}

class ListPage extends StatefulWidget {
  final ShopList list;
  final Future<void> Function() onChanged;
  final List<String> initialNotes;
  const ListPage({
    super.key,
    required this.list,
    required this.onChanged,
    this.initialNotes = const [],
  });
  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final _picker = ImagePicker();
  late final List<String> _notes = [...widget.initialNotes];
  bool _asc = true;
  bool _busy = false;
  String _status = '';

  ShopList get _l => widget.list;
  List<Item> get _items => _l.items;

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  /// 修改数据并保存
  void _mut(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      final notes = await importScreenshots(_picker, _items, (s) {
        if (mounted) setState(() => _status = s);
      });
      if (notes != null) {
        _notes
          ..clear()
          ..addAll(notes);
        await widget.onChanged();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final name = await askText(context, title: '重命名列表', initial: _l.name, hint: '列表名称');
    if (name == null) return;
    _mut(() => _l.name = name);
  }

  Future<void> _clearAll() async {
    if (!await confirm(context, '清空「${_l.name}」里的所有商品？')) return;
    _mut(() {
      _items.clear();
      _notes.clear();
    });
  }

  Future<_EditResult?> _editDialog({Item? it}) {
    final codeCtrl = TextEditingController(
        text: it != null && it.hasCode ? '${it.prefix}${it.series}-${it.number}' : '');
    final nameCtrl = TextEditingController(text: it?.name ?? '');
    final qtyCtrl = TextEditingController(text: '${it?.qty ?? 1}');
    return showDialog<_EditResult>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(it == null ? '手动添加' : '编辑商品'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: '编号', hintText: '例如 HSJ26-435'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '商品名（可选）'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '数量'),
            ),
          ]),
        ),
        actions: [
          if (it != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, _EditResult('', '', 1, delete: true)),
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              _EditResult(codeCtrl.text, nameCtrl.text, int.tryParse(qtyCtrl.text.trim()) ?? 1),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _manualAdd() async {
    final r = await _editDialog();
    if (r == null) return;
    final p = parseCodeOnly(r.code, name: r.name.trim(), qty: _cq(r.qty));
    if (p == null) return _toast('编号格式不对，应类似 HSJ26-435');
    if (_items.any((e) => e.key == p.key)) return _toast('这个编号已经在清单里了');
    _mut(() => _items.add(p));
  }

  Future<void> _edit(Item it) async {
    final r = await _editDialog(it: it);
    if (r == null) return;
    if (r.delete) {
      _mut(() => _items.remove(it));
      return;
    }
    final qty = _cq(r.qty);
    final codeText = r.code.trim();
    final Item next;
    if (codeText.isEmpty) {
      if (it.hasCode) return _toast('编号不能为空');
      final nm = r.name.trim();
      next = Item(name: nm.isEmpty ? it.name : nm, qty: qty);
    } else {
      final p = parseCodeOnly(codeText, name: r.name.trim(), qty: qty);
      if (p == null) return _toast('编号格式不对，应类似 HSJ26-435');
      next = p;
    }
    if (next.key != it.key && _items.any((e) => e.key == next.key)) {
      return _toast('这个编号已经在清单里了');
    }
    _mut(() {
      final i = _items.indexOf(it);
      if (i >= 0) _items[i] = next;
    });
  }

  Future<void> _export(String kind) async {
    final groups = groupAndSort(_items, ascending: _asc);
    final noCode = _items.where((e) => !e.hasCode).toList();
    if (groups.isEmpty && noCode.isEmpty) return _toast('清单是空的');
    try {
      final p = kind == 'txt'
          ? await exportTxt(_l.name, groups, noCode)
          : kind == 'xlsx'
              ? await exportXlsx(_l.name, groups, noCode)
              : await exportPng(_l.name, groups, noCode);
      await Share.shareXFiles([XFile(p)]);
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  Widget _stepper(Item it) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: it.qty > 1
              ? () => _mut(() {
                    it.qty--;
                    it.qtyGuess = false;
                  })
              : null,
        ),
        Text(
          '${it.qty}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: it.qtyGuess ? Colors.orange : null,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: it.qty < 99
              ? () => _mut(() {
                    it.qty++;
                    it.qtyGuess = false;
                  })
              : null,
        ),
      ]);

  Widget _tile(Item it) => Dismissible(
        key: ObjectKey(it),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => _mut(() => _items.remove(it)),
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: ListTile(
            dense: true,
            title: Text(it.hasCode ? it.code : it.name),
            subtitle: it.hasCode && it.name.isNotEmpty ? Text(it.name) : null,
            onTap: () => _edit(it),
            trailing: _stepper(it),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final groups = groupAndSort(_items, ascending: _asc);
    final noCode = _items.where((e) => !e.hasCode).toList();
    final totalQty = _items.fold<int>(0, (a, b) => a + b.qty);
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(
        title: Text(_l.name),
        actions: [
          IconButton(tooltip: '重命名', icon: const Icon(Icons.edit), onPressed: _rename),
          if (_items.isNotEmpty)
            IconButton(tooltip: '清空', icon: const Icon(Icons.delete_sweep), onPressed: _clearAll),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.photo_library),
                label: const Text('导入购物车截图'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _manualAdd,
              icon: const Icon(Icons.add),
              label: const Text('手动加'),
            ),
          ]),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            Padding(padding: const EdgeInsets.all(6), child: Text(_status)),
          ],
          for (final n in _notes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(n, style: TextStyle(color: n.contains('！') || n.contains('失败') ? Colors.red : null)),
            ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('共 ${_items.length} 种 / $totalQty 件')),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('升序')),
                  ButtonSegment(value: false, label: Text('降序')),
                ],
                selected: {_asc},
                onSelectionChanged: (s) => setState(() => _asc = s.first),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('点商品可改编号/名称/数量，右侧 −/+ 快速改数量，向左滑删除',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ],
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text('${g.prefix}（${g.items.length} 种 / ${g.sumQty} 件）', style: titleStyle),
            ),
            for (final it in g.items) _tile(it),
          ],
          if (noCode.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text('无编号商品（${noCode.length}）· 点击可补编号', style: titleStyle),
            ),
            for (final it in noCode) _tile(it),
          ],
        ],
      ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  for (final k in const ['txt', 'xlsx', 'png'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilledButton.tonal(
                          onPressed: () => _export(k),
                          child: Text('导出 ${k.toUpperCase()}'),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
    );
  }
}
