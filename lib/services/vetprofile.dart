
import 'package:flutter/material.dart';

import 'call_service.dart';

class VetProfilePage extends StatelessWidget {
  final String vetUid;
  final String vetName;
  final String vetImage;

  const VetProfilePage({
    Key? key,
    required this.vetUid,
    required this.vetName,
    required this.vetImage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(vetName)),
      body: Column(
        children: [
          CircleAvatar(backgroundImage: NetworkImage(vetImage), radius: 50),
          const SizedBox(height: 20),
          Text(vetName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CallScreen.start(receiverId: "SpVru3IY3hTvzedpwAftJvz5klk1"),
                ),
              );
            },
            child: const Text("Start Video Call"),
          ),
        ],
      ),
    );
  }
}
