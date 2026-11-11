import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'exporter.dart';
import 'ocr_service.dart';
import 'parser.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '购物清单',
        theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _picker = ImagePicker();
  final List<Item> _items = [];
  final List<String> _notes = [];
  bool _asc = true;
  bool _busy = false;
  String _status = '';

  void _add(Iterable<Item> list) {
    final keys = _items.map((e) => e.key).toSet();
    for (final it in list) {
      if (keys.add(it.key)) _items.add(it);
    }
  }

  Future<void> _pick() async {
    final files = await _picker.pickMultiImage();
    if (files.isEmpty) return;
    setState(() {
      _busy = true;
      _notes.clear();
    });
    for (var i = 0; i < files.length; i++) {
      final tag = '第${i + 1}张';
      setState(() => _status = '识别$tag / 共${files.length}张…');
      try {
        final r = await recognizeCart(files[i].path, onProgress: (p) {
          if (mounted) setState(() => _status = '识别$tag / 共${files.length}张 ${(p * 100).round()}%');
        });
        _add(r.items);
        if (r.expected == null) {
          _notes.add('$tag：识别到 ${r.items.length} 件（没找到底部合计数量，无法校验）');
        } else if (r.expected != r.items.length) {
          _notes.add('$tag：识别到 ${r.items.length} 件，但截图显示共 ${r.expected} 件，请检查！');
        } else {
          _notes.add('$tag：${r.items.length} 件，与合计数量一致 ✓');
        }
      } catch (e) {
        _notes.add('$tag识别失败：$e');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<String?> _askCode({String? initial, String title = '输入编号'}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如 HSJ26-435'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('确定')),
        ],
      ),
    );
  }

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _manualAdd() async {
    final s = await _askCode();
    if (s == null) return;
    final it = parseCodeOnly(s);
    if (it == null) return _toast('格式不对，应类似 HSJ26-435');
    setState(() => _add([it]));
  }

  Future<void> _fix(Item old) async {
    final s = await _askCode(title: '补充编号：${old.name}');
    if (s == null) return;
    final it = parseCodeOnly(s, name: old.name);
    if (it == null) return _toast('格式不对，应类似 HSJ26-435');
    setState(() {
      _items.remove(old);
      _add([it]);
    });
  }

  Future<void> _export(String kind) async {
    final groups = groupAndSort(_items, ascending: _asc);
    final noCode = _items.where((e) => !e.hasCode).toList();
    if (groups.isEmpty && noCode.isEmpty) return _toast('清单是空的');
    try {
      final p = kind == 'txt'
          ? await exportTxt(groups, noCode)
          : kind == 'xlsx'
              ? await exportXlsx(groups, noCode)
              : await exportPng(groups, noCode);
      await Share.shareXFiles([XFile(p)]);
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupAndSort(_items, ascending: _asc);
    final noCode = _items.where((e) => !e.hasCode).toList();
    final coded = _items.length - noCode.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('购物清单'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_sweep),
              onPressed: () => setState(() {
                _items.clear();
                _notes.clear();
              }),
            ),
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
                label: const Text('选择购物车截图'),
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
              Text('共 ${_items.length} 件（有编号 $coded）'),
              const Spacer(),
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
          ],
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text('${g.prefix}（${g.items.length}）',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final it in g.items)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 2),
                child: ListTile(
                  dense: true,
                  title: Text(it.code),
                  subtitle: it.name.isEmpty ? null : Text(it.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _items.remove(it)),
                  ),
                ),
              ),
          ],
          if (noCode.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text('无编号商品（${noCode.length}）· 点击可补编号',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final it in noCode)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 2),
                child: ListTile(
                  dense: true,
                  title: Text(it.name),
                  onTap: () => _fix(it),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _items.remove(it)),
                  ),
                ),
              ),
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
