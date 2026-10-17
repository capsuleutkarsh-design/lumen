// Android's parts that run anywhere: the output rate Gleo sends, the honest signal path
// (Android's mixer, Bluetooth's lossy codec) and reading the route the app reports.
import 'package:flutter_test/flutter_test.dart';
import 'package:gleo/audio/sound.dart';
import 'package:gleo/platform/android.dart';

const flac = SourceInfo(badge: 'FLAC 24/96', format: 's32', rate: 96000, bits: 24, channels: 2);
const phone = DeviceInfo(name: 'Phone speaker', android: true, nativeRate: 48000, outFormat: 'floatp', outRate: 96000, outChannels: 2);
const bt = DeviceInfo(name: 'Bluetooth headphones', android: true, bluetooth: true, nativeRate: 48000, outFormat: 'floatp', outRate: 96000, outChannels: 2);

void main() {
  testWidgets('the lock-screen view keeps the screen on only for a minute after a wake or touch', (t) async {
    pokeLockView();
    expect(lockAwake.value, isTrue);
    await t.pump(const Duration(seconds: 59));
    pokeLockView(); // a touch starts the minute again
    await t.pump(const Duration(seconds: 59));
    expect(lockAwake.value, isTrue);
    await t.pump(const Duration(seconds: 2));
    expect(lockAwake.value, isFalse);
    pokeLockView();
    pokeLockView(on: false); // the screen went off
    expect(lockAwake.value, isFalse);
  });

  test('Gleo sends the song rate up to 96 kHz; higher rates stay in their family', () {
    final s = SoundSettings()..bestQuality = false;
    expect(androidRate(s, phone, 44100), 0);
    expect(androidRate(s, phone, 96000), 0);
    expect(androidRate(s, phone, 192000), 96000);
    expect(androidRate(s, phone, 176400), 88200);
    expect(buildAudioChain(s, phone, flac).options['audio-samplerate'], '0');
  });

  test('Best quality converts to the output rate with soxr', () {
    final s = SoundSettings()..bestQuality = true;
    expect(androidRate(s, phone, 44100), 48000);
    expect(androidRate(s, phone, 48000), 0);
    final c = buildAudioChain(s, phone, flac);
    expect(c.options['audio-samplerate'], '48000');
    expect(c.options['audio-swresample-o'], contains('soxr'));
    // Unknown output rate (API without the property): the song's own rate.
    expect(androidRate(s, const DeviceInfo(android: true), 44100), 0);
  });

  test('Windows is unchanged: no rate forced in shared mode', () {
    expect(buildAudioChain(SoundSettings()..bestQuality = true, const DeviceInfo(), flac).options['audio-samplerate'], '0');
  });

  test('the signal path never claims bit-perfect on Android, and names the Bluetooth codec', () {
    final p = signalPath(SoundSettings()..bestQuality = false, phone, flac);
    expect(p.why, contains('Android mixes the sound'));
    expect(p.why.join(), isNot(contains('Windows')));
    expect(p.steps, containsAllInOrder(['FLAC 24/96', '96 kHz 32-bit float', 'Android mixer (48 kHz)', 'Phone speaker']));
    final b = signalPath(SoundSettings(), bt, flac);
    expect(b.steps, containsAllInOrder(['Android mixer (48 kHz)', 'Bluetooth codec', 'Bluetooth headphones']));
    expect(b.why.join(', '), contains('lossy codec'));
  });

  test('the route: names, and the native rate (listed rates up to 96 kHz, else the mixer)', () {
    final r = AudioRoute.from({'kind': 'bluetooth', 'product': 'WH-1000XM4', 'rates': <int>[], 'mixerRate': 48000, 'sdk': 30});
    expect(r.bluetooth, isTrue);
    expect(r.name, 'Bluetooth headphones');
    expect(r.nativeRate, 48000);
    expect(AudioRoute.from({'kind': 'usb', 'rates': [44100, 48000, 96000, 192000], 'mixerRate': 48000}).nativeRate, 96000);
    expect(AudioRoute.from({'kind': 'wired'}).name, 'Wired headphones');
    expect(AudioRoute.from(const {}).name, 'Phone speaker');
  });
}
