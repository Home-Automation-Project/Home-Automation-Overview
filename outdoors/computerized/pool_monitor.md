Swimming Pool Monitor you can build with an ESP32. It supports push alerts (via Home Assistant/MQTT) and an optional pump relay with safety interlocks.

1) What this build does

Measures water temperature (DS18B20, waterproof).

Monitors water level (one or two float switches, or a pressure transducer—your choice).

Reports to MQTT (Home Assistant-friendly).

Sends push alerts (freeze risk, low water, pump issues).

Optional: Controls the pump via a safe dry-contact relay (not switching mains directly).

2) Recommended hardware (MVP)

ESP32 DevKitC (WROOM-32)

DS18B20 waterproof temperature probe (+ 4.7kΩ pull-up to 3V3)

Float switches (2 × NO types, vertical or side-mount), or a 0.5–4.5V pressure transducer for level (optional)

5V relay module (opto-isolated) → drives a contactor coil or a pump controller’s remote “dry contact” input

⚠️ Do not switch 120/240 VAC pump motor directly with a hobby relay. Use a rated contactor or a pump controller’s low-voltage input.

5V USB PSU (≥1 A), IP65 enclosure, cable glands

Optional upgrades

Analog pressure transducer (0–1 bar) tee’d on the suction side for level proxy

Flow sensor on return line (turbine) for “running but no flow” diagnostics

3) Wiring (ASCII)
ESP32 DevKitC
├── DS18B20 (Temp)
│   ├─ VCC → 3.3V
│   ├─ GND → GND
│   └─ DATA → GPIO4   (add 4.7kΩ pull-up from DATA to 3.3V)
│
├── Float: LOW level switch (N.O.)
│   ├─ one lead → GPIO13
│   └─ other → GND
│   (enable INPUT_PULLUP → closed = LOW water)
│
├── Float: HIGH/OK level switch (N.O., optional)
│   ├─ one lead → GPIO14
│   └─ other → GND
│   (INPUT_PULLUP → closed = level OK)
│
└── Pump Relay (LOW-voltage control only!)
    ├─ IN  → GPIO26   (active HIGH energizes coil)
    ├─ VCC → 5V
    └─ GND → GND

5V USB PSU → ESP32 5V & Relay VCC (common GND)


If using a 0.5–4.5 V pressure transducer for level: power at 5 V, feed output through a 100k/100k divider into GPIO32 ADC (0.25–2.25 V at ADC).

4) Flash the firmware (Arduino IDE)

Install:

ESP32 boards

Libraries: OneWire, DallasTemperature, PubSubClient (MQTT), ArduinoJson

Paste the sketch below as pool_monitor.ino, set your Wi-Fi/MQTT, and choose whether you have one or two floats (or the analog level).

pool_monitor.ino
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// ====== USER CONFIG ======
#define WIFI_SSID  "YOUR_WIFI"
#define WIFI_PASS  "YOUR_PASS"

#define MQTT_HOST  "192.168.1.10"
#define MQTT_PORT  1883
#define MQTT_USER  "mqtt_user"     // "" if not needed
#define MQTT_PASS  "mqtt_pass"     // "" if not needed

#define DEVICE_NAME   "pool_monitor_1"
#define BASE_PREFIX   "home/pool/"   // topics under home/pool/monitor_1/...
// =========================

// Pins
#define PIN_DS18B20   4
#define PIN_FLOAT_LOW 13    // N.O. to GND, INPUT_PULLUP -> LOW = triggered (low water)
#define PIN_FLOAT_OK  14    // optional "level OK" float; comment if unused
#define PIN_PUMP_RELAY 26   // active HIGH
//#define PIN_LEVEL_ADC 32   // uncomment if using analog level sensor

// Features
#define HAVE_FLOAT_OK 1     // set 0 if only one float
//#define HAVE_ANALOG_LEVEL 1 // uncomment if using pressure/level analog

// Analog level calibration (if used, 0.5–4.5V sensor w/ 100k/100k divider)
#define LV_VMIN   0.25f   // volts at 0%
#define LV_VMAX   2.25f   // volts at 100%
#define LV_SMOOTH 10

// Sampling
#define SAMPLE_MS 5000
#define MQTT_RETAIN false

// Freeze threshold (°C): alert if below
#define FREEZE_C  2.0

// Pump safety
#define MIN_SWITCH_INTERVAL_MS  60000UL  // min 60s between relay toggles

WiFiClient wifi;
PubSubClient mqtt(wifi);

OneWire oneWire(PIN_DS18B20);
DallasTemperature dallas(&oneWire);

char topic_state[128], topic_avail[128], topic_cmd[128], topic_disc[7][192];

volatile bool pumpCmdPending = false;
volatile bool pumpCmdOn = false;
bool pumpState = false;
unsigned long lastRelayToggle = 0;

unsigned long tLast = 0;

// Debounce helpers
bool readFloat(int pin, int samples=8) {
  int c=0;
  for (int i=0;i<samples;i++){ c += (digitalRead(pin)==LOW); delay(3); }
  return c > samples/2; // true = closed
}

void mqttCallback(char* topic, byte* payload, unsigned int len) {
  String t(topic); String body;
  for (unsigned int i=0;i<len;i++) body += (char)payload[i];
  body.trim();
  if (t == String(topic_cmd)) {
    if (body.equalsIgnoreCase("ON") || body.equalsIgnoreCase("1") || body.equalsIgnoreCase("true")) {
      pumpCmdPending = true; pumpCmdOn = true;
    } else if (body.equalsIgnoreCase("OFF") || body.equalsIgnoreCase("0") || body.equalsIgnoreCase("false")) {
      pumpCmdPending = true; pumpCmdOn = false;
    }
  }
}

void wifiUp() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis()-t0 < 20000) delay(200);
}

void mqttUp() {
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  while (!mqtt.connected()) {
    if (MQTT_USER[0]) {
      if (mqtt.connect(DEVICE_NAME, MQTT_USER, MQTT_PASS, topic_avail, 1, true, "offline")) break;
    } else {
      if (mqtt.connect(DEVICE_NAME, nullptr, nullptr, topic_avail, 1, true, "offline")) break;
    }
    delay(1000);
  }
  mqtt.publish(topic_avail, "online", true);
  mqtt.subscribe(topic_cmd);
}

void publishDiscovery() {
  // Home Assistant discovery for: temp, level_low, level_ok, pump switch
  StaticJsonDocument<512> doc; char buf[512];

  // Temperature
  snprintf(topic_disc[0], sizeof(topic_disc[0]), "homeassistant/sensor/%s/temp/config", DEVICE_NAME);
  doc.clear();
  doc["name"] = "Pool Water Temperature";
  doc["uniq_id"] = String(DEVICE_NAME) + "_temp";
  doc["stat_t"] = topic_state;
  doc["avty_t"] = topic_avail;
  doc["unit_of_meas"] = "°C";
  doc["dev_cla"] = "temperature";
  doc["val_tpl"] = "{{ value_json.temp_c }}";
  doc["dev"]["ids"][0] = DEVICE_NAME;
  serializeJson(doc, buf, sizeof(buf));
  mqtt.publish(topic_disc[0], buf, true);

  // Level low (binary)
  snprintf(topic_disc[1], sizeof(topic_disc[1]), "homeassistant/binary_sensor/%s/level_low/config", DEVICE_NAME);
  doc.clear();
  doc["name"] = "Pool Level Low";
  doc["uniq_id"] = String(DEVICE_NAME) + "_level_low";
  doc["stat_t"] = topic_state;
  doc["avty_t"] = topic_avail;
  doc["dev_cla"] = "problem";
  doc["val_tpl"] = "{{ value_json.level_low }}";
  doc["pl_on"] = "ON"; doc["pl_off"] = "OFF";
  doc["dev"]["ids"][0] = DEVICE_NAME;
  serializeJson(doc, buf, sizeof(buf));
  mqtt.publish(topic_disc[1], buf, true);

#if HAVE_FLOAT_OK
  // Level OK (binary)
  snprintf(topic_disc[2], sizeof(topic_disc[2]), "homeassistant/binary_sensor/%s/level_ok/config", DEVICE_NAME);
  doc.clear();
  doc["name"] = "Pool Level OK";
  doc["uniq_id"] = String(DEVICE_NAME) + "_level_ok";
  doc["stat_t"] = topic_state;
  doc["avty_t"] = topic_avail;
  doc["dev_cla"] = "moisture";
  doc["val_tpl"] = "{{ value_json.level_ok }}";
  doc["pl_on"] = "ON"; doc["pl_off"] = "OFF";
  doc["dev"]["ids"][0] = DEVICE_NAME;
  serializeJson(doc, buf, sizeof(buf));
  mqtt.publish(topic_disc[2], buf, true);
#endif

  // Pump switch
  snprintf(topic_disc[3], sizeof(topic_disc[3]), "homeassistant/switch/%s/pump/config", DEVICE_NAME);
  doc.clear();
  doc["name"] = "Pool Pump";
  doc["uniq_id"] = String(DEVICE_NAME) + "_pump";
  doc["stat_t"] = topic_state;
  doc["cmd_t"] = topic_cmd;
  doc["avty_t"] = topic_avail;
  doc["pl_on"] = "ON"; doc["pl_off"] = "OFF";
  doc["val_tpl"] = "{{ value_json.pump_state }}";
  doc["dev"]["ids"][0] = DEVICE_NAME;
  serializeJson(doc, buf, sizeof(buf));
  mqtt.publish(topic_disc[3], buf, true);
}

void setup() {
  pinMode(PIN_FLOAT_LOW, INPUT_PULLUP);
#if HAVE_FLOAT_OK
  pinMode(PIN_FLOAT_OK, INPUT_PULLUP);
#endif
  pinMode(PIN_PUMP_RELAY, OUTPUT);
  digitalWrite(PIN_PUMP_RELAY, LOW);
  pumpState = false;

  Serial.begin(115200);

  dallas.begin();

  snprintf(topic_state, sizeof(topic_state), "%s%s/state", BASE_PREFIX, DEVICE_NAME);
  snprintf(topic_avail, sizeof(topic_avail), "%s%s/availability", BASE_PREFIX, DEVICE_NAME);
  snprintf(topic_cmd,   sizeof(topic_cmd),   "%s%s/cmd", BASE_PREFIX, DEVICE_NAME);

  wifiUp();
  mqttUp();
  publishDiscovery();

  tLast = millis();
}

void loop() {
  if (!mqtt.connected()) mqttUp();
  mqtt.loop();

  // Handle pump commands with interlock
  if (pumpCmdPending) {
    unsigned long now = millis();
    if (now - lastRelayToggle >= MIN_SWITCH_INTERVAL_MS) {
      pumpState = pumpCmdOn;
      digitalWrite(PIN_PUMP_RELAY, pumpState ? HIGH : LOW);
      lastRelayToggle = now;
      pumpCmdPending = false;
    }
  }

  unsigned long now = millis();
  if (now - tLast >= SAMPLE_MS) {
    tLast = now;

    // Read temperature
    dallas.requestTemperatures();
    float tc = dallas.getTempCByIndex(0);
    bool freezeRisk = (!isnan(tc) && tc <= FREEZE_C);

    // Floats
    bool low = readFloat(PIN_FLOAT_LOW);
#if HAVE_FLOAT_OK
    bool ok = readFloat(PIN_FLOAT_OK);
#endif

    // Build JSON
    StaticJsonDocument<384> doc;
    if (isnan(tc)) doc["temp_c"] = nullptr; else doc["temp_c"] = tc;
    doc["freeze_risk"] = freezeRisk;
    doc["level_low"] = low ? "ON" : "OFF";
#if HAVE_FLOAT_OK
    doc["level_ok"]  = ok ? "ON" : "OFF";
#endif
    doc["pump_state"] = pumpState ? "ON" : "OFF";

    char payload[384];
    size_t n = serializeJson(doc, payload, sizeof(payload));
    mqtt.publish(topic_state, payload, MQTT_RETAIN);
    Serial.write(payload, n); Serial.println();
  }

  delay(5);
}

5) Home Assistant push alerts (examples)

These work automatically with the discovery above. Add any of these:

Freeze protection

automation:
  - alias: "Pool freeze risk"
    trigger:
      - platform: numeric_state
        entity_id: sensor.pool_water_temperature
        below: 2.0
        for: "00:05:00"
    action:
      - service: notify.mobile_app_phone
        data:
          message: "Pool freeze risk: water ≤ 2°C"
      # optional: turn on pump
      - service: switch.turn_on
        target: { entity_id: switch.pool_pump }


Low water alert

automation:
  - alias: "Pool low water"
    trigger:
      - platform: state
        entity_id: binary_sensor.pool_level_low
        to: "on"
        for: "00:02:00"
    action:
      - service: notify.mobile_app_phone
        data:
          message: "Pool water level low — check skimmer/auto-fill."
      # optional: stop pump to protect it
      - service: switch.turn_off
        target: { entity_id: switch.pool_pump }


Pump safety interlock (software guard)

automation:
  - alias: "Block pump if low water"
    trigger:
      - platform: state
        entity_id: binary_sensor.pool_level_low
        to: "on"
    action:
      - service: switch.turn_off
        target: { entity_id: switch.pool_pump }

6) Safe pump control notes (important)

Prefer dry-contact control into a pool controller’s low-voltage input (e.g., “remote” terminals) or drive a rated contactor coil (24 VAC/12 VDC) that switches the pump mains.

Do not route mains through hobby relay boards. If you must switch mains, use a motor-rated contactor in an electrical enclosure; follow local electrical codes or hire a pro.

Add minimum off/on time (already in firmware) to avoid rapid cycling.

7) Optional: analog level via pressure transducer

Power sensor at 5 V; output 0.5–4.5 V → divider → GPIO32 ADC.

Map voltage to depth with a linear function; set alert when depth drops.

Want this added to the firmware? Tell me your sensor range (bar/psi) and I’ll drop in the exact constants + code patch.

8) Next steps / extras

Add ORP/pH logging (analog pH/ORP boards; needs careful calibration & isolation).

Add flow to detect “pump on, no flow” (clog/air lock).

Schedule pump via HA automations (e.g., off-peak energy times).
