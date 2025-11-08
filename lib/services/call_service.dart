import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CallService {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;
  final _config = {
    'iceServers': [
      // Free STUN; for production add your TURN server
      {'urls': 'stun:stun.l.google.com:19302'}
    ]
  };
  final _constraints = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  Future<void> _ensurePc({
    required Function(MediaStream stream) onRemote,
  }) async {
    print('⚙️ Initializing PeerConnection...');
    try {
      _pc ??= await createPeerConnection(_config, _constraints);
      print('✅ PeerConnection created.');

      _local = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user'}
      });
      print('🎥 Local stream acquired (Unified Plan).');

// Add individual tracks instead of entire stream
      for (var track in _local!.getTracks()) {
        await _pc!.addTrack(track, _local!);
      }
      print('🔗 Local tracks added to PeerConnection.');

// Unified Plan uses onTrack instead of onAddStream
      _pc!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remote = event.streams[0];
          onRemote(_remote!);
          print('📡 Remote stream received (Unified Plan).');
        }
      };

    } catch (e, st) {
      print('❌ Error initializing PeerConnection: $e');
      print(st);
    }
  }

  MediaStream? get localStream => _local;
  MediaStream? get remoteStream => _remote;

  Future<String> startCall({
    required String receiverId,
    required Function(MediaStream) onRemote,
  }) async {
    final callerId = _auth.currentUser!.uid;
    print('📞 Starting call...');
    print('👤 Caller UID: $callerId');
    print('🎯 Receiver UID: $receiverId');

    await _ensurePc(onRemote: onRemote);
    print('✅ PeerConnection initialized.');

    final callDoc = _fs.collection('calls').doc();
    print('📝 Created Firestore doc ID: ${callDoc.id}');

    final callerCand = callDoc.collection('callerCandidates');
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        callerCand.add({'candidate': c.toMap()});
        print('❄️ Added ICE candidate for caller.');
      }
    };

    final offer = await _pc!.createOffer({'offerToReceiveVideo': 1, 'offerToReceiveAudio': 1});
    await _pc!.setLocalDescription(offer);
    print('🎥 Offer created & set locally.');

    await callDoc.set({
      'callerId': callerId,
      'receiverId': receiverId,
      'status': 'ringing',
      'offer': offer.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    print('🔥 Firestore call doc written successfully.');

    // Listen for answer
    callDoc.snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;
      if (data['answer'] != null) {
        print('📡 Answer received from receiver!');
        final remoteDesc = await _pc!.getRemoteDescription();
        if (remoteDesc == null) {
          final answer = RTCSessionDescription(
            data['answer']['sdp'],
            data['answer']['type'],
          );
          await _pc!.setRemoteDescription(answer);
          print('✅ Remote description set (call connected).');
        }
      }

      if (data['status'] == 'ended') {
        print('❌ Call ended by receiver.');
        endCall(callDoc.id);
      }
    });

    // Listen for receiver ICE
    callDoc.collection('receiverCandidates').snapshots().listen((q) async {
      for (final d in q.docChanges) {
        if (d.type == DocumentChangeType.added) {
          final cand = RTCIceCandidate(
            d.doc['candidate']['candidate'],
            d.doc['candidate']['sdpMid'],
            d.doc['candidate']['sdpMLineIndex'],
          );
          await _pc!.addCandidate(cand);
          print('❄️ Added ICE candidate from receiver.');
        }
      }
    });

    print('✅ Call setup complete. Returning callId: ${callDoc.id}');
    return callDoc.id;
  }


  Future<void> answerCall({
    required String callId,
    required Function(MediaStream) onRemote,
  }) async {
    await _ensurePc(onRemote: onRemote);

    final callDoc = _fs.collection('calls').doc(callId);
    final snap = await callDoc.get();
    final data = snap.data()!;
    final offer = data['offer'];
    await _pc!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));

    // ICE: write receiver candidates
    final rc = callDoc.collection('receiverCandidates');
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        rc.add({'candidate': c.toMap()});
      }
    };

    final answer = await _pc!.createAnswer({'offerToReceiveVideo': 1, 'offerToReceiveAudio': 1});
    await _pc!.setLocalDescription(answer);

    await callDoc.update({
      'answer': answer.toMap(),
      'status': 'connected',
    });

    // Listen for caller ICE
    callDoc.collection('callerCandidates').snapshots().listen((q) async {
      for (final d in q.docChanges) {
        if (d.type == DocumentChangeType.added) {
          final cand = RTCIceCandidate(
            d.doc['candidate']['candidate'],
            d.doc['candidate']['sdpMid'],
            d.doc['candidate']['sdpMLineIndex'],
          );
          await _pc!.addCandidate(cand);
        }
      }
    });
  }

  Future<void> endCall(String callId) async {
    try {
      await _fs.collection('calls').doc(callId).update({'status': 'ended'});
    } catch (_) {}
    await _pc?.close();
    _pc = null;
    await _local?.dispose();
    await _remote?.dispose();
    _local = null;
    _remote = null;
  }
}



class CallScreen extends StatefulWidget {
  final String receiverId;   // when you start a call
  final String? callId;      // when you answer a call
  final bool isAnswering;

  const CallScreen.start({super.key, required this.receiverId})
      : callId = null, isAnswering = false;

  const CallScreen.answer({super.key, required this.callId})
      : receiverId = '', isAnswering = true;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _service = CallService();
  final _localView = RTCVideoRenderer();
  final _remoteView = RTCVideoRenderer();
  String? _callId;

  @override
  void initState() {
    super.initState();
    _localView.initialize();
    _remoteView.initialize();
    _boot();
  }

  Future<void> _boot() async {
    if (widget.isAnswering) {
      await _service.answerCall(
        callId: widget.callId!,
        onRemote: (s) => _remoteView.srcObject = s,
      );
      _localView.srcObject = _service.localStream;
      _callId = widget.callId!;
    } else {
      _callId = await _service.startCall(
        receiverId: widget.receiverId,
        onRemote: (s) => _remoteView.srcObject = s,
      );
      _localView.srcObject = _service.localStream;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _localView.dispose();
    _remoteView.dispose();
    if (_callId != null) {
      _service.endCall(_callId!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Remote full screen
        Positioned.fill(child: RTCVideoView(_remoteView, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)),
        // Local small preview
        Positioned(
          right: 16,
          top: 48,
          width: 120,
          height: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: RTCVideoView(_localView, mirror: true),
          ),
        ),
        // Controls
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 32.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: () {
                    if (_callId != null) _service.endCall(_callId!);
                    Navigator.pop(context);
                  },
                  child: const Icon(Icons.call_end),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
