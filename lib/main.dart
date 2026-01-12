import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  await FirebaseAuth.instance.signInAnonymously();
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Neon Chat',
      theme: ThemeData.dark(),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver {
  final messagesRef =
      FirebaseFirestore.instance.collection('messages');
  final usersRef =
      FirebaseFirestore.instance.collection('users');

  final TextEditingController controller = TextEditingController();
  final FocusNode inputFocusNode = FocusNode();

  String? username;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setupUser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    inputFocusNode.dispose();
    super.dispose();
  }

  // 🔄 Online / Offline handling
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      setOnline(false);
    } else if (state == AppLifecycleState.resumed) {
      setOnline(true);
    }
  }

  // 👤 USER SETUP
  Future<void> setupUser() async {
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await usersRef.doc(user.uid).get();

    if (!doc.exists) {
      await askUsername();
    } else {
      username = doc['username'];
      setOnline(true);
    }
  }

  Future<void> askUsername() async {
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Choose a username'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            hintText: 'Your name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;

              final user =
                  FirebaseAuth.instance.currentUser!;
              username = nameCtrl.text.trim();

              await usersRef.doc(user.uid).set({
                'username': username,
                'online': true,
                'lastSeen': FieldValue.serverTimestamp(),
              });

              Navigator.pop(context);
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  Future<void> setOnline(bool online) async {
    final user = FirebaseAuth.instance.currentUser!;
    await usersRef.doc(user.uid).update({
      'online': online,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  // 💬 SEND MESSAGE
  void sendMessage() {
    final text = controller.text.trim();
    if (text.isEmpty || username == null) return;

    messagesRef.add({
      'text': text,
      'username': username,
      'uid': FirebaseAuth.instance.currentUser!.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    controller.clear();
    inputFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neon Chat'),
        centerTitle: true,
      ),
      body: Row(
        children: [
          // 👥 LEFT SIDEBAR (USERS)
          Container(
            width: 220,
            color: Colors.black87,
            child: StreamBuilder<QuerySnapshot>(
              stream: usersRef.snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox();
                }

                final users = snapshot.data!.docs;

                return ListView(
                  children: users.map((doc) {
                    final data =
                        doc.data() as Map<String, dynamic>;
                    final isOnline = data['online'] == true;

                    return ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 12,
                        color: isOnline
                            ? Colors.greenAccent
                            : Colors.grey,
                      ),
                      title: Text(
                        data['username'],
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: isOnline
                              ? Colors.greenAccent
                              : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),

          // 💬 CHAT AREA
          Expanded(
            child: Column(
              children: [
                // Messages
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: messagesRef
                        .orderBy('createdAt')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs;

                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data =
                              docs[index].data()
                                  as Map<String, dynamic>;
                          final isMe = data['uid'] == myUid;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin:
                                  const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 14),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Colors.greenAccent
                                        .withOpacity(0.2)
                                    : Colors.white10,
                                borderRadius:
                                    BorderRadius.circular(16),
                              ),
                              child: Text(
                                "${data['username']}: ${data['text']}",
                                style:
                                    const TextStyle(fontSize: 16),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                // Input
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: inputFocusNode,
                          textInputAction:
                              TextInputAction.send,
                          onSubmitted: (_) => sendMessage(),
                          decoration:
                              const InputDecoration(
                            hintText: 'Type message...',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: sendMessage,
                      ),
                    ],
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
