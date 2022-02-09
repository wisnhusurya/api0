import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:api0/api0.dart';
import 'package:api0/utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

//MyData _data;

void main() {
  Api0.config['url'] = 'http://localhost:33299';
  runApp(ChangeNotifierProvider(create: (context) => MyData(), child: MyApp()));
}

class MyData extends ChangeNotifier {
  String _platformVersion = 'Unknown';

  String get platformVersion => _platformVersion;

  set platformVersion(String v) {
    _platformVersion = v;
    notifyListeners();
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  @override
  void initState() {
    super.initState();
  }



  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Consumer<MyData>(builder: (context, data, child) {
      return MyHomePage(title: "API0 Example App}");
    }));
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.title}) : super(key: key);
  final String? title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

enum _Actions { deleteAll }
enum _ItemActions { delete, edit }

class _MyHomePageState extends State<MyHomePage> {
  String? platformVersion = null;
  List<_SecItem> _items = [];

  @override
  void initState() {
    super.initState();

    // _readAll();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String? t_platformVersion;
    if (platformVersion != null) return;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      t_platformVersion = await Api0.platformVersion();
    } on PlatformException {
      t_platformVersion = 'Failed to get platform version.';
    }
    setState(() => platformVersion = t_platformVersion);
  }

  _buttonPress() {
    () async {
      API0Response r = await Api0.apiJSON(API0Method.post, '/api1', {'data': 'data1'});
      if (r.error.code == "OK") {
        _showAlert(r.toString());
      } else {
        _showAlert(r.error.messageText);
      }
    }();
  }

  _button2Press() {
    () async {
      await Api0.secureStorageWrite(key: "testkey1", value: "abc");
      await Api0.secureStorageWrite(key: "testkey1", value: "def");
    }();
  }

  _showAlert(String? t) {
    if (t == null) t = "ERROR";
    Widget okButton = TextButton(
      child: Text("OK"),
      onPressed: () {
        Navigator.of(context).pop();
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("My title"),
      content: Text(t),
      actions: [
        okButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context2) {
        return alert;
      },
    );
  }

  Future<Null> _readAll() async {
    final all = await Api0.secureStorageReadAll();
    List<_SecItem> l = [];
    if (all != null) {
      for (var k in all.keys) {
        l.add(_SecItem(k, all[k]));
      }
    }
    setState(() {
      _items = l;
    });
  }

  void _deleteAll() async {
    await Api0.secureStorageDeleteAll();
    _readAll();
  }

  void _addNewItem() async {
    final String key = _randomValue();
    final String value = _randomValue();

    var r = await Api0.secureStorageWrite(key: key, value: value);
    print(r);
    _readAll();
  }

  @override
  Widget build(BuildContext context) {
    initPlatformState();
    return Scaffold(
        appBar: AppBar(
          title: Consumer<MyData>(builder: (context, data, child) {
            return Text('Plugin ${platformVersion}');
          }),
          actions: <Widget>[
            IconButton(key: Key('write'), onPressed: _button2Press, icon: Icon(Icons.access_alarm)),
            IconButton(key: Key('add_random'), onPressed: _addNewItem, icon: Icon(Icons.add)),
            IconButton(key: Key('api_test'), onPressed: _buttonPress, icon: Icon(Icons.fingerprint)),
            PopupMenuButton<_Actions>(
                key: Key('popup_menu'),
                onSelected: (action) {
                  switch (action) {
                    case _Actions.deleteAll:
                      _deleteAll();
                      break;
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<_Actions>>[
                      PopupMenuItem(
                        key: Key('delete_all'),
                        value: _Actions.deleteAll,
                        child: Text('Delete all'),
                      ),
                    ])
          ],
        ),
        body: ListView.builder(
          itemCount: _items.length,
          itemBuilder: (BuildContext context, int index) => ListTile(
            trailing: PopupMenuButton(
                key: Key('popup_row_$index'),
                onSelected: (_ItemActions action) => _performAction(action, _items[index]),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<_ItemActions>>[
                      PopupMenuItem(
                        value: _ItemActions.delete,
                        child: Text(
                          'Delete',
                          key: Key('delete_row_$index'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ItemActions.edit,
                        child: Text(
                          'Edit',
                          key: Key('edit_row_$index'),
                        ),
                      ),
                    ]),
            title: Text(
              _items[index].value,
              key: Key('title_row_$index'),
            ),
            subtitle: Text(
              _items[index].key,
              key: Key('subtitle_row_$index'),
            ),
          ),
        ));
  }

  Future<Null> _performAction(_ItemActions action, _SecItem item) async {
    switch (action) {
      case _ItemActions.delete:
        await Api0.secureStorageDelete(key: item.key);
        _readAll();

        break;
      case _ItemActions.edit:
        final result = await showDialog<String>(context: context, builder: (context) => _EditItemWidget(item.value));
        if (result != null) {
          await Api0.secureStorageWrite(key: item.key, value: result);
          _readAll();
        }
        break;
    }
  }

  String _randomValue() {
    final rand = Random();
    final codeUnits = List.generate(20, (index) {
      return rand.nextInt(26) + 65;
    });

    return String.fromCharCodes(codeUnits);
  }
}

class _SecItem {
  _SecItem(this.key, this.value);

  final String key;
  final String value;
}

class _EditItemWidget extends StatelessWidget {
  _EditItemWidget(String text) : _controller = TextEditingController(text: text);

  final TextEditingController _controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit item'),
      content: TextField(
        key: Key('title_field'),
        controller: _controller,
        autofocus: true,
      ),
      actions: <Widget>[
        TextButton(key: Key('cancel'), onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
        TextButton(key: Key('save'), onPressed: () => Navigator.of(context).pop(_controller.text), child: Text('Save')),
      ],
    );
  }
}
