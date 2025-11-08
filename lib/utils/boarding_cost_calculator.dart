double calculateTotalCost({
  required int selectedDaysCount,
  required int numberOfPets,
  required double pricePerDay,
  required bool dailyWalkingRequired,
  required String walkingFee,
  required double transportCost,
  required String foodOption, // "provider" or "self"
  Map<String, dynamic>? foodInfo,
}) {
  // Base boarding cost calculation.
  double baseBoardingCost = selectedDaysCount * pricePerDay * numberOfPets;

  // Daily walking fee.
  double walkingFeeAmount = dailyWalkingRequired ? (double.tryParse(walkingFee) ?? 0.0) : 0.0;

  // Calculate food cost if the "provider" option is selected.
  double foodCost = 0.0;
  if (foodOption == 'provider' && foodInfo != null) {
    double costPerDay = double.tryParse(foodInfo['cost_per_day'].toString()) ?? 0.0;
    foodCost = costPerDay * selectedDaysCount * numberOfPets;
  }

  // Total cost is the sum of all individual costs.
  return baseBoardingCost + walkingFeeAmount + transportCost + foodCost;
}
