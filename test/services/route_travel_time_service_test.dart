import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/route_travel_time_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.zelia/route_travel_time');
  final calls = <MethodCall>[];

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    calls.clear();
  });

  test('aucun lieu ne part vers le calcul sans autorisation locale', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isTravelCalculationAuthorized') return false;
      fail('Le calcul ne doit pas être appelé sans autorisation.');
    });
    const gateway = AppleMapsRouteTravelTimeGateway(channel: channel);

    final minutes = await gateway.estimateMinutes(
      RouteTravelTimeRequest(
        origin: '1 rue de la Paix',
        destination: 'Cabinet médical',
        departureAt: DateTime(2026, 8, 20, 9),
      ),
    );

    expect(minutes, isNull);
    expect(calls.map((call) => call.method), [
      'isTravelCalculationAuthorized',
    ]);
  });

  test('le calcul autorisé transmet seulement les données du trajet', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isTravelCalculationAuthorized') return true;
      if (call.method == 'estimateTravelTime') return {'minutes': 17.2};
      return null;
    });
    const gateway = AppleMapsRouteTravelTimeGateway(channel: channel);
    final departure = DateTime(2026, 8, 20, 9);

    final minutes = await gateway.estimateMinutes(
      RouteTravelTimeRequest(
        origin: '  Maison  ',
        destination: 'Dentiste',
        departureAt: departure,
        mode: RouteTravelMode.publicTransport,
      ),
    );

    expect(minutes, 18);
    final calculation = calls.singleWhere(
      (call) => call.method == 'estimateTravelTime',
    );
    expect(calculation.arguments, {
      'origin': 'Maison',
      'destination': 'Dentiste',
      'departureAtMilliseconds': departure.millisecondsSinceEpoch,
      'mode': 'publicTransport',
    });
  });

  test('l’autorisation peut être activée et relue sur l’appareil', () async {
    var authorized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setTravelCalculationAuthorized') {
        authorized =
            (call.arguments as Map<Object?, Object?>)['authorized'] == true;
        return null;
      }
      if (call.method == 'isTravelCalculationAuthorized') return authorized;
      return null;
    });
    const gateway = AppleMapsRouteTravelTimeGateway(channel: channel);

    await gateway.setAuthorized(true);

    expect(await gateway.isAuthorized(), isTrue);
  });
}
