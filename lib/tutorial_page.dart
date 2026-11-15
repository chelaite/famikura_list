import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 版本号：发新版时手动更新
const kAppVersion = '1.0';

Future<File> _flagFile() async {
  final d = await getApplicationDocumentsDirectory();
  return File('${d.path}/tutorial_seen');
}

/// 是否已经显示过教程；读取失败时当作已显示，避免反复打扰
Future<bool> tutorialSeen() async {
  try {
    return await (await _flagFile()).exists();
  } catch (_) {
    return true;
  }
}

Future<void> markTutorialSeen() async {
  try {
    await (await _flagFile()).writeAsString('1');
  } catch (_) {}
}

class _Slide {
  final IconData icon;
  final String title;
  final List<String> bullets; // **粗体**
  final String? footer;
  const _Slide(this.icon, this.title, this.bullets, {this.footer});
}

const _slides = <_Slide>[
  _Slide(Icons.photo_library_outlined, '导入截图', [
    '在网站购物车页面截一张长图，点首页的「导入截图」，可以一次选多张',
    '**橙色**数量表示没识别到，已先按 1 计，请自己核对',
    '应用会用截图底部的「合计数量」检查有没有漏',
  ]),
  _Slide(Icons.view_list_outlined, '整理清单', [
    '商品自动按团体分组，可切换升序 / 降序',
    '点 −/＋ 改数量，点商品可编辑，向左滑删除',
    '首页长按列表：全选、合并、删除、分享',
  ]),
  _Slide(
    Icons.storefront_outlined,
    '商品库与分享',
    [
      '点首页的商店图标，同步所选的团体或个人，商品名会自动变准确，清单里也能看缩略图',
      '搜索框可以搜**商品名、编号和标签**（比如成员名）；搜不到时按键盘的搜索键，会**联网搜索**，搜过的词以后在本地也能搜到',
      '商品加入购物车后，可以生成新清单，也可以加进已有的列表',
      '列表可导出 TXT / Excel / PNG，也能分享给别人，对方点首页的导入按钮即可还原',
    ],
    footer: '非官方个人开源工具。艺人的姓名、肖像、商品图片等相关权利归艺人所属事务所及其他权利人所有。',
  ),
];

class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});
  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final _ctrl = PageController();
  int _i = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _rich(String s) {
    final parts = s.split('**');
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 16, height: 1.5),
        children: [
          for (var i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: i.isOdd ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
        ],
      ),
    );
  }

  Widget _slideView(_Slide p) {
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Icon(p.icon, size: 88, color: primary),
          const SizedBox(height: 16),
          Text(
            p.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          for (final b in p.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(fontSize: 16, height: 1.5)),
                  Expanded(child: _rich(b)),
                ],
              ),
            ),
          if (p.footer != null) ...[
            const SizedBox(height: 12),
            Text(
              p.footer!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _slides.length - 1;
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerRight,
                child: last
                    ? null
                    : TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('跳过')),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _i = i),
                children: [for (final p in _slides) _slideView(p)],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _i ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _i ? primary : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? () => Navigator.of(context).pop()
                      : () => _ctrl.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                  child: Text(last ? '开始使用' : '下一步'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAboutAppDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Famikura List  v$kAppVersion'),
      content: const SingleChildScrollView(
        child: Text(
          '非官方的个人开源工具，用于整理 ファミクラストア 日本站的购物清单。\n\n'
          '艺人的姓名、肖像、商品图片等相关权利归艺人所属事务所及其他权利人所有。'
          '本应用不包含这些内容，仅在使用时从官方网站读取，并缓存在你自己的手机上。',
          style: TextStyle(height: 1.5),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
    ),
  );
}
