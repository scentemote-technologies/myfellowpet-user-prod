import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class PetRemoveReasonPage extends StatefulWidget {
  final String petId;
  final String petName;

  const PetRemoveReasonPage({
    required this.petId,
    required this.petName,
    super.key,
  });

  @override
  _PetRemoveReasonPageState createState() => _PetRemoveReasonPageState();
}

class _PetRemoveReasonPageState extends State<PetRemoveReasonPage> {
  String? _reason;
  final _notesCtl = TextEditingController();
  bool _processing = false;
  static const Color teal = Color(0xFF25ADAD);
  static const Color accent = Color(0xFF3D3D3D);

  // Variable to hold the fetched reasons
  List<Map<String, dynamic>> _reasons = [];
  bool _isLoadingReasons = true;
  String? _reasonFetchError;

  @override
  void initState() {
    super.initState();
    _fetchReasons();
  }

  @override
  void dispose() {
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _fetchReasons() async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('pet_removal_reason')
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null && data.containsKey('reasons')) {
          setState(() {
            _reasons = List<Map<String, dynamic>>.from(data['reasons']);
            _isLoadingReasons = false;
          });
        } else {
          setState(() {
            _reasonFetchError = 'Data not found in document.';
            _isLoadingReasons = false;
          });
        }
      } else {
        setState(() {
          _reasonFetchError = 'Settings document not found.';
          _isLoadingReasons = false;
        });
      }
    } catch (e) {
      setState(() {
        _reasonFetchError = 'Failed to fetch reasons: $e';
        _isLoadingReasons = false;
      });
    }
  }

  Future<void> _confirm() async {
    if (_reason == null) return;

    setState(() => _processing = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final petDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('users-pets')
        .doc(widget.petId);

    try {
      // 1️⃣ Fetch all pet data
      final petSnap = await petDocRef.get();
      if (!petSnap.exists) throw 'Pet not found';

      final petData = petSnap.data()!;

      // 2️⃣ Prepare removal document with all fields
      final removalData = {
        ...petData,
        'removedAt': FieldValue.serverTimestamp(),
        'reason': _reason,
        'extraNotes': _reason == 'other' ? _notesCtl.text.trim() : null,
      };

      // 3️⃣ Write to pet_removals sub-collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('pet_removals')
          .doc(widget.petId)
          .set(removalData);

      // 4️⃣ Delete from users-pets
      await petDocRef.delete();

      // 5️⃣ Pop true to signal successful removal
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pet removed successfully'),
          backgroundColor: teal,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to remove — please try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Remove ${widget.petName}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: accent)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: accent),
      ),
      backgroundColor: Colors.grey.shade50,
      body: _isLoadingReasons
          ? const Center(child: CircularProgressIndicator())
          : _reasonFetchError != null
          ? Center(child: Text('Error: $_reasonFetchError'))
          : Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Why are you removing this pet?',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
            const SizedBox(height: 24),

            // Dynamically generate RadioListTiles
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: _reasons.map((reasonMap) {
                  return RadioListTile<String>(
                    value: reasonMap['id'],
                    groupValue: _reason,
                    activeColor: teal,
                    onChanged: (v) => setState(() => _reason = v),
                    title: Text(reasonMap['label'], style: GoogleFonts.poppins(color: accent)),
                  );
                }).toList(),
              ),
            ),

            // Optional notes for "Other"
            if (_reason == 'other') ...[
              const SizedBox(height: 24),
              TextFormField(
                controller: _notesCtl,
                decoration: InputDecoration(
                  labelText: 'Reason for removal',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  labelStyle: GoogleFonts.poppins(color: Colors.grey.shade700),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 3,
                style: GoogleFonts.poppins(color: accent),
              ),
            ],

            const Spacer(),

            // Confirm button
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _processing || _reason == null
                    ? null
                    : () => _showRemoveConfirmationDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: teal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _processing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                  'Confirm Remove',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(
                'Are you sure you want to remove this pet?',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This action cannot be undone.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _confirm();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Remove',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}