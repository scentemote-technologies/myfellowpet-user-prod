// lib/models/shop.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Shop {
  /// Firestore document ID
  final String id;

  /// The service_id field in your document
  final String serviceId;

  /// The shopId field in your document
  final String shopId;

  /// Display name
  final String name;

  /// Area or location name
  final String areaName;

  /// URL to the image
  final String imageUrl;

  /// The price field from your document
  final int price;

  /// List of pet types
  final List<String> pets;

  /// Is the service certified by MFP
  final bool mfpCertified;

  /// The type of service run (e.g., "Home Run")
  final String type;

  /// Is an offer currently active for this service
  final bool isOfferActive;

  /// Daily rates map
  final Map<String, dynamic> ratesDaily;

  /// Hourly rates map
  final Map<String, dynamic> ratesHourly;

  /// Other fields from the Firestore document
  final bool adminApproved;
  final String adminApprovalTime;
  final bool adminVerificationStatus;
  final String closeTime;
  final String openTime;
  final String description;
  final GeoPoint locationGeopoint;
  final String maxPetsAllowed;
  final String maxPetsAllowedPerHour;
  final Map<String, dynamic> mealRates;
  final Map<String, dynamic> offerDailyRates;
  final Map<String, dynamic> offerMealRates;
  final Map<String, dynamic> offerWalkingRates;
  final List<String> imageUrls;
  final String fullAddress;
  final String ownerName;
  final String ownerPhone;
  final String uid;

  /// Precomputed distance (you can set this after fetching location)
  double distanceKm;

  Shop({
    required this.id,
    required this.serviceId,
    required this.shopId,
    required this.name,
    required this.areaName,
    required this.imageUrl,
    required this.price,
    required this.pets,
    required this.mfpCertified,
    required this.type,
    required this.isOfferActive,
    required this.ratesDaily,
    required this.ratesHourly,
    required this.adminApproved,
    required this.adminApprovalTime,
    required this.adminVerificationStatus,
    required this.closeTime,
    required this.openTime,
    required this.description,
    required this.locationGeopoint,
    required this.maxPetsAllowed,
    required this.maxPetsAllowedPerHour,
    required this.mealRates,
    required this.offerDailyRates,
    required this.offerMealRates,
    required this.offerWalkingRates,
    required this.imageUrls,
    required this.fullAddress,
    required this.ownerName,
    required this.ownerPhone,
    required this.uid,
    this.distanceKm = 0.0,
  });

  /// Factory to create from a Firestore doc snapshot
  factory Shop.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Shop(
      id: doc.id,
      serviceId: data['service_id'] as String? ?? doc.id,
      shopId: data['shop_user_id'] as String? ?? '',
      name: data['shop_name'] as String? ?? 'Unknown Shop',
      areaName: data['area_name'] as String? ?? 'Unknown Area',
      imageUrl: data['shop_logo'] as String? ?? '',
      price: int.tryParse(data['price']?.toString() ?? '') ?? 0,
      pets: List<String>.from(data['pets'] ?? <String>[]),
      mfpCertified: data['mfp_certified'] as bool? ?? false,
      type: data['type'] as String? ?? '',
      isOfferActive: data['isOfferActive'] as bool? ?? false,
      ratesDaily: data['rates_daily'] as Map<String, dynamic>? ?? {},
      ratesHourly: data['rates_hourly'] as Map<String, dynamic>? ?? {},
      adminApproved: data['adminApproved'] as bool? ?? false,
      adminApprovalTime: data['admin_approval_time']?.toString() ?? '',
      adminVerificationStatus: data['admin_verification_status'] as bool? ?? false,
      closeTime: data['close_time'] as String? ?? '',
      openTime: data['open_time'] as String? ?? '',
      description: data['description'] as String? ?? '',
      locationGeopoint: data['shop_location'] as GeoPoint? ?? const GeoPoint(0.0, 0.0),
      maxPetsAllowed: data['max_pets_allowed'] as String? ?? '',
      maxPetsAllowedPerHour: data['max_pets_allowed_per_hour'] as String? ?? '',
      mealRates: data['meal_rates'] as Map<String, dynamic>? ?? {},
      offerDailyRates: data['offer_daily_rates'] as Map<String, dynamic>? ?? {},
      offerMealRates: data['offer_meal_rates'] as Map<String, dynamic>? ?? {},
      offerWalkingRates: data['offer_walking_rates'] as Map<String, dynamic>? ?? {},
      imageUrls: List<String>.from(data['image_urls'] ?? []),
      fullAddress: data['full_address'] as String? ?? '',
      ownerName: data['owner_name'] as String? ?? '',
      ownerPhone: data['owner_phone'] as String? ?? '',
      uid: data['uid'] as String? ?? '',
    );
  }
}