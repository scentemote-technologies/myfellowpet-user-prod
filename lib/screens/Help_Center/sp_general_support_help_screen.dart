import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// --- PROFESSIONAL DESIGN SYSTEM & CONSTANTS ---
const Color kPrimaryColor = Color(0xFF2CB4B6);
const Color kSecondaryColor = Color(0xFF0F8889);
const Color kNeutralDark = Color(0xFF37474F);
const Color kBackgroundLight = Color(0xFFF0F4F8);

// Default Status Colors
const Color kStatusOpen = kPrimaryColor;
const Color kStatusAwaiting = Color(0xFFFF9800);
const Color kStatusOffline = Color(0xFFE57373);

// WhatsApp-style colors adapted to your scheme
// Primary Teal for User Bubble, Light Blue/White for Bot Bubble
const Color kBubbleUser = Color(0xFFDCF8C6); // Light WhatsApp-like green adapted to blue scheme
const Color kBubbleBot = Colors.white;
const Color kChatBackground = Color(0xFFE5DDD5); // Light background for the chat area

class SupportHelpController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final RxBool helpMenuOpen = false.obs;
  final RxBool isLoading = true.obs;
  final RxList<SupportMessage> conversation = <SupportMessage>[].obs;
  final RxList<SupportOption> options = <SupportOption>[].obs;
  final Rx<Color> secondaryColor = kSecondaryColor.obs;
  final RxnString sessionId = RxnString();
  final RxnString ticketId = RxnString();
  final RxString ticketStatus = 'open'.obs;
  final RxString ticketProgress = 'Collecting details'.obs;
  final Rxn<DateTime> sessionCreatedAt = Rxn<DateTime>();
  final Rxn<DateTime> lastUpdated = Rxn<DateTime>();

  final _scrollController = ScrollController();


  late Map<String, Map<String, dynamic>> _nodes;
  String _currentNodeKey = 'start';
  String? _activeBotMessageId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _ticketSub;
  final String _guestUid =
      'sp_guest_${DateTime.now().millisecondsSinceEpoch}';

  bool get isAtRoot => _currentNodeKey == 'start';
  CollectionReference<Map<String, dynamic>>? get _messageCollection {
    final sid = sessionId.value;
    if (sid == null) return null;
    return _firestore
        .collection('UserGeneralQueries')
        .doc(sid)
        .collection('messages');
  }

  @override
  void onInit() {
    super.onInit();
    _loadNodes();
    // Auto-scroll function
    ever(conversation, (_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void onClose() {
    _messagesSub?.cancel();
    _ticketSub?.cancel();
    _scrollController.dispose();
    super.onClose();
  }

  // --- CONTROLLER LOGIC (Performance Optimized) ---

  Future<void> _loadNodes() async {
    final defaultNodes = _temporaryNodes();
    Map<String, Map<String, dynamic>> fetchedNodes = {};
    Map<String, dynamic>? fetchedData;
    try {
      final docRef =
      _firestore.collection('menuConfigs').doc('general_support_sp_v1');
      final snapshot = await docRef.get();
      fetchedData = snapshot.data();
      if (fetchedData == null || fetchedData['nodes'] is! Map) {
        await docRef.set(
          {'nodes': Map<String, dynamic>.from(defaultNodes)},
          SetOptions(merge: true),
        );
        fetchedNodes = defaultNodes;
      } else {
        fetchedNodes = (fetchedData['nodes'] as Map<String, dynamic>).map(
              (key, value) => MapEntry(
            key,
            Map<String, dynamic>.from(value as Map),
          ),
        );
      }
      final extractedColor = _extractSecondaryColor(fetchedData);
      if (extractedColor != null) {
        secondaryColor.value = extractedColor;
      }
    } catch (_) {
      // ignore errors and fall back to temporary nodes
    }
    _nodes = fetchedNodes.isNotEmpty ? fetchedNodes : defaultNodes;
    _bootstrapConversation();
    isLoading.value = false;
  }

  Future<bool> _ensureSession() async {
    final user = _auth.currentUser;
    if (sessionId.value != null) {
      return true;
    }
    try {
      final now = Timestamp.now();
      final String userId = user?.uid ?? _guestUid;
      final Map<String, dynamic> startedBy =
      _buildStartedBy(userId: userId, user: user);

      final sessionPayload = {
        'participants': [userId],
        'flowId': 'general_support_sp_v1',
        'createdAt': now,
        'role': 'app_user',
        'startedBy': startedBy,
      };
      final sessionDoc =
      await _firestore.collection('UserGeneralQueries').add(sessionPayload);
      sessionId.value = sessionDoc.id;
      sessionCreatedAt.value = DateTime.now();

      final ticketPayload = {
        'sessionId': sessionDoc.id,
        'userId': userId,
        'status': 'open',
        'progress': 'Collecting initial details',
        'createdAt': now,
        'updatedAt': now,
      };
      final ticketDoc =
      await _firestore.collection('SupportTickets').add(ticketPayload);
      ticketId.value = ticketDoc.id;
      ticketStatus.value = ticketPayload['status']!.toString();
      ticketProgress.value = ticketPayload['progress']!.toString();
      lastUpdated.value = DateTime.now();

      _listenToTicket(ticketDoc.id);
      _listenToMessages(sessionDoc.id);

      final messageCollection = sessionDoc.collection('messages');
      final existingMessages = await messageCollection.limit(1).get();
      if (existingMessages.docs.isEmpty) {
        await _sendBotNode('start');
      }
      return true;
    } catch (_) {
      ticketStatus.value = 'offline';
      ticketProgress.value =
      'Unable to reach support right now. Please try again shortly.';
      return false;
    }
  }

  void _listenToMessages(String sessionDocId) {
    _messagesSub?.cancel();
    _messagesSub = _firestore
        .collection('UserGeneralQueries')
        .doc(sessionDocId)
        .collection('messages')
        .orderBy('ts')
        .snapshots()
        .listen((snapshot) {
      _rehydrateConversation(snapshot);
      if (isLoading.value) {
        isLoading.value = false;
      }
    });
  }

  void _listenToTicket(String ticketDocId) {
    _ticketSub?.cancel();
    _ticketSub = _firestore
        .collection('SupportTickets')
        .doc(ticketDocId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;
      final String? status = data['status']?.toString();
      if (status != null && status.isNotEmpty) {
        ticketStatus.value = status;
      }
      final String? progress = data['progress']?.toString();
      if (progress != null && progress.isNotEmpty) {
        ticketProgress.value = progress;
      }
      final dynamic updatedAt = data['updatedAt'];
      if (updatedAt is Timestamp) {
        lastUpdated.value = updatedAt.toDate();
      }
    });
  }

  void _rehydrateConversation(
      QuerySnapshot<Map<String, dynamic>> snapshot,
      ) {
    final docs = snapshot.docs;
    final Set<String> answeredMessageIds = <String>{};
    for (final doc in docs) {
      final data = doc.data();
      final String? replyTo = data['replyTo']?.toString();
      if (replyTo != null && replyTo.isNotEmpty) {
        answeredMessageIds.add(replyTo);
      }
    }
    final messages = docs.map((doc) {
      final data = doc.data();
      final String sender = (data['sender'] ?? 'bot').toString();
      final Timestamp? rawTs = data['ts'] as Timestamp?;
      final DateTime timestamp =
      rawTs != null ? rawTs.toDate() : DateTime.now();
      final String payload = (data['payload'] ?? '').toString();
      final List<SupportOption> optionsForMessage = <SupportOption>[];
      final dynamic rawOptions = data['options'];
      if (rawOptions is List) {
        for (final dynamic item in rawOptions) {
          if (item is Map) {
            optionsForMessage.add(
              SupportOption.fromMap(Map<String, dynamic>.from(item)),
            );
          }
        }
      }
      final String? rawKey = data['rawKey']?.toString();
      if (rawKey != null && rawKey.isNotEmpty) {
        _currentNodeKey = rawKey;
      }
      return SupportMessage(
        id: doc.id,
        fromBot: sender == 'bot',
        text: payload,
        timestamp: timestamp,
        options: optionsForMessage,
        rawKey: rawKey,
        isAnswered: answeredMessageIds.contains(doc.id),
      );
    }).toList();

    if (messages.length != conversation.length || (messages.isNotEmpty && messages.last.id != conversation.last.id)) {
      conversation.assignAll(messages);
    }

    if (messages.isNotEmpty) {
      lastUpdated.value = messages.last.timestamp;
    }
    _deriveLatestOptions(docs, answeredMessageIds);
  }

  void _deriveLatestOptions(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      Set<String> answered,
      ) {
    bool foundActive = false;
    for (final doc in docs.reversed) {
      final data = doc.data();
      final String sender = (data['sender'] ?? '').toString();
      if (sender != 'bot') continue;
      final String messageId = doc.id;
      final List<SupportOption> opts = <SupportOption>[];
      final dynamic raw = data['options'];
      if (raw is List) {
        for (final dynamic item in raw) {
          if (item is Map) {
            opts.add(
              SupportOption.fromMap(Map<String, dynamic>.from(item)),
            );
          }
        }
      }
      final bool isAnswered = answered.contains(messageId);
      if (!isAnswered && opts.isNotEmpty) {
        options.assignAll(opts);
        _activeBotMessageId = messageId;
        _currentNodeKey = data['nodeKey']?.toString() ?? _currentNodeKey;
        foundActive = true;
        break;
      }
    }
    if (!foundActive) {
      options.clear();
      _activeBotMessageId = null;
    }
  }

  void _markActiveBotMessageAsAnswered() {
    if (conversation.isEmpty) return;
    int? targetIndex;
    if (_activeBotMessageId != null) {
      final int idx =
      conversation.indexWhere((msg) => msg.id == _activeBotMessageId);
      if (idx != -1) {
        targetIndex = idx;
      }
    }
    targetIndex ??= _latestBotOptionsIndex();
    if (targetIndex != null) {
      // rely on firestore listener
    }
  }

  int? _latestBotOptionsIndex() {
    for (int i = conversation.length - 1; i >= 0; i--) {
      final SupportMessage msg = conversation[i];
      if (msg.fromBot && msg.options.isNotEmpty && !msg.isAnswered) {
        return i;
      }
    }
    return null;
  }

  Future<void> _touchTicket({
    required String status,
    required String progress,
    Map<String, dynamic>? extra,
  }) async {
    final String? tid = ticketId.value;
    if (tid == null) return;
    final payload = <String, dynamic>{
      'status': status,
      'progress': progress,
      'updatedAt': Timestamp.now(),
      if (extra != null) ...extra,
    };
    await _firestore
        .collection('SupportTickets')
        .doc(tid)
        .set(payload, SetOptions(merge: true));
    ticketStatus.value = status;
    ticketProgress.value = progress;
    lastUpdated.value = DateTime.now();
  }

  Color? _extractSecondaryColor(Map<String, dynamic>? data) {
    if (data == null) return null;
    final dynamic rawDirect = data['secondaryColor'];
    final dynamic rawTheme =
    data['theme'] is Map ? (data['theme'] as Map)['secondaryColor'] : null;
    return _parseColor(rawDirect) ?? _parseColor(rawTheme);
  }

  Color? _parseColor(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return Color(raw);
    if (raw is String) {
      final cleaned = raw.trim().replaceAll('#', '').toUpperCase();
      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }
      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    }
    return null;
  }

  Map<String, dynamic> _buildStartedBy({
    required String userId,
    User? user,
  }) {
    if (user != null) {
      final provider = user.providerData.isNotEmpty
          ? user.providerData.first
          : null;
      final String name = user.displayName ??
          provider?.displayName ??
          _deriveNameFromEmail(user.email ?? provider?.email);
      final String email =
          user.email ?? provider?.email ?? 'not_provided';
      final String phone =
          user.phoneNumber ?? provider?.phoneNumber ?? 'not_provided';
      return {
        'uid': userId,
        'source': 'firebase_auth',
        if (provider?.providerId != null)
          'authProvider': provider!.providerId,
        'name': name,
        'email': email,
        'phone': phone,
      };
    }

    return {
      'uid': userId,
      'source': 'guest_placeholder',
      'name': 'Guest User',
      'email': 'guest@mfp.app',
      'phone': '+910000000000',
    };
  }

  String _deriveNameFromEmail(String? email) {
    if (email == null || email.isEmpty) return 'App User';
    final int atIndex = email.indexOf('@');
    if (atIndex <= 0) return email;
    return email.substring(0, atIndex);
  }

  void _bootstrapConversation() {
    final startNode = _nodes[_currentNodeKey] ?? _nodes.values.first;
    final text = (startNode['text'] ?? 'Hey there!').toString();
    final initialOptions = _extractOptions(startNode);
    conversation.assignAll([
      SupportMessage(
        fromBot: true,
        text: text,
        timestamp: DateTime.now(),
        options: initialOptions,
      )
    ]);
    options.assignAll(initialOptions);
  }

  void toggleHelpMenu() => helpMenuOpen.toggle();

  Future<void> resetJourney() async {
    _currentNodeKey = 'start';
    options.clear();
    conversation.clear();
    _activeBotMessageId = null;

    final String? oldTicket = ticketId.value;
    if (oldTicket != null) {
      await _firestore.collection('SupportTickets').doc(oldTicket).set(
        {
          'status': 'closed',
          'progress': 'User restarted the conversation.',
          'updatedAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );
    }

    _messagesSub?.cancel();
    _ticketSub?.cancel();
    sessionId.value = null;
    ticketId.value = null;
    ticketStatus.value = 'open';
    ticketProgress.value = 'Collecting initial details';
    _bootstrapConversation();
    isLoading.value = false;
  }

  Future<void> selectOption(SupportOption option) async {
    _markActiveBotMessageAsAnswered();
    options.clear();
    if (sessionId.value == null) {
      final bool sessionReady = await _ensureSession();
      if (!sessionReady) {
        _selectOptionOffline(option);
        return;
      }
    }

    final messagesRef = _messageCollection;
    if (messagesRef == null) {
      _selectOptionOffline(option);
      return;
    }
    try {
      // 1. Send User Message
      await messagesRef.add({
        'sender': 'user',
        'type': 'option',
        'payload': option.label,
        'rawKey': option.key,
        if (_activeBotMessageId != null) 'replyTo': _activeBotMessageId,
        'ts': Timestamp.now(),
      });

      // 2. Update Ticket Status
      final nextNode = _nodes[option.key];
      await _touchTicket(
        status: 'open',
        progress: 'You selected "${option.label}".',
        extra: {'latestSelection': option.key},
      );

      // 3. Send Bot Response
      if (nextNode == null) {
        options.clear();
        await _touchTicket(
          status: 'awaiting_agent',
          progress: 'Our specialist will take it from here.',
        );
        return;
      }

      await _sendBotNode(option.key);
    } catch (_) {
      _selectOptionOffline(option);
    }
  }

  void _selectOptionOffline(SupportOption option) {
    _markActiveBotMessageAsAnswered();
    options.clear();
    final now = DateTime.now();
    conversation.add(
      SupportMessage(
        fromBot: false,
        text: option.label,
        timestamp: now,
        rawKey: option.key,
      ),
    );
    final nextNode = _nodes[option.key];
    if (nextNode == null) {
      conversation.add(
        SupportMessage(
          fromBot: true,
          text:
          'We are preparing that answer for you. Meanwhile, reach us from the quick actions menu.',
          timestamp: now.add(const Duration(milliseconds: 500)),
        ),
      );
      options.clear();
      return;
    }
    _currentNodeKey = option.key;
    conversation.add(
      SupportMessage(
        fromBot: true,
        text: nextNode['text'].toString(),
        timestamp: DateTime.now().add(const Duration(milliseconds: 300)),
      ),
    );
    final nextOptions = _extractOptions(nextNode);
    options.assignAll(nextOptions);
  }

  Future<void> _sendBotNode(String nodeKey) async {
    final node = _nodes[nodeKey];
    if (node == null) return;
    _currentNodeKey = nodeKey;
    final List<SupportOption> nodeOptions = _extractOptions(node);
    final String copy = (node['text'] ?? '').toString();

    final messagesRef = _messageCollection;
    if (messagesRef != null) {
      final docRef = await messagesRef.add({
        'sender': 'bot',
        'type': 'text',
        'payload': copy,
        'options':
        nodeOptions.map((SupportOption opt) => opt.toFirestore()).toList(),
        'nodeKey': nodeKey,
        'ts': Timestamp.now(),
      });
      _activeBotMessageId = docRef.id;
    } else {
      conversation.add(
        SupportMessage(
          fromBot: true,
          text: copy,
          timestamp: DateTime.now(),
          options: nodeOptions,
        ),
      );
    }

    options.assignAll(nodeOptions);
    final bool hasChoices = nodeOptions.isNotEmpty;
    final String targetStatus =
    hasChoices ? ticketStatus.value : 'awaiting_agent';
    final String progressMessage = hasChoices
        ? 'Please choose an option to continue.'
        : 'A support specialist will review your ticket shortly.';
    await _touchTicket(
      status: targetStatus.isEmpty ? 'open' : targetStatus,
      progress: progressMessage,
      extra: {'activeNode': nodeKey},
    );
  }

  List<SupportOption> _extractOptions(Map<String, dynamic> node) {
    if (node['options'] is! List) return [];
    final List raw = node['options'] as List;
    return raw
        .whereType<Map>()
        .map((opt) => SupportOption(
      key: opt['key']?.toString() ?? '',
      label: opt['label']?.toString() ?? '',
    ))
        .where((opt) => opt.key.isNotEmpty && opt.label.isNotEmpty)
        .toList();
  }

  Map<String, Map<String, dynamic>> _temporaryNodes() {
    return {
      'start': {
        'text':
        'Hey there 👋\nI can get you instant answers. Please select a category to begin.',
        'options': [
          {
            'key': 'order_care',
            'label': 'Track or manage bookings',
          },
          {
            'key': 'payment_support',
            'label': 'Billing & refunds',
          },
          {
            'key': 'account_help',
            'label': 'Account & app issues',
          },
          {
            'key': 'contact_support',
            'label': 'Contact a human specialist',
          },
        ],
      },
      'order_care': {
        'text':
        'You can follow every step of your service in the **My Orders** section.\n\nOpen Orders tab → select your booking → tap **Live timeline** to view all progress.',
        'options': [
          {
            'key': 'order_delays',
            'label': 'My professional is delayed',
          },
          {
            'key': 'order_reschedule',
            'label': 'Need to reschedule a visit',
          },
        ],
      },
      'order_delays': {
        'text':
        'If the partner is delayed by more than 15 minutes, the timeline highlights it automatically.\n\nNeed urgent help? Use **Call partner** inside the booking card.',
        'options': [],
      },
      'order_reschedule': {
        'text':
        'Tap **Change slot** on your booking → choose a new date & time.\n\nWe will notify the professional instantly.',
        'options': [],
      },
      'payment_support': {
        'text':
        'All payments are securely handled by Razorpay.\n\nTo view invoices, head to **Wallet → Transactions**. Refunds reflect within 2–5 bank days depending on your provider.',
        'options': [
          {
            'key': 'refund_status',
            'label': 'Where is my refund?',
          },
          {
            'key': 'payment_methods',
            'label': 'Supported payment methods',
          },
        ],
      },
      'refund_status': {
        'text':
        'Refund timelines:\n• UPI / Wallet: 0–24 hrs\n• Card / Net Banking: 2–5 working days\n\nStill not received it? Share the transaction ID with support and we will escalate it.',
        'options': [],
      },
      'payment_methods': {
        'text':
        'We accept UPI, all major cards, and net banking. For corporate tie-ups, please contact support to enable invoiced billing.',
        'options': [],
      },
      'account_help': {
        'text':
        'Need to update your profile, pet details, or notification preferences? Head to **Profile → Settings**.\n\nYou can also enable one-tap logins by verifying your phone number.',
        'options': [
          {
            'key': 'app_troubleshoot',
            'label': 'App is not working properly',
          },
        ],
      },
      'app_troubleshoot': {
        'text':
        'Try these quick fixes:\n1. Pull-to-refresh on home\n2. Force-close & reopen the app\n3. Ensure a stable connection\n\nIf the issue persists, capture a screen recording and share it with support—our engineers will investigate.',
        'options': [],
      },
      'contact_support': {
        'text':
        'Need human assistance? Choose an option from the **quick actions card** (top right icon) or email us at care@myfellowpet.com. We typically respond within 15 minutes.',
        'options': [],
      },
    }.map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
    );
  }
}

// --- UI WIDGETS ---

class SupportHelpScreen extends StatelessWidget {
  SupportHelpScreen({super.key});

  final SupportHelpController controller = Get.put(SupportHelpController());
  final DateFormat _timeFormat = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Set the background color of the scaffold to match the chat background for seamless integration
      backgroundColor: kChatBackground,
      body: SafeArea(
        child: Obx(
              () => Stack(
            children: [
              Column(
                children: [
                  _buildHeader(context),
                  // Removed the large 12px container spacer here
                  Expanded(
                    // The _buildBody handles the actual chat area
                    child: controller.isLoading.value
                        ? const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                        AlwaysStoppedAnimation(kPrimaryColor),
                      ),
                    )
                        : _buildBody(context),
                  ),
                ],
              ),
              _QuickActionsCard(
                visible: controller.helpMenuOpen.value,
                secondaryColor: controller.secondaryColor.value,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final Color headerStartColor = kPrimaryColor;
    final Color headerEndColor =
    Color.lerp(controller.secondaryColor.value, Colors.white, 0.1)!;

    return Container(
      // Reduced top margin, removed side margins for wider header (less margin waste)
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        // Use a solid color or minimal gradient for a cleaner WhatsApp-like header
        color: kPrimaryColor,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support Hub',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // --- Quick Actions/Admin Icon ---
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                FontAwesomeIcons.solidCommentDots, // Icon for Quick Actions Menu
                color: Colors.white,
                size: 20,
              ),
              onPressed: controller.toggleHelpMenu,
              tooltip: 'Quick Actions',
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                FontAwesomeIcons.userCog, // Admin Icon
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return _ConversationPanel(
      controller: controller,
      timeFormat: _timeFormat,
      scrollController: controller._scrollController,
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.controller,
    required this.timeFormat,
    required this.scrollController,
  });

  final SupportHelpController controller;
  final DateFormat timeFormat;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Container(
      // The chat area fills the remaining space, no horizontal margin here
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: kChatBackground, // WhatsApp-like chat background
      ),
      child: Obx(
            () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Bot Header/Info (WhatsApp Status Style) ---
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kPrimaryColor, kSecondaryColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.pets, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FellowBot',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kNeutralDark,
                          ),
                        ),
                        Text(
                          'Your always-on support assistant.',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Reset Button
                  IconButton(
                    onPressed: () => controller.resetJourney(),
                    icon: const Icon(Icons.refresh, color: kPrimaryColor, size: 20),
                    tooltip: 'Start a new conversation',
                  ),
                ],
              ),
            ),

            // Ticket Status Banner
            if (controller.ticketId.value != null)
              Padding(
                // Use less margin to hug the chat area
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: _TicketStatusBanner(
                  ticketId: controller.ticketId.value!,
                  status: controller.ticketStatus.value,
                  progress: controller.ticketProgress.value,
                  lastUpdated: controller.lastUpdated.value,
                  timeFormat: timeFormat,
                ),
              ),

            // --- CONVERSATION LIST (Performance Optimized & Edge-to-Edge) ---
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                reverse: true,
                padding: const EdgeInsets.only(bottom: 10, top: 10), // Minimal vertical padding
                itemCount: controller.conversation.length,
                separatorBuilder: (_, __) => const SizedBox(height: 5), // Smaller separator for chat look
                itemBuilder: (_, index) {
                  final message = controller.conversation[controller.conversation.length - 1 - index];
                  return _MessageBubble(
                    message: message,
                    timeFormat: timeFormat,
                    onOptionTap: controller.selectOption,
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

class _TicketStatusBanner extends StatelessWidget {
  const _TicketStatusBanner({
    required this.ticketId,
    required this.status,
    required this.progress,
    required this.lastUpdated,
    required this.timeFormat,
  });

  final String ticketId;
  final String status;
  final String progress;
  final DateTime? lastUpdated;
  final DateFormat timeFormat;

  @override
  Widget build(BuildContext context) {
    Color background;
    Color border;
    IconData icon;
    Color iconColor;

    if (status == 'awaiting_agent') {
      background = kStatusAwaiting.withOpacity(0.1);
      border = kStatusAwaiting.withOpacity(0.3);
      icon = Icons.access_time_filled;
      iconColor = kStatusAwaiting;
    } else if (status == 'offline') {
      background = kStatusOffline.withOpacity(0.1);
      border = kStatusOffline.withOpacity(0.3);
      icon = Icons.error_outline;
      iconColor = kStatusOffline;
    } else {
      background = kStatusOpen.withOpacity(0.1);
      border = kStatusOpen.withOpacity(0.3);
      icon = Icons.info_outline; // Changed icon for general info
      iconColor = kStatusOpen;
    }

    final String statusLabel = _formatStatus(status);
    final String? updatedLabel = lastUpdated == null
        ? null
        : 'Updated ${timeFormat.format(lastUpdated!)}';
    final String ticketLabel = 'Ticket ${_shortTicket(ticketId)}';

    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85, // Constrain size for cleaner look
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: iconColor,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kNeutralDark,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ticketLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: kNeutralDark.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              progress,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: kNeutralDark,
                height: 1.3,
              ),
            ),
            if (updatedLabel != null)
              Text(
                updatedLabel,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: kNeutralDark.withOpacity(0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _shortTicket(String fullId) {
    if (fullId.length <= 6) return fullId.toUpperCase();
    return fullId.substring(0, 6).toUpperCase();
  }

  static String _formatStatus(String raw) {
    if (raw.isEmpty) return 'Open';
    return raw
        .split('_')
        .where((segment) => segment.isNotEmpty)
        .map(
          (segment) =>
      segment[0].toUpperCase() + segment.substring(1).toLowerCase(),
    )
        .join(' ');
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.timeFormat,
    this.onOptionTap,
  });

  final SupportMessage message;
  final DateFormat timeFormat;
  final ValueChanged<SupportOption>? onOptionTap;

  @override
  Widget build(BuildContext context) {
    final bool isBot = message.fromBot;
    final Alignment alignment =
    isBot ? Alignment.centerLeft : Alignment.centerRight;
    final Color bubbleColor = isBot ? kBubbleBot : kBubbleUser;

    // WhatsApp Style Corner Logic
    const double radius = 10.0;
    final BorderRadius borderRadius = BorderRadius.only(
      topLeft: Radius.circular(radius),
      topRight: Radius.circular(radius),
      bottomLeft: Radius.circular(isBot ? 2.0 : radius), // Tiny corner on side of message flow
      bottomRight: Radius.circular(isBot ? radius : 2.0), // Tiny corner on side of message flow
    );

    final TextStyle bodyStyle = GoogleFonts.poppins(
      fontSize: 14,
      height: 1.3,
      color: isBot ? kNeutralDark : kNeutralDark.withOpacity(0.9),
    );
    final TextStyle timeStyle = GoogleFonts.poppins(
      fontSize: 10,
      color: isBot ? kNeutralDark.withOpacity(0.5) : kNeutralDark.withOpacity(0.5),
    );

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          // Minimal margin needed to separate bubbles from screen edge
          margin: EdgeInsets.only(
            left: isBot ? 8 : 0,
            right: isBot ? 0 : 8,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
            isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Text(
                message.text,
                style: bodyStyle,
                textAlign: isBot ? TextAlign.left : TextAlign.left, // Text always aligns left within the bubble
              ),
              if (isBot &&
                  message.options.isNotEmpty &&
                  !message.isAnswered &&
                  onOptionTap != null) ...[
                const SizedBox(height: 8),
                for (final option in message.options)
                  _InlineOptionButton(
                    option: option,
                    onTap: () => onOptionTap!(option),
                  ),
              ],
              const SizedBox(height: 4),
              Text(
                timeFormat.format(message.timestamp),
                style: timeStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineOptionButton extends StatelessWidget {
  const _InlineOptionButton({
    required this.option,
    required this.onTap,
  });

  final SupportOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // The tap action must be instantaneous to avoid the stuttering delay
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kBubbleBot, // White background for crisp button
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: kPrimaryColor.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            option.label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kPrimaryColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionPanel extends StatelessWidget {
  const _OptionPanel({required this.controller});

  final SupportHelpController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final options = controller.options;
      if (options.isNotEmpty) {
        return const SizedBox.shrink();
      }
      final status = controller.ticketStatus.value;
      IconData icon = Icons.check_circle_outline;
      Color iconColor = kStatusOpen;
      String title = 'All set!';
      String subtitle =
          'Need more help? Pop open the quick actions menu or restart the journey.';

      if (status == 'awaiting_agent') {
        icon = Icons.access_time_filled;
        iconColor = kStatusAwaiting;
        title = 'Ticket Filed';
        subtitle =
        'Hang tight while a support specialist reviews your request.';
      } else if (status == 'offline') {
        icon = Icons.error_outline;
        iconColor = kStatusOffline;
        title = 'Connection Error';
        subtitle =
        'We could not connect to support right now. Please try again shortly.';
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        // Simple white container overlaying the chat background
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 5,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kNeutralDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: kNeutralDark.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.visible,
    required this.secondaryColor,
  });

  final bool visible;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    final Color contentColor = Colors.white.withOpacity(0.95);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      right: 8, // Close to edge
      top: visible ? 60 : -260, // Position adjusted for header height
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: Material(
          elevation: 16,
          borderRadius: BorderRadius.circular(16),
          shadowColor: kNeutralDark.withOpacity(0.3),
          child: Container(
            width: 260,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  secondaryColor,
                  Color.lerp(secondaryColor, kPrimaryColor, 0.4)!,
                ],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.live_help, color: contentColor, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Quick Actions',
                      style: GoogleFonts.poppins(
                        color: contentColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20, thickness: 0.5, color: Colors.white54),

                _QuickActionTile(
                  icon: Icons.call_outlined,
                  title: 'Call Concierge',
                  subtitle: 'Speak to a live specialist',
                  contentColor: contentColor,
                ),
                _QuickActionTile(
                  icon: Icons.email_outlined,
                  title: 'Email Support',
                  subtitle: 'care@myfellowpet.com',
                  contentColor: contentColor,
                ),
                _QuickActionTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Help Centre',
                  subtitle: 'Browse guides & policies',
                  contentColor: contentColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.contentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color contentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: contentColor.withOpacity(0.9), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: contentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    color: contentColor.withOpacity(0.8),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- DATA MODELS ---

class SupportMessage {
  SupportMessage({
    required this.fromBot,
    required this.text,
    required this.timestamp,
    this.id,
    this.options = const <SupportOption>[],
    this.rawKey,
    this.isAnswered = false,
  });

  final bool fromBot;
  final String text;
  final DateTime timestamp;
  final String? id;
  final List<SupportOption> options;
  final String? rawKey;
  final bool isAnswered;

  SupportMessage copyWith({
    bool? fromBot,
    String? text,
    DateTime? timestamp,
    String? id,
    List<SupportOption>? options,
    String? rawKey,
    bool? isAnswered,
  }) {
    return SupportMessage(
      fromBot: fromBot ?? this.fromBot,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      id: id ?? this.id,
      options: options ?? this.options,
      rawKey: rawKey ?? this.rawKey,
      isAnswered: isAnswered ?? this.isAnswered,
    );
  }
}

class SupportOption {
  SupportOption({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;

  factory SupportOption.fromMap(Map<String, dynamic> map) {
    return SupportOption(
      key: (map['key'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'key': key,
      'label': label,
    };
  }
}