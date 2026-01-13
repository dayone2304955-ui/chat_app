import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyAVjCfOKeVI8wh3Y0JRWrAsfV_mlAmuwv8",
      authDomain: "neon-chat-d6f99.firebaseapp.com",
      projectId: "neon-chat-d6f99",
      storageBucket: "neon-chat-d6f99.firebasestorage.app",
      messagingSenderId: "895991678818",
      appId: "1:895991678818:web:ac39a6c099907239d90e3b",
      measurementId: "G-TCW25PPZG7"
    ),
  );

  await FirebaseAuth.instance.signInAnonymously();
  runApp(const MyApp());
}

enum AppTheme { auroraGlass, deepSpace }

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppTheme theme = AppTheme.auroraGlass;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ChatScreen(
        theme: theme,
        onThemeChanged: (t) => setState(() => theme = t),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final AppTheme theme;
  final ValueChanged<AppTheme> onThemeChanged;

  const ChatScreen({
    super.key,
    required this.theme,
    required this.onThemeChanged,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver {
  final messagesRef = FirebaseFirestore.instance.collection('messages');
  final usersRef = FirebaseFirestore.instance.collection('users');

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // ✅ PRESENCE (ADDED)
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  DatabaseReference? _statusRef;
  StreamSubscription? _connectionSub;

  bool autoScrollEnabled = true;
  String? username;
  Timer? _heartbeatTimer;

  // ---------------- TEXT STYLES ----------------

  TextStyle get appTitle => const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: 0.5,
      );

  TextStyle get sidebarName => const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
      );

  TextStyle get sidebarStatus => TextStyle(
        color: Colors.white.withOpacity(0.6),
        fontSize: 12,
      );

  TextStyle get chatText => const TextStyle(
        color: Colors.white,
        fontSize: 15,
      );

  TextStyle get inputText => const TextStyle(
        color: Colors.white,
        fontSize: 15,
      );

  // ---------------- INIT ----------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setupUser();
    setupPresence(); // ✅ ADDED
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final atBottom = _scrollController.offset >=
          _scrollController.position.maxScrollExtent - 24;
      if (atBottom && !autoScrollEnabled) {
        setState(() => autoScrollEnabled = true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // ✅ ADD
    _heartbeatTimer?.cancel();                    // ✅ ADD
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      await usersRef.doc(user.uid).update({
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }

    if (state == AppLifecycleState.resumed) {
      await usersRef.doc(user.uid).update({
        'lastSeen': FieldValue.serverTimestamp(),
      });

      setupPresence();
    }
  }


  Future<void> setupUser() async {
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await usersRef.doc(user.uid).get();

    if (!doc.exists) {
      await askUsername();
    } else {
      username = doc['username'];
    }
  }

  // ---------------- PRESENCE (ADDED) ----------------

  Future<void> setupPresence() async {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;

    final connectedRef = _rtdb.ref('.info/connected');
    _statusRef = _rtdb.ref('status/$uid');

    _connectionSub?.cancel();

    _connectionSub = connectedRef.onValue.listen((event) async {
      final connected = event.snapshot.value == true;
      if (!connected) return;

      // 🔥 Guaranteed offline on crash / tab close
      await _statusRef!.onDisconnect().set({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });

      // 🟢 Mark online
      await _statusRef!.set({
        'online': true,
        'lastSeen': ServerValue.timestamp,
      });
    });

    // 🔁 RTDB → Firestore mirror (online ONLY)
    _statusRef!.onValue.listen((event) async {
      final data = event.snapshot.value as Map?;
      if (data == null) return;

      await usersRef.doc(uid).update({
        'online': data['online'],
      });
    });
  }


  Future<void> askUsername() async {
    final ctrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Choose username"),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;

              final user = FirebaseAuth.instance.currentUser!;
              username = ctrl.text.trim();

              await usersRef.doc(user.uid).set({
                'username': username,
                'lastSeen': FieldValue.serverTimestamp(),
              });

              Navigator.pop(context);
            },
            child: const Text("Join"),
          ),
        ],
      ),
    );
  }

  // ---------------- MESSAGE ----------------

  void sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    await messagesRef.add({
      'text': text,
      'username': username,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _controller.clear();
    _focusNode.requestFocus();
  }

  // ---------------- AUTO SCROLL ----------------

  void scrollToBottom() {
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  // ---------------- VISUAL HELPERS ----------------

  Widget auroraBackground({required Widget child}) {
    final isAurora = widget.theme == AppTheme.auroraGlass;

    return Container(
      decoration: BoxDecoration(
        gradient: isAurora
            ? const RadialGradient(
                center: Alignment.topRight,
                radius: 1.2,
                colors: [
                  Color(0xFF1F7AFF),
                  Color(0xFF0B1025),
                  Color(0xFF05070E),
                ],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF02040A),
                  Color(0xFF080D1A),
                ],
              ),
      ),
      child: child,
    );
  }

  Widget glassPanel({required Widget child}) {
    final isAurora = widget.theme == AppTheme.auroraGlass;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isAurora
                  ? [
                      Colors.white.withOpacity(0.14),
                      Colors.white.withOpacity(0.04),
                    ]
                  : [
                      Colors.white.withOpacity(0.08),
                      Colors.white.withOpacity(0.02),
                    ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.18),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: auroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Text("Sky", style: appTitle),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => SimpleDialog(
                            title: const Text("Theme"),
                            children: [
                              SimpleDialogOption(
                                onPressed: () {
                                  widget.onThemeChanged(AppTheme.auroraGlass);
                                  Navigator.pop(context);
                                },
                                child: const Text("Aurora Glass (Premium)"),
                              ),
                              SimpleDialogOption(
                                onPressed: () {
                                  widget.onThemeChanged(AppTheme.deepSpace);
                                  Navigator.pop(context);
                                },
                                child: const Text("Deep Space (Night Focus)"),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text(
                        "Theme",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: glassPanel(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: usersRef
                            .where('lastSeen',
                                isGreaterThan: Timestamp.fromDate(
                                  DateTime.now().subtract(const Duration(minutes: 10)),
                                ))
                            .snapshots(),
                          builder: (_, snap) {
                            if (!snap.hasData) return const SizedBox();
                            return ListView(
                              padding: const EdgeInsets.all(10),
                              children: snap.data!.docs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;                                
                                final bool online = data['online'] == true;
                                final Timestamp? lastSeenTs = data['lastSeen'] as Timestamp?;
                                final DateTime now = DateTime.now();
                                
                                String statusText;

                                if (online) {
                                  statusText = "Online";
                                } else if (lastSeenTs == null) {
                                  statusText = "Offline";
                                } else {
                                  final diff = now.difference(lastSeenTs.toDate());

                                  if (diff.inMinutes < 1) {
                                    statusText = "Last seen just now";
                                  } else if (diff.inMinutes < 60) {
                                    statusText = "Last seen ${diff.inMinutes} min ago";
                                  } else if (diff.inHours < 24) {
                                    statusText = "Last seen ${diff.inHours} h ago";
                                  } else {
                                    statusText = "Last seen ${diff.inDays} d ago";
                                  }
                                }


                                return ListTile(
                                  leading: Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: online
                                        ? Colors.cyanAccent
                                        : Colors.grey,
                                  ),
                                  title: Text(data['username'], style: sidebarName),
                                  subtitle: Text(
                                     statusText,
                                    style: sidebarStatus,
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: messagesRef.orderBy('createdAt').snapshots(),
                              builder: (_, snap) {
                                if (!snap.hasData) {
                                  return const Center(child: CircularProgressIndicator());
                                }

                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (autoScrollEnabled) scrollToBottom();
                                });

                                final docs = snap.data!.docs;

                                return ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.all(14),
                                  itemCount: docs.length,
                                  itemBuilder: (_, i) {
                                    final data =
                                        docs[i].data() as Map<String, dynamic>;
                                    final isMe = data['username'] == username;

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Align(
                                        alignment: isMe
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        child: Container(
                                          constraints:
                                              const BoxConstraints(maxWidth: 420),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: widget.theme ==
                                                    AppTheme.auroraGlass
                                                ? Colors.white.withOpacity(0.10)
                                                : Colors.white.withOpacity(0.06),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.12),
                                            ),
                                          ),
                                          child: Text(
                                            data['text'],
                                            style: chatText,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: glassPanel(
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                style: inputText,
                                onSubmitted: (_) => sendMessage(),
                                decoration: InputDecoration(
                                  hintText: "Type a message…",
                                  hintStyle: TextStyle(
                                      color: Colors.white.withOpacity(0.5)),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.all(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
