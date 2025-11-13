import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- Your App Colors ---
const Color primaryColor = Color(0xFF00C2CB);
const Color secondaryColor = Color(0xFF0097A7);
const Color darkColor = Color(0xFF263238);
const Color lightTextColor = Color(0xFF757575);
const Color pageBackgroundColor = Color(0xFFFFFFFF);
const Color aiBubbleColor = Color(0xFFF5F7FA); // Clean light grey for AI

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final List<types.Message> _messages = [];
  final _uuid = const Uuid();
  late final types.User _user;

  // The AI Persona
  final _ai = const types.User(
    id: 'ai-assistant',
    firstName: 'MyFellowPet',
    lastName: 'AI',
  );

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _user = types.User(
      id: FirebaseAuth.instance.currentUser?.uid ?? _uuid.v4(),
      firstName: 'You',
    );
    _addInitialMessage();
  }

  void _addInitialMessage() {
    final aiMessage = types.TextMessage(
      author: _ai,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: _uuid.v4(),
      text:
      "Hi! I'm your MyFellowPet assistant. 🐾\n\nI can check boarder availability or find services for you. Try asking:\n\"Find dog boarders in Indiranagar for next weekend.\"",
    );
    _addMessage(aiMessage);
  }

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  List<Map<String, String>> _generateMessageHistory() {
    return _messages.reversed.map((m) {
      final role = (m.author.id == _ai.id) ? 'assistant' : 'user';
      if (m is types.TextMessage) {
        return {'role': role, 'content': m.text};
      }
      return {'role': 'user', 'content': ''};
    }).where((m) => m['content']!.isNotEmpty).toList();
  }

  void _handleSendPressed(types.PartialText message) async {
    final userMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: _uuid.v4(),
      text: message.text,
    );

    _addMessage(userMessage);
    setState(() => _isLoading = true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('chatWithAI');
      final history = _generateMessageHistory();

      // Call Cloud Function
      final result = await callable.call({'messages': history});
      final data = result.data as Map<String, dynamic>;

      if (data['success'] == true) {
        final aiResponseText = data['reply'] as String;
        final aiMessage = types.TextMessage(
          author: _ai,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          id: _uuid.v4(),
          text: aiResponseText,
        );
        _addMessage(aiMessage);
      } else {
        _showError(data['error']?.toString());
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String? error) {
    final errorMessage = types.TextMessage(
      author: _ai,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: _uuid.v4(),
      text: "Oops! Something went wrong: ${error ?? 'Unknown error'}",
    );
    _addMessage(errorMessage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackgroundColor,
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: darkColor),
        title: Text(
          'MyFellowPet Assistant',
          style: GoogleFonts.poppins(
            color: darkColor,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
      ),
      body: Chat(
        messages: _messages,
        onSendPressed: _handleSendPressed,
        user: _user,
        showUserAvatars: true,
        showUserNames: false,
        typingIndicatorOptions: TypingIndicatorOptions(
          typingUsers: _isLoading ? [_ai] : [],
        ),

        // --- THEME CONFIGURATION ---
        theme: DefaultChatTheme(
          // Colors
          primaryColor: primaryColor,
          secondaryColor: aiBubbleColor,
          backgroundColor: pageBackgroundColor,
          inputBackgroundColor: Colors.white,
          inputTextColor: darkColor,

          // Message Text Styles (Fixed for new version)
          sentMessageBodyTextStyle: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          receivedMessageBodyTextStyle: GoogleFonts.poppins(
            color: darkColor,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),

          // Input Text Styles
          inputTextStyle: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: darkColor,
          ),

          // Spacing & Layout ("Breathable")
          messageInsetsVertical: 12,
          messageInsetsHorizontal: 16,
          messageBorderRadius: 18,
          inputPadding: const EdgeInsets.all(18),
          inputMargin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),

          // Input Decoration
          inputBorderRadius: BorderRadius.circular(24),
          inputContainerDecoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade200), // Subtle border
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),

          // Avatars & Icons
          sendButtonIcon: const Icon(Icons.send_rounded, color: primaryColor),
          userAvatarTextStyle: GoogleFonts.poppins(
              fontSize: 10, fontWeight: FontWeight.bold
          ),
          userNameTextStyle: GoogleFonts.poppins(
              fontSize: 10, fontWeight: FontWeight.bold
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(types.User user) {
    final bool isAi = user.id == _ai.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 4), // Align with text bubble
      child: CircleAvatar(
        radius: 16,
        backgroundColor: isAi ? aiBubbleColor : primaryColor.withOpacity(0.1),
        child: Icon(
          isAi ? Icons.auto_awesome : Icons.person,
          color: isAi ? primaryColor : primaryColor,
          size: 18,
        ),
      ),
    );
  }
}