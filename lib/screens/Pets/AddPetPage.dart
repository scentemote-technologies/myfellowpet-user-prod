  import 'dart:io';
  import 'dart:typed_data';

  import 'package:cloud_firestore/cloud_firestore.dart';
  import 'package:crop_your_image/crop_your_image.dart';
  import 'package:file_picker/file_picker.dart';
  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:firebase_storage/firebase_storage.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter_image_compress/flutter_image_compress.dart';
  import 'package:google_fonts/google_fonts.dart';
  import 'package:image_picker/image_picker.dart';
  import 'package:intl/intl.dart';
  import 'package:path_provider/path_provider.dart';
  import 'package:recaptcha_enterprise_flutter/recaptcha_action.dart';
  import 'package:recaptcha_enterprise_flutter/recaptcha_enterprise.dart';

import '../Boarding/boarding_parameters_selection_page.dart';
  // Define professional colors for consistency
  const Color primaryTeal = Color(0xFF2CB4B6); // For the primary action
  const Color neutralDark = Color(0xFF37474F); // For titles and main text
  const Color warningYellow = Color(0xFFFFC107); // For the main icon/warning
  class PetType {
    final String id;
    final bool display;

    PetType({required this.id, required this.display});
  }

  class AddPetPage extends StatefulWidget {
    @override
    _AddPetPageState createState() => _AddPetPageState();
  }

  class _AddPetPageState extends State<AddPetPage> {
    static const Color accent = Color(0xFF3D3D3D);
    static const Color teal = Color(0xFF25ADAD);
    File? _pdfReport;
    String _reportType = ''; // "pdf", "manually_entered", or "never"
    List<Map<String, dynamic>> _vaccines = [];

    final _formKey = GlobalKey<FormState>();
    final _picker = ImagePicker();

    File? _originalFile;
    File? _croppedFile;
    bool _isSaving = false;
    bool _isCropping = false;

    bool _isNeutered = false;
    final _allergiesCtl = TextEditingController();
    final _conditionsCtl = TextEditingController();
    final _dietNotesCtl = TextEditingController();
    String? _activityLevel; // "Low", "Moderate", "High"
    final _vetNameCtl = TextEditingController();
    final _vetPhoneCtl = TextEditingController();
    final _emergencyContactCtl = TextEditingController();

    List<PetType> _petTypes = [];
    List<String> _breeds = [];
    String? _gender; // "Male" or "Female"

    String? _selectedType;
    String? _selectedBreed;
    final _notesCtl = TextEditingController();
    final _historyCtl = TextEditingController();

    List<String> _likes = [];
    List<String> _dislikes = [];
    bool _loadingExtras = false;
    List<File> _extraImages = [];
    List<String> _extraImageUrls = [];

    final _customLikeCtl = TextEditingController();
    final _customDislikeCtl = TextEditingController();

    final _nameCtl = TextEditingController();
    final _ageCtl = TextEditingController();

    String _weightType = 'exact'; // 'exact' or 'range'
    final _exactWeightCtl = TextEditingController();
    String? _selectedRange;
    String? _selectedSize;
    final List<String> _weightRanges = [
      '0 - 10 kg',
      '11 - 20 kg',
      '21 - 30 kg',
      '31 - 40 kg',
      '41 - 50 kg',
      '50+ kg',
    ];
    final List<String> _sizeRanges = [
      'Small',
      'Medium',
      'Large',
      'Giant',

    ];

    int _petCount = 0;

    @override
    void initState() {
      super.initState();
      _loadPetTypes();
      _updatePetCount();
    }

    @override
    void dispose() {
      _nameCtl.dispose();
      _ageCtl.dispose();
      _notesCtl.dispose();
      _historyCtl.dispose();
      _allergiesCtl.dispose();
      _conditionsCtl.dispose();
      _dietNotesCtl.dispose();
      _vetNameCtl.dispose();
      _vetPhoneCtl.dispose();
      _emergencyContactCtl.dispose();
      _exactWeightCtl.dispose();
      _customLikeCtl.dispose();
      _customDislikeCtl.dispose();
      super.dispose();
    }

    Future<void> _loadPetTypes() async {
      final snapshot = await FirebaseFirestore.instance.collection('pet_types').get();
      setState(() {
        _petTypes = snapshot.docs
            .map((d) => PetType(
          id: d.id,
          display: (d.data()['display'] as bool? ?? false),
        ))
            .toList();
      });
    }

    Future<void> _updatePetCount() async {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('users-pets')
          .get();
      setState(() => _petCount = snap.size);
    }

    Future<void> _loadBreeds(String typeId) async {
      final snapshot = await FirebaseFirestore.instance
          .collection('pet_types')
          .doc(typeId)
          .collection('breeds')
          .get();
      setState(() {
        _breeds = snapshot.docs.map((d) => d['name'] as String).toList();
        _selectedBreed = null;
      });
    }

    Future<void> _pickImage() async {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (picked == null) return;
      setState(() {
        _originalFile = File(picked.path);
        _croppedFile = null;
        _isCropping = true;
      });
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => FreeFormCropSheet(
          file: _originalFile!,
          onCropped: (file) => setState(() {
            _croppedFile = file;
            _isCropping = false;
          }),
        ),
      );
      Navigator.of(context).pop();
    }

    Future<String> _uploadImage(File f) async {
      final user = FirebaseAuth.instance.currentUser!;
      final fn = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.png';
      final ref = FirebaseStorage.instance.ref().child('pets/$fn');
      await ref.putFile(f);
      return ref.getDownloadURL();
    }

    Future<String> _uploadPdf(File f) async {
      final user = FirebaseAuth.instance.currentUser!;
      final fn = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final ref = FirebaseStorage.instance.ref().child('pets/reports/$fn');
      await ref.putFile(f);
      return ref.getDownloadURL();
    }

    Future<bool> _runRecaptcha() async {
      try {
        final token = await RecaptchaEnterprise.execute(
          RecaptchaAction.custom('CREATE_PET'),
          timeout: 10000,
        );
        debugPrint('🔐 reCAPTCHA token: $token');
        return token.isNotEmpty;
      } catch (e) {
        debugPrint('reCAPTCHA failed: $e');
        return false;
      }
    }

    Future<void> _onSubmit() async {
      if (!_formKey.currentState!.validate()) return;

      if (_reportType.isEmpty) {
        // 1. Set the default state (moved up for logic)
        setState(() => _reportType = 'never');

        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false, // User must make a choice
          builder: (BuildContext context) {
            // --- Cleaned up: no nested showDialog ---
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: 500), // Max width, good for tablets

                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  backgroundColor: Colors.white,
                  insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),

                  // --- Title Section ---
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: warningYellow, size: 28),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Missing Vaccination Data',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            color: neutralDark,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // --- Content Section ---
                  content: Container(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You have not provided any vaccination records for this pet.',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            color: neutralDark.withOpacity(0.8),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text.rich(
                          TextSpan(
                            text:
                            'By continuing, the pet will be officially marked as ',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              color: neutralDark.withOpacity(0.8),
                            ),
                            children: [
                              TextSpan(
                                text: '“Never Vaccinated” ',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade700,
                                ),
                              ),
                              const TextSpan(text: 'in the profile.'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- Action Buttons ---
                  actions: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(
                              'Cancel & Add Record',
                              style: GoogleFonts.poppins(
                                color: neutralDark.withOpacity(0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryTeal,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              elevation: 2,
                            ),
                            child: Text(
                              'Proceed Anyway',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  actionsPadding: EdgeInsets.zero,
                ),
              ),
            );
          },
        );
        if (proceed != true) return;
      }


      if (_petCount >= 2) {
        final success = await _runRecaptcha();
        if (!success) return;
      }

      // --- Add a try-catch block here ---
      try {
        await _addPet();
      } catch (e) {
        // Handle the error, for example, by showing a SnackBar or an AlertDialog
        print('Error saving pet: $e'); // Log the error for debugging
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save pet. Please try again. Error: $e'),
          ),
        );
        // You might also want to stop the loading state
        setState(() => _isSaving = false);
      }
    }

    Future<void> _addPet() async {
      setState(() => _isSaving = true);
      final user = FirebaseAuth.instance.currentUser!;
      final petRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('users-pets')
          .doc();
      final batch = FirebaseFirestore.instance.batch();

      // 1. Prepare all data for the document
      final Map<String, dynamic> petData = {
        'name': _nameCtl.text.trim(),
        'pet_type': _selectedType,
        'pet_breed': _selectedBreed,
        'size': _selectedSize,
        'pet_age': _ageCtl.text.trim(),
        'notes': _notesCtl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'gender': _gender,
        'report_type': _reportType,
        'weight_type': _weightType,
        'medical_history': _historyCtl.text.trim(),
        'likes': _likes,
        'dislikes': _dislikes,
        'is_neutered': _isNeutered,
        'allergies': _allergiesCtl.text.trim(),
        'medical_conditions': _conditionsCtl.text.trim(),
        'diet_notes': _dietNotesCtl.text.trim(),
        'activity_level': _activityLevel,
        'vet_name': _vetNameCtl.text.trim(),
        'vet_phone': _vetPhoneCtl.text.trim(),
        'emergency_contact': _emergencyContactCtl.text.trim(),
      };

      if (_weightType == 'exact') {
        petData['weight'] = double.tryParse(_exactWeightCtl.text);
      } else if (_weightType == 'range') {
        petData['weight_range'] = _selectedRange;
      }
      if (_reportType == 'manually_entered') {
        petData['vaccines'] = _vaccines;
      }

      // 2. Upload files in parallel
      final List<Future<String>> uploadFutures = [];
      final toUpload = _croppedFile ?? _originalFile;
      if (toUpload != null) {
        uploadFutures.add(_uploadImage(toUpload));
      } else {
        uploadFutures.add(Future.value(''));
      }

      if (_reportType == 'pdf' && _pdfReport != null) {
        uploadFutures.add(_uploadPdf(_pdfReport!));
      } else {
        uploadFutures.add(Future.value(''));
      }

      for (var f in _extraImages) {
        uploadFutures.add(_uploadImage(f));
      }

      final results = await Future.wait(uploadFutures);

      // 3. Add URLs to the data map and set the document in the batch
      final profileImageUrl = results[0];
      if (profileImageUrl.isNotEmpty) petData['pet_image'] = profileImageUrl;

      final pdfUrl = results[1];
      if (pdfUrl.isNotEmpty) petData['report_url'] = pdfUrl;

      _extraImageUrls = results.sublist(2).whereType<String>().toList();
      if (_extraImageUrls.isNotEmpty) petData['pet_images'] = _extraImageUrls;

      batch.set(petRef, petData);

      // 4. Commit the batch
      await batch.commit();

      await _updatePetCount();
      if (mounted) Navigator.pop(context, true);
      setState(() => _isSaving = false);
    }

    Future<String?> _showTypeDialog() {
      final ctrl = TextEditingController();
      var filtered = List<PetType>.from(_petTypes);
      return showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Select Type',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: teal)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search, color: accent),
                    ),
                    onChanged: (v) {
                      setSt(() {
                        filtered = _petTypes.where((t) => t.id.toLowerCase().contains(v.toLowerCase())).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final type = filtered[i];
                        final label = type.id[0].toUpperCase() + type.id.substring(1);
                        return ListTile(
                          title: Text(
                            type.display ? label : '$label (Coming Soon)',
                            style: GoogleFonts.poppins(color: type.display ? Colors.black : Colors.grey),
                          ),
                          enabled: type.display,
                          dense: true,
                          onTap: type.display ? () => Navigator.of(ctx).pop(type.id) : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget _buildHeader(String title) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: accent)),
      );
    }

    Widget _buildChipManager(String title, List<String> list, TextEditingController controller, VoidCallback onAdd) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(title),
          if (list.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: list.map((item) => Chip(
                label: Text(item),
                onDeleted: () => setState(() => list.remove(item)),
              )).toList(),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildTextFormField(controller, 'Add a ${title.toLowerCase().substring(0, title.length -1)}')),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle, color: teal),
                onPressed: onAdd,
              )
            ],
          )
        ],
      );
    }

    Widget _buildTextFormField(TextEditingController controller, String label, {TextInputType? keyboardType, int maxLines = 1, String? Function(String?)? validator}) {
      return TextFormField(
        controller: controller,
        enabled: true,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        validator: validator,
      );
    }

    Future<T?> _showSearchDialog<T>({required List<T> items, required String title, required String Function(T) label,}) {
      final ctrl = TextEditingController();
      var filtered = List<T>.from(items);
      return showDialog<T>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Select $title',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: teal,
                      )),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctrl,
                    style: GoogleFonts.poppins(),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search, color: accent),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: accent)),
                    ),
                    onChanged: (v) {
                      setSt(() {
                        filtered = items.where((i) => label(i).toLowerCase().contains(v.toLowerCase())).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(label(filtered[i]), style: GoogleFonts.poppins()),
                        onTap: () => Navigator.of(ctx).pop(filtered[i]),
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

    void _showVaccinationOptions() {
      showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (sheetCtx) {
            return Padding(
              padding: MediaQuery.of(sheetCtx).viewInsets,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Text('Vaccination Report',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: teal)),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.picture_as_pdf, color: teal),
                    title: Text('Upload PDF', style: GoogleFonts.poppins()),
                    onTap: () async {
                      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
                      if (res?.files.single.path != null) {
                        final file = File(res!.files.single.path!);
                        setState(() {
                          _reportType = 'pdf';
                          _pdfReport = file;
                          _vaccines = [];
                        });
                        if (mounted) Navigator.pop(sheetCtx);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit, color: teal),
                    title: Text('Enter Manually', style: GoogleFonts.poppins()),
                    onTap: () {
                      _showManualEntry(sheetCtx);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.not_interested, color: teal),
                    title: Text('Never Vaccinated', style: GoogleFonts.poppins()),
                    onTap: () {
                      setState(() {
                        _reportType = 'never';
                        _pdfReport = null;
                        _vaccines = [];
                      });
                      if (mounted) Navigator.pop(sheetCtx);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          });
    }

    Future<void> _pickPdf() async {
      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (res != null) {
        setState(() => _pdfReport = File(res.files.single.path!));
      }
    }

    void _showManualEntry(BuildContext sheetCtx) {
      showDialog<void>(
        context: sheetCtx,
        barrierDismissible: false,
        builder: (dialogCtx) {
          // make a local copy to work on
          final tempList = List<Map<String, dynamic>>.from(_vaccines);

          // A GlobalKey to manage the FormState for validation
          final _dialogFormKey = GlobalKey<FormState>();

          return StatefulBuilder(builder: (ctx, setSt) {
            // The validation logic now correctly checks for a non-empty name and a valid dateGiven.
            // The 'nextDue' date is intentionally not included in the validation, making it optional.
            bool allFilled() {
              if (tempList.isEmpty) return false;
              return tempList.every((v) =>
              (v['name'] as String).trim().isNotEmpty &&
                  v['dateGiven'] is DateTime);
            }

            return AlertDialog(
              insetPadding: EdgeInsets.zero,
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),

              // ── Title ─────────────────────────────────────────
              title: Text(
                'Enter Vaccines',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: teal,
                ),
              ),

              // ── Content ───────────────────────────────────────
              content: SizedBox(
                width: double.maxFinite,
                child: Form(
                  key: _dialogFormKey,
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
                            });
                          }),
                          icon: Icon(Icons.add, color: teal),
                          label: Text('Add Vaccine',
                              style: GoogleFonts.poppins(color: teal)),
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
                              // Vaccine Name
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
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Name is required';
                                  }
                                  return null;
                                },
                                onChanged: (v) => setSt(() => vac['name'] = v),
                              ),
                              const SizedBox(height: 12),

                              // Date Given
                              InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: vac['dateGiven'] ?? DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                    builder: (context, child) {
                                      return Theme(
                                        data: Theme.of(context).copyWith(
                                          colorScheme: ColorScheme.light(
                                            primary: teal,
                                            onPrimary: Colors.white,
                                            onSurface: accent,
                                          ),
                                          textButtonTheme: TextButtonThemeData(
                                            style: TextButton.styleFrom(
                                              foregroundColor: teal,
                                            ),
                                          ),
                                          dialogTheme: DialogTheme(
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16.0),
                                            ),
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
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
                              // Next Due Date (Optional)
                              InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: vac['nextDue'] ?? DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                    builder: (context, child) {
                                      return Theme(
                                        data: Theme.of(context).copyWith(
                                          colorScheme: ColorScheme.light(
                                            primary: teal,
                                            onPrimary: Colors.white,
                                            onSurface: accent,
                                          ),
                                          textButtonTheme: TextButtonThemeData(
                                            style: TextButton.styleFrom(
                                              foregroundColor: teal,
                                            ),
                                          ),
                                          dialogTheme: DialogTheme(
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16.0),
                                            ),
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
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
              ),

              // ── Actions ────────────────────────────────────────
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('Cancel', style: GoogleFonts.poppins(color: accent)),
                ),
                TextButton(
                  onPressed: allFilled()
                      ? () {
                    // Validate the form before processing
                    if (_dialogFormKey.currentState!.validate()) {
                      setState(() {
                        _reportType = 'manually_entered';
                        _pdfReport = null;
                        _vaccines = tempList;
                      });
                      if (mounted) Navigator.pop(dialogCtx);
                      if (mounted) Navigator.pop(sheetCtx);
                    }
                  }
                      : null, // Button is disabled if validation fails
                  child: Text(
                    'OK',
                    style: GoogleFonts.poppins(color: allFilled() ? teal : Colors.grey),
                  ),
                ),
              ],
            );
          });
        },
      );
    }

    InputDecoration _inDec(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: accent),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide(color: accent, width: 2.5),
      ),
      labelStyle: GoogleFonts.poppins(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );


    @override
    Widget build(BuildContext context) {
      Widget imgSection;
      if (_croppedFile != null || _originalFile != null) {
        final f = _croppedFile ?? _originalFile!;
        imgSection = GestureDetector(
          onTap: _pickImage,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.
            file(f, height: 220, width: double.infinity, fit: BoxFit.cover),
          ),
        );
      } else {
        imgSection = GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_a_photo, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    'Tap to upload the profile picture of your pet',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // We wrap the entire page in a Stack to show the loader on top
      return Stack( // <-- NEW: Start of the Stack
        children: [
          Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              centerTitle: true,
              title: Text('Add New Pet', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              backgroundColor: Colors.white,
              elevation: 1,
              iconTheme: const IconThemeData(color: Colors.black),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              // Your existing Column and Form go here without any changes
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // All your TextFormFields, Dropdowns, etc. remain here
                        // ... from "Basic Details" ...
                        Text('Basic Details', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: accent)),
                        const SizedBox(height: 5),
                        TextFormField(
                          controller: _nameCtl,
                          cursorColor: primaryColor,
                          style: GoogleFonts.poppins(),
                          decoration: InputDecoration(
                            labelText: 'Pet Name',
                            labelStyle: GoogleFonts.poppins(color: accent),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: accent),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: teal),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          validator: (v) => v!.isEmpty ? 'Fill out this field' : null,
                        ),
                        const SizedBox(height: 16),
                        Text('Gender', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: accent)),
                        Row(
                          children: ['Male', 'Female'].map((g) {
                            return Expanded(
                              child: RadioListTile<String>(
                                title: Text(g, style: GoogleFonts.poppins()),
                                value: g,
                                groupValue: _gender,
                                activeColor: teal,
                                onChanged: (v) => setState(() => _gender = v),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () async {
                            final sel = await _showTypeDialog();
                            if (sel != null) {
                              setState(() {
                                _selectedType = sel;
                                _breeds = [];
                                _loadBreeds(sel);
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Pet Type',
                              labelStyle: GoogleFonts.poppins(color: accent),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: accent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: teal),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              suffixIcon: Icon(Icons.arrow_drop_down, color: accent),
                            ),
                            child: Text(
                              _selectedType != null ? '${_selectedType![0].toUpperCase()}${_selectedType!.substring(1)}' : 'Select type',
                              style: GoogleFonts.poppins(color: _selectedType == null ? Colors.grey : Colors.black),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () async {
                            if (_selectedType == null) return;
                            final sel = await _showSearchDialog<String>(
                              items: _breeds,
                              title: 'Breed',
                              label: (i) => i,
                            );
                            if (sel != null) setState(() => _selectedBreed = sel);
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Breed',
                              labelStyle: GoogleFonts.poppins(color: accent),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: accent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: teal),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              suffixIcon: Icon(Icons.arrow_drop_down, color: accent),
                            ),
                            child: Text(
                              _selectedBreed ?? 'Select breed',
                              style: GoogleFonts.poppins(color: _selectedBreed == null ? Colors.grey : Colors.black),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _ageCtl,
                          cursorColor: primaryColor,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.poppins(),
                          decoration: InputDecoration(
                            labelText: 'Age (years)',
                            labelStyle: GoogleFonts.poppins(color: accent),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: accent),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: teal),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          validator: (v) => v!.isEmpty ? 'Fill out this field' : null,
                        ),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<String>(
                          value: _selectedSize,
                          items: _sizeRanges.map(
                                (r) => DropdownMenuItem(
                              value: r,
                              child: Text(r, style: GoogleFonts.poppins(color: Colors.black)),
                            ),
                          ).toList(),
                          decoration: InputDecoration(
                            labelText: 'Size Range',
                            labelStyle: GoogleFonts.poppins(color: accent),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: accent),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: teal),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          ),
                          style: GoogleFonts.poppins(color: Colors.black),
                          onChanged: (v) => setState(() => _selectedSize = v),
                          validator: (v) {
                            if (v == null) {
                              return 'Select a size';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        if (_weightType == 'exact')
                          TextFormField(
                            controller: _exactWeightCtl,
                            cursorColor: primaryColor,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Weight (kg)',
                              labelStyle: GoogleFonts.poppins(color: accent),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: accent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: teal),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            style: GoogleFonts.poppins(),
                            validator: (v) {
                              if (_weightType == 'exact' && (v == null || v.isEmpty)) {
                                return 'Enter weight';
                              }
                              return null;
                            },
                          ),
                        if (_weightType == 'range')
                          DropdownButtonFormField<String>(
                            value: _selectedRange,
                            items: _weightRanges.map(
                                  (r) => DropdownMenuItem(
                                value: r,
                                child: Text(r, style: GoogleFonts.poppins(color: Colors.black)),
                              ),
                            ).toList(),
                            decoration: InputDecoration(
                              labelText: 'Weight Range',
                              labelStyle: GoogleFonts.poppins(color: accent),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: accent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: teal),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            ),
                            style: GoogleFonts.poppins(color: Colors.black),
                            onChanged: (v) => setState(() => _selectedRange = v),
                            validator: (v) {
                              if (_weightType == 'range' && v == null) {
                                return 'Select a range';
                              }
                              return null;
                            },
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                title: Text('Exact', style: GoogleFonts.poppins()),
                                value: 'exact',
                                groupValue: _weightType,
                                activeColor: teal,
                                onChanged: (v) => setState(() => _weightType = v!),
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                title: Text('Range', style: GoogleFonts.poppins()),
                                value: 'range',
                                groupValue: _weightType,
                                activeColor: teal,
                                onChanged: (v) => setState(() {
                                  _weightType = v!;
                                  _exactWeightCtl.clear();
                                  _selectedRange = null;
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const SizedBox(height: 20),
                        TextFormField(
                          cursorColor: primaryColor,
                          controller: _historyCtl,
                          style: GoogleFonts.poppins(),
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'Previous Medical History (If any)',
                            labelStyle: GoogleFonts.poppins(color: accent),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: accent),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: teal),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const SizedBox(height: 20),
                        if (_selectedType != null)
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('company_documents')
                                .doc('pet_suggestions')
                                .collection('types')
                                .doc(_selectedType)
                                .snapshots(),
                            builder: (ctx, snap) {
                              if (!snap.hasData) return const SizedBox();
                              final data = snap.data!.data() as Map<String, dynamic>? ?? {};
                              final suggLikes = List<String>.from(data['likes'] ?? <String>[]);
                              final suggDislikes = List<String>.from(data['dislikes'] ?? <String>[]);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildChipManager('Likes', _likes, _customLikeCtl, () {
                                    final text = _customLikeCtl.text.trim();
                                    if (text.isNotEmpty && !_likes.contains(text)) setState(() => _likes.add(text));
                                    _customLikeCtl.clear();
                                  }),
                                  const SizedBox(height: 12),
                                  Text('Tap a suggestion:', style: GoogleFonts.poppins()),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    children: suggLikes.map((s) {
                                      final selected = _likes.contains(s);
                                      return ChoiceChip(
                                        label: Text(s, style: GoogleFonts.poppins(fontSize: 10, color: selected ? Colors.white : accent)),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        labelPadding: EdgeInsets.zero,
                                        selected: selected,
                                        selectedColor: teal,

                                        backgroundColor: Colors.white,
                                        onSelected: (_) {
                                          setState(() {
                                            if (selected) {
                                              _likes.remove(s);
                                            } else {
                                              _likes.add(s);
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 24),
                                  _buildChipManager('Dislikes', _dislikes, _customDislikeCtl, () {
                                    final text = _customDislikeCtl.text.trim();
                                    if (text.isNotEmpty && !_dislikes.contains(text)) setState(() => _dislikes.add(text));
                                    _customDislikeCtl.clear();
                                  }),
                                  const SizedBox(height: 12),
                                  Text('Tap a suggestion:', style: GoogleFonts.poppins()),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    children: suggDislikes.map((s) {
                                      final selected = _dislikes.contains(s);
                                      return ChoiceChip(
                                        label: Text(s, style: GoogleFonts.poppins(fontSize: 10, color: selected ? Colors.white : accent)),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        labelPadding: EdgeInsets.zero,
                                        selected: selected,
                                        selectedColor: Colors.redAccent,
                                        backgroundColor: Colors.white,
                                        onSelected: (_) {
                                          setState(() {
                                            if (selected) {
                                              _dislikes.remove(s);
                                            } else {
                                              _dislikes.add(s);
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              );
                            },
                          ),
                        const SizedBox(height: 20),
                        const SizedBox(height: 20),
                        Text('Health Info', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: accent)),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: ElevatedButton(
                            onPressed: _showVaccinationOptions,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: teal,
                              foregroundColor: Colors.white,
                              textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('Add Vaccination Report', style: GoogleFonts.poppins()),
                          ),
                        ),
                        if (_reportType == 'pdf' && _pdfReport != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(border: Border.all(color: teal), borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                Icon(Icons.picture_as_pdf, color: teal),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_pdfReport!.path.split('/').last, style: GoogleFonts.poppins())),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => setState(() {
                                    _reportType = '';
                                    _pdfReport = null;
                                  }),
                                ),
                              ],
                            ),
                          )
                        else if (_reportType == 'manually_entered' && _vaccines.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(border: Border.all(color: teal), borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Vaccines Entered:', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: teal)),
                                const SizedBox(height: 8),
                                for (var v in _vaccines)
                                  Text(
                                    '${v['name']} – ${DateFormat.yMMMd().format(v['dateGiven'])}',
                                    style: GoogleFonts.poppins(),
                                  ),
                              ],
                            ),
                          )
                        else if (_reportType == 'never')
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(border: Border.all(color: teal), borderRadius: BorderRadius.circular(12)),
                              child: Text('Never Vaccinated', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: teal)),
                            ),
                        const SizedBox(height: 12),
                        TextFormField(
                          cursorColor: primaryColor,
                          controller: _allergiesCtl,
                          style: GoogleFonts.poppins(),
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Allergies (if any)',
                            labelStyle: GoogleFonts.poppins(color: accent),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: accent)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: teal)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          cursorColor: primaryColor,
                          controller: _conditionsCtl,
                          style: GoogleFonts.poppins(),
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Medical Conditions',
                            labelStyle: GoogleFonts.poppins(color: accent),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: accent)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: teal)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          cursorColor: primaryColor,
                          controller: _dietNotesCtl,
                          style: GoogleFonts.poppins(),
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Dietary Notes / Favorites',
                            labelStyle: GoogleFonts.poppins(color: accent),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: accent)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: teal)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          value: _isNeutered,
                          activeColor: teal,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _gender == 'Female' ? 'Spayed?' : _gender == 'Male' ? 'Neutered?' : 'Spayed / Neutered?',
                              style: GoogleFonts.poppins(),
                            ),
                          ),
                          onChanged: (v) => setState(() => _isNeutered = v),
                        ),
                        const SizedBox(height: 20),
                        const SizedBox(height: 20),
                        Text('Activity Level', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: accent)),
                        Wrap(
                          spacing: 6,
                          children: ['Low', 'Moderate', 'High'].map((lvl) {
                            final sel = _activityLevel == lvl;
                            return ChoiceChip(
                              label: Text(lvl, style: GoogleFonts.poppins(color: sel ? Colors.white : accent)),
                              selected: sel,
                              selectedColor: teal,
                              backgroundColor: Colors.white,
                              onSelected: (_) => setState(() => _activityLevel = lvl),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        const SizedBox(height: 20),
                        Text('Veterinary Details', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: accent)),
                        const SizedBox(height: 8),
                        TextFormField(
                          cursorColor: primaryColor,
                          controller: _vetNameCtl,
                          style: GoogleFonts.poppins(),
                          decoration: InputDecoration(
                            labelText: 'Vet / Clinic Name',
                            labelStyle: GoogleFonts.poppins(color: accent),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: accent)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: teal)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          cursorColor: primaryColor,
                          controller: _vetPhoneCtl,
                          style: GoogleFonts.poppins(),
                          keyboardType: TextInputType.phone,
                          maxLength: 10, // <-- Add this line
                          decoration: InputDecoration(
                            labelText: 'Vet Phone',
                            labelStyle: GoogleFonts.poppins(color: accent),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: accent)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: teal)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            counterText: "", // <-- Add this line to hide the counter
                          ),
                        ),
                        const SizedBox(height: 20),
                        const SizedBox(height: 20),
                        Text('Emergency Contact', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: accent)),
                        const SizedBox(height: 8),
                        TextFormField(
                          cursorColor: primaryColor,
                          controller: _emergencyContactCtl,
                          style: GoogleFonts.poppins(),
                          keyboardType: TextInputType.phone, // <-- Add this line for numeric keyboard
                          maxLength: 10, // <-- Add this line
                          decoration: InputDecoration(
                            labelText: 'Emergency Contact',
                            labelStyle: GoogleFonts.poppins(color: accent),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: accent)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: teal)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            counterText: "", // <-- Add this line to hide the counter
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  imgSection,
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Additional Photos',
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: accent)),
                      const SizedBox(height: 8),
                      if (_extraImages.isEmpty)
                        GestureDetector(
                          onTap: _pickExtraImages,
                          child: Container(
                            height: 150,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.photo_library_outlined, size: 40, color: Colors.grey),
                                  const SizedBox(height: 8),
                                  Text('Tap to add up to 5 more pictures', style: GoogleFonts.poppins(color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                              child: Text('${_extraImages.length} / 5 photos added',
                                  style: GoogleFonts.poppins(color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                            ),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ..._extraImages.asMap().entries.map((entry) {
                                  final int index = entry.key;
                                  final File file = entry.value;
                                  return SizedBox(
                                    width: 72,
                                    height: 72,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.file(file, width: 72, height: 72, fit: BoxFit.cover),
                                        ),
                                        Positioned(
                                          top: -8,
                                          right: -8,
                                          child: InkWell(
                                            onTap: () => _removeExtraImage(index),
                                            child: const CircleAvatar(
                                              radius: 12,
                                              backgroundColor: Colors.black54,
                                              child: Icon(Icons.close, color: Colors.white, size: 14),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                if (_extraImages.length < 5)
                                  GestureDetector(
                                    onTap: _pickExtraImages,
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: const Icon(Icons.add_a_photo_outlined, color: Colors.grey),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      if (_loadingExtras)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      'Adding more photos is highly recommended as it builds trust with service providers.',
                      textAlign: TextAlign.left,
                      style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            // Your existing BottomNavigationBar already handles the button's loading state
            // ... inside the build method
            bottomNavigationBar: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.grey.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, -10))
                ],
              ),
              child: ElevatedButton(
                // MODIFIED: The button is now disabled when _isSaving is true
                onPressed: _isSaving ? null : _onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: const BorderSide(color: teal, width: 2),
                  ),
                  elevation: 0,
                  textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text("Submit"),
                  ],
                ),
              ),
            ),
          ),

          // -- NEW: This is the loading overlay --
          if (_isSaving)
            Container(
              // Use a semi-transparent black color for the background
              color: Colors.black.withOpacity(0.7),
              // Center the contents
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The circular progress indicator
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    const SizedBox(height: 20),
                    // A helpful text message
                    Text(
                      'Adding your pet...',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 18,
                        // Important: remove the default text decoration
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    void _removeExtraImage(int index) {
      setState(() {
        _extraImages.removeAt(index);
      });
    }

    Future<void> _pickExtraImages() async {
      final available = 5 - _extraImages.length;
      if (available == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You can only add up to 5 extra photos')),
        );
        return;
      }
      final picked = await _picker.pickMultiImage();
      if (picked == null || picked.isEmpty) return;
      final toProcess = picked.take(available);
      setState(() => _loadingExtras = true);
      final List<Future<File>> compressFutures = [];
      for (final XFile x in toProcess) {
        compressFutures.add(
          FlutterImageCompress.compressAndGetFile(
            x.path,
            '${x.path}_cmp.jpg',
            quality: 70,
            minWidth: 800,
            minHeight: 800,
          ).then((compressedResult) => File(compressedResult!.path)),
        );
      }
      final compressedFiles = await Future.wait(compressFutures);
      setState(() {
        _extraImages.addAll(compressedFiles);
        _loadingExtras = false;
      });
    }
  }

  class FreeFormCropSheet extends StatefulWidget {
    final File file;
    final void Function(File) onCropped;
    const FreeFormCropSheet({Key? key, required this.file, required this.onCropped}) : super(key: key);
    @override
    _FreeFormCropSheetState createState() => _FreeFormCropSheetState();
  }

  class _FreeFormCropSheetState extends State<FreeFormCropSheet> {
    final _controller = CropController();
    bool _loading = false;
    static const Color accent = Color(0xFF3D3D3D);

    Future<void> _doCrop(Uint8List data) async {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/pet_${DateTime.now().millisecondsSinceEpoch}.png';
      final outFile = await File(path).writeAsBytes(data);
      widget.onCropped(outFile);
      if (mounted) Navigator.pop(context);
    }

    void _onCropped(CropResult result) {
      if (result is CropSuccess) _doCrop(result.croppedImage);
    }

    @override
    Widget build(BuildContext context) {
      return SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * .75,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Text('Crop & Adjust', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Expanded(
                child: Crop(
                  controller: _controller,
                  image: widget.file.readAsBytesSync(),
                  onCropped: _onCropped,
                  aspectRatio: null,
                  initialRectBuilder: InitialRectBuilder.withSizeAndRatio(size: 1.0, aspectRatio: null),
                  withCircleUi: false,
                  interactive: true,
                  baseColor: Colors.white,
                  maskColor: Colors.black.withAlpha(100),
                  cornerDotBuilder: (size, alignment) => DotControl(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loading ? null : () {
                  setState(() => _loading = true);
                  _controller.crop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: accent, width: 3),
                  ),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text('Done Cropping'),
                    SizedBox(width: 10),
                    Icon(Icons.check, size: 20, color: Colors.black87,),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }