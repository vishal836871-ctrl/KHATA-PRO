import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await Firebase.initializeApp(); await FirebaseAuth.instance.signInAnonymously(); } catch(e){}
  runApp(ChangeNotifierProvider(create: (_) => KhataProvider(), child: const KhataApp()));
}

class KhataApp extends StatelessWidget {
  const KhataApp({super.key});
  @override Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mummy Ka Khata PRO',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal, textTheme: GoogleFonts.poppinsTextTheme()),
      home: const HomePage(),
    );
  }
}

class KhataEntry {
  String id, name, note; int amount; bool isUdhar; DateTime date;
  KhataEntry({required this.id, required this.name, required this.amount, required this.isUdhar, required this.date, this.note=''});
}

class KhataProvider extends ChangeNotifier {
  List<KhataEntry> entries = [];
  String familyId = "MUMMY-FAMILY-001";
  SpeechToText speech = SpeechToText();
  bool isListening = false;
  String voiceText = "";

  KhataProvider(){ loadData(); }

  void loadData(){
    try{
      FirebaseFirestore.instance.collection('khata_pro').where('familyId', isEqualTo: familyId).snapshots().listen((snap){
        entries = snap.docs.map((d){
          var data = d.data();
          return KhataEntry(id: d.id, name: data['name']??'', amount: data['amount']??0, isUdhar: data['isUdhar']??true, date: (data['date'] as Timestamp).toDate(), note: data['note']??'');
        }).toList();
        entries.sort((a,b)=>b.date.compareTo(a.date));
        notifyListeners();
      });
    }catch(e){}
  }

  Future addEntry(String name, int amount, bool isUdhar, String note) async {
    final e = KhataEntry(id: DateTime.now().toString(), name: name, amount: amount, isUdhar: isUdhar, date: DateTime.now(), note: note);
    entries.insert(0, e); notifyListeners();
    try{
      await FirebaseFirestore.instance.collection('khata_pro').add({
        'familyId': familyId, 'name': name, 'amount': amount, 'isUdhar': isUdhar, 'note': note, 'date': Timestamp.now()
      });
    }catch(_){}
  }

  int get totalUdhar => entries.where((e)=>e.isUdhar).fold(0, (s,e)=>s+e.amount);
  int get totalJama => entries.where((e)=>!e.isUdhar).fold(0, (s,e)=>s+e.amount);

  Future startVoice(Function(String) onResult) async {
    bool avail = await speech.initialize();
    if(avail){
      isListening = true; notifyListeners();
      speech.listen(onResult: (res){ voiceText = res.recognizedWords; onResult(voiceText); notifyListeners(); });
    }
  }
  void stopVoice(){ speech.stop(); isListening=false; notifyListeners(); }

  Map<String, int> get chartData {
    Map<String, int> map = {};
    for(var e in entries){ map[e.name] = (map[e.name]??0) + e.amount; }
    return map;
  }
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=> _HomePageState(); }
class _HomePageState extends State<HomePage> {
  int idx=0;
  @override Widget build(BuildContext context){
    var prov = context.watch<KhataProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text("Mummy Ka Khata PRO 💰"), actions: [
        IconButton(onPressed: ()=> Share.share("Mummy Ka Khata PRO - Family ID: ${prov.familyId}"), icon: const Icon(Icons.share)),
        Center(child: Padding(padding: EdgeInsets.only(right:12), child: Text(prov.familyId, style: TextStyle(fontSize:10)))),
      ]),
      body: [KhataList(), StatsPage(), FamilyPage()][idx],
      bottomNavigationBar: NavigationBar(selectedIndex: idx, onDestinationSelected: (i)=>setState(()=>idx=i), destinations: const [
        NavigationDestination(icon: Icon(Icons.book), label: "Khata"),
        NavigationDestination(icon: Icon(Icons.bar_chart), label: "Graph"),
        NavigationDestination(icon: Icon(Icons.family_restroom), label: "Family"),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: ()=> showAddDialog(context), label: const Text("Add"), icon: const Icon(Icons.add)),
    );
  }
}

class KhataList extends StatelessWidget {
  @override Widget build(BuildContext context){
    var p = context.watch<KhataProvider>();
    return Column(children: [
      Card(margin: EdgeInsets.all(12), child: Padding(padding: EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        Column(children: [Text("Udhar Diya", style: TextStyle(color: Colors.red)), Text("₹${p.totalUdhar}", style: TextStyle(fontSize:22, fontWeight: FontWeight.bold, color: Colors.red))]),
        Column(children: [Text("Jama Hua", style: TextStyle(color: Colors.green)), Text("₹${p.totalJama}", style: TextStyle(fontSize:22, fontWeight: FontWeight.bold, color: Colors.green))]),
      ]))),
      Expanded(child: p.entries.isEmpty? Center(child: Text("Koi entry nahi, Add dabao ya Voice bolo!")) : ListView.builder(itemCount: p.entries.length, itemBuilder: (_,i){
        var e = p.entries[i];
        return ListTile(leading: CircleAvatar(backgroundColor: e.isUdhar? Colors.red.shade100: Colors.green.shade100, child: Icon(e.isUdhar? Icons.arrow_upward: Icons.arrow_downward, color: e.isUdhar? Colors.red: Colors.green)), title: Text(e.name, style: TextStyle(fontWeight: FontWeight.bold)), subtitle: Text("${DateFormat('dd MMM').format(e.date)} • ${e.note}"), trailing: Text("₹${e.amount}", style: TextStyle(fontWeight: FontWeight.bold, fontSize:18, color: e.isUdhar? Colors.red: Colors.green)));
      }))
    ]);
  }
}

class StatsPage extends StatelessWidget {
  @override Widget build(BuildContext context){
    var data = context.watch<KhataProvider>().chartData;
    if(data.isEmpty) return Center(child: Text("Graph ke liye data nahi"));
    var spots = data.entries.toList();
    return Padding(padding: EdgeInsets.all(16), child: Column(children: [
      Text("Top Log - Kitna Udhar", style: TextStyle(fontSize:18, fontWeight: FontWeight.bold)),
      SizedBox(height: 20),
      SizedBox(height: 250, child: BarChart(BarChartData(barGroups: List.generate(spots.length.clamp(0,5), (i)=> BarChartGroupData(x: i, barRods: [BarChartRodData(toY: spots[i].value.toDouble(), color: Colors.teal)] )), titlesData: FlTitlesData(show: true, bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v,_)=> Text(spots[v.toInt()].key.substring(0, spots[v.toInt()].key.length>4?4:spots[v.toInt()].key.length), style: TextStyle(fontSize:10)))))))),
    ]));
  }
}

class FamilyPage extends StatelessWidget {
  @override Widget build(BuildContext context){
    var p = context.watch<KhataProvider>();
    return Center(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.family_restroom, size: 80, color: Colors.teal),
      SizedBox(height: 20),
      Text("Family Sharing ID", style: TextStyle(fontSize:20, fontWeight: FontWeight.bold)),
      SizedBox(height: 10),
      SelectableText(p.familyId, style: TextStyle(fontSize:22, letterSpacing: 2, fontWeight: FontWeight.bold, color: Colors.teal)),
      SizedBox(height: 10),
      Text("Is ID ko ghar ke sabhi logon me share karo.\nSabka khata ek jagah sync hoga.", textAlign: TextAlign.center),
      SizedBox(height: 20),
      ElevatedButton.icon(onPressed: ()=> Share.share("Mere Khata PRO me join karo! Family ID: ${p.familyId}"), icon: Icon(Icons.share), label: Text("Share Family ID")),
    ])));
  }
}

void showAddDialog(BuildContext context){
  TextEditingController nameC = TextEditingController();
  TextEditingController amountC = TextEditingController();
  TextEditingController noteC = TextEditingController();
  bool isUdhar = true;
  var prov = context.read<KhataProvider>();

  // Voice parse logic
  void parseVoice(String text){
    text = text.toLowerCase();
    RegExp numReg = RegExp(r'(\d+)');
    var match = numReg.firstMatch(text);
    if(match!=null) amountC.text = match.group(1)!;

    if(text.contains("liya") || text.contains("jama") || text.contains("mila")) isUdhar = false;
    if(text.contains("diya") || text.contains("udhar")) isUdhar = true;

    // name extract - last word before ko
    if(text.contains("ko")){
      var parts = text.split("ko")[0].split(" ");
      if(parts.isNotEmpty) nameC.text = parts[parts.length-1];
    }
  }

  showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx){
    return StatefulBuilder(builder: (ctx, setSt){
      return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left:16, right:16, top:16), child: Consumer<KhataProvider>(builder: (_,pr,__){
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [Text("Nayi Entry", style: TextStyle(fontSize:20, fontWeight: FontWeight.bold)), Spacer(), IconButton(onPressed: () async {
            if(!pr.isListening){ await pr.startVoice((txt){ parseVoice(txt); setSt((){}); }); } else { pr.stopVoice(); }
          }, icon: Icon(pr.isListening? Icons.mic: Icons.mic_none, color: pr.isListening? Colors.red: Colors.teal, size:30)),]),
          if(pr.isListening) Text("Sun raha hu: ${pr.voiceText}", style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic)),
          Text("Bolo: '500 Rupye Ramesh ko diye'"),
          SizedBox(height:10),
          TextField(controller: nameC, decoration: InputDecoration(labelText: "Naam (Ramesh)", border: OutlineInputBorder())),
          SizedBox(height:10),
          TextField(controller: amountC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "Rakam", border: OutlineInputBorder(), prefixText: "₹ ")),
          SizedBox(height:10),
          Row(children: [
            ChoiceChip(label: Text("Udhar Diya"), selected: isUdhar, onSelected: (v)=>setSt(()=>isUdhar=true)),
            SizedBox(width:10),
            ChoiceChip(label: Text("Jama Liya"), selected:!isUdhar, onSelected: (v)=>setSt(()=>isUdhar=false)),
          ]),
          TextField(controller: noteC, decoration: InputDecoration(labelText: "Note (optional)", border: OutlineInputBorder())),
          SizedBox(height:16),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: (){
            if(nameC.text.isNotEmpty && amountC.text.isNotEmpty){
              prov.addEntry(nameC.text, int.tryParse(amountC.text)??0, isUdhar, noteC.text);
              Navigator.pop(ctx);
            }
          }, child: Text("SAVE KARO"))),
          SizedBox(height:20),
        ]);
      }));
    });
  });
}
