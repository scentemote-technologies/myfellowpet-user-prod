// lib/preloaders/PetsInfoProvider.dart
// ✨ FULLY CORRECTED CODE ✨
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../main.dart'; // We need this for the navigatorKey

class PetProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _pets = [];
  bool _loading = false;

  /// A Future that completes only after pets are loaded AND precached.
  final Completer<void> _ready = Completer<void>();
  Future<void> get fullyLoaded => _ready.future;

  List<Map<String, dynamic>> get pets => _pets;
  bool get isLoading => _loading;

  PetProvider() {
    // Kick off loading & precaching immediately.
    _loadPets();
  }

  void setPets(List<Map<String, dynamic>> newPets) {
    _pets = newPets;
    notifyListeners();
  }

  Future<void> _loadPets() async {
    _loading = true;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _ready.complete();
      _loading = false; // ✨ Also set loading to false
      notifyListeners(); // ✨ And notify
      return;
    }

    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('users-pets')
        .get();

    _pets = snapshot.docs.map((doc) {
      final data = doc.data();
      // ✨ Added more fields from your petpreloaders.dart logic to be safe
      return {
        'pet_id': data['pet_id'] ?? doc.id,
        'name': data['name'] ?? '',
        'pet_image': data['pet_image'] as String?,
        'pet_type': data['pet_type'] as String?,
        'size': data['size'] as String?,
        'pet_breed': data['pet_breed'] as String?,
      };
    }).toList();

    // --- ✨ THIS IS THE FIX ---
    // We get the context *before* the async gap
    final context = navigatorKey.currentContext;

    // Check if the context is valid before trying to precache
    if (context != null) {
      try {
        await Future.wait(_pets.map((pet) async {
          final url = pet['pet_image'];
          if (url != null && url.isNotEmpty) {
            // We use the 'context' variable which we know is not null
            await precacheImage(NetworkImage(url), context);
          }
        }));
      } catch (e) {
        // This can happen if the context is lost during the await
        // It's safe to ignore, as precaching is an optimization, not critical
        print("Image precaching failed (safe to ignore): $e");
      }
    }
    // --- END OF FIX ---

    _loading = false;
    notifyListeners();
    _ready.complete(); // signal “all done”
  }
}