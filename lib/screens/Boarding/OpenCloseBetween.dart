import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Widget buildOpenHoursWidget(String openTime, String closeTime, List<dynamic> sortedDates) {
  if (sortedDates.isEmpty) {
    return const Text('No drop-off dates selected.');
  }

  // Convert all dates to DateTime and sort
  List<DateTime> dates = sortedDates.map((d) {
    if (d is Timestamp) return d.toDate();
    return d as DateTime;
  }).toList()
    ..sort();

  // Format helper
  String formatDate(DateTime date) => DateFormat('EEEE, MMM d, y').format(date);

  return Padding(
    padding: const EdgeInsets.only(left: 5, bottom: 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Note:',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: const TextStyle(color: Colors.black, fontSize: 14),
            children: [
              const TextSpan(text: '• Drop off your pet between '),
              TextSpan(
                text: openTime,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: ' and '),
              TextSpan(
                text: closeTime,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        ...(() {
          List<List<DateTime>> grouped = [];
          for (DateTime date in dates) {
            if (grouped.isEmpty || date.difference(grouped.last.last).inDays > 1) {
              grouped.add([date]);
            } else {
              grouped.last.add(date);
            }
          }

          return grouped.map((group) {
            final lastDate = group.last;
            final pickupDay = lastDate.add(const Duration(days: 1));
            final formattedPickupDay = formatDate(pickupDay);
            return Padding(
              padding: const EdgeInsets.only(left: 0, top: 5),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                  children: [
                    const TextSpan(text: '• Please come on '),
                    TextSpan(
                      text: formattedPickupDay,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ' at '),
                    TextSpan(
                      text: openTime,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ' to pick up your pet.'),
                  ],
                ),
              ),
            );
          }).toList();
        })(),


      ],
    ),
  );
}
