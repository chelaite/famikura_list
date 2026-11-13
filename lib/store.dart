import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'parser.dart';

class ShopList {
  String id;
  String name;
  DateTime created;
  List<Item> items;
  ShopList({required this.id, required this.name, required this.created, List<Item>? items})
      : items = items ?? [];

  int get totalQty => items.fold(0, (a, b) => a + b.qty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': created.toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory ShopList.fromJson(Map<String, dynamic> j) => ShopList(
        id: j['id'] as String,
        name: j['name'] as String,
        created: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        items: ((j['items'] as List?) ?? [])
            .map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}

class Store {
  static Future<File> _file() async {
    final d = await getApplicationDocumentsDirectory();
    return File('${d.path}/lists.json');
  }

  static Future<List<ShopList>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString()) as List;
      return data.map((e) => ShopList.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<ShopList> lists) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(lists.map((e) => e.toJson()).toList()));
  }
}
