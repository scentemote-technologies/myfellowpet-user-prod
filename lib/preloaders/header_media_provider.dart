import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A provider that listens to Firestore for the header-image URL,
/// preloads it immediately, and exposes a ready flag + cached ImageProvider.
class HeaderMediaProvider extends ChangeNotifier {
  final BuildContext context;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  /// The preloaded/cached image.
  ImageProvider? imageProvider;

  /// True once the latest image (if any) has been cached.
  bool ready = false;

  HeaderMediaProvider(this.context) {
    // Start listening to Firestore right away
    _subscription = FirebaseFirestore.instance
        .collection('company_documents')
        .doc('homescreen_images')
        .snapshots()
        .listen(_onSnapshot);
  }

  Future<void> _onSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) async {
    final url = snap.data()?['boarding'] as String? ?? '';
    if (url.isEmpty) {
      // No URL → consider ready but no image
      ready = true;
      notifyListeners();
      return;
    }

    // Signal that we're loading a new image
    ready = false;
    notifyListeners();

    final provider = NetworkImage(url);
    try {
      // Preload into Flutter's image cache
      await precacheImage(provider, context);
      imageProvider = provider;
    } catch (e) {
      debugPrint('⚠️ Failed to preload header image: $e');
    }

    // Now it's ready to display
    ready = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
