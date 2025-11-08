import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting

class NotificationsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications'),
      ),
      body: NotificationsList(),
    );
  }
}

class NotificationsList extends StatelessWidget {
  // Helper method to format timestamp to DD/MM/YYYY
  String formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    final formatter = DateFormat('dd/MM/yyyy');
    return formatter.format(date);
  }

  // Helper method to build RichText with bolded text
  RichText buildRichText(String assignedEmployee, String formattedStartDate, String formattedEndDate, String shopName) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 16, color: Colors.black), // Default text style
        children: [
          TextSpan(
            text: '$assignedEmployee',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: ' has been assigned to be the caretaker for your pet from '),
          TextSpan(
            text: '$formattedStartDate',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: ' to '),
          TextSpan(
            text: '$formattedEndDate',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: ' at '),
          TextSpan(
            text: '$shopName',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get the current user
    final User? user = FirebaseAuth.instance.currentUser;
    final String? userId = user?.uid;

    if (userId == null) {
      return Center(child: Text('User not logged in'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('boarding-bookings')
          .where('user_id', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('No notifications'));
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index].data() as Map<String, dynamic>;

            final assignedEmployee = doc['assigned_employee'] as String? ?? 'Unknown';
            final shopName = doc['shopName'] as String? ?? 'Unknown';
            final shopImage = doc['shop_image'] as String?; // Fetch the shop_image URL
            final startDate = doc['start_date'] as Timestamp?;
            final endDate = doc['end_date'] as Timestamp?;

            final formattedStartDate = startDate != null ? formatDate(startDate) : 'Unknown start date';
            final formattedEndDate = endDate != null ? formatDate(endDate) : 'Unknown end date';

            final notificationText = buildRichText(assignedEmployee, formattedStartDate, formattedEndDate, shopName);

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: shopImage != null
                    ? NetworkImage(shopImage) // Load the image from URL
                    : AssetImage('assets/placeholder.png') as ImageProvider, // Placeholder image
                radius: 30, // Adjust the radius as needed
              ),
              title: notificationText,
              onTap: () {
                // Handle tile tap
              },
            );
          },
        );
      },
    );
  }
}
