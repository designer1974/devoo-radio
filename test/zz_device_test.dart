// Solo sul ramo "diag": avvia l'app vera su un emulatore Android e riporta il motivo se si chiude.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _script = r'''
set -x
SDK=${ANDROID_HOME:-$ANDROID_SDK_ROOT}
export ANDROID_SDK_ROOT=$SDK
SM=$SDK/cmdline-tools/latest/bin/sdkmanager
AM=$SDK/cmdline-tools/latest/bin/avdmanager
ADB=$SDK/platform-tools/adb
IMG="system-images;android-30;google_apis;x86_64"
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
sudo udevadm control --reload-rules; sudo udevadm trigger --name-match=kvm
sudo chmod 666 /dev/kvm || true
echo "RESULT kvm: $(ls -la /dev/kvm 2>&1)" >> result.txt
curl -sL -o pro.apk https://github.com/designer1974/devoo-radio/releases/download/pro-build-26/DevooRadioPro.apk
curl -sL -o free.apk https://github.com/designer1974/devoo-radio/releases/download/build-18/DevooRadio.apk
ls -la *.apk
yes | $SM --install "emulator" "platform-tools" "$IMG" > sdk.log 2>&1
tr '\r' '\n' < sdk.log | grep -v '^ *\[' | grep -v '^$' | tail -4 | sed 's/^/RESULT sdk: /' >> result.txt
ls $SDK/emulator/emulator >> result.txt 2>&1
export ANDROID_AVD_HOME=$PWD/avd; mkdir -p $ANDROID_AVD_HOME
ls $SDK/system-images/android-30/google_apis/x86_64 2>&1 | head -3 | sed 's/^/RESULT img: /' >> result.txt
echo no | $AM create avd -n t -k "$IMG" -p $ANDROID_AVD_HOME/t.avd --force > avd.log 2>&1
tr '\r' '\n' < avd.log | grep -iE "error|warn|exception" | head -5 | sed 's/^/RESULT avd: /' >> result.txt
ls $ANDROID_AVD_HOME | sed 's/^/RESULT avdhome: /' >> result.txt
$SDK/emulator/emulator -avd t -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -no-snapshot -memory 3072 > emu.log 2>&1 &
sleep 40
if ! pgrep -f qemu-system > /dev/null; then
  echo "RESULT emulatore morto" >> result.txt
  tr '\r' '\n' < emu.log | grep -v '^$' | tail -14 | sed 's/^/RESULT emu: /' >> result.txt
  exit 1
fi
timeout 400 $ADB wait-for-device
for i in $(seq 1 90); do [ "$($ADB shell getprop sys.boot_completed | tr -d '\r')" = "1" ] && break; sleep 5; done
echo BOOTED
sleep 10
for p in pro:com.designer1974.devoo_radio.pro free:com.designer1974.devoo_radio; do
  f=${p%%:*}; pkg=${p#*:}
  $ADB install -r $f.apk
  $ADB logcat -c
  $ADB shell monkey -p $pkg -c android.intent.category.LAUNCHER 1
  sleep 30
  pid=$($ADB shell pidof $pkg | tr -d '\r')
  echo "RESULT $f pid=[$pid]" | tee -a result.txt
  $ADB logcat -d > logcat_$f.txt
  $ADB shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" | head -3 | sed "s/^/RESULT $f /" | tee -a result.txt
done
''';

void main() {
  test('app sul telefono', () async {
    if (Platform.environment['GITHUB_REF_NAME'] != 'diag') return;
    final dir = Directory.systemTemp.createTempSync('dev');
    File('${dir.path}/run.sh').writeAsStringSync(_script);
    // tutto su file: il server adb resta acceso e terrebbe aperti i tubi
    await Process.run('bash', ['-c', 'timeout 1500 bash run.sh > all.log 2>&1 < /dev/null'], workingDirectory: dir.path);
    final all = File('${dir.path}/all.log');
    final log = all.existsSync() ? all.readAsStringSync() : '';
    final out = <String>[];
    final res = File('${dir.path}/result.txt');
    if (res.existsSync()) out.addAll(res.readAsLinesSync());
    for (final f in ['pro', 'free']) {
      final lc = File('${dir.path}/logcat_$f.txt');
      if (!lc.existsSync()) {
        out.add('$f: nessun logcat');
        continue;
      }
      final lines = lc.readAsLinesSync();
      final keep = lines
          .where((l) =>
              l.contains('AndroidRuntime') ||
              l.contains('FATAL') ||
              l.contains(' E flutter') ||
              l.contains('F DEBUG') ||
              l.contains('F libc') ||
              (l.contains(' E ') && l.toLowerCase().contains('devoo')))
          .take(16);
      out.add('--- $f ---');
      out.addAll(keep);
    }
    if (out.length < 4) {
      final s = log.split('\n').where((l) => !l.startsWith('+ ')).toList();
      out.addAll(s.skip(s.length > 30 ? s.length - 30 : 0));
    }
    for (final l in out.take(38)) {
      // ignore: avoid_print
      print('error ${l.length > 300 ? l.substring(0, 300) : l}');
    }
    fail('diagnosi');
  }, timeout: const Timeout(Duration(minutes: 45)));
}
