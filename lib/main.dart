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
       databaseURL: "https://neon-chat-d6f99-default-rtdb.firebaseio.com",
    ),
  );

  await FirebaseAuth.instance.signInAnonymously();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // ---------------- FIREBASE ----------------

  final usersRef = FirebaseFirestore.instance.collection('users');
  final messagesRef = FirebaseFirestore.instance.collection('messages');

  final DatabaseReference presenceRoot =
      FirebaseDatabase.instance.ref('status');

  DatabaseReference? _myStatusRef;
  StreamSubscription? _connectionSub;

  // ---------------- UI ----------------

  final TextEditingController _controller = TextEditingController();
  String? username;

  // ---------------- TEXT STYLES ----------------

  TextStyle get sidebarName => const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
      );

  TextStyle get sidebarStatus => TextStyle(
        color: Colors.white.withOpacity(0.6),
        fontSize: 12,
      );

  // ---------------- INIT ----------------

  @override
  void initState() {
    super.initState();
    setupUser();
    setupPresence();
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _controller.dispose();
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

  // ---------------- PRESENCE (FINAL, STABLE) ----------------

  void setupPresence() {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;

    final connectedRef =
        FirebaseDatabase.instance.ref('.info/connected');
    _myStatusRef = presenceRoot.child(uid);

    _connectionSub?.cancel();
    _connectionSub = connectedRef.onValue.listen((event) {
      if (event.snapshot.value != true) return;

      _myStatusRef!.onDisconnect().set({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });

      _myStatusRef!.set({
        'online': true,
        'lastSeen': ServerValue.timestamp,
      });
    });
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
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1025),
      body: SafeArea(
        child: Row(
          children: [
            // -------- SIDEBAR --------
            SizedBox(
              width: 220,
              child: StreamBuilder<DatabaseEvent>(
                stream: presenceRoot.onValue,
                builder: (_, presenceSnap) {
                  final Map presence =
                      presenceSnap.data?.snapshot.value as Map? ?? {};

                  return StreamBuilder<QuerySnapshot>(
                    stream: usersRef.snapshots(),
                    builder: (_, userSnap) {
                      if (!userSnap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      return ListView(
                        padding: const EdgeInsets.all(10),
                        children: userSnap.data!.docs.map((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>;
                          final uid = doc.id;

                          final status = presence[uid] as Map?;
                          final bool online =
                              status?['online'] == true;

                          String statusText;

                          if (online) {
                            statusText = "Online";
                          } else {
                            final ts =
                                status?['lastSeen'] as int?;
                            if (ts == null) {
                              statusText = "Offline";
                            } else {
                              final diff = DateTime.now()
                                  .difference(
                                      DateTime.fromMillisecondsSinceEpoch(ts));
                              statusText =
                                  "Last seen ${diff.inMinutes} min ago";
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
                            title: Text(
                              data['username'],
                              style: sidebarName,
                            ),
                            subtitle: Text(
                              statusText,
                              style: sidebarStatus,
                            ),
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
              child: Column(
                children: [
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: messagesRef
                          .orderBy('createdAt')
                          .snapshots(),
                      builder: (_, snap) {
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        return ListView(
                          padding: const EdgeInsets.all(10),
                          children: snap.data!.docs.map((doc) {
                            final data =
                                doc.data() as Map<String, dynamic>;
                            return ListTile(
                              title: Text(
                                data['username'],
                                style:
                                    const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                data['text'],
                                style:
                                    const TextStyle(color: Colors.white70),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => sendMessage(),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "Type a message",
                        hintStyle:
                            TextStyle(color: Colors.white54),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
