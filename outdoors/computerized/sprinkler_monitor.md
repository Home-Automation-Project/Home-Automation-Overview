Sprinkler Flow Monitor with an ESP32 and a Hall-effect flow sensor. You’ll get live L/min, total liters, and leak/broken-head alerts in Home Assistant via MQTT.

0) What you’ll build

Hardware: ESP32 + in-line turbine (Hall) flow sensor on the main irrigation line

Metrics: Instantaneous flow (L/min), total consumption (L), “flowing” boolean

Smart: Detects unexpected flow (leak), or abnormally high flow (broken head)

Integrations: MQTT sensors + optional HA utility_meter for daily/weekly totals

1) Pick the right flow sensor (max reliability)

Choose a threaded Hall turbine that matches your pipe size:

¾" line → YF-B5 / FS300A-G3/4 (common garden size)

1" line → YF-B10 / FS300A-G1 (less restriction, better for high flow)

Typical spec (YF-S201 class):
f (Hz) ≈ 7.5 × Q (L/min) → about 450 pulses per liter.
⚠️ These numbers vary by model and plumbing; you’ll calibrate (Step 7).

Plumbing notes

Put it on the main line after the backflow preventer and before zone branches.

Install straight pipe runs (ideally >10× diameter upstream, >5× downstream) for accuracy.

Arrow on body must match water direction. Use PTFE tape; don’t overtighten plastic threads.

Add a small Y-strainer upstream if you have sediment.

2) Parts list

ESP32 DevKit (WROOM-32)

1× Hall flow sensor (thread size to match line)

Weatherproof box (IP65), cable glands

5V USB supply (≥1A), short USB cable

Pull-up resistor 10kΩ from signal to 3.3V (if your sensor output is open-collector)

Bypass/decoupling: 100 nF across sensor V+ to GND (near the sensor leads)

3) Wiring (text diagram)
[Flow Sensor]
  RED  ----  +5V  (from ESP32 5V or PSU)
  BLACK ---- GND  (common with ESP32 GND)
  YELLOW --- ESP32 GPIO25  (signal/pulses)

[Pull-up] 10kΩ from GPIO25 to 3.3V (important if sensor is open-collector)


Important

Many Hall sensors are rated 5–24V and have an open-collector output. Power the sensor with 5V, but pull the output up to 3.3V, not 5V, to protect the ESP32.

Keep the signal run short or use twisted pair (signal+GND).

Avoid GPIOs 34–39 for interrupts (they’re input-only but fine); I use GPIO25 here.

4) Firmware (Arduino IDE)

Install ESP32 board support + PubSubClient (MQTT). Paste this as sprinkler_flow_monitor.ino, edit the config block at the top.

#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>

// ====== CONFIG ======
#define WIFI_SSID  "YOUR_WIFI"
#define WIFI_PASS  "YOUR_PASS"

#define MQTT_HOST  "192.168.1.10"
#define MQTT_PORT  1883
#define MQTT_USER  "mqtt_user"     // "" if not needed
#define MQTT_PASS  "mqtt_pass"     // "" if not needed

#define DEVICE_NAME    "sprinkler_flow_1"
#define BASE_TOPIC     "home/sprinkler/flow1"  // publishes to .../state, .../availability

// GPIO for flow pulses
#define FLOW_PIN       25

// Sampling + calibration
#define SAMPLE_MS      2000     // window to compute L/min
#define PULSES_PER_L   450.0    // starting point; will calibrate in step 7
#define FLOW_ON_LPM    0.3      // threshold L/min to call "flowing" true

// Leak/broken head heuristics (optional)
#define LEAK_MINUTES   10       // flow detected > this many minutes outside schedule => leak
#define HIGH_FLOW_LPM  25.0     // if above => possible broken head
// ====================

WiFiClient espClient;
PubSubClient mqtt(espClient);

volatile uint32_t pulseCount = 0;
uint32_t lastSampleMs = 0;
uint32_t lastPulseCount = 0;
double totalLiters = 0.0;
bool flowing = false;

char availTopic[96];
char stateTopic[96];

void IRAM_ATTR onPulse() {
  pulseCount++;
}

void wifiUp() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 20000) delay(200);
}

void mqttUp() {
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  while (!mqtt.connected()) {
    if (MQTT_USER[0]) {
      if (mqtt.connect(DEVICE_NAME, MQTT_USER, MQTT_PASS, availTopic, 1, true, "offline")) break;
    } else {
      if (mqtt.connect(DEVICE_NAME, nullptr, nullptr, availTopic, 1, true, "offline")) break;
    }
    delay(1000);
  }
  mqtt.publish(availTopic, "online", true);
}

void setup() {
  Serial.begin(115200);

  pinMode(FLOW_PIN, INPUT);
  // If your sensor needs a pull-up, either hardware 10k to 3.3V or:
  // pinMode(FLOW_PIN, INPUT_PULLUP);  // use only if sensor tolerates pull-up to 3.3V

  attachInterrupt(digitalPinToInterrupt(FLOW_PIN), onPulse, FALLING);

  snprintf(availTopic, sizeof(availTopic), "%s/availability", BASE_TOPIC);
  snprintf(stateTopic, sizeof(stateTopic), "%s/state", BASE_TOPIC);

  wifiUp();
  mqttUp();

  lastSampleMs = millis();
}

void loop() {
  if (!mqtt.connected()) mqttUp();
  mqtt.loop();

  uint32_t now = millis();
  if (now - lastSampleMs >= SAMPLE_MS) {
    uint32_t pulsesNow = pulseCount; // atomic read on ESP32 is fine for 32-bit
    uint32_t deltaP = pulsesNow - lastPulseCount;
    lastPulseCount = pulsesNow;

    double seconds = (now - lastSampleMs) / 1000.0;
    lastSampleMs = now;

    double pulsesPerSec = deltaP / seconds;
    // Convert to L/min:
    // If you know PULSES_PER_L: Q(L/min) = (pulsesPerSec * 60) / PULSES_PER_L
    double flowLpm = (pulsesPerSec * 60.0) / PULSES_PER_L;

    // Accumulate liters directly from pulses:
    totalLiters += (double)deltaP / PULSES_PER_L;

    bool newFlowing = flowLpm >= FLOW_ON_LPM;
    flowing = newFlowing;

    // Publish JSON state
    // { "flow_lpm": x.xx, "liters_total": y.yy, "flowing": true/false, "pulses": N }
    char payload[192];
    snprintf(payload, sizeof(payload),
      "{\"flow_lpm\":%.2f,\"liters_total\":%.3f,\"flowing\":%s,\"pulses\":%lu}",
      flowLpm, totalLiters, flowing ? "true" : "false", (unsigned long)pulsesNow);
    mqtt.publish(stateTopic, payload, false);

    // Optional console
    Serial.println(payload);
  }

  delay(5);
}

5) Home Assistant (MQTT) quick config

Sensors

mqtt:
  sensor:
    - name: "Sprinkler Flow (L/min)"
      unique_id: sprinkler_flow_lpm
      state_topic: "home/sprinkler/flow1/state"
      unit_of_measurement: "L/min"
      value_template: "{{ value_json.flow_lpm | float }}"
    - name: "Sprinkler Total (L)"
      unique_id: sprinkler_total_l
      state_topic: "home/sprinkler/flow1/state"
      unit_of_measurement: "L"
      value_template: "{{ value_json.liters_total | float }}"
  binary_sensor:
    - name: "Sprinkler Flowing"
      unique_id: sprinkler_flowing
      state_topic: "home/sprinkler/flow1/state"
      value_template: "{{ 'ON' if value_json.flowing else 'OFF' }}"
      device_class: moving


Daily usage counter

utility_meter:
  sprinkler_daily:
    source: sensor.sprinkler_total_l
    cycle: daily


Leak / broken-head alerts (examples)

automation:
  - alias: "Leak: Unexpected flow"
    trigger:
      - platform: state
        entity_id: binary_sensor.sprinkler_flowing
        to: "on"
        for: "00:10:00"   # flowing > 10 minutes
    condition:
      # Add your "not scheduled" conditions here (time window or an input_boolean)
      - condition: time
        after: "22:00:00"
        before: "05:30:00"
    action:
      - service: notify.mobile_app_phone
        data:
          message: "Sprinkler leak? Flow for 10+ min outside schedule."

  - alias: "Broken head: Excessive flow"
    trigger:
      - platform: numeric_state
        entity_id: sensor.sprinkler_flow_lpm
        above: 25     # adjust for your system
        for: "00:00:30"
    action:
      - service: notify.mobile_app_phone
        data:
          message: "Sprinkler flow unusually high — check for a broken head."

6) Power & enclosure

Place ESP32 + buck/USB supply in an IP65 box near the plumbing.

Keep the sensor body outside; run the 3-wire cable into the box.

Add a 100 µF electrolytic across ESP32 5V/GND to ride out Wi-Fi bursts.

Common ground between ESP32 and sensor is required.

7) Calibration (do this once)

In HA (or Serial), zero your total liters (flash or reset your counter).

Open a single zone that gives steady flow into a bucket/metered container.

Run until you’ve collected a known volume (e.g., 10.0 L).

Read the pulse count (or compute from liters_total if you kept default 450).

If your firmware only shows liters_total, also capture the delta pulses during the run (temporarily print pulseCount to Serial, or compute: deltaP = liters_total * PULSES_PER_L if default was close).

Compute K-factor:

PULSES_PER_L = (delta pulses) / (measured liters)


Put that new value in the sketch, reflash, repeat a quick check.

Example: You captured 19,000 pulses for 40.0 liters → PULSES_PER_L = 475.0

8) Variations & upgrades

Pressure sensor (0–10 bar analog) on ESP32 ADC to enrich diagnostics.

Per-zone analytics: If you have your irrigation controller integrated in HA, tag each “flowing” period with the active zone entity for zone-by-zone water usage.

Non-invasive ultrasonic clamp-on (expensive, less DIY), if you can’t cut into the pipe.

## add pressure sensor
line pressure sensor to your sprinkler flow monitor so you can see PSI/bar, catch low-pressure/broken head events faster, and spot leaks even when flow is small.

1) Pick a sensor (3 solid choices)

Easiest (recommended): 0.5–4.5 V ratiometric, 5 V supply, 1/4" NPT/BSP

Range: 0–6 bar (0–87 PSI) or 0–10 bar (0–145 PSI)

Output: 10%–90% of supply (0.5–4.5 V when powered from 5 V)

Works great with a simple voltage divider to the ESP32 ADC (max 3.3 V).

Alternative (cleaner ADC range): 4–20 mA industrial transmitter

Same pressure ranges, powered at 12–24 V typically.

Read with a sense resistor: 165 Ω → 0.66–3.3 V (perfect for ESP32).

Most robust electrically, slightly more wiring.

Best accuracy (optional): external ADC

Use an ADS1115 I²C 16-bit ADC for prettier numbers if you want.

Not required—ESP32 ADC is fine with averaging.

2) Where to install it

Tee it on the main irrigation line after backflow preventer, before zone valves.

If you want per-zone diagnostics later, you can add more ports on each branch, but one main sensor is already very useful.

Use PTFE tape, don’t over-torque plastic fittings; add a small isolation valve if you want to service the transducer.

3) Wiring
Option A — 0.5–4.5 V sensor @5 V (with divider) (recommended for simplicity)
Sensor (0–6 bar, 0.5–4.5 V ratiometric)
  RED   →  +5V
  BLACK →  GND
  GREEN →  Divider → ESP32 ADC (GPIO 32 suggested)

Voltage Divider (to keep ≤ 3.3V):
  Sensor OUT ── R1=100k ──┬──> to ESP32 GPIO32 (ADC)
                          |
                         R2=100k
                          |
                         GND

(0.5–4.5 V becomes ~0.25–2.25 V at the ADC — safely inside 3.3 V)


Add a 100 nF cap sensor OUT→GND near the sensor lead to tame noise.

Option B — 4–20 mA sensor (industrial)
Sensor +24V (or 12–24V) loop
  +V (supply) → Sensor +
  Sensor – → Sense resistor 165 Ω → GND
  Tap across resistor → ESP32 ADC (GPIO32)

Voltages: 4 mA → 0.66 V, 20 mA → 3.30 V (perfect for 3.3 V ADC)
Use 1% metal-film resistor; common GND with ESP32.

4) Cal constants you’ll use

PRESS_PIN — the ADC pin (e.g., 32).

PRESS_V_MIN / PRESS_V_MAX — sensor output at 0 / full scale after the divider.

For 0.5–4.5 V with 100k/100k divider → 0.25–2.25 V.

PRESS_MAX_BAR — choose your sensor rating (e.g., 6.0 or 10.0).

We’ll read multiple samples, median+average, then map voltage → bar/PSI.

5) Drop-in firmware (flow + pressure + MQTT)

Paste this over your current sketch (or merge the pressure parts). Change Wi-Fi/MQTT and constants at the top.

#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>

// ====== WIFI / MQTT ======
#define WIFI_SSID  "YOUR_WIFI"
#define WIFI_PASS  "YOUR_PASS"

#define MQTT_HOST  "192.168.1.10"
#define MQTT_PORT  1883
#define MQTT_USER  "mqtt_user"      // "" if not needed
#define MQTT_PASS  "mqtt_pass"      // "" if not needed

#define DEVICE_NAME "sprinkler_monitor_1"
#define BASE_TOPIC  "home/sprinkler/main"  // .../state, .../availability

// ====== FLOW SENSOR ======
#define FLOW_PIN       25
#define SAMPLE_MS      2000
#define PULSES_PER_L   450.0
#define FLOW_ON_LPM    0.3

// ====== PRESSURE SENSOR ======
// Option A: 0.5–4.5V ratiometric @5V with 100k/100k divider → 0.25–2.25V at ADC
#define PRESS_PIN        32
#define PRESS_MAX_BAR    6.0        // set to your sensor's full-scale (6 or 10 bar)
#define PRESS_V_MIN      0.25f      // ADC voltage when pressure = 0 bar (after divider)
#define PRESS_V_MAX      2.25f      // ADC voltage when pressure = full-scale (after divider)

// ADC & smoothing
#define ADC_SAMPLES      32
#define ADC_ATTEN        ADC_11db   // allows up to ~3.3V range comfortably
#define ADC_VREF         3.30f      // ESP32 effective reference (approx; we'll infer using atten)
#define USE_MEDIAN       1

// ====== OPTIONAL HEURISTICS ======
#define HIGH_FLOW_LPM    25.0       // broken head suspicion
#define LOW_PRESS_BAR    1.0        // low supply pressure threshold
#define NO_FLOW_DROP_BAR 0.2        // pressure drop considered significant when no flow

// ====== GLOBALS ======
WiFiClient espClient;
PubSubClient mqtt(espClient);

volatile uint32_t pulseCount = 0;
uint32_t lastSampleMs = 0;
uint32_t lastPulseCount = 0;
double totalLiters = 0.0;
bool flowing = false;

char availTopic[96];
char stateTopic[96];

void IRAM_ATTR onPulse() { pulseCount++; }

void wifiUp() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 20000) delay(200);
}
void mqttUp() {
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  while (!mqtt.connected()) {
    if (MQTT_USER[0]) {
      if (mqtt.connect(DEVICE_NAME, MQTT_USER, MQTT_PASS, availTopic, 1, true, "offline")) break;
    } else {
      if (mqtt.connect(DEVICE_NAME, nullptr, nullptr, availTopic, 1, true, "offline")) break;
    }
    delay(1000);
  }
  mqtt.publish(availTopic, "online", true);
}

// Simple median-of-N helper
int medianN(uint16_t *a, int n) {
  for (int i=0;i<n;i++){ // insertion sort is fine for small N
    int j=i; uint16_t t=a[i];
    while (j>0 && a[j-1]>t){ a[j]=a[j-1]; j--; }
    a[j]=t;
  }
  return a[n/2];
}

float readPressureVoltage() {
  analogSetPinAttenuation(PRESS_PIN, ADC_ATTEN);
  uint16_t buf[ADC_SAMPLES];
  for (int i=0;i<ADC_SAMPLES;i++) {
    buf[i] = analogRead(PRESS_PIN);
    delayMicroseconds(200);
  }
  uint32_t sum = 0;
  if (USE_MEDIAN) {
    int m = medianN(buf, ADC_SAMPLES);
    // small average around median for stability
    for (int i=0;i<ADC_SAMPLES;i++) sum += buf[i];
    float avg = sum / (float)ADC_SAMPLES;
    float mix = 0.7f * m + 0.3f * avg;   // weighted
    // Convert raw to volts
    // ESP32 raw is 0..4095 for ~0..Vmax (with ADC_11db ~ 3.3V typical)
    return mix * (ADC_VREF / 4095.0f);
  } else {
    for (int i=0;i<ADC_SAMPLES;i++) sum += buf[i];
    float avg = sum / (float)ADC_SAMPLES;
    return avg * (ADC_VREF / 4095.0f);
  }
}

float voltsToBar(float v) {
  // Clamp
  if (v < PRESS_V_MIN) v = PRESS_V_MIN;
  if (v > PRESS_V_MAX) v = PRESS_V_MAX;
  float span = PRESS_V_MAX - PRESS_V_MIN;
  float frac = (span > 0.0001f) ? (v - PRESS_V_MIN) / span : 0.0f;
  float bar = frac * PRESS_MAX_BAR;
  if (bar < 0) bar = 0;
  return bar;
}

float barToPsi(float bar) { return bar * 14.5038f; }

void setup() {
  Serial.begin(115200);

  pinMode(FLOW_PIN, INPUT);
  attachInterrupt(digitalPinToInterrupt(FLOW_PIN), onPulse, FALLING);

  snprintf(availTopic, sizeof(availTopic), "%s/availability", BASE_TOPIC);
  snprintf(stateTopic, sizeof(stateTopic), "%s/state", BASE_TOPIC);

  wifiUp();
  mqttUp();

  lastSampleMs = millis();
}

void loop() {
  if (!mqtt.connected()) mqttUp();
  mqtt.loop();

  uint32_t now = millis();
  if (now - lastSampleMs >= SAMPLE_MS) {
    // --- Flow ---
    uint32_t pulsesNow = pulseCount;
    uint32_t deltaP = pulsesNow - lastPulseCount;
    lastPulseCount = pulsesNow;

    double seconds = (now - lastSampleMs) / 1000.0;
    lastSampleMs = now;

    double pulsesPerSec = deltaP / seconds;
    double flowLpm = (pulsesPerSec * 60.0) / PULSES_PER_L;
    totalLiters += (double)deltaP / PULSES_PER_L;
    flowing = (flowLpm >= FLOW_ON_LPM);

    // --- Pressure ---
    float v = readPressureVoltage();
    float bar = voltsToBar(v);
    float psi = barToPsi(bar);

    // --- Optional simple diagnostics (just add to your automations if you want) ---
    bool brokenHeadSuspect = (flowLpm > HIGH_FLOW_LPM) && (bar < LOW_PRESS_BAR);
    // You could also track pressure drop trend when no flow to detect leaks.

    // --- Publish JSON ---
    char payload[256];
    snprintf(payload, sizeof(payload),
      "{\"flow_lpm\":%.2f,\"liters_total\":%.3f,\"flowing\":%s,"
      "\"pressure_bar\":%.2f,\"pressure_psi\":%.1f,"
      "\"v_adc\":%.3f,\"pulses\":%lu,\"broken_head\":%s}",
      flowLpm, totalLiters, flowing ? "true":"false",
      bar, psi,
      v, (unsigned long)pulsesNow, brokenHeadSuspect ? "true":"false");

    mqtt.publish(stateTopic, payload, false);
    Serial.println(payload);
  }

  delay(5);
}

6) Home Assistant updates

Add/extend sensors to read pressure and a broken-head flag:

mqtt:
  sensor:
    - name: "Sprinkler Pressure (bar)"
      state_topic: "home/sprinkler/main/state"
      unit_of_measurement: "bar"
      value_template: "{{ value_json.pressure_bar | float }}"
    - name: "Sprinkler Pressure (psi)"
      state_topic: "home/sprinkler/main/state"
      unit_of_measurement: "psi"
      value_template: "{{ value_json.pressure_psi | float }}"
  binary_sensor:
    - name: "Sprinkler Broken Head Suspect"
      state_topic: "home/sprinkler/main/state"
      value_template: "{{ 'ON' if value_json.broken_head else 'OFF' }}"
      device_class: problem


Sample alert:

automation:
  - alias: "Broken head suspected"
    trigger:
      - platform: state
        entity_id: binary_sensor.sprinkler_broken_head_suspect
        to: "on"
        for: "00:00:20"
    action:
      - service: notify.mobile_app_phone
        data:
          message: "Sprinkler: high flow + low pressure — possible broken head."

7) Calibrate pressure (quick)

With irrigation off, note the static pressure value; compare to a mechanical gauge on a hose bib close to the same plumbing.

If there’s an offset, tweak PRESS_V_MIN a little (it sets the 0-bar intercept) or add a small PRESS_OFFSET_BAR term (you can add a line bar += PRESS_OFFSET_BAR;).

If full-scale reads slightly high/low, adjust PRESS_V_MAX or PRESS_MAX_BAR to match.

8) Troubleshooting

ADC noise/jitter: keep sensor wiring short, add 100 nF cap to GND, and keep Wi-Fi antenna away from the analog line.

Ratiometric sensors: their output moves with supply voltage. Power from a stable 5 V source.

Divider accuracy: use 1% resistors; if you change values, update PRESS_V_MIN/MAX accordingly.

4–20 mA: use a precise 165 Ω 1% resistor; verify 20 mA → ~3.30 V.