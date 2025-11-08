import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// A result class that holds the transport cost and individual distances.
class TransportCostResult {
  final double totalCost;
  final double pickupDistance;
  final double dropoffDistance;

  TransportCostResult({
    required this.totalCost,
    required this.pickupDistance,
    required this.dropoffDistance,
  });
}

/// Returns the distance (in meters) between two locations using the Google Distance Matrix API.
Future<double> getDistanceFromGoogle(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
    ) async {
  const String apiKey = 'AIzaSyCbr1VKuRpq-1TYYhlbUEuWl5xZpUg3dBo';
  final url =
      'https://maps.googleapis.com/maps/api/distancematrix/json?origins=$originLat,$originLng&destinations=$destLat,$destLng&key=$apiKey';
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    final jsonResponse = jsonDecode(response.body);
    final elements = jsonResponse['rows']?[0]?['elements'];
    if (elements != null && elements[0]['status'] == 'OK') {
      double distanceMeters = (elements[0]['distance']['value'] as num).toDouble();
      return distanceMeters;
    }
  }
  throw Exception("Error fetching distance from Google API");
}

/// Calculates the transport cost and returns a TransportCostResult.
///
/// The parameters:
/// - serviceProviderLocation: Provider’s location (GeoPoint)
/// - userLocation: User’s location (GeoPoint)
/// - pickupRequired: true if pickup is required
/// - dropoffRequired: true if dropoff is required
/// - costPerKm: cost per kilometer
Future<TransportCostResult> calculateTransportCost({
  required GeoPoint serviceProviderLocation,
  required GeoPoint userLocation,
  required bool pickupRequired,
  required bool dropoffRequired,
  required double costPerKm,
}) async {
  double distanceInMeters = await getDistanceFromGoogle(
    userLocation.latitude,
    userLocation.longitude,
    serviceProviderLocation.latitude,
    serviceProviderLocation.longitude,
  );
  double distanceInKm = distanceInMeters / 1000.0;
  double pickupDistance = pickupRequired ? distanceInKm : 0.0;
  double dropoffDistance = dropoffRequired ? distanceInKm : 0.0;
  double totalCost = (pickupDistance + dropoffDistance) * costPerKm;
  return TransportCostResult(
    totalCost: totalCost,
    pickupDistance: pickupDistance,
    dropoffDistance: dropoffDistance,
  );
}
