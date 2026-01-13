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
      measurementId: "G-TCW25PPZG7",
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
  final DatabaseReference presenceRef =
      FirebaseDatabase.instance.ref('status');

  final messagesRef = FirebaseFirestore.instance.collection('messages');
  final usersRef = FirebaseFirestore.instance.collection('users');

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  DatabaseReference? _statusRef;
  StreamSubscription? _connectionSub;

  bool autoScrollEnabled = true;
  String? username;

  // ---------------- INIT ----------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setupUser();
    setupPresence();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionSub?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------- USER ----------------

  Future<void> setupUser() async {
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await usersRef.doc(user.uid).get();

    if (!doc.exists) {
      await askUsername();
    } else {
      username = doc['username'];
    }
  }

  // ---------------- PRESENCE (FINAL & CORRECT) ----------------

  Future<void> setupPresence() async {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;

    final connectedRef = _rtdb.ref('.info/connected');
    _statusRef = _rtdb.ref('status/$uid');

    _connectionSub?.cancel();
    _connectionSub = connectedRef.onValue.listen((event) {
      if (event.snapshot.value != true) return;

      _statusRef!.onDisconnect().set({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });

      _statusRef!.set({
        'online': true,
        'lastSeen': ServerValue.timestamp,
      });
    });
  }

  // ---------------- USERNAME ----------------

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

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Row(
          children: [
            // -------- SIDEBAR --------
            SizedBox(
              width: 220,
              child: StreamBuilder<DatabaseEvent>(
                stream: presenceRef.onValue,
                builder: (_, presenceSnap) {
                  final presenceData =
                      presenceSnap.data?.snapshot.value as Map? ?? {};

                  return StreamBuilder<QuerySnapshot>(
                    stream: usersRef.snapshots(),
                    builder: (_, userSnap) {
                      if (!userSnap.hasData) return const SizedBox();

                      return ListView(
                        padding: const EdgeInsets.all(10),
                        children: userSnap.data!.docs.map((doc) {
                          final user =
                              doc.data() as Map<String, dynamic>;
                          final uid = doc.id;

                          final status = presenceData[uid] as Map?;
                          final bool online =
                              status?['online'] == true;

                          String statusText;
                          if (online) {
                            statusText = "Online";
                          } else if (status?['lastSeen'] is int) {
                            final diff = DateTime.now().difference(
                              DateTime.fromMillisecondsSinceEpoch(
                                  status!['lastSeen']),
                            );
                            statusText =
                                "Last seen ${diff.inMinutes} min ago";
                          } else {
                            statusText = "Offline";
                          }

                          return ListTile(
                            leading: Icon(
                              Icons.circle,
                              size: 10,
                              color: online
                                  ? Colors.cyanAccent
                                  : Colors.grey,
                            ),
                            title: Text(user['username']),
                            subtitle: Text(statusText),
                          );
                        }).toList(),
                      );
                    },
                  );
                },
              ),
            ),

            // -------- CHAT --------
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    messagesRef.orderBy('createdAt').snapshots(),
                builder: (_, snap) {
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }

                  return ListView(
                    children: snap.data!.docs.map((doc) {
                      final data =
                          doc.data() as Map<String, dynamic>;
                      return ListTile(
                        title: Text(data['username']),
                        subtitle: Text(data['text']),
                      );
                    }).toList(),
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
