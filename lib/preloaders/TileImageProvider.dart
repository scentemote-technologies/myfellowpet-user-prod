import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TileImageProvider with ChangeNotifier {
  Map<String, String> _tileImages = {};

  Map<String, String> get tileImages => _tileImages;

  Future<void> loadTileImages() async {
    print("Loading tile images...");

    try {
      final doc = await FirebaseFirestore.instance
          .collection('company_documents')
          .doc('homescreen_images')
          .get();

      print("Fetched doc: ${doc.exists}");

      if (doc.exists) {
        final data = doc.data();
        print("Data from Firestore: $data");

        if (data != null && data['home_page_tile_images'] is Map) {
          _tileImages = Map<String, String>.from(data['home_page_tile_images']);
          print("Loaded tile images: $_tileImages");
          notifyListeners();
        } else {
          print("home_page_tile_images missing or wrong format.");
        }
      }
    } catch (e) {
      print("Error in loadTileImages: $e");
    }
  }


  String getImageFor(String service) {
    return _tileImages[service.toLowerCase()] ?? '';
  }
}
