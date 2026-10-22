import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'https://qeajxxdydrjcorzohkpo.supabase.co';
const String supabaseKey = 'sb_publishable_YdfCUNwARuyJF1OIDA8EXg_yGUmsJPu';

const Color pageBackground = Color(0xFFF4F7F5);
const Color forestGreen = Color(0xFF167D58);
const Color darkGreen = Color(0xFF18352A);
const Color cardBorder = Color(0xFFE5ECE7);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(const LandslideApp());
}

class LandslideApp extends StatelessWidget {
  const LandslideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TerraWatch - Landslide Monitoring',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: pageBackground,
        colorScheme: ColorScheme.fromSeed(seedColor: forestGreen),
        appBarTheme: const AppBarTheme(
          backgroundColor: pageBackground,
          foregroundColor: darkGreen,
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final supabase = Supabase.instance.client;
  Timer? _pollingTimer;

  List<Map<String, dynamic>> allReadings = [];
  List<Map<String, dynamic>> mlPredictions = [];
  Map<String, dynamic>? nodeGIS;

  String? selectedNode;
  bool loading = true;
  bool refreshing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    loadDashboardData();
    // Continuous polling every 3 seconds to keep sync with Python simulator
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      loadDashboardData(isBackground: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> loadDashboardData({bool isBackground = false}) async {
    if (refreshing && !isBackground) return;

    if (!isBackground) {
      setState(() {
        loading = allReadings.isEmpty;
        refreshing = true;
        error = null;
      });
    }

    try {
      // 1. Fetch live sensor readings
      final sensorResult = await supabase
          .from('sensor_readings')
          .select()
          .order('recorded_at', ascending: false)
          .limit(200);

      final sensorData = List<Map<String, dynamic>>.from(sensorResult);
      sensorData.sort((a, b) => timestamp(a).compareTo(timestamp(b)));

      // Determine active node
      final availableNodes =
          sensorData
              .map((r) => r['node_id']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      String? activeNode = selectedNode;
      if (activeNode == null || !availableNodes.contains(activeNode)) {
        activeNode = availableNodes.isEmpty ? null : availableNodes.first;
      }

      // 2. Fetch ML predictions & GIS metadata for active node
      List<Map<String, dynamic>> mlData = [];
      Map<String, dynamic>? gisData;

      if (activeNode != null) {
        final mlResult = await supabase
            .from('ml_predictions')
            .select()
            .eq('node_id', activeNode)
            .order('created_at', ascending: false)
            .limit(20);
        mlData = List<Map<String, dynamic>>.from(mlResult);

        final gisResult = await supabase
            .from('node_gis_features')
            .select()
            .eq('node_id', activeNode)
            .maybeSingle();
        gisData = gisResult;
      }

      if (!mounted) return;

      setState(() {
        allReadings = sensorData;
        mlPredictions = mlData;
        nodeGIS = gisData;
        selectedNode = activeNode;
        loading = false;
        refreshing = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        refreshing = false;
        if (!isBackground) error = e.toString();
      });
    }
  }

  DateTime timestamp(Map<String, dynamic> row) {
    return DateTime.tryParse(row['recorded_at']?.toString() ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  double number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<String> get nodeNames {
    final names =
        allReadings
            .map((r) => r['node_id']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return names;
  }

  List<Map<String, dynamic>> get nodeReadings {
    return allReadings
        .where((r) => r['node_id']?.toString() == selectedNode)
        .toList();
  }

  Map<String, dynamic>? get latestSensor {
    final rows = nodeReadings;
    return rows.isEmpty ? null : rows.last;
  }

  Map<String, dynamic>? get latestML {
    return mlPredictions.isEmpty ? null : mlPredictions.first;
  }

  Color riskColor(String risk) {
    switch (risk.toUpperCase()) {
      case 'CRITICAL':
      case 'HIGH':
        return const Color(0xFFCC3D48);
      case 'WARNING':
      case 'MEDIUM':
        return const Color(0xFFD1851C);
      default:
        return forestGreen;
    }
  }

  double? get tiltRate {
    final rows = nodeReadings;
    if (rows.length < 2) return null;

    final previous = rows[rows.length - 2];
    final current = rows.last;

    final elapsedMinutes =
        timestamp(current).difference(timestamp(previous)).inMilliseconds /
        60000.0;

    if (elapsedMinutes <= 0) return null;

    return (number(current['tilt_change']) - number(previous['tilt_change'])) /
        elapsedMinutes;
  }

  String formatTime(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'Time unavailable';

    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}:'
        '${d.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 650;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.terrain_rounded, color: forestGreen, size: 30),
            SizedBox(width: 10),
            Text(
              'TerraWatch',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        actions: [
          if (refreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Refresh readings',
              onPressed: () => loadDashboardData(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      endDrawer: _buildGISDrawer(),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null && allReadings.isEmpty
          ? _errorView()
          : allReadings.isEmpty
          ? _emptyView()
          : RefreshIndicator(
              onRefresh: () => loadDashboardData(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(compact ? 16 : 28),
                children: [
                  const Text(
                    'LANDSLIDE EARLY WARNING SYSTEM',
                    style: TextStyle(
                      color: forestGreen,
                      fontSize: 11,
                      letterSpacing: 1.7,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Monitoring dashboard',
                    style: TextStyle(
                      fontSize: compact ? 26 : 33,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: darkGreen,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hyperlocal fusion of real-time telemetry, '
                    'geospatial layers, and predictive ML scoring.',
                    style: TextStyle(color: Colors.grey.shade700, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  _buildNodeSelector(compact),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    _inlineError(),
                  ],
                  if (latestSensor != null) ...[
                    const SizedBox(height: 18),
                    _buildRiskSection(compact),
                    const SizedBox(height: 18),
                    _buildMetricGrid(),
                    const SizedBox(height: 22),
                    _buildTrendSection(),
                    const SizedBox(height: 18),
                    _buildMLPredictionHistory(),
                    const SizedBox(height: 18),
                    _buildRecentReadings(),
                  ] else ...[
                    const SizedBox(height: 30),
                    const Center(
                      child: Text('No telemetry available for this node.'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Prototype monitoring interface. '
                    'Sensor thresholds and alert rules require '
                    'field validation before operational use.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildNodeSelector(bool compact) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: forestGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.sensors_rounded, color: forestGreen),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monitoring node',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: darkGreen,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Select sensor station',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          DropdownButton<String>(
            value: selectedNode,
            underline: const SizedBox(),
            borderRadius: BorderRadius.circular(12),
            items: nodeNames.map((node) {
              return DropdownMenuItem<String>(
                value: node,
                child: Text(
                  node,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
            onChanged: (node) {
              setState(() => selectedNode = node);
              loadDashboardData();
            },
          ),
          const SizedBox(width: 8),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'View Terrain GIS Data',
              icon: const Icon(Icons.layers_outlined, color: forestGreen),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskSection(bool compact) {
    final hwRisk = latestSensor?['risk_level']?.toString() ?? 'NORMAL';
    final mlRisk = latestML?['predicted_risk']?.toString() ?? 'PENDING';
    final mlConfidence = latestML?['model_confidence'] != null
        ? ((number(latestML!['model_confidence'])) * 100).toStringAsFixed(1)
        : null;

    if (compact) {
      return Column(
        children: [
          _buildRiskBanner(
            title: 'HARDWARE RULE-BASED STATUS',
            risk: hwRisk,
            subtitle:
                '$selectedNode · ${formatTime(latestSensor?['recorded_at'])}',
            icon: Icons.speed_rounded,
          ),
          const SizedBox(height: 12),
          _buildRiskBanner(
            title: 'ML PREDICTED RISK TIER',
            risk: mlRisk,
            subtitle: mlConfidence != null
                ? 'Model Confidence: $mlConfidence% · ${formatTime(latestML?['created_at'])}'
                : 'Awaiting model inference...',
            icon: Icons.psychology_rounded,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _buildRiskBanner(
            title: 'HARDWARE RULE-BASED',
            risk: hwRisk,
            subtitle:
                '$selectedNode · ${formatTime(latestSensor?['recorded_at'])}',
            icon: Icons.speed_rounded,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildRiskBanner(
            title: 'ML PREDICTED RISK',
            risk: mlRisk,
            subtitle: mlConfidence != null
                ? 'Confidence: $mlConfidence%'
                : 'Awaiting inference',
            icon: Icons.psychology_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildRiskBanner({
    required String title,
    required String risk,
    required String subtitle,
    required IconData icon,
  }) {
    final color = riskColor(risk);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  risk.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricGrid() {
    final reading = latestSensor!;
    final rate = tiltRate;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 600
            ? 2
            : constraints.maxWidth < 950
            ? 3
            : 6;

        const gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: cardWidth,
              child: _metricCard(
                title: 'Soil moisture',
                value: '${number(reading['moisture']).toStringAsFixed(1)}%',
                subtitle: 'Capacitive probe',
                icon: Icons.water_drop_outlined,
                color: Colors.blue,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _metricCard(
                title: 'Tilt change',
                value: '${number(reading['tilt_change']).toStringAsFixed(2)}°',
                subtitle: 'Inclination shift',
                icon: Icons.screen_rotation_alt_rounded,
                color: Colors.deepPurple,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _metricCard(
                title: 'Tilt rate',
                value: rate == null
                    ? 'N/A'
                    : '${rate >= 0 ? '+' : ''}${rate.toStringAsFixed(3)}°/min',
                subtitle: rate == null
                    ? 'Need 2 timestamps'
                    : 'Angular velocity',
                icon: Icons.trending_up_rounded,
                color: Colors.deepOrange,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _metricCard(
                title: 'Rain intensity',
                value:
                    '${number(reading['rainfall_intensity']).toStringAsFixed(1)} mm',
                subtitle: 'Daily intensity proxy',
                icon: Icons.grain_rounded,
                color: Colors.teal,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _metricCard(
                title: '7-Day Rain',
                value:
                    '${number(reading['rainfall_7day']).toStringAsFixed(1)} mm',
                subtitle: 'Antecedent saturation',
                icon: Icons.calendar_view_week_rounded,
                color: Colors.indigo,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _metricCard(
                title: 'Pore pressure',
                value:
                    '${number(reading['pore_pressure']).toStringAsFixed(1)} kPa',
                subtitle: 'Hydrostatic pressure',
                icon: Icons.compress_rounded,
                color: Colors.brown,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: darkGreen,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 10,
              height: 1.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTrendSection() {
    final rows = nodeReadings;

    return _sectionCard(
      title: 'Slope movement trend',
      subtitle: 'Recorded tilt-change values in chronological order',
      icon: Icons.show_chart_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.length >= 2)
            SizedBox(
              height: 230,
              width: double.infinity,
              child: CustomPaint(
                painter: TrendPainter(
                  values: rows.map((r) => number(r['tilt_change'])).toList(),
                ),
              ),
            )
          else
            const SizedBox(
              height: 150,
              child: Center(
                child: Text('More readings are needed to display trend.'),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: forestGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text('Tilt change', style: TextStyle(fontSize: 12)),
              ),
              Text(
                '${rows.length} loaded records',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMLPredictionHistory() {
    return _sectionCard(
      title: 'ML Risk Evaluation Log',
      subtitle: 'Dynamic Random Forest scoring from ml_predictions',
      icon: Icons.batch_prediction_rounded,
      child: mlPredictions.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No ML risk evaluations recorded yet.'),
            )
          : Column(
              children: mlPredictions.take(6).map((prediction) {
                final risk = prediction['predicted_risk']?.toString() ?? 'LOW';
                final color = riskColor(risk);
                final confidence = prediction['model_confidence'] != null
                    ? ((number(prediction['model_confidence'])) * 100)
                          .toStringAsFixed(1)
                    : '--';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: color.withValues(alpha: 0.16)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined, color: color, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'RISK: ${risk.toUpperCase()}',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              formatTime(prediction['created_at']),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Text(
                          '$confidence% conf',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: darkGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildRecentReadings() {
    final recent = nodeReadings.reversed.take(8).toList();

    return _sectionCard(
      title: 'Recent sensor readings',
      subtitle: 'Latest telemetry packets received',
      icon: Icons.history_rounded,
      child: recent.isEmpty
          ? const Text('No recent readings.')
          : Column(children: recent.map(_readingRow).toList()),
    );
  }

  Widget _readingRow(Map<String, dynamic> reading) {
    final risk = reading['risk_level']?.toString() ?? 'NORMAL';
    final color = riskColor(risk);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pageBackground,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatTime(reading['recorded_at']),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tilt: ${number(reading['tilt_change']).toStringAsFixed(2)}°'
                  ' · Moist: ${number(reading['moisture']).toStringAsFixed(1)}%'
                  ' · Rain: ${number(reading['rainfall_intensity']).toStringAsFixed(1)} mm'
                  ' · Pore: ${number(reading['pore_pressure']).toStringAsFixed(1)} kPa',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            risk,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGISDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: darkGreen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(
                  Icons.terrain_rounded,
                  size: 36,
                  color: Colors.white,
                ),
                const SizedBox(height: 8),
                Text(
                  '$selectedNode GIS Parameters',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Static geospatial context layers',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          if (nodeGIS != null) ...[
            _drawerTile(
              'Elevation',
              '${number(nodeGIS!['elevation_m']).toStringAsFixed(0)} m',
            ),
            _drawerTile(
              'Slope Angle',
              '${number(nodeGIS!['slope_angle_deg']).toStringAsFixed(1)}°',
            ),
            _drawerTile(
              'Curvature',
              '${number(nodeGIS!['curvature']).toStringAsFixed(2)}',
            ),
            _drawerTile(
              'Soil Type',
              nodeGIS!['soil_type']?.toString() ?? 'Unknown',
            ),
            _drawerTile(
              'Soil Depth',
              '${number(nodeGIS!['soil_depth_m']).toStringAsFixed(1)} m',
            ),
            _drawerTile(
              'Lithology',
              nodeGIS!['lithology']?.toString() ?? 'Unknown',
            ),
            _drawerTile(
              'Land Use',
              nodeGIS!['land_use']?.toString() ?? 'Unknown',
            ),
            _drawerTile(
              'NDVI Index',
              '${number(nodeGIS!['ndvi']).toStringAsFixed(2)}',
            ),
            _drawerTile(
              'Distance to Stream',
              '${number(nodeGIS!['distance_to_stream_m']).toStringAsFixed(0)} m',
            ),
            _drawerTile(
              'Distance to Road',
              '${number(nodeGIS!['distance_to_road_m']).toStringAsFixed(0)} m',
            ),
            _drawerTile(
              'Annual Rainfall',
              '${number(nodeGIS!['annual_rainfall_mm']).toStringAsFixed(0)} mm',
            ),
          ] else
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No static GIS records found for this node station.'),
            ),
        ],
      ),
    );
  }

  Widget _drawerTile(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(
        label,
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),
      trailing: Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: darkGreen,
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: forestGreen, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: darkGreen,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _inlineError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Refresh failed. Displaying previously loaded readings.',
        style: TextStyle(color: Colors.deepOrange),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Unable to load sensor data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => loadDashboardData(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sensors_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No sensor readings found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => loadDashboardData(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class TrendPainter extends CustomPainter {
  final List<double> values;

  TrendPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 50 || size.height <= 35) {
      return;
    }

    const left = 38.0;
    const right = 8.0;
    const top = 14.0;
    const bottom = 25.0;

    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final spread = maxValue - minValue;
    final range = spread == 0 ? 1.0 : spread;

    final gridPaint = Paint()
      ..color = const Color(0xFFE7EEE9)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = top + chartHeight * i / 4;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );

      final labelValue = maxValue - range * i / 4;
      final label = TextPainter(
        text: TextSpan(
          text: labelValue.toStringAsFixed(1),
          style: const TextStyle(color: Colors.grey, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: left - 3);

      label.paint(canvas, Offset(0, y - 6));
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = left + chartWidth * i / (values.length - 1);
      final y =
          top + chartHeight - ((values[i] - minValue) / range) * chartHeight;
      points.add(Offset(x, y));
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }

    final areaPath = Path()
      ..moveTo(points.first.dx, top + chartHeight)
      ..lineTo(points.first.dx, points.first.dy);

    for (final point in points.skip(1)) {
      areaPath.lineTo(point.dx, point.dy);
    }

    areaPath
      ..lineTo(points.last.dx, top + chartHeight)
      ..close();

    final chartRect = Rect.fromLTWH(left, top, chartWidth, chartHeight);

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          colors: [
            forestGreen.withValues(alpha: 0.20),
            forestGreen.withValues(alpha: 0.01),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(chartRect),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = forestGreen
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (final point in [points.first, points.last]) {
      canvas.drawCircle(point, 4, Paint()..color = forestGreen);
    }

    final startLabel = TextPainter(
      text: const TextSpan(
        text: 'Older',
        style: TextStyle(color: Colors.grey, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    startLabel.paint(canvas, Offset(left, size.height - 16));

    final endLabel = TextPainter(
      text: const TextSpan(
        text: 'Latest',
        style: TextStyle(color: Colors.grey, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    endLabel.paint(
      canvas,
      Offset(size.width - right - endLabel.width, size.height - 16),
    );
  }

  @override
  bool shouldRepaint(covariant TrendPainter oldDelegate) {
    return !listEquals(oldDelegate.values, values);
  }
}
