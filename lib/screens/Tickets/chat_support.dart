// lib/sp_main.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';


enum SearchMode { orderId, name, number }

// Add this state variable
SearchMode _currentSearchMode = SearchMode.orderId;


class UserOrderSupportPage extends StatefulWidget {
  final String? initialOrderId;
  final String serviceId;
  final String shop_name;
  final String? user_phone_number;
  final String? user_uid;
  final String? drawerType; // <-- ADDED: Parameter to track the last-opened drawer

  const UserOrderSupportPage({
    Key? key,
    required this.initialOrderId,
    required this.serviceId,
    required this.shop_name,
    required this.user_phone_number,
    required this.user_uid,
    this.drawerType, // <-- ADDED: Parameter to track the last-opened drawer
  }) : super(key: key);

  @override
  _UserOrderSupportPageState createState() => _UserOrderSupportPageState();
}

class _UserOrderSupportPageState extends State<UserOrderSupportPage> {


  String? _orderId;
  String? _sessionId;
  final String myCurrentServiceId = FirebaseAuth.instance.currentUser?.uid ?? '';

  Map<String, dynamic>? _menu;
  String _currentNode = 'start';
  bool _loading = true,
      _botTyping = false,
      _showEscalation = false,
      _historyMode = false;
  final _scrollCtrl = ScrollController();
  final _answered = <String>{};
  late final String _uid;

  // ADD THESE NEW VARIABLES to the _SPChatPageState class:
  final _searchQueryController = TextEditingController();
  List<DocumentSnapshot> _searchResults = [];
  bool _isSearching = false;
  String? _searchErrorText;

  Stream<QuerySnapshot>? _messagesStream;
  List<DocumentSnapshot> _cachedDocs = [];

  List<String>? _orderIds;
  bool _ordersLoading = false;

  bool _isManualEntryMode = false;
  final _manualOrderIdController = TextEditingController();
  String? _manualOrderErrorText;

  // ▼▼▼ ADD THESE NEW VARIABLES FOR RESPONSIVE UI ▼▼▼
  static const double _mobileBreakpoint = 800.0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Widget? _drawerContent;
  // ▲▲▲ END OF NEW VARIABLES ▲▲▲

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser!.uid;
    _loadCompletedOrders();

    if (widget.initialOrderId != null) {
      _loadAndDisplaySession(widget.initialOrderId!);
    }
  }

  @override
  void didUpdateWidget(covariant UserOrderSupportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialOrderId != oldWidget.initialOrderId) {
      if (widget.initialOrderId != null) {
        _loadAndDisplaySession(widget.initialOrderId!);
      } else {
        setState(() {
          _sessionId = null;
          _orderId = null;
          _messagesStream = null;
          _cachedDocs = [];
          _historyMode = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _manualOrderIdController.dispose();
    super.dispose();
  }

  Future<void> _loadAndDisplaySession(String ticketId) async {
    setState(() => _loading = true);
    _sessionId = ticketId;
    _currentNode = 'start';

    try {
      final sessionDoc = await FirebaseFirestore.instance
          .collection('UserChatSessions')
          .doc(ticketId)
          .get();
      if (sessionDoc.exists) {
        _orderId = sessionDoc.data()?['orderId'];
      }

      final cfg = await FirebaseFirestore.instance
          .collection('menuConfigs')
          .doc('support_user_v1')
          .get();
      _menu = cfg.data()!['nodes'] as Map<String, dynamic>;

      _messagesStream = FirebaseFirestore.instance
          .collection('UserChatSessions')
          .doc(ticketId)
          .collection('messages')
          .orderBy('ts')
          .snapshots();

      final messagesSnap = await FirebaseFirestore.instance
          .collection('UserChatSessions')
          .doc(ticketId)
          .collection('messages')
          .limit(1)
          .get();

      if (messagesSnap.docs.isEmpty) {
        final initialPrompt = (_orderId == null)
            ? 'What can we help you with?'
            : 'How can I help with Order $_orderId?';
        _sendBot(
          initialPrompt,
          _menu![_currentNode]['options'] as List<dynamic>,
        );
      }

      setState(() {
        _loading = false;
        _historyMode = true;
      });
    } catch (e) {
      print("Error loading session: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _loadCompletedOrders() async {
    setState(() => _ordersLoading = true);
    try {
      final completedSnap = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(widget.serviceId)
          .collection('completed_orders')
          .get();
      final completedIds = completedSnap.docs.map((d) => d.id).toList();

      final bookingSnap = await FirebaseFirestore.instance
          .collection('users-sp-boarding')
          .doc(widget.serviceId)
          .collection('service_request_boarding')
          .get();
      final bookingIds = bookingSnap.docs.map((d) => d.id).toList();

      setState(() {
        _orderIds = [...completedIds, ...bookingIds];
        _ordersLoading = false;
      });
    } catch (e) {
      print('❌ Error loading orders: $e');
      setState(() => _ordersLoading = false);
    }
  }

  Future<void> _sendBot(String text, List<dynamic> opts) async {
    if (_sessionId == null) return;
    setState(() => _botTyping = true);
    await Future.delayed(const Duration(milliseconds: 400));
    await FirebaseFirestore.instance
        .collection('UserChatSessions')
        .doc(_sessionId)
        .collection('messages')
        .add({
      'sender': 'bot',
      'type': 'text',
      'payload': text,
      'options': opts,
      'ts': Timestamp.now(),
    });
    setState(() {
      _botTyping = false;
      _scrollToBottom();
      if (opts.isEmpty) _showEscalation = true;
    });
  }

  void _onTap(Map<String, dynamic> opt, String msgId) {
    if (_sessionId == null || _answered.contains(msgId)) return;
    FirebaseFirestore.instance
        .collection('UserChatSessions')
        .doc(_sessionId)
        .collection('messages')
        .add({
      'sender': 'user',
      'type': 'option',
      'payload': opt['label'],
      'rawKey': opt['key'],
      'ts': Timestamp.now(),
    });
    setState(() => _answered.add(msgId));

    _currentNode = opt['key'];
    final next = _menu![_currentNode] as Map<String, dynamic>?;
    if (next != null) {
      _sendBot(next['text'], next['options'] as List<dynamic>);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _bubble(Map<String, dynamic> d, String id) {
    final isBot = d['sender'] == 'bot';
    final txt = d['payload'] as String;
    final ts = (d['ts'] as Timestamp).toDate();
    final opts = isBot
        ? (d['options'] as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    final align = isBot ? Alignment.centerLeft : Alignment.centerRight;
    final bg = isBot ? Colors.white : const Color(0xFF2CB4B6).withOpacity(0.5);
    final radius = isBot
        ? const BorderRadius.only(
      topRight: Radius.circular(16),
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(16),
    )
        : const BorderRadius.only(
      topLeft: Radius.circular(16),
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(16),
    );

    return Align(
      alignment: align,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
        ),
        child: Column(
          crossAxisAlignment:
          isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(
              txt,
              style: GoogleFonts.poppins(fontSize: 16, height: 1.3),
            ),
            const SizedBox(height: 6),
            Text(
              '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
              style: GoogleFonts.poppins(fontSize: 10, color: Colors.black87),
            ),
            if (isBot && !_answered.contains(id) && opts.isNotEmpty) ...[
              const Divider(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: opts.map((o) {
                  return GestureDetector(
                    onTap: () => _onTap(o, id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF2CB4B6)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Tooltip(
                        message: o['key'] as String,
                        child: Text(
                          o['label'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ▼▼▼ THIS IS THE NEW MAIN BUILD METHOD ▼▼▼
  // It checks the screen width and calls the appropriate layout builder.
  @override
  Widget build(BuildContext context) {
      return _buildMobileLayout();
  }

  Widget _buildMobileLayout() {

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 1,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          _historyMode ? 'Chat History' : 'Live Chat',
          style: GoogleFonts.poppins(color: Colors.black87),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context, rootNavigator: true).pop();
            }
          },
        ),

      ),
      body: _buildChatStreamUI(),
    );
  }




  Future<void> _searchOrders() async {
    final rawQuery = _searchQueryController.text.trim();
    final serviceId = widget.serviceId;

    // --- 1. Initial Validation & Cleanup ---
    if (rawQuery.isEmpty) {
      setState(() => _searchErrorText = 'Please enter a value to search.');
      return;
    }

    if (_currentSearchMode == SearchMode.number) {
      if (!RegExp(r'^\d{10}$').hasMatch(rawQuery)) {
        setState(() => _searchErrorText = 'Phone number must be exactly 10 digits.');
        return;
      }
    }

    setState(() {
      _isSearching = true;
      _searchResults = [];
      _searchErrorText = null;
    });

    try {
      final collectionRef = FirebaseFirestore.instance.collection('users-sp-boarding').doc(serviceId);
      final foundDocs = <DocumentSnapshot>[];
      final searchCollections = ['service_request_boarding', 'completed_orders'];

      // --- 2. Normalized Query Values ---
      final lowerCaseQuery = rawQuery.toLowerCase();
      final prefixEnd = '\u{f8ff}';

      // Final, standardized query value for phone search
      String phoneQueryValue = (_currentSearchMode == SearchMode.number) ? ('+91' + rawQuery) : '';

      print('-------------------------------------------');
      print('🔍 STARTING SEARCH for Service ID: $serviceId');
      print('   > Mode: ${_currentSearchMode.toString().split('.').last}');
      print('   > Raw Input: "$rawQuery"');

      // --- 3. Execute Search ---
      for (final collectionName in searchCollections) {
        final col = collectionRef.collection(collectionName);
        print('   -> Searching collection: $collectionName');

        if (_currentSearchMode == SearchMode.orderId) {
          // ORDER ID SEARCH: Uses the dedicated lowercase field
          final fieldName = 'order_id_lowercase';
          print('      Running Order ID Query (Field: $fieldName): $lowerCaseQuery to ${lowerCaseQuery + prefixEnd}');

          final idSnap = await col
              .where(fieldName, isGreaterThanOrEqualTo: lowerCaseQuery)
              .where(fieldName, isLessThanOrEqualTo: lowerCaseQuery + prefixEnd)
              .limit(10)
              .get();
          foundDocs.addAll(idSnap.docs);
          print('         Found ${idSnap.docs.length} docs via $fieldName.');


        } else if (_currentSearchMode == SearchMode.name) {
          // NAME SEARCH: Uses the dedicated lowercase field
          final fieldName = 'user_name_lowercase';
          print('      Running Name Query (Field: $fieldName): $lowerCaseQuery to ${lowerCaseQuery + prefixEnd}');

          final nameSnap = await col
              .where(fieldName, isGreaterThanOrEqualTo: lowerCaseQuery)
              .where(fieldName, isLessThanOrEqualTo: lowerCaseQuery + prefixEnd)
              .limit(10)
              .get();
          foundDocs.addAll(nameSnap.docs);
          print('         Found ${nameSnap.docs.length} docs via $fieldName.');


        } else if (_currentSearchMode == SearchMode.number) {
          // Phone Search (Exact Prefix Match)
          final fieldName = 'phone_number';
          print('      Running Phone Query (Field: $fieldName): $phoneQueryValue to ${phoneQueryValue + prefixEnd}');

          final phoneSnap = await col
              .where(fieldName, isGreaterThanOrEqualTo: phoneQueryValue)
              .where(fieldName, isLessThanOrEqualTo: phoneQueryValue + prefixEnd)
              .limit(10)
              .get();
          foundDocs.addAll(phoneSnap.docs);
          print('         Found ${phoneSnap.docs.length} docs via $fieldName.');
        }
      }

      // --- 4. Remove Duplicates and Finalize ---
      // Uses document ID as the key to ensure uniqueness
      final uniqueDocsMap = Map<String, DocumentSnapshot>.fromIterable(
          foundDocs.where((doc) => doc.exists),
          key: (doc) => (doc as DocumentSnapshot).id
      );

      final uniqueDocs = uniqueDocsMap.values.toList().cast<DocumentSnapshot>();

      setState(() {
        _searchResults = uniqueDocs;
        _searchErrorText = uniqueDocs.isEmpty ? 'No matching orders found.' : null;
        _isSearching = false;
      });

      print('-------------------------------------------');
      print('✅ SEARCH COMPLETE. Total unique documents found: ${uniqueDocs.length}');
      print('-------------------------------------------');

    } catch (e) {
      print('🚨 CRITICAL FIREBASE ERROR: $e');
      setState(() {
        _searchErrorText = 'A critical error occurred. Please check console for required index links.';
        _isSearching = false;
      });
    }
  }

  // ▼▼▼ NEW WIDGET FOR THE CHAT MESSAGE STREAM (FOR MOBILE) ▼▼▼
  Widget _buildChatStreamUI() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey(_sessionId),
      stream: _messagesStream,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('Error: ${snap.error}',
                style: GoogleFonts.poppins(color: Colors.red)),
          );
        }
        final docs = snap.data?.docs ?? _cachedDocs;
        if (snap.hasData) _cachedDocs = docs;
        return ListView.builder(
          controller: _scrollCtrl,
          padding: EdgeInsets.only(top: 12, bottom: _showEscalation ? 60 : 12),
          itemCount: docs.length + (_botTyping ? 1 : 0),
          itemBuilder: (c, i) {
            if (i < docs.length) {
              return _bubble(
                  docs[i].data()! as Map<String, dynamic>, docs[i].id);
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                children: [
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('Bot is typing…',
                      style: GoogleFonts.poppins(color: Colors.grey)),
                ],
              ),
            );
          },
        );
      },
    );
  }

}