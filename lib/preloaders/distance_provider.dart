// lib/providers/distance_provider.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class DistanceProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  Position? _currentPosition;
  Map<String,double> _distances = {};

  DistanceProvider(this._firestore) {
    _init();
  }

  Map<String,double> get distances => _distances;

  Future<void> _init() async {
    // 1) get permission + current location
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    _currentPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // 2) listen to your services collection
    _firestore
        .collection('users-sp-boarding')
        .snapshots()
        .listen(_recomputeAllDistances);
  }

  void _recomputeAllDistances(QuerySnapshot batch) {
    if (_currentPosition == null) return;
    for (var doc in batch.docs) {
      final id  = doc.get('service_id') as String;
      final loc = doc.get('shop_location') as GeoPoint;
      final m   = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        loc.latitude,
        loc.longitude,
      );
      _distances[id] = m / 1000.0;
    }
    notifyListeners();
  }
}
