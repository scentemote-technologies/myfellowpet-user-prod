import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/call_service.dart';

class VetHomePage extends StatelessWidget {
  const VetHomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final vetId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("Vet Dashboard")),
      body: Stack(
        children: [
          // 👇 Your normal vet home content here
          Center(
            child: Text(
              "Welcome, Doctor 🐾",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),

          // 👇 Add the listener right here
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('calls')
                .where('receiverId', isEqualTo: vetId)
                .where('status', isEqualTo: 'ringing')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SizedBox.shrink();
              }

              final call = snapshot.data!.docs.first;
              final callId = call.id;

              // 👇 Show popup immediately
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => AlertDialog(
                    title: const Text("Incoming Video Call"),
                    content: const Text("A pet parent is calling you 🐾"),
                    actions: [
                      TextButton(
                        onPressed: () {
                          FirebaseFirestore.instance
                              .collection('calls')
                              .doc(callId)
                              .update({'status': 'connected'});
                          Navigator.pop(context); // close dialog
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CallScreen.answer(callId: callId),
                            ),
                          );
                        },
                        child: const Text("Accept"),
                      ),
                      TextButton(
                        onPressed: () {
                          FirebaseFirestore.instance
                              .collection('calls')
                              .doc(callId)
                              .update({'status': 'ended'});
                          Navigator.pop(context);
                        },
                        child: const Text("Reject"),
                      ),
                    ],
                  ),
                );
              });

              return const SizedBox.shrink(); // don't build anything visually
            },
          ),
        ],
      ),
    );
  }
}
