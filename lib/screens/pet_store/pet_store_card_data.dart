// --- 📄 lib/models/pet_store_card_data.dart (FINAL CORRECTED & OPTIMIZED) ---
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
// OPTIMIZATION: Removed unused import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PetStoreCardData {
  final String serviceId;
  final String shopName;
  final String logoUrl;
  final List<String> imageUrls;
  final String areaName;
  final String district;
  final GeoPoint location;
  final List<String> categories;
  final Map<String, Map<String, String>> storeHours;

  // 💥 FIX: ADDED PHONE NUMBER FIELD 💥
  final String phoneNumber;

  // Mutable field for distance (requires calculation outside the factory)
  double distanceKm;

  PetStoreCardData({
    required this.serviceId,
    required this.shopName,
    required this.logoUrl,
    required this.imageUrls,
    required this.areaName,
    required this.district,
    required this.location,
    required this.categories,
    required this.storeHours,
    // 💥 FIX: ADDED PHONE NUMBER TO CONSTRUCTOR 💥
    required this.phoneNumber,
    this.distanceKm = double.infinity,
  });

  // Factory to convert Firestore data (from users-sp-store) to the model
  factory PetStoreCardData.fromMap(Map<String, dynamic> data, String id) {
    // Optimization: More compact, safer way to process store_hours
    final Map<String, Map<String, String>> storeHours = {};
    final rawHours = Map<String, dynamic>.from(data['store_hours'] ?? {});

    rawHours.forEach((key, value) {
      if (value is Map) {
        // Safe casting for nested map to prevent runtime exceptions
        storeHours[key] = Map<String, String>.from(value.map((k, v) => MapEntry(k.toString(), v.toString())));
      }
    });

    return PetStoreCardData(
      serviceId: id,
      shopName: data['shop_name'] ?? 'N/A',
      logoUrl: data['shop_logo'] ?? '',
      imageUrls: List<String>.from(data['store_images'] ?? []),
      areaName: data['area_name'] ?? 'N/A',
      district: data['district'] ?? 'N/A',
      location: data['location_geopoint'] as GeoPoint? ?? const GeoPoint(0, 0), // Use safe casting
      categories: List<String>.from(data['product_categories'] ?? []),
      storeHours: storeHours,
      // 💥 FIX: PARSE PHONE NUMBER 💥
      phoneNumber: data['phone_number'] ?? '',
    );
  }
}

// --------------------------------------------------------------------------
// --- 🛠️ Utility Functions (Remaining functions are correct and optimized) ---
// --------------------------------------------------------------------------

// Converts time strings like "11:00 PM" to minutes from midnight
int _timeOfDayToMinutes(String timeStr) {
  if (timeStr.isEmpty || timeStr == 'Not Set') return -1;
  try {
    final parts = timeStr.split(RegExp(r'[:\s]'));
    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);
    final isPM = parts.length > 2 && parts[2].toUpperCase() == 'PM';

    if (isPM && hour < 12) hour += 12;
    if (!isPM && hour == 12) hour = 0; // Midnight 12:xx AM to 00:xx

    return hour * 60 + minute;
  } catch (e) {
    return -1;
  }
}

// Logic to determine opening status and time based on store hours
Map<String, dynamic> getStoreStatus(Map<String, Map<String, String>> storeHours, BuildContext context) {
  final now = DateTime.now();
  final dayName = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][now.weekday - 1];
  final todayHours = storeHours[dayName];

  final openTimeStr = todayHours?['open'] ?? 'Not Set';
  final closeTimeStr = todayHours?['close'] ?? 'Not Set';

  if (todayHours == null || openTimeStr == 'Not Set' || closeTimeStr == 'Not Set' || openTimeStr.isEmpty || closeTimeStr.isEmpty) {
    return {'isOpen': false, 'statusText': 'Hours Not Set', 'timeString': ''};
  }

  final openMinutes = _timeOfDayToMinutes(openTimeStr);
  final closeMinutes = _timeOfDayToMinutes(closeTimeStr);
  final currentMinutes = now.hour * 60 + now.minute;

  if (openMinutes == -1 || closeMinutes == -1) {
    return {'isOpen': false, 'statusText': 'Closed (Invalid Format)', 'timeString': ''};
  }

  bool isOpen;
  int closingDisplayMinutes;

  if (closeMinutes < openMinutes) {
    // Overnight operation (e.g., 10 PM - 2 AM)
    isOpen = (currentMinutes >= openMinutes || currentMinutes < closeMinutes);
    closingDisplayMinutes = closeMinutes;
  } else {
    // Same-day operation
    isOpen = (currentMinutes >= openMinutes && currentMinutes < closeMinutes);
    closingDisplayMinutes = closeMinutes;
  }

  // Force 12-hour format with AM/PM using DateTime and DateFormat
  final closeTime = DateTime(now.year, now.month, now.day, closingDisplayMinutes ~/ 60, closingDisplayMinutes % 60);

  // Use 'h:mm a' pattern for 12-hour format with AM/PM
  final String closeTimeFormatted = DateFormat('h:mm a').format(closeTime);

  return {
    'isOpen': isOpen,
    'statusText': isOpen ? 'Open till $closeTimeFormatted' : 'Closed',
    'timeString': isOpen ? closeTimeFormatted : 'Closed',
  };
}