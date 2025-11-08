// --- 📄 lib/models/pet_store_detail_data.dart (FINAL CORRECTED & OPTIMIZED) ---

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myfellowpet_user/screens/pet_store/pet_store_card_data.dart';
// Note: Removed UI-related imports (flutter/material, url_launcher) for a clean data model.

class PetStoreDetailData extends PetStoreCardData {
  // Store Info
  final String description;
  final String specialty;
  final List<String> paymentModes;
  // NOTE: 'storeImages' field remains removed as it is redundant to 'imageUrls' in the base class.

  // Logistics
  final int deliveryRadiusKm;
  final int fulfillmentTimeMin;
  final int minOrderValue;
  final int flatDeliveryFee;

  // Policy & Support
  final String supportEmail;
  final int returnWindowValue;
  final String returnWindowUnit;
  final String returnPolicyText;
  final String partnerPolicyUrl;

  // Full Address Details
  final String street;
  final String postalCode;
  final String state;
  final GeoPoint locationGeopoint;


  PetStoreDetailData({
    required super.serviceId,
    required super.shopName,
    required super.logoUrl,
    required super.imageUrls,
    required super.areaName,
    required super.district,
    required super.location,
    required super.categories,
    required super.storeHours,

    // 💥 FIX: ADDED PHONE NUMBER TO CONSTRUCTOR 💥
    // Assuming phoneNumber is part of the PetStoreCardData base class
    required super.phoneNumber,

    required this.description,
    required this.specialty,
    required this.paymentModes,
    required this.deliveryRadiusKm,
    required this.fulfillmentTimeMin,
    required this.minOrderValue,
    required this.flatDeliveryFee,
    required this.supportEmail,
    required this.returnWindowValue,
    required this.returnWindowUnit,
    required this.returnPolicyText,
    required this.partnerPolicyUrl,
    required this.street,
    required this.postalCode,
    required this.state,
    required this.locationGeopoint,
  });

  factory PetStoreDetailData.fromFirestore(Map<String, dynamic> data, String id) {
    // Optimization: More compact, safer way to process store_hours
    final Map<String, Map<String, String>> storeHours = {};
    final Map<String, dynamic> rawHours = Map<String, dynamic>.from(data['store_hours'] ?? {});

    rawHours.forEach((key, value) {
      if (value is Map) {
        // Safe casting for nested map to prevent runtime exceptions
        storeHours[key] = Map<String, String>.from(value.map((k, v) => MapEntry(k.toString(), v.toString())));
      }
    });

    final GeoPoint rawGeoPoint = data['location_geopoint'] as GeoPoint? ?? const GeoPoint(0, 0);
    final List<String> images = List<String>.from(data['store_images'] ?? []);

    // 💥 FIX: Safely retrieve phone number 💥
    final String phoneNumber = data['dashboard_whatsapp'] ?? '';


    return PetStoreDetailData(
      serviceId: id,
      shopName: data['shop_name'] ?? 'Pet Store',
      logoUrl: data['shop_logo'] ?? '',
      imageUrls: images,
      areaName: data['area_name'] ?? '',
      district: data['district'] ?? '',
      location: rawGeoPoint,
      categories: List<String>.from(data['product_categories'] ?? []),
      storeHours: storeHours,

      // 💥 FIX: ASSIGN PHONE NUMBER 💥
      phoneNumber: phoneNumber,

      // Detail Fields
      description: data['description'] ?? 'No description provided.',
      specialty: data['specialty_niche'] ?? 'General pet supplies.',
      paymentModes: List<String>.from(data['accepted_payment_modes'] ?? []),

      // Optimization: Safe casting for integer fields
      deliveryRadiusKm: data['delivery_radius_km'] is int ? data['delivery_radius_km'] : (data['delivery_radius_km'] as num?)?.toInt() ?? 0,
      fulfillmentTimeMin: data['fulfillment_time_min'] is int ? data['fulfillment_time_min'] : (data['fulfillment_time_min'] as num?)?.toInt() ?? 0,
      minOrderValue: data['delivery_min_order_value'] is int ? data['delivery_min_order_value'] : (data['delivery_min_order_value'] as num?)?.toInt() ?? 0,
      flatDeliveryFee: data['delivery_flat_fee'] is int ? data['delivery_flat_fee'] : (data['delivery_flat_fee'] as num?)?.toInt() ?? 0,

      supportEmail: data['support_email'] ?? 'support@store.com',
      returnWindowValue: data['return_window_value'] is int ? data['return_window_value'] : (data['return_window_value'] as num?)?.toInt() ?? 0,
      returnWindowUnit: data['return_window_unit'] ?? 'Days',
      returnPolicyText: data['return_policy_text'] ?? 'Standard return policy applies.',
      partnerPolicyUrl: data['partner_policy_url'] ?? '',

      street: data['street'] ?? '',
      postalCode: data['postal_code'] ?? '',
      state: data['state'] ?? '',
      locationGeopoint: rawGeoPoint,
    );
  }
}