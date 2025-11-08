import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import 'distance_provider.dart';

class BoardingCardsProvider extends ChangeNotifier {
  final BuildContext context;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? majorityPetType;

  List<Map<String, dynamic>> cards = [];
  bool ready = false;
  StreamSubscription<QuerySnapshot>? _subscription;

  BoardingCardsProvider(this.context) {
    _init();
  }

  Future<void> fetchUserMajorityPet() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('users-pets')
          .get();
      if (snapshot.docs.isEmpty) return;
      final petTypes = snapshot.docs
          .map((doc) => doc.data()['pet_type'] as String?)
          .where((type) => type != null)
          .cast<String>()
          .toList();
      if (petTypes.isEmpty) return;
      final counts = <String, int>{};
      for (final type in petTypes) {
        counts[type] = (counts[type] ?? 0) + 1;
      }
      final maxCount = counts.values.reduce(max);
      final majorityTypes =
      counts.keys.where((key) => counts[key] == maxCount).toList();
      majorityPetType = majorityTypes[Random().nextInt(majorityTypes.length)];
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching user majority pet: $e');
    }
  }

  Future<void> _init() async {
    fetchUserMajorityPet();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('boarding_cards');
    _subscription = FirebaseFirestore.instance
        .collection('users-sp-boarding')
        .where('display', isEqualTo: true)
        .limit(10)
        .snapshots()
        .listen(
        _onSnapshot,
        onError: (error) {
          // This will now print the real error instead of ignoring it
          print("!!!!!! PROVIDER STREAM FAILED: $error !!!!!!");
          ready = true; // Set ready to true to stop the loading indicator
          cards = [];   // Ensure cards list is empty
          notifyListeners();
        }
    );  }

  // ✅ NEW: Centralized sorting method.
  void _sortCardsByDistance() {
    cards.sort((a, b) {
      final da = a['distance'] ?? double.infinity;
      final db = b['distance'] ?? double.infinity;
      return da.compareTo(db);
    });
  }

  void recalculateCardDistances(Position userPosition) {
    if (cards.isEmpty) return;
    for (var card in cards) {
      final locationData = card['shop_location'];
      if (locationData is GeoPoint) {
        final distanceInMeters = Geolocator.distanceBetween(
          userPosition.latitude,
          userPosition.longitude,
          locationData.latitude,
          locationData.longitude,
        );
        card['distance'] = distanceInMeters / 1000.0;
      }
    }
    _sortCardsByDistance(); // Sort after calculating
    notifyListeners();
  }

  // ✅ FIX: This method now ONLY replaces the data and does NOT sort.
  // This is the key to preventing the card from moving.
  void replaceService(String oldId, Map<String, dynamic> newServiceData) {
    final index = cards.indexWhere((card) => card['id'] == oldId);
    if (index != -1) {
      cards[index] = newServiceData;
      notifyListeners();
    }
  }

  Future<void> _onSnapshot(QuerySnapshot snap) async {
    if (!ready) {
      ready = true;
    }
    if (snap.docs.isEmpty) {
      cards = [];
      notifyListeners();
      await _cacheCards();
      return;
    }
    final distances = context.read<DistanceProvider>().distances;
    List<Map<String, dynamic>> allBranches = snap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final serviceId = doc.id;
      final standardPricesMap = Map<String, dynamic>.from(data['pre_calculated_standard_prices'] ?? {});
      final offerPricesMap = Map<String, dynamic>.from(data['pre_calculated_offer_prices'] ?? {});
      final List<num> allPrices = [];
      standardPricesMap.values.forEach((petPriceMap) {
        allPrices.addAll((petPriceMap as Map<String, dynamic>).values.cast<num>());
      });
      offerPricesMap.values.forEach((petPriceMap) {
        allPrices.addAll((petPriceMap as Map<String, dynamic>).values.cast<num>());
      });
      double minPrice = allPrices.isNotEmpty ? allPrices.reduce(min).toDouble() : 0.0;
      double maxPrice = allPrices.isNotEmpty ? allPrices.reduce(max).toDouble() : 0.0;
      return {
        ...data,
        'id': serviceId,
        'service_id': data['service_id'] ?? serviceId,
        'shopName': data['shop_name'] ?? 'Unknown Shop',
        'areaName': data['area_name'] ?? 'Unknown Area',
        'shop_image': data['shop_logo'] ?? '',
        'distance': distances[serviceId] ?? double.infinity,
        'min_price': minPrice,
        'max_price': maxPrice,
      };
    }).toList();

    final Map<String, List<Map<String, dynamic>>> groupedByShopName = {};
    for (final branch in allBranches) {
      final shopName = branch['shopName'];
      (groupedByShopName[shopName] ??= []).add(branch);
    }
    final List<Map<String, dynamic>> finalCardList = [];
    groupedByShopName.forEach((shopName, branches) {
      if (branches.isEmpty) return;
      branches.sort((a, b) => a['distance'].compareTo(b['distance']));
      final closestBranch = branches.first;
      final otherBranchIds = branches
          .map((b) => b['id'] as String)
          .where((id) => id != closestBranch['id'])
          .toList();
      closestBranch['other_branches'] = otherBranchIds;
      finalCardList.add(closestBranch);
    });

    cards = finalCardList;
    _sortCardsByDistance(); // Sort the fresh list by distance
    notifyListeners();
    await _cacheCards();
    await _precacheImages();
  }

  Future<void> _cacheCards() async {
    final List<Map<String, dynamic>> serializableCards = cards.map((card) {
      final serializableCard = Map<String, dynamic>.from(card);
      for (var key in ['location_geopoint', 'shop_location']) {
        if (serializableCard[key] is GeoPoint) {
          final geoPoint = serializableCard[key] as GeoPoint;
          serializableCard[key] = {'latitude': geoPoint.latitude, 'longitude': geoPoint.longitude,};
        }
      }
      for (var key in ['created_at', 'admin_approval_time', 'timestamp']) {
        if (serializableCard[key] is Timestamp) {
          final timestamp = serializableCard[key] as Timestamp;
          serializableCard[key] = timestamp.toDate().toIso8601String();
        }
      }
      return serializableCard;
    }).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('boarding_cards', jsonEncode(serializableCards));
    } catch (e) {
      print('❌ Error saving cards to local storage: $e');
    }
  }

  Future<void> _precacheImages() async {
    if (context.mounted) {
      await Future.wait(cards.map((card) {
        final url = card['shop_image'] as String? ?? '';
        return url.isNotEmpty
            ? precacheImage(NetworkImage(url), context)
            : Future.value();
      }));
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}