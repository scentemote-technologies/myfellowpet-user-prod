import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/boarding_shop_details.dart';
import '../../preloaders/BoardingCardsProvider.dart';
import '../../preloaders/distance_provider.dart';
import '../../preloaders/favorites_provider.dart';
import 'boarding_homepage.dart';
import 'boarding_servicedetailspage.dart';

class SearchResultsPage extends StatefulWidget {
  const SearchResultsPage({Key? key}) : super(key: key);

  @override
  _SearchResultsPageState createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  final TextEditingController _searchController = TextEditingController();
  String query = '';
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _searchController.addListener(() {
      final v = _searchController.text.trim();
      setState(() => query = v.toLowerCase());
      if (v.isNotEmpty) _saveToHistory(v);
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _history = prefs.getStringList('search_history') ?? []);
  }

  Future<void> _saveToHistory(String term) async {
    final prefs = await SharedPreferences.getInstance();
    _history.remove(term);
    _history.insert(0, term);
    if (_history.length > 10) _history = _history.sublist(0, 10);
    await prefs.setStringList('search_history', _history);
  }

  Future<void> _removeFromHistory(String term) async {
    final prefs = await SharedPreferences.getInstance();
    _history.remove(term);
    await prefs.setStringList('search_history', _history);
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distances = context.watch<DistanceProvider>().distances;
    final shopProv = context.watch<ShopDetailsProvider>();
    final allShops = shopProv.shops;

    // filter and sort
    final filtered = (query.isEmpty
        ? List.of(allShops)
        : allShops.where((s) => s.name.toLowerCase().contains(query)).toList())
      ..sort((a, b) {
        final da = distances[a.id] ?? double.infinity;
        final db = distances[b.id] ?? double.infinity;
        return da.compareTo(db);
      });

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFFF6F6F6),
          elevation: 0,
          leading: const BackButton(color: Colors.black87),
          title: Text(
            'Search Results',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          bottom: const TabBar(
            indicatorColor: Color(0xFF25ADAD),
            labelColor: Colors.black87,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Overnight Requests'),
              Tab(text: 'Daycare'),
            ],
          ),
        ),
        backgroundColor: Colors.white,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.1), blurRadius: 12, spreadRadius: 2)],
                ),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        final term = _searchController.text.trim();
                        if (term.isNotEmpty) _saveToHistory(term);
                        setState(() => query = term.toLowerCase());
                      },
                      child: const Icon(Icons.search, color: Color(0xFF7C3AED)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search services...',
                          hintStyle: GoogleFonts.poppins(fontSize: 14),
                          border: InputBorder.none,
                          suffixIcon: query.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () {
                            _searchController.clear(); setState(() => query = '');
                          }),
                        ),
                        style: GoogleFonts.poppins(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // History chips
            if (query.isEmpty && _history.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _history.map((term) {
                    return InputChip(
                      label: Text(term, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF2CB4B6))),
                      backgroundColor: const Color(0xFF7DFDFF).withOpacity(0.1),
                      side: const BorderSide(color: Color(0xFF2CB4B6)),
                      onPressed: () {
                        _searchController.text = term;
                        setState(() => query = term.toLowerCase());
                      },
                      onDeleted: () => _removeFromHistory(term),
                    );
                  }).toList(),
                ),
              ),

            // Tab views
            Expanded(
              child: TabBarView(
                children: [
                  // Boarding tab
                  ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _buildServiceCardFromShop(filtered[i], distances, mode: 1),
                  ),

                  // Grooming tab
                  ComingSoonPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceCardFromShop(
      Shop shop,
      Map<String, double> distances, {
        int mode = 1,
      }) {
    final dKm = distances[shop.id] ?? 0.0;

    // Build a single-entry rates map from your shop.price
    final rawPrice = int.tryParse(shop.price.toString()) ?? 0;
    final ratesMap = {'Standard': rawPrice};

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.0),
        duration: const Duration(milliseconds: 200),
        builder: (context, scale, __) => Transform.scale(
          scale: scale,
          child: Card(
            elevation: 0,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                final term = query.trim();
                if (term.isNotEmpty) _saveToHistory(term);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BoardingServiceDetailPage(
                      mode: mode.toString(),
                      pets: shop.pets,
                      documentId: shop.id,
                      shopName: shop.name,
                      shopImage: shop.imageUrl,
                      areaName: shop.areaName,
                      distanceKm: dKm,
                      rates: ratesMap, // ← now required
                      isOfferActive: shop.isOfferActive, preCalculatedStandardPrices: {}, preCalculatedOfferPrices: {}, otherBranches: [], isCertified: true,                    ),
                  ),
                );
              },
              child: Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image + like
                      Stack(
                        children: [
                          Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 135,
                                height: 155,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border:
                                  Border.all(color: Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Image.network(
                                  shop.imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Icon(
                                      Icons.image_not_supported,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Consumer<FavoritesProvider>(
                              builder: (ctx, favProv, _) {
                                final isLiked = favProv.liked.contains(shop.id);
                                return Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: const Color(0xFFFF5B20)),
                                    color: Colors.white,
                                  ),
                                  height: 45,
                                  width: 45,
                                  child: IconButton(
                                    onPressed: () => favProv.toggle(shop.id),
                                    icon: AnimatedSwitcher(
                                      duration:
                                      const Duration(milliseconds: 300),
                                      transitionBuilder:
                                          (child, animation) =>
                                          ScaleTransition(
                                              scale: animation,
                                              child: child),
                                      child: Icon(
                                        isLiked
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        key: ValueKey(isLiked),
                                        color: isLiked
                                            ? const Color(0xFFFF5B20)
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),

                      // Details
                      Expanded(
                        child: Padding(
                          padding:
                          const EdgeInsets.fromLTRB(16, 20, 12, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shop.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(Icons.currency_rupee,
                                      size: 16, color: Colors.grey),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${shop.price} / day',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      size: 16, color: Colors.grey),
                                  const SizedBox(width: 6),
                                  Text(
                                    shop.areaName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 32,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: shop.pets
                                      .map((pet) => Padding(
                                    padding: const EdgeInsets.only(
                                        right: 8.0),
                                    child: Container(
                                      padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border:
                                        Border.all(color: Colors.grey),
                                        borderRadius:
                                        BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        pet,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ))
                                      .toList(),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${dKm.toStringAsFixed(1)} km away',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF4F4F4F)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
