// lib/preloaders/petpreloaders.dart
// ✨ FULLY OPTIMIZED AND CORRECTED CODE ✨

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

/// A simple model for your pet data.
class Pet {
  final String id;
  final String name;
  final String imageUrl;
  final String breed;
  final String age;
  final String petType; // ✨ ADDED
  final String size;    // ✨ ADDED

  Pet({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.breed,
    required this.age,
    required this.petType, // ✨ ADDED
    required this.size,    // ✨ ADDED
  });

  Map<String, dynamic> toMap() {
    return {
      'pet_id': id,
      'name': name,
      'pet_image': imageUrl,
      'pet_breed': breed,
      'pet_age': age,
      'pet_type': petType, // ✨ ADDED
      'size': size,       // ✨ ADDED
    };
  }

  factory Pet.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Pet(
      id: data['pet_id'] as String? ?? doc.id,
      name: data['name'] as String? ?? 'Unnamed',
      imageUrl: data['pet_image'] as String? ?? '',
      breed: data['pet_breed'] as String? ?? 'unknown', // ✨ Default to 'unknown'
      age: data['pet_age'] as String? ?? 'NA',
      petType: data['pet_type'] as String? ?? 'unknown', // ✨ ADDED
      size: data['size'] as String? ?? 'unknown',       // ✨ ADDED
    );
  }
}

/// A singleton “repository” you can call from anywhere.
class PetService {
  PetService._();
  static final PetService instance = PetService._();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  /// Returns a stream of Pet objects, updating in real-time.
  Stream<List<Pet>> watchMyPets(BuildContext context) {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('users-pets')
        .snapshots()
        .map((snap) {
      final pets = snap.docs.map((d) => Pet.fromDoc(d)).toList();

      // Use a local context to avoid passing BuildContext if it's not needed
      final localContext = context;

      // Fire-and-forget image caching;
      for (var pet in pets) {
        if (pet.imageUrl.isNotEmpty && localContext.mounted) {
          precacheImage(NetworkImage(pet.imageUrl), localContext).catchError((_) {
            // Optional: Log caching error
          });
        }
      }
      return pets;
    });
  }

  /// Returns a stream of pet data as Map for UI builders.
  Stream<List<Map<String, dynamic>>> watchMyPetsAsMap(BuildContext context) {
    return watchMyPets(context).map(
          (list) => list.map((p) => p.toMap()).toList(),
    );
  }

  /// Legacy: one-time fetch (if needed).
  Future<List<Pet>> fetchMyPets(BuildContext context) async {
    final uid = _auth.currentUser!.uid;
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('users-pets')
        .get();

    final pets = snap.docs.map((doc) => Pet.fromDoc(doc)).toList();

    // Use a local context
    final localContext = context;

    // Fire-and-forget caching as before
    for (var pet in pets) {
      if (pet.imageUrl.isNotEmpty && localContext.mounted) {
        precacheImage(NetworkImage(pet.imageUrl), localContext).catchError((_) {
          // Optional: Log caching error
        });
      }
    }
    return pets;
  }
}