import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class RefundInputPage extends StatefulWidget {
  final Function(double) onSubmit;

  const RefundInputPage({super.key, required this.onSubmit});

  @override
  State<RefundInputPage> createState() => _RefundInputPageState();
}

class _RefundInputPageState extends State<RefundInputPage> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Refund Request")),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Enter refund amount",
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                widget.onSubmit(double.tryParse(controller.text) ?? 0);
                Navigator.pop(context);
              },
              child: Text("Submit Refund"),
            )
          ],
        ),
      ),
    );
  }
}
