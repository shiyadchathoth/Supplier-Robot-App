import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'firebase_options.dart';

class ThemeState extends ChangeNotifier {
  String _theme = 'dark';
  ColorScheme _colorScheme = const ColorScheme.dark();
  SharedPreferences? _prefs;

  ThemeState() {
    SharedPreferences.getInstance().then((value) {
      _prefs = value;
      _theme = (_prefs?.getBool('darkMode') ?? true) ? 'dark' : 'light';
      notifyListeners();
    });
  }

  String get theme => _theme;
  ColorScheme get colorScheme => _colorScheme;

  setTheme(String theme) {
    _theme = theme;
    _colorScheme =
        theme == 'dark' ? const ColorScheme.dark() : const ColorScheme.light();
    notifyListeners();
    _prefs?.setBool('darkMode', theme == 'dark');
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => ThemeState())],
        child: Consumer<ThemeState>(
            builder: (context, theme, child) => MaterialApp(
                  title: 'Supplier Robot Client',
                  initialRoute: '/',
                  routes: {
                    '/': (context) =>
                        const MyHomePage(title: 'Supplier Robot Client'),
                    '/settings': (context) => const SettingsPage(),
                    '/about': (context) => const AboutPage(),
                  },
                  theme: ThemeData(
                      primarySwatch: Colors.amber,
                      useMaterial3: true,
                      colorScheme: theme.theme == 'dark'
                          ? const ColorScheme.dark()
                          : const ColorScheme.light(),
                      bottomNavigationBarTheme:
                          const BottomNavigationBarThemeData(
                              enableFeedback: true,
                              backgroundColor: Colors.black,
                              selectedItemColor: Colors.black,
                              unselectedItemColor: Colors.black)
                      // primarySwatch: Color.fromARGB(a, r, g, b)
                      ),
                )));
  }
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('About')),
        body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Center(
                  child: Text('//TODO',
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                          fontSize: 25.0))),
            ]));
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool dbConnectionState = true;
  bool darkMode = false;
  @override
  Widget build(BuildContext context) {
    darkMode = Provider.of<ThemeState>(context).theme == 'dark';
    return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          children: [
            ListTile(
              title: const Text("Dark mode"),
              trailing: Switch(
                  value: darkMode,
                  onChanged: (bool newValue) {
                    setState(() {
                      darkMode = newValue;
                    });
                    Provider.of<ThemeState>(context, listen: false)
                        .setTheme(darkMode ? 'dark' : 'light');
                    // return value;
                  }),
            ),
          ],
        ));
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum Commands {
  forward,
  backward,
  left,
  right,
  stop,
  gototable,
  gotokitchen,
  talk,
  stoptalk,
}

const commandChar = {
  Commands.forward: 'B',
  Commands.backward: 'A',
  Commands.left: 'D',
  Commands.right: 'E',
  Commands.stop: 'C',
  Commands.gotokitchen: 'K',
  Commands.gototable: 'T',
  Commands.talk: 'W',
  Commands.stoptalk: 'R',
};

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  bool dbConnectionState = true;
  bool _isScanning = false;
  String _devAddr = '';
  String _connectingToAddr = '';
  BluetoothConnection? _connection;
  FirebaseApp? firebaseApp;
  FirebaseFirestore? firestore;
  Map<String, BluetoothDevice> devices = {};
  FlutterTts tts = FlutterTts();
  bool isChanged = true;
  // ignore: prefer_final_fields
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 500),
    vsync: this,
  );

  void _ledOn() {
    _connection?.output.add(ascii.encode("1"));
  }

  void _sendBluetooth(String s) {
    _connection?.output.add(ascii.encode(s));
  }

  void _ledOff() {
    _connection?.output.add(ascii.encode("0"));
  }

  Future<bool> connectTodevice(String addr) async {
    if (devices[addr] == null) return false;

    setState(() {
      _devAddr = '';
    });

    _connection = await BluetoothConnection.toAddress(addr);
    _devAddr = addr;
    _connection?.input?.listen((event) {
      print(ascii.decode(event));
    });
    debugPrint('Connected!');
    setState(() {});

    return true;
  }

  void scanBluetooth() async {
    devices.clear();
    await FlutterBluetoothSerial.instance.cancelDiscovery();
    setState(() {
      _isScanning = true;
      _controller.repeat();
    });
    FlutterBluetoothSerial.instance
        .getBondedDevices()
        .asStream()
        .listen((devicesList) {
      for (final device in devicesList) {
        debugPrint('[bonded] name: ${device.name}, ${device.type}');
        setState(() {
          devices.addAll({device.address: device});
        });
      }
    }).onDone(() {
      debugPrint('Done scanning bonded devices');
    });
    FlutterBluetoothSerial.instance.startDiscovery().listen((event) {
      debugPrint('name: ${event.device.name}, ${event.device.type}');
      setState(() {
        devices.addAll({event.device.address: event.device});
      });
    }).onDone(() {
      setState(() {
        _controller.reset();
        _isScanning = false;
      });
      debugPrint('Done scanning bluetooth');
    });
  }

  @override
  void initState() {
    super.initState();

    FlutterBluetoothSerial.instance
        .requestEnable()
        .then((_) => scanBluetooth());
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .then((value) {
      setState(() {
        firebaseApp = value;
        firestore = FirebaseFirestore.instance;
      });
      firestore
          ?.collection('command')
          .doc('move-to')
          .snapshots()
          .listen((event) {
        if (!event.exists) return;
        debugPrint("data: ${event.data()}");
        final direction = event.data()?["direction"] ?? '';
        if (direction == "stop") {
          _sendBluetooth(commandChar[Commands.stop]!);
        } else if (direction == "grandmaroom") {
          _sendBluetooth(commandChar[Commands.gotokitchen]!);
        } else if (direction == "hall") {
          _sendBluetooth(commandChar[Commands.gototable]!);
        }

        try {
          firestore
              ?.collection('command')
              .doc('move-to')
              .update({direction: '__accepted__'});
        } catch (_) {}
        ;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
        initialIndex: 1,
        length: 3,
        child: Scaffold(
          bottomNavigationBar: const TabBar(
              indicatorWeight: 5,
              indicatorSize: TabBarIndicatorSize.label,
              splashBorderRadius: BorderRadius.all(Radius.circular(50.0)),
              tabs: [
                Tab(icon: Icon(Icons.control_camera), text: "Controls"),
                Tab(icon: Icon(Icons.comment), text: "Commands"),
                Tab(icon: Icon(Icons.bluetooth), text: "Bluetooth"),
                // Tab(icon: Icon(Icons.data_object), text: "DB"),
              ]),
          appBar: AppBar(

              // elevation: 0,
              title: Text(widget.title),
              actions: [
                PopupMenuButton(
                    constraints:
                        const BoxConstraints(minWidth: 200, maxWidth: 200),
                    onSelected: (val) {
                      if (val == 0) {
                        Navigator.of(context).pushNamed('/settings');
                      } else if (val == 1) {
                        Navigator.of(context).pushNamed('/about');
                      }
                    },
                    itemBuilder: (context) => [
                          const PopupMenuItem(
                              value: 0, child: Text('Settings')),
                          const PopupMenuItem(
                            value: 1,
                            child: Text('About'),
                          )
                        ]),
              ]),
          body: TabBarView(children: [
            Padding(
                padding: const EdgeInsets.all(2.0),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Center(
                          // Center is a layout widget. It takes a single child and positions it
                          // in the middle of the parent.
                          child: Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Center(
                                child: Listener(
                                    onPointerUp: (_) => _sendBluetooth(
                                        commandChar[Commands.stop]!),
                                    onPointerDown: (_) => _sendBluetooth(
                                        commandChar[Commands.forward]!),
                                    child: IconButton(
                                        iconSize: 100.0,
                                        padding: const EdgeInsets.all(10.0),
                                        icon: const Icon(
                                          Icons.keyboard_arrow_up,
                                        ),
                                        onPressed: () {}))),
                            Center(
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                  Listener(
                                      onPointerUp: (_) => _sendBluetooth(
                                          commandChar[Commands.stop]!),
                                      onPointerDown: (_) => _sendBluetooth(
                                          commandChar[Commands.left]!),
                                      child: IconButton(
                                          iconSize: 80.0,
                                          // color: Colors.orange,
                                          padding: const EdgeInsets.all(15.0),
                                          icon: const Icon(
                                              Icons.keyboard_arrow_left),
                                          onPressed: () {})),
                                  IconButton(
                                      iconSize: 80.0,
                                      // color: Colors.orange,
                                      padding: const EdgeInsets.all(15.0),
                                      icon: const Icon(Icons.circle),
                                      onPressed: () => _sendBluetooth(
                                          commandChar[Commands.stop]!)),
                                  Listener(
                                      onPointerUp: (_) => _sendBluetooth(
                                          commandChar[Commands.stop]!),
                                      onPointerDown: (_) => _sendBluetooth(
                                          commandChar[Commands.right]!),
                                      child: IconButton(
                                          iconSize: 80.0,
                                          // color: Colors.orange,
                                          padding: const EdgeInsets.all(15.0),
                                          icon: const Icon(
                                              Icons.keyboard_arrow_right),
                                          onPressed: () {})),
                                ])),
                            Center(
                                child: Listener(
                                    onPointerUp: (_) => _sendBluetooth(
                                        commandChar[Commands.stop]!),
                                    onPointerDown: (_) => _sendBluetooth(
                                        commandChar[Commands.backward]!),
                                    child: IconButton(
                                        iconSize: 80.0,
                                        // color: Colors.orange,
                                        padding: const EdgeInsets.all(15.0),
                                        icon: const Icon(
                                            Icons.keyboard_arrow_down),
                                        onPressed: () {}))),
                          ],
                        ),
                      )),
                    ])),

            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Divider(
                color: Colors.transparent,
              ),
              ListTile(
                title: const Text('Go to table'),
                titleTextStyle:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 25),
                textColor: Color.fromARGB(255, 255, 255, 255),
                leading: const Icon(
                  Icons.table_bar,
                  size: 25.0,
                ),
                iconColor: Color.fromARGB(255, 255, 255, 255),
                onTap: () => _sendBluetooth(commandChar[Commands.gototable]!),
              ),
              const Divider(
                color: Colors.transparent,
              ),
              ListTile(
                title: const Text('Go to Kitchen'),
                titleTextStyle:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 25),
                textColor: Color.fromARGB(255, 255, 255, 255),
                leading: const Icon(
                  Icons.kitchen,
                  size: 25.0,
                ),
                iconColor: Color.fromARGB(255, 255, 255, 255),
                onTap: () => _sendBluetooth(commandChar[Commands.gotokitchen]!),
              ),
              const Divider(
                color: Colors.transparent,
              ),
              ListTile(
                  title: const Text('Stop'),
                  titleTextStyle:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 25.0),
                  leading: const Icon(
                    Icons.stop_circle,
                    size: 28.0,
                  ),
                  onTap: () => _sendBluetooth(commandChar[Commands.stop]!)),
              const Divider(color: Colors.transparent),
              ListTile(
                title: const Text('Talk'),
                titleTextStyle:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 25),
                leading: const Icon(
                  Icons.mic,
                  size: 25.0,
                ),
                onTap: () => _sendBluetooth(commandChar[Commands.talk]!),
              ),
              const Divider(
                color: Colors.transparent,
              ),
            ]),
            // ])),
            // }),
            Consumer<ThemeState>(
                builder: (context, theme, child) => Scaffold(
                    floatingActionButton: RotationTransition(
                      turns: CurvedAnimation(
                        parent: _controller,
                        curve: Curves.linear,
                      ),
                      child: IconButton(
                          color: _isScanning ? Colors.lightBlue : null,
                          padding: const EdgeInsets.all(15.0),
                          onPressed: scanBluetooth,
                          iconSize: 30.0,
                          icon: const Icon(Icons.radar)),
                    ),
                    body: ListView.builder(
                        itemCount: devices.length,
                        itemBuilder: (context, i) {
                          final device = devices[devices.keys.elementAt(i)]!;
                          return ListTile(
                              onTap: () async {
                                if (_devAddr != device.address) {
                                  try {
                                    setState(() {
                                      _connectingToAddr = device.address;
                                    });
                                    if (await connectTodevice(device.address) ==
                                        true) {
                                      _connectingToAddr = '';
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'Connected to ${device.name}!')));
                                    } else {
                                      setState(() {
                                        _connectingToAddr = '';
                                      });

                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'Connecting to ${device.name} failed :(')));
                                    }
                                  } on PlatformException catch (e) {
                                    setState(() {
                                      _connectingToAddr = '';
                                    });

                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Error connecting to ${device.name} \n[${e.code}] ${e.message}')));
                                  } catch (e) {
                                    try {
                                      setState(() {
                                        _connectingToAddr = '';
                                      });

                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'Error connecting to ${device.name}: ${e.toString()}')));
                                    } catch (_) {/*bruh*/}
                                  }
                                } else {
                                  try {
                                    await _connection?.finish();
                                    _connection?.dispose();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Disconnected ${device.name}!')));
                                    _devAddr = '';
                                    setState(() {});
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(e.toString())));
                                  }
                                }
                              },
                              tileColor: device.address == _devAddr
                                  ? Colors.lightBlue.withOpacity(0.25)
                                  : null,
                              title: Text(
                                device.name ?? '<no name>',
                                style: device.name == null
                                    ? const TextStyle(color: Colors.grey)
                                    : null,
                              ),
                              subtitle: Text(device.address),
                              trailing: _devAddr == device.address
                                  ? const Icon(Icons.bluetooth_connected)
                                  : (_connectingToAddr == device.address
                                      ? CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation<
                                                  Color>(
                                              Colors.grey.withOpacity(0.75)),
                                        )
                                      : null));
                        }))),
          ]),
        ));
  }
}
