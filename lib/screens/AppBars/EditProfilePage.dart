import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class EditProfilePage extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> userData;

  const EditProfilePage({
    required this.uid,
    required this.userData,
  });

  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtl;
  late TextEditingController _emailCtl;
  late TextEditingController _maskedPhoneCtl;
  static const Color accent = Color(0xFF3D3D3D);
  static const Color teal = Color(0xFF25ADAD);
  File? _pdfReportFile;
  String? _pdfReportUrl; // from firestore


  // store originals for change detection
  late String _originalName;
  late String _originalEmail;

  bool _saving = false;
  bool _canEdit = false;
  int _daysLeft = 0;

  late String _reportType;              // “pdf”, “manually_entered”, or “never”
  late List<Map<String,dynamic>> _vaccines;

  @override
  void initState() {
    super.initState();


    // grab and store original values
    _originalName = widget.userData['name'] as String? ?? '';
    _originalEmail = widget.userData['email'] as String? ?? '';

    final rawPhone =
    (widget.userData['phone_number'] as String? ?? '').replaceFirst('+91', '');

    _nameCtl = TextEditingController(text: _originalName);
    _emailCtl = TextEditingController(text: _originalEmail);
    _maskedPhoneCtl = TextEditingController(text: rawPhone);

    _checkLastChange();
    _pdfReportUrl = widget.userData['report_url'] as String?;
    if (_pdfReportUrl != null) {
      // you could download it or just keep the URL here
    }
    _reportType = widget.userData['report_type'] as String? ?? 'never';
    _vaccines   = List<Map<String,dynamic>>.from(
        widget.userData['vaccines'] as List? ?? <Map<String,dynamic>>[]
    );
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _maskedPhoneCtl.dispose();
    super.dispose();
  }

  Future<void> _checkLastChange() async {
    final docRef = FirebaseFirestore.instance.doc('users/${widget.uid}');
    final snap = await docRef.get();
    final ts = snap.data()?['change_timestamp'] as Timestamp?;

    if (ts == null) {
      setState(() => _canEdit = true);
      return;
    }

    final last = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(last).inDays;

    if (diff >= 14) {
      setState(() => _canEdit = true);
    } else {
      setState(() {
        _canEdit = false;
        _daysLeft = 14 - diff;
      });
    }
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevents tapping outside to dismiss
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Text(
          'Confirm Changes',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        content: RichText(
          text: TextSpan(
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.black87,
              height: 1.4,
            ),
            children: [
              const TextSpan(text: 'You can change your profile only '),
              TextSpan(
                text: 'once every 14 days',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const TextSpan(text: '. '),
              TextSpan(
                text: 'Are you sure ',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const TextSpan(text: 'you want to proceed?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(), // just close
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _save();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              'Yes, proceed',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF00C2CB), // for example your teal accent
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _uploadPdf(File f) async {
    final user = FirebaseAuth.instance.currentUser!;
    final fn = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final ref = FirebaseStorage.instance.ref().child('pets/reports/$fn');
    await ref.putFile(f);
    return ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtl.text.trim();
    final email = _emailCtl.text.trim();

    // extra guard: shouldn't happen thanks to onPressed check
    if (name == _originalName && email == _originalEmail) return;

    final docRef = FirebaseFirestore.instance.doc('users/${widget.uid}');
    final data = {
      'name': name,
      'email': email,
      'change_timestamp': FieldValue.serverTimestamp(),
      'report_type': _reportType,
      if (_reportType == 'manually_entered') 'vaccines': _vaccines,
      if (_reportType == 'pdf') 'report_url': await _uploadPdf(_pdfReportFile!),
      // no extra field needed for 'never'
    };
    await docRef.update(data);


    setState(() => _saving = true);
    try {
      await docRef.update(data);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile updated successfully',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e, stack) {
      debugPrint('❌ Firestore update FAILED: $e');
      debugPrintStack(stackTrace: stack);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save. Please try again.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } finally {
      setState(() => _saving = false);
    }
  }
  void _showVaccineDialog() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (sheetCtx) {
          // make locals
          String tempType   = _reportType;
          File?  tempPdf    = _pdfReportFile;
          List<Map<String,dynamic>> tempList = List.from(_vaccines);

          return Padding(
            padding: MediaQuery.of(sheetCtx).viewInsets,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Text('Vaccination Info',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: teal,
                    )
                ),
                const Divider(),

                // ── Upload PDF ─────────────────────────
                RadioListTile<String>(
                  title: Text('Upload PDF', style: GoogleFonts.poppins()),
                  value: 'pdf',
                  groupValue: tempType,
                  activeColor: teal,
                  onChanged: (v) async {
                    final res = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                    );
                    if (res?.files.single.path != null) {
                      tempPdf = File(res!.files.single.path!);
                      tempType = 'pdf';
                      tempList.clear();
                      setState((){}); // to update
                      // close sheet immediately
                      setState(() {
                        _reportType     = 'pdf';
                        _pdfReportFile  = tempPdf;
                        _pdfReportUrl   = null; // we’ll upload on save
                        _vaccines       = [];
                      });
                      Navigator.pop(sheetCtx);
                    }
                  },
                ),

                // ── Enter Manually ────────────────────
                RadioListTile<String>(
                  title: Text('Enter Manually', style: GoogleFonts.poppins()),
                  value: 'manually_entered',
                  groupValue: tempType,
                  activeColor: teal,
                  onChanged: (v) {
                    // first close the sheet
                    Navigator.pop(sheetCtx);
                    // then pass sheetCtx into the dialog
                    _showManualEntry(sheetCtx);
                  },
                ),


                // ── Never Vaccinated ──────────────────
                RadioListTile<String>(
                  title: Text('Never Vaccinated', style: GoogleFonts.poppins()),
                  value: 'never',
                  groupValue: tempType,
                  activeColor: teal,
                  onChanged: (v) {
                    setState(() {
                      _reportType    = 'never';
                      _pdfReportFile = null;
                      _vaccines      = [];
                    });
                    Navigator.pop(sheetCtx);
                  },
                ),

                const SizedBox(height: 12),
              ],
            ),
          );
        }
    );
  }
  void _showManualEntry(BuildContext sheetCtx) {
    showDialog<void>(
      context: sheetCtx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        // Make a local working copy
        final tempList = List<Map<String, dynamic>>.from(_vaccines);

        return StatefulBuilder(builder: (ctx, setSt) {
          bool allRequiredFilled() {
            return tempList.isNotEmpty &&
                tempList.every((v) =>
                (v['name'] as String).trim().isNotEmpty &&
                    v['dateGiven'] is DateTime
                );
          }

          return AlertDialog(
            insetPadding: EdgeInsets.zero,
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

            // ── Title ─────────────────────────────────────────
            title: Text(
              'Enter Vaccines',
              style: GoogleFonts.poppins(
                fontSize: 20, fontWeight: FontWeight.w600, color: teal,
              ),
            ),

            // ── Content ───────────────────────────────────────
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tempList.length + 1,
                itemBuilder: (_, i) {
                  if (i == tempList.length && tempList.length < 30) {
                    return TextButton.icon(
                      onPressed: () => setSt(() {
                        tempList.add({
                          'name':      '',
                          'dateGiven': null,
                          'nextDue':   null,
                          'clinic':    '',
                          'notes':     '',
                        });
                      }),
                      icon: Icon(Icons.add, color: teal),
                      label: Text('Add Vaccine', style: GoogleFonts.poppins(color: teal)),
                    );
                  }

                  final vac = tempList[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1) Vaccine Name (required)
                          TextFormField(
                            initialValue: vac['name'],
                            style: GoogleFonts.poppins(),
                            decoration: InputDecoration(
                              labelText: 'Vaccine Name',
                              labelStyle: GoogleFonts.poppins(color: accent),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: accent, width: 1.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: teal, width: 2.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onChanged: (v) => setSt(() => vac['name'] = v),
                          ),
                          const SizedBox(height: 12),

                          // 2) Date Given (required)
                          InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: vac['dateGiven'] ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (d != null) setSt(() => vac['dateGiven'] = d);
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Date Given',
                                labelStyle: GoogleFonts.poppins(color: accent),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: accent, width: 1.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                vac['dateGiven'] != null
                                    ? DateFormat.yMMMd().format(vac['dateGiven'])
                                    : 'Pick date',
                                style: GoogleFonts.poppins(
                                  color: vac['dateGiven'] != null ? Colors.black : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 3) Next Due Date (optional)
                          InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: vac['nextDue'] ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (d != null) setSt(() => vac['nextDue'] = d);
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Next Due Date (Optional)',
                                labelStyle: GoogleFonts.poppins(color: accent),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: accent, width: 1.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                vac['nextDue'] != null
                                    ? DateFormat.yMMMd().format(vac['nextDue'])
                                    : 'None',
                                style: GoogleFonts.poppins(
                                  color: vac['nextDue'] != null ? Colors.black : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 4) Vet/Clinic Name (optional)
                          TextFormField(
                            initialValue: vac['clinic'],
                            style: GoogleFonts.poppins(),
                            decoration: InputDecoration(
                              labelText: 'Vet/Clinic Name (Optional)',
                              labelStyle: GoogleFonts.poppins(color: accent),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: accent, width: 1.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: teal, width: 2.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onChanged: (v) => setSt(() => vac['clinic'] = v),
                          ),
                          const SizedBox(height: 12),

                          // 5) Notes (optional)
                          TextFormField(
                            initialValue: vac['notes'],
                            maxLines: 3,
                            style: GoogleFonts.poppins(),
                            decoration: InputDecoration(
                              labelText: 'Notes (Optional)',
                              labelStyle: GoogleFonts.poppins(color: accent),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: accent, width: 1.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: teal, width: 2.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onChanged: (v) => setSt(() => vac['notes'] = v),
                          ),

                          Align(
                            alignment: Alignment.topRight,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => setSt(() => tempList.removeAt(i)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Actions ────────────────────────────────────────
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Cancel', style: GoogleFonts.poppins(color: accent)),
              ),
              TextButton(
                onPressed: allRequiredFilled()
                    ? () {
                  setState(() {
                    _reportType = 'manually_entered';
                    _pdfReportFile = null;
                    _vaccines = tempList;
                  });
                  Navigator.pop(dialogCtx);
                  Navigator.pop(sheetCtx);
                }
                    : null,
                child: Text('OK', style: GoogleFonts.poppins(color: teal)),
              ),
            ],
          );
        });
      },
    );
  }





  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF6F6F6);
    const Color teal = Color(0xFF25ADAD);

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile', style: GoogleFonts.poppins()),
        backgroundColor: backgroundColor,
        elevation: 1,
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Name Field
                TextFormField(
                  controller: _nameCtl,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    labelStyle: GoogleFonts.poppins(),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: GoogleFonts.poppins(),
                  validator: (v) =>
                  v!.trim().isEmpty ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),

                // Email Field
                TextFormField(
                  controller: _emailCtl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: GoogleFonts.poppins(),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: GoogleFonts.poppins(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Enter your email';
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v))
                      return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone Field (masked & disabled)
                TextFormField(
                  controller: _maskedPhoneCtl,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    labelStyle: GoogleFonts.poppins(),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: GoogleFonts.poppins(color: Colors.black87),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Phone number cannot be changed. If you want to use a new number, please log in again with that number.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),


                // If too soon, show days-left note
                if (!_canEdit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'You can update your profile again in $_daysLeft days.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),


                const SizedBox(height: 24),

                // Save Button
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_saving || !_canEdit)
                        ? null
                        : () {
                      final name = _nameCtl.text.trim();
                      final email = _emailCtl.text.trim();
                      if (name == _originalName &&
                          email == _originalEmail) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'No changes to save',
                              style: GoogleFonts.poppins(),
                            ),
                          ),
                        );
                        return;
                      }
                      _showConfirmDialog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                      'Save Changes',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
