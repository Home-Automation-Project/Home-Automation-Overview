# Pet monitoring
backyard pet tracker using an ESP32 and RFID/NFC tags on collars that logs gate crossings (enter/exit) via MQTT (Home Assistant-friendly)

How the system works (at a glance)

Your gate becomes a small RFID portal with two readers (A and B) spaced ~10–15 cm apart.

When a tagged pet walks through, the system sees a sequence:

A → B = ENTER yard

B → A = EXIT yard

An ESP32 reads the two readers, determines direction, and publishes an MQTT JSON event (and optional “seen” pings for debugging/telemetry).

1) Choose your tag tech (quick guide)

You can do this with either 125 kHz RFID (longer collar-friendly range) or 13.56 MHz NFC (shorter range, cheaper readers):

Option A — 125 kHz (recommended for collars)

Typical parts: RDM6300 (or ID-12LA) readers; EM4100/EM4200 keyfob collar tags.

Range: usually 4–10 cm with a decent coil—better than most hobby NFC.

Wiring: simple UART (reader TX → ESP32 RX).

Great reliability for a gate “portal.”

Option B — 13.56 MHz NFC

Parts: MFRC522 (cheap) or PN532 (better but pricier) + NTAG/MIFARE keyfobs.

Range: 2–4 cm unless you build/choose a larger antenna.

Wiring: SPI (MFRC522) or SPI/I²C (PN532).

Works, but you must position the collar close to the antenna (narrower read zone).

If you want “pet just walks through” with minimal fuss, pick Option A (125 kHz).

2) Bill of Materials (for both)
Core (common)

ESP32 DevKit (ESP32-WROOM-32 dev board)

5 V power (≥1 A) + weatherproof cable

IP65 enclosure + cable glands

Mounting: 3D-printed or wood/plastic panels to hold antennas flush to gate frame

Two IR break-beam sensors (optional) to tighten direction logic (A then B vs B then A)
– but the two-reader order is usually enough

Option A — 125 kHz (recommended)

2× RDM6300 RFID readers (or 2× ID-12LA)

2× EM4100/EM4200 collar keyfobs (one per pet, buy extras)

Option B — 13.56 MHz NFC

2× MFRC522 readers (or 2× PN532)

2× NTAG213/215 or MIFARE collar tags

3) Physical layout (portal)

Mount Reader A on one side of the gate opening, Reader B on the other, co-planar, antennas facing each other.

Space 10–15 cm apart (tune for your tag/readers).

Aim the read zone so a collar passes ~3–6 cm from the antenna when the pet crosses.

Keep metal away from antennas or add a thin acrylic faceplate (doesn’t attenuate much).

Direction convention (you pick):

Let A = Outside, B = Inside.

Sequence A→B = ENTER yard

Sequence B→A = EXIT yard

4) Wiring (Option A: RDM6300 x2 → ESP32)

ESP32 pins (suggested):

Reader A TX → GPIO 26 (ESP32 RX for UART1)

Reader B TX → GPIO 27 (ESP32 RX for UART2)

Both readers: 5V and GND (share supply)

(RDM6300 is TX-only, no RX needed back to reader)

ESP32 has flexible UARTs. We’ll create two HardwareSerials and pin them as above.
Keep reader cables short and away from mains lines.

5) Firmware (Option A — 125 kHz RDM6300, two readers, MQTT + direction)

Paste into the Arduino IDE as pet_portal_rdm6300.ino and install PubSubClient (MQTT).
This sketch:

reads both readers,

de-duplicates noisy repeats,

infers direction by sequence within a time window,

publishes “seen” and “event” (enter/exit) to MQTT.

#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>

// ------------ USER CONFIG ------------
#define WIFI_SSID     "YOUR_WIFI"
#define WIFI_PASS     "YOUR_PASSWORD"

#define MQTT_HOST     "192.168.1.10"
#define MQTT_PORT     1883
#define MQTT_USER     "mqtt_user"   // "" if not needed
#define MQTT_PASS     "mqtt_pass"   // "" if not needed
#define MQTT_BASE     "home/pets/gate"  // topics: gate/seen, gate/event

#define DEVICE_NAME   "gate_portal_1"

// Reader side semantics:
#define A_IS_OUTSIDE  1   // if 1: A->B = ENTER, B->A = EXIT; if 0: reversed

// Timings
#define WINDOW_MS     3000   // max time between A then B (or B then A) to call it a crossing
#define DEDUP_MS      1500   // ignore same tag/side repeats within this window

// Pins (RDM6300 -> ESP32 RX only)
#define RX_A  26
#define RX_B  27

// ------------ END USER CONFIG --------

HardwareSerial RFID_A(1); // UART1
HardwareSerial RFID_B(2); // UART2

WiFiClient wifi;
PubSubClient mqtt(wifi);

struct SeenRec {
  String tag;
  char side;     // 'A' or 'B'
  uint32_t ms;   // millis when seen
};
#define MAX_REC 12
SeenRec lastSeen[MAX_REC]; // small ring buffer
int seenHead = 0;

struct Dedup {
  String tag;
  char side;
  uint32_t ms;
};
#define MAX_DEDUP 16
Dedup dedup[MAX_DEDUP];

struct NameMap {
  const char* tag;   // your 10-char hex from the RDM6300 (e.g., "0A00BC12EF")
  const char* pet;   // "Luna", "Max"
};
// Fill in once you know your tag IDs (printed to Serial/MQTT)
// Example placeholders:
NameMap names[] = {
  {"0A00BC12EF", "Luna"},
  {"1F00AA7742", "Max"},
};
const int N_NAMES = sizeof(names)/sizeof(names[0]);

// --- WiFi/MQTT ---
void wifiUp() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long t = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t < 20000) delay(200);
}
void mqttUp() {
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  while (!mqtt.connected()) {
    if (MQTT_USER[0]) {
      if (mqtt.connect(DEVICE_NAME, MQTT_USER, MQTT_PASS)) break;
    } else {
      if (mqtt.connect(DEVICE_NAME)) break;
    }
    delay(1000);
  }
}

// --- Utils ---
const char* petNameFor(const String& tag) {
  for (int i=0;i<N_NAMES;i++) if (tag.equalsIgnoreCase(names[i].tag)) return names[i].pet;
  return "unknown";
}
bool dedupHit(const String& tag, char side) {
  uint32_t now = millis();
  for (int i=0;i<MAX_DEDUP;i++) {
    if (dedup[i].tag == tag && dedup[i].side == side && (now - dedup[i].ms) < DEDUP_MS) {
      return true;
    }
  }
  // record/update slot
  int oldest = 0;
  uint32_t oldestMs = 0xFFFFFFFF;
  for (int i=0;i<MAX_DEDUP;i++) {
    if (dedup[i].tag.length()==0) { oldest = i; break; }
    if (dedup[i].ms < oldestMs) { oldest = i; oldestMs = dedup[i].ms; }
  }
  dedup[oldest] = {tag, side, now};
  return false;
}

void publishJSON(const String& topicSuffix, const String& payload) {
  String topic = String(MQTT_BASE) + "/" + topicSuffix;
  mqtt.publish(topic.c_str(), payload.c_str());
}

// --- RDM6300 frame parser ---
// RDM6300 typical frame: 0x02 + 10 ASCII HEX (ID) + 2 ASCII HEX (checksum) + 0x03
// We return the 10-hex ID as String (uppercase).
bool readRDM6300Frame(Stream& s, String& outId) {
  // look for STX
  if (!s.available()) return false;
  while (s.available()) {
    int b = s.read();
    if (b == 0x02) {
      // read until ETX or timeout
      String data = "";
      uint32_t start = millis();
      while ((millis() - start) < 30) {
        while (s.available()) {
          char c = (char)s.read();
          if (c == 0x03) {
            // done
            if (data.length() >= 12) {
              outId = data.substring(0, 10);
              outId.toUpperCase();
              return true;
            } else {
              return false;
            }
          } else {
            if (isprint((unsigned char)c)) data += c;
          }
        }
        delay(1);
      }
      return false;
    }
  }
  return false;
}

// --- Direction logic ---
// We push each sighting into a ring buffer. When we see side X, we check if the same tag
// was seen on the other side within WINDOW_MS. If yes, we emit ENTER/EXIT based on order.

void recordSeen(const String& tag, char side) {
  lastSeen[seenHead] = {tag, side, millis()};
  seenHead = (seenHead + 1) % MAX_REC;
}

bool findRecentOpposite(const String& tag, char side, SeenRec& recOut) {
  uint32_t now = millis();
  char other = (side=='A') ? 'B' : 'A';
  for (int i=0;i<MAX_REC;i++) {
    const SeenRec& r = lastSeen[i];
    if (r.tag == tag && r.side == other && (now - r.ms) < WINDOW_MS) {
      recOut = r;
      return true;
    }
  }
  return false;
}

void maybePublishDirection(const String& tag, char currentSide) {
  SeenRec prior;
  if (!findRecentOpposite(tag, currentSide, prior)) return;

  const char* pet = petNameFor(tag);
  const char* direction = "unknown";

  // Determine direction based on A/B order and A_IS_OUTSIDE
  // If we saw A then B within WINDOW_MS → "ENTER" when A is outside
  // If we saw B then A → "EXIT"
  if (prior.side=='A' && currentSide=='B') {
    direction = A_IS_OUTSIDE ? "enter" : "exit";
  } else if (prior.side=='B' && currentSide=='A') {
    direction = A_IS_OUTSIDE ? "exit" : "enter";
  }

  // Publish event (direction)
  String payload = "{";
  payload += "\"device\":\"" + String(DEVICE_NAME) + "\",";
  payload += "\"tag\":\"" + tag + "\",";
  payload += "\"pet\":\"" + String(pet) + "\",";
  payload += "\"direction\":\"" + String(direction) + "\",";
  payload += "\"t\":" + String((uint32_t)millis());
  payload += "}";

  publishJSON("event", payload);
  Serial.println("[EVENT] " + payload);
}

void publishSeen(const String& tag, char side) {
  const char* pet = petNameFor(tag);
  String payload = "{";
  payload += "\"device\":\"" + String(DEVICE_NAME) + "\",";
  payload += "\"tag\":\"" + tag + "\",";
  payload += "\"pet\":\"" + String(pet) + "\",";
  payload += "\"side\":\"" + String(side) + "\",";
  payload += "\"t\":" + String((uint32_t)millis());
  payload += "}";
  publishJSON("seen", payload);
  Serial.println("[SEEN] " + payload);
}

void setup() {
  Serial.begin(115200);

  // Two UARTs for the two readers (TX only from readers to these RX pins)
  RFID_A.begin(9600, SERIAL_8N1, RX_A, -1);
  RFID_B.begin(9600, SERIAL_8N1, RX_B, -1);

  wifiUp();
  mqttUp();

  Serial.println("Pet Portal (RDM6300 x2) ready.");
}

void loop() {
  if (!mqtt.connected()) mqttUp();
  mqtt.loop();

  // Reader A
  String id;
  if (readRDM6300Frame(RFID_A, id)) {
    if (!dedupHit(id, 'A')) {
      recordSeen(id, 'A');
      publishSeen(id, 'A');
      maybePublishDirection(id, 'A');
    }
  }

  // Reader B
  if (readRDM6300Frame(RFID_B, id)) {
    if (!dedupHit(id, 'B')) {
      recordSeen(id, 'B');
      publishSeen(id, 'B');
      maybePublishDirection(id, 'B');
    }
  }
}


How to get your tag IDs:

Power one reader, open Serial Monitor @115200, pass a tag by Reader A—you’ll see [SEEN] ... "tag":"XXXXXXXXXX". Copy into the names[] table with your pet’s name.

6) MQTT → Home Assistant

Sensors (quick start)

# configuration.yaml
mqtt:
  sensor:
    - name: "Pet Portal Last Event"
      state_topic: "home/pets/gate/event"
      value_template: "{{ value_json.pet ~ ' ' ~ value_json.direction }}"
    - name: "Pet Portal Last Seen"
      state_topic: "home/pets/gate/seen"
      value_template: "{{ value_json.pet ~ ' @ ' ~ value_json.side }}"


Automations (example)

automation:
  - alias: "Notify when pet exits"
    trigger:
      - platform: mqtt
        topic: home/pets/gate/event
    condition:
      - condition: template
        value_template: "{{ trigger.payload_json.direction == 'exit' }}"
    action:
      - service: notify.mobile_app_yourphone
        data:
          message: "{{ trigger.payload_json.pet }} just EXITED the yard."


You can also create binary_sensors per pet by matching payload_json.pet and direction.

7) Option B (NFC, MFRC522) wiring & code notes

Wiring (two MFRC522 on one SPI bus):

MOSI=23, MISO=19, SCK=18 (shared)

SS (SDA) A = 5, SS (SDA) B = 17 (unique)

RST A = 16, RST B = 4 (unique)

Both readers 3.3V (careful with power draw)

Core read loop (sketchlet)

#include <SPI.h>
#include <MFRC522.h>
#define SS_A 5
#define RST_A 16
#define SS_B 17
#define RST_B 4
MFRC522 mfrcA(SS_A, RST_A), mfrcB(SS_B, RST_B);

void setup(){
  SPI.begin();
  mfrcA.PCD_Init();
  mfrcB.PCD_Init();
}

bool readUID(MFRC522& r, String& uid){
  if (!r.PICC_IsNewCardPresent() || !r.PICC_ReadCardSerial()) return false;
  uid = "";
  for (byte i=0;i<r.uid.size;i++){ if (r.uid.uidByte[i]<16) uid += "0"; uid += String(r.uid.uidByte[i], HEX); }
  uid.toUpperCase();
  r.PICC_HaltA(); r.PCD_StopCrypto1();
  return true;
}

void loop(){
  String id;
  if (readUID(mfrcA, id)) { /* handle side A like above */ }
  if (readUID(mfrcB, id)) { /* handle side B like above */ }
}


Swap this into the main sketch where the RDM6300 reads occur and keep the same direction and MQTT logic.

8) Field tuning & reliability tips

Spacing/placement: start at 10–12 cm apart; adjust until both readers reliably see the tag as the pet crosses.

Antenna facing: keep antennas parallel; avoid metal nearby; mount behind thin acrylic or thin plastic.

Window & dedup: tweak WINDOW_MS (2–4 s) and DEDUP_MS (1–2 s) to your pets’ speed.

IR beams (optional): add two break-beams aligned with A and B. Use their trigger order as secondary confirmation for direction if you have a tricky portal.

Power: use a stable 5 V ≥1 A supply; put a 100 µF electrolytic near the readers.

Weatherproofing: keep electronics in an IP65 box, antennas behind a cover panel.

Interference: separate reader wires and AC mains; twist signal + GND pairs if runs are long.

9) Nice upgrades

Pet door automation: tie a relay to unlock a smart pet door only for allowed pets + time windows.

Server logging: mirror MQTT on a small Python service to SQLite/CSV and a dashboard.

BLE backup: add BLE beacon on the collar and use ESPHome BLE proxy for presence when the pet is in range (complements RFID direction at gate).

UWB (later): add UWB anchors for room-level tracking if you want to get fancy.

## for max distance
🐾 Backyard Pet Tracker with ESP32 + RDM6300 (max distance)
1. Hardware You’ll Need

ESP32 DevKitC (WROOM-32 dev board)

2× RDM6300 125 kHz RFID readers (UART output, small PCB with coil antenna)

EM4100/EM4200 RFID collar tags (waterproof keyfobs or epoxy “disk” tags are best for pets)

5 V DC power supply ≥1 A (USB adapter in weatherproof enclosure)

IP65 enclosure for electronics, cable glands

Mounting panels (thin acrylic/plastic) to protect and hold antennas flat at the gate

Wiring (dupont or soldered leads, short as possible from reader to ESP32)

2. Physical Setup

Mount Reader A on the outside of the gate, Reader B on the inside.

Position them 10–15 cm apart facing each other, so a collar passes through both fields when a pet walks through.

Tag range with RDM6300 + EM4100 fobs is usually 4–10 cm; adjust antenna placement to catch collars reliably.

Convention:

A → B = Enter (pet came into yard)

B → A = Exit (pet left yard)

3. Wiring (ESP32 ↔ RDM6300)

Each RDM6300 only transmits tag ID via TX pin (no RX needed back).

Reader A TX → ESP32 GPIO 26 (UART1 RX)

Reader B TX → ESP32 GPIO 27 (UART2 RX)

Both readers 5V → ESP32 5V, GND → ESP32 GND

👉 Keep wires short, use twisted pair (TX+GND together) if longer runs.

4. Firmware (Arduino IDE)
Libraries:

PubSubClient (MQTT)

WiFi.h (built-in)

Sketch (pet_portal_rdm6300.ino)

This firmware:

Connects to WiFi + MQTT

Reads both RDM6300 readers

Detects sequence A→B or B→A within 3 seconds → publishes ENTER/EXIT event

Publishes raw “seen” events too

I included this in my last message, but here’s the essentials:

// Configure pins
#define RX_A 26   // Reader A TX -> GPIO26
#define RX_B 27   // Reader B TX -> GPIO27

HardwareSerial RFID_A(1);  // UART1
HardwareSerial RFID_B(2);  // UART2

// WiFi + MQTT setup ...
// (see full sketch above for complete code)

// Read RDM6300 frames -> get tag ID
bool readRDM6300Frame(Stream& s, String& outId) {
  if (!s.available()) return false;
  while (s.available()) {
    int b = s.read();
    if (b == 0x02) {  // STX
      String data = "";
      while (s.available()) {
        char c = (char)s.read();
        if (c == 0x03) {  // ETX
          if (data.length() >= 10) {
            outId = data.substring(0, 10); // 10 hex chars
            outId.toUpperCase();
            return true;
          }
        } else {
          data += c;
        }
      }
    }
  }
  return false;
}


👉 Full sketch (with WiFi, MQTT, event logic) is the long one I gave above — you can copy/paste that directly.

5. Get Your Tag IDs

Flash firmware

Open Serial Monitor @115200

Swipe each collar tag past Reader A

You’ll see output like:

[SEEN] {"tag":"0A00BC12EF","pet":"unknown","side":"A"}


Copy the tag hex string into the names[] table in the sketch:

NameMap names[] = {
  {"0A00BC12EF", "Luna"},
  {"1F00AA7742", "Max"},
};

6. MQTT → Home Assistant

The sketch publishes JSON to:

home/pets/gate/seen (every read, with tag/side)

home/pets/gate/event (only when direction resolved: enter/exit)

Example automation (HA YAML):

automation:
  - alias: Notify when pet exits
    trigger:
      - platform: mqtt
        topic: home/pets/gate/event
    condition:
      - condition: template
        value_template: "{{ trigger.payload_json.direction == 'exit' }}"
    action:
      - service: notify.mobile_app_myphone
        data:
          message: "{{ trigger.payload_json.pet }} just left the yard"

7. Tips for Reliable Reads

Portal spacing: Start ~12 cm apart, adjust until both reliably see the tag.

Tag placement: On collar front (chest area) gives best read as pet squeezes through.

Time windows: Adjust WINDOW_MS in code (3 s default) if your pets are faster/slower.

Weatherproofing: Put electronics in a waterproof box; only coil antennas need to be “exposed” behind acrylic.

## Wiring
🐾 Backyard Pet Tracker with ESP32 + RDM6300
1. Hardware

ESP32 DevKitC (WROOM-32)

2× RDM6300 125 kHz RFID readers

2× EM4100/EM4200 RFID collar tags (waterproof keyfobs recommended)

5 V 1 A+ USB power supply & cable

IP65 enclosure + cable glands

Thin acrylic/plastic panel to mount readers behind

2. Wiring

Reader A TX → ESP32 GPIO26 (UART1 RX)

Reader B TX → ESP32 GPIO27 (UART2 RX)

Both readers 5 V → ESP32 5 V

Both readers GND → ESP32 GND

ESP32 connects via Wi-Fi to MQTT broker

📷 Wiring Diagram:


3. Firmware Setup

Install Arduino IDE + ESP32 board support

Add PubSubClient library (for MQTT)

Flash the provided sketch: pet_portal_rdm6300.ino

Open Serial Monitor @115200 to read tag IDs when you swipe a collar tag

4. Tag Registration

Swipe each pet’s collar tag by Reader A

Serial Monitor will print the 10-character hex ID

Copy these IDs into the firmware names[] table, e.g.:

NameMap names[] = {
  {"0A00BC12EF", "Luna"},
  {"1F00AA7742", "Max"},
};

5. MQTT / Home Assistant

MQTT Topics:

home/pets/gate/seen → raw sightings (tag + side A/B)

home/pets/gate/event → resolved events (enter/exit)

Example automation (HA YAML):

automation:
  - alias: Notify when pet exits
    trigger:
      - platform: mqtt
        topic: home/pets/gate/event
    condition:
      - condition: template
        value_template: "{{ trigger.payload_json.direction == 'exit' }}"
    action:
      - service: notify.mobile_app_myphone
        data:
          message: "{{ trigger.payload_json.pet }} just left the yard"

6. Field Tips

Mount readers ~10–15 cm apart, antennas facing each other

Put tags on collar front/chest area for best reads

Tune firmware constants:

WINDOW_MS = crossing window (default 3000 ms)

DEDUP_MS = ignore duplicate same-side reads (default 1500 ms)

Use a weatherproof box for ESP32 + electronics; only reader coils need to be “exposed”

Add a 100 µF capacitor near ESP32 5 V input to handle power spikes

🖇️ Backyard Pet Tracker Wiring (ESP32 + 2× RDM6300)

Connections:

Reader A (Outside gate)

TX → ESP32 GPIO26 (UART1 RX)

5V → ESP32 5V

GND → ESP32 GND

Reader B (Inside gate)

TX → ESP32 GPIO27 (UART2 RX)

5V → ESP32 5V

GND → ESP32 GND

ESP32

Powered by same 5V supply (USB adapter in weatherproof box)

Connects to Wi-Fi → Publishes MQTT messages (topics: /seen, /event)

🔄 Logical Flow

Pet with collar tag walks through gate.

Reader A sees tag first, then Reader B → interpreted as ENTER yard.

Reader B sees tag first, then Reader A → interpreted as EXIT yard.

ESP32 publishes JSON event to MQTT, e.g.:

{
  "device": "gate_portal_1",
  "tag": "0A00BC12EF",
  "pet": "Luna",
  "direction": "exit",
  "t": 3456789
}

📝 Quick Sketch Guide

If you want to re-draw this on paper or in Fritzing:

Draw an ESP32 DevKitC rectangle in the center.

On the left, Reader A box → arrow “TX → GPIO26” + shared 5V/GND lines.

On the right, Reader B box → arrow “TX → GPIO27” + shared 5V/GND lines.

On the bottom, a “5V USB supply” feeding both the ESP32 and the readers.

On the top, draw a cloud labeled “Wi-Fi → MQTT broker.”