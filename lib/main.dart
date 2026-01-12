import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "YOUR_API_KEY",
      authDomain: "YOUR_PROJECT.firebaseapp.com",
      projectId: "YOUR_PROJECT_ID",
      storageBucket: "YOUR_PROJECT.appspot.com",
      messagingSenderId: "SENDER_ID",
      appId: "APP_ID",
    ),
  );

  await FirebaseAuth.instance.signInAnonymously();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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

class _ChatScreenState extends State<ChatScreen> {
  final messagesRef = FirebaseFirestore.instance.collection('messages');
  final usersRef = FirebaseFirestore.instance.collection('users');

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  bool autoScrollEnabled = true;
  String? username;

  @override
  void initState() {
    super.initState();
    setupUser();
  }

  // ---------------- USER SETUP ----------------

  Future<void> setupUser() async {
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await usersRef.doc(user.uid).get();

    if (!doc.exists) {
      await askUsername();
    } else {
      username = doc['username'];
      setOnlineStatus(true);
    }
  }

  Future<void> askUsername() async {
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Choose username"),
        content: TextField(controller: nameCtrl),
        actions: [
          TextButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;

              final user = FirebaseAuth.instance.currentUser!;
              username = nameCtrl.text.trim();

              await usersRef.doc(user.uid).set({
                'username': username,
                'online': true,
                'lastSeen': FieldValue.serverTimestamp(),
              });

              Navigator.pop(context);
            },
            child: const Text("Join"),
          )
        ],
      ),
    );
  }

  Future<void> setOnlineStatus(bool online) async {
    final user = FirebaseAuth.instance.currentUser!;
    await usersRef.doc(user.uid).update({
      'online': online,
      'lastSeen': FieldValue.serverTimestamp(),
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
    _focusNode.requestFocus();
  }

  // ---------------- AUTO SCROLL ----------------

  void scrollToBottom() {
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Neon Chat"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(
              autoScrollEnabled ? Icons.arrow_downward : Icons.pause,
              color: autoScrollEnabled ? Colors.greenAccent : Colors.grey,
            ),
            tooltip: autoScrollEnabled
                ? "Auto-scroll ON"
                : "Auto-scroll OFF",
            onPressed: () {
              setState(() => autoScrollEnabled = !autoScrollEnabled);
            },
          )
        ],
      ),
      body: Row(
        children: [
          // -------- LEFT SIDEBAR --------
          Container(
            width: 220,
            color: Colors.black87,
            child: StreamBuilder<QuerySnapshot>(
              stream: usersRef.snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();

                return ListView(
                  children: snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final online = data['online'] == true;

                    return ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 10,
                        color: online ? Colors.greenAccent : Colors.grey,
                      ),
                      title: Text(
                        data['username'],
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        online ? "Online" : "Offline",
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              online ? Colors.greenAccent : Colors.grey,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),

          // -------- CHAT AREA --------
          Expanded(
            child: Column(
              children: [
                // MESSAGES
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

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (autoScrollEnabled) scrollToBottom();
                      });

                      final messages = snapshot.data!.docs;

                      return NotificationListener<UserScrollNotification>(
                        onNotification: (notification) {
                          if (notification.direction ==
                              ScrollDirection.forward) {
                            setState(() => autoScrollEnabled = false);
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final data = messages[index].data()
                                as Map<String, dynamic>;

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                "${data['username']}: ${data['text']}",
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),

                // INPUT
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: const TextStyle(color: Colors.greenAccent),
                    decoration: const InputDecoration(
                      hintText: "Type a message...",
                      hintStyle: TextStyle(color: Colors.greenAccent),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => sendMessage(),
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
