import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../preloaders/hidden_services_provider.dart';
import '../Boarding/boarding_servicedetailspage.dart';

class HiddenServicesPage extends StatefulWidget {
  const HiddenServicesPage({Key? key}) : super(key: key);

  @override
  State<HiddenServicesPage> createState() => _HiddenServicesPageState();
}

class _HiddenServicesPageState extends State<HiddenServicesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _confirmRestoreAll(BuildContext context, HiddenServicesProvider hideProv) async {
    final design = DesignConstants();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Restore',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: design.textDark,
          ),
        ),
        content: Text(
          'Are you sure you want to restore all hidden services?',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: design.textLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: design.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Restore All',
              style: GoogleFonts.poppins(
                color: design.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (var id in List<String>.from(hideProv.hidden)) {
        hideProv.toggle(id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hideProv = context.watch<HiddenServicesProvider>();
    final design = DesignConstants();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        title: Text(
          'Hidden Services',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: design.textDark,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Restore All',
            icon: Icon(Icons.restore, color: design.primaryColor),
            onPressed: () => _confirmRestoreAll(context, hideProv),
          ),
        ],
      ),
      backgroundColor: design.backgroundColor,
      body: Padding(
        padding: design.contentPadding,
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Search bar
            TextField(
              controller: _searchController,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'Search hidden centers...',
                hintStyle: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                prefixIcon: Icon(Icons.search, color: design.textLight),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: design.primaryColor,
                    width: 2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Colors.redAccent,
                    width: 1.5,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Colors.redAccent,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users-sp-boarding')
                    .snapshots(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snap.hasData) {
                    return Center(
                      child: Text(
                        'No hidden services found.',
                        style: GoogleFonts.poppins(color: Colors.grey[600]),
                      ),
                    );
                  }

                  final docs = snap.data!.docs;

                  // Filter hidden & search
                  final hiddenDocs = docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final id = data['service_id'] as String? ?? '';
                    final name = (data['shop_name'] as String? ?? '').toLowerCase();
                    return hideProv.hidden.contains(id) &&
                        name.contains(_query);
                  }).toList();

                  if (hiddenDocs.isEmpty) {
                    return Center(
                      child: Text(
                        'Nothing to restore.',
                        style: GoogleFonts.poppins(color: Colors.grey[600]),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: hiddenDocs.length,
                    itemBuilder: (ctx, i) {
                      final doc = hiddenDocs[i];
                      final serviceData = doc.data() as Map<String, dynamic>;
                      final serviceId = serviceData['service_id'] as String;

                      // Handle rates with offer logic
                      final isOfferActive =
                          serviceData['isOfferActive'] as bool? ?? false;
                      final String ratesKey =
                      isOfferActive ? 'offer_daily_rates' : 'rates_daily';
                      final rawRatesMap =
                          (serviceData[ratesKey] as Map?)?.cast<String, dynamic>() ??
                              {};
                      final rates = rawRatesMap.map((size, val) =>
                          MapEntry(size, int.tryParse(val.toString()) ?? 0));

                      final prices = rates.values.where((p) => p > 0).toList();
                      final minPrice =
                      prices.isEmpty ? 0 : prices.reduce((a, b) => a < b ? a : b);

                      return Card(
                        color: Colors.white,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(1)),
                        elevation: 2,
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              serviceData['shop_logo'] ?? '',
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                          title: Text(
                            serviceData['shop_name'] ?? '',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${serviceData['area_name'] ?? 'N/A'} • Starts from ₹$minPrice / day',
                            style: GoogleFonts.poppins(
                                fontSize: 14, color: design.textLight),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, color: design.textDark),
                            onSelected: (_) => hideProv.toggle(serviceId),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'restore',
                                child: Text('Un-hide Service',
                                    style: GoogleFonts.poppins()),
                              ),
                            ],
                          ),
                          onTap: () async {


                            final pets =
                            List<String>.from(serviceData['pets'] ?? []);

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BoardingServiceDetailPage(
                                  documentId: doc.id,
                                  shopName: serviceData['shop_name'],
                                  shopImage: serviceData['shop_logo'],
                                  areaName: serviceData['area_name'],
                                  distanceKm: 0.0,
                                  pets: pets,
                                  mode: "1",
                                  rates: rates,
                                  isOfferActive: isOfferActive, preCalculatedStandardPrices: {}, preCalculatedOfferPrices: {}, otherBranches: [], isCertified: true, // ADD THIS LINE
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
