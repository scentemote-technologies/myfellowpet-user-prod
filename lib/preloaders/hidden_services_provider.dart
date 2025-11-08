import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';

class HiddenServicesProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Set<String> hidden = {};
  bool _loaded = false;
  bool get isLoaded => _loaded;

  HiddenServicesProvider() {
    _loadHiddenOnStartup();
  }

  Future<void> _loadHiddenOnStartup() async {
    final user = _auth.currentUser;
    if (user == null) {
      _loaded = true;
      notifyListeners();
      return;
    }
    final doc = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('user_preferences')
        .doc('boarding')
        .get();

    if (doc.exists && doc.data()?['hidden'] is List) {
      hidden = Set<String>.from(doc.data()!['hidden']);
    }
    _loaded = true;           // ← mark loaded
    notifyListeners();
  }

  void toggle(String serviceId) {
    if (hidden.contains(serviceId)) {
      hidden.remove(serviceId);
    } else {
      hidden.add(serviceId);
    }
    notifyListeners();
    _saveHidden();  // push your updated set back to Firestore
  }

  Future<void> _saveHidden() {
    final user = _auth.currentUser;
    if (user == null) return Future.value();
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('user_preferences')
        .doc('boarding')
        .set({'hidden': hidden.toList()}, SetOptions(merge: true));
  }
}
