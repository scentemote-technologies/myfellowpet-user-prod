import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/boarding_shop_details.dart';

class ShopDetailsProvider extends ChangeNotifier {
  List<Shop> _shops = [];
  List<Shop> get shops => _shops;

  /// Call once at startup to load the first 10.
  Future<void> loadFirstTen() async {
    final snap = await FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .limit(10)
        .get();
    _shops = snap.docs.map((d) => Shop.fromDoc(d)).toList();
    notifyListeners();
  }
}
