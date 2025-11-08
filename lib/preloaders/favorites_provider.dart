import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FavoritesProvider extends ChangeNotifier {
  Set<String> _liked = {};
  Set<String> get liked => _liked;

  FavoritesProvider() {
    _init();
  }

  void _init() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('user_preferences')
        .doc('boarding')
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      _liked = data == null
          ? {}
          : List<String>.from(data['liked'] ?? []).toSet();
      notifyListeners();
    });
  }

  Future<void> toggle(String serviceId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('user_preferences')
        .doc('boarding');
    final snap = await ref.get();
    final current = List<String>.from(snap.data()?['liked'] ?? []);
    if (current.contains(serviceId)) {
      current.remove(serviceId);
    } else {
      current.add(serviceId);
    }
    await ref.set({'liked': current});
    // _liked update will come via the listener above.
  }
}
