# Drone Landing Pad + Charging Station
The idea is: your drone lands on a pad, pads align the contacts (or inductive coils), the ESP32 manages safe charging, and optionally reports to Home Assistant or pushes alerts.
* NeoPixel guidance ring at dusk
* a pad marker (QR/AprilTag) for the drone’s self-alignment
* an ESP32-CAM that grabs a snapshot on touchdown for verification

## What this system does

Provides a flat, visible landing target (possibly with LEDs for guidance).

Aligns the drone with charging contacts (spring pins, copper pads, or induction coils).

Uses an ESP32 to:

Detect when the drone has landed.

Enable/disable charging safely.

Monitor battery voltage/current (optional).

Push status (MQTT/push alerts).

(Optional) Relay or MOSFET to cut power to pad when drone is flying.

## Hardware
NeoPixel ring (WS2812/WS2812B, 12–24 LEDs)

Ambient light sensor (either a simple LDR + 100 kΩ divider to ADC, or BH1750 I²C)

ESP32-CAM (AI-Thinker) + 5 V (≥1 A)

Printed fiducial marker (QR or AprilTag/ArUco) laminated on the pad surface

ESP32 DevKitC (WROOM-32)

12–24 V DC supply (to match your drone’s charger or LiPo charging board input)

Step-down DC-DC module (to regulate for pad, LEDs, sensors if needed)

Charging contacts:

Option A (simpler): Spring-loaded pogo pins (on pad) touching copper plates (under drone skids/legs).

Option B (advanced): Inductive charging coils (Qi modules, higher complexity).

Relay or MOSFET module (to switch pad charging power on/off).

Current sensor (INA219 or ACS712) to monitor charging.

Landing detection:

Pressure/weight sensor (load cell), or

Limit switches under pad, or

Simple “contact detected = drone landed.”

LED strips / Neopixels (optional for pad guidance).

Enclosure (weatherproof if outdoors).

Step 1: Pad surface

Build a flat plywood/acrylic disk (30–60 cm diameter depending on drone).

Print or paint H-style landing marker in high-contrast colors.

Mount copper pads (foil tape or PCB sections) flush into surface where drone’s skids/feet align.

Add spring pogo pins (gold-plated) at matching spots.

Step 2: Charging interface

Connect pogo pins to a relay-controlled line that feeds the drone’s charger input.

Important: don’t connect raw supply to the drone! Instead:

Either: feed into the drone’s charge port (if it supports DC input).

Or: route through a smart charging board (LiPo charger) that’s tuned for your battery chemistry.

Add a diode or ideal MOSFET arrangement so current can’t backfeed when no drone is present.

Step 3: Landing detection

Options:

Simplest: detect continuity between pogo pins (when drone sits, contacts short → ESP32 senses low-ohm path).

Better: use a load cell under pad to detect weight > X grams.

Backup: small microswitches under legs.

Step 4: ESP32 wiring

GPIO 26 → Relay IN (controls pad charging line).

GPIO 34 → Voltage divider sense (detects pad voltage).

SDA/SCL → INA219 current sensor (optional).

GPIO 18/19 → Neopixel data (optional LED ring).

Step 5: Firmware flow

ESP32 boots, relay = OFF (safe).

Pad idle: publish pad/idle.

Drone lands → contact/weight detected.

ESP32 waits 2–3 sec (stabilize).

Relay ON → enable charging line.

Measure current/voltage; publish charging state.

If drone lifts off (contacts open or weight < threshold) → Relay OFF immediately, publish pad/empty.

Step 6: MQTT integration

Topics like:

dronepad/status → idle, landed, charging

dronepad/voltage → V

dronepad/current → A

dronepad/alerts → e.g., “drone lifted, charging stopped”

4. Example firmware (Arduino IDE)
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>

// === Config ===
#define WIFI_SSID "YOUR_WIFI"
#define WIFI_PASS "YOUR_PASS"
#define MQTT_HOST "192.168.1.10"
#define MQTT_PORT 1883
#define MQTT_USER "mqtt_user"
#define MQTT_PASS "mqtt_pass"

#define RELAY_PIN 26
#define CONTACT_PIN 34   // reads voltage/contact presence
#define THRESHOLD 1000   // ADC threshold for "landed"

// === Globals ===
WiFiClient espClient;
PubSubClient mqtt(espClient);

enum PadState { IDLE, LANDED, CHARGING };
PadState state = IDLE;

void wifiUp() {
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  while (WiFi.status() != WL_CONNECTED) delay(500);
}
void mqttUp() {
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  while (!mqtt.connected()) {
    mqtt.connect("dronepad", MQTT_USER, MQTT_PASS);
    delay(500);
  }
}

void publish(const char* topic, const char* msg) {
  mqtt.publish(topic, msg, true);
}

void setup() {
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW); // safe off
  pinMode(CONTACT_PIN, INPUT);
  Serial.begin(115200);
  wifiUp(); mqttUp();
  publish("dronepad/status","idle");
}

void loop() {
  if (!mqtt.connected()) mqttUp();
  mqtt.loop();

  int val = analogRead(CONTACT_PIN);
  if (val > THRESHOLD) {
    if (state == IDLE) {
      state = LANDED;
      publish("dronepad/status","landed");
      delay(2000); // wait stabilize
      digitalWrite(RELAY_PIN,HIGH);
      state = CHARGING;
      publish("dronepad/status","charging");
    }
  } else {
    if (state != IDLE) {
      digitalWrite(RELAY_PIN,LOW);
      state = IDLE;
      publish("dronepad/status","idle");
    }
  }

  delay(500);
}

5. Safety notes ⚠️

Never charge LiPos directly from a raw supply. Use a smart charger module or ensure your drone supports DC-in charging.

Relay module only controls low-voltage charger output or a DC supply into the charger, not mains AC.

Add fuse or resettable polyfuse between supply and charging line.

Ensure contacts are gold-plated for corrosion resistance outdoors.


2) Wiring additions (text diagram)
[NeoPixel ring]
  Din  ---- GPIO18 (ESP32)
  5V   ---- 5V (same supply as ESP32)
  GND  ---- GND (common with ESP32)
  (add 330 Ω inline on Din; add 1000 µF electrolytic across 5V/GND near ring)

[Light sensor (choose one)]
  A) LDR + 100k divider:
     LDR ─┬─ 3.3V
           └─ node → ESP32 GPIO33 (ADC)
     100k ─┬─ GND
  B) BH1750 I²C:
     SDA → GPIO21, SCL → GPIO22, VCC→3.3V, GND→GND

[ESP32-CAM]  (separate module for snapshots)
  5V  → 5V PSU     GND → GND (common)
  (no extra pins needed unless you add PIR/trigger)


(Keep all grounds common across ESP32, ESP32-CAM, charger, relay, and LEDs.)

3) Pad marker for self-alignment

Print a large AprilTag (family 36h11) or a high-contrast QR code (≥20 cm square).

Mount it centered on the pad, matte-laminated (no glare).

Your drone’s downward camera or autopilot can lock to this marker to finish the landing.

Keep a bold “H” ring and the LED ring concentric with the marker to help visual servoing.

4) ESP32 (pad controller) — firmware with NeoPixels + dusk logic

Libraries (Arduino IDE):
PubSubClient, Adafruit_NeoPixel (+ your existing Wi-Fi/MQTT setup)

drone_pad_controller.ino (core additions)
#include <Adafruit_NeoPixel.h>

// --- NeoPixel config ---
#define PIX_PIN      18
#define PIX_COUNT    16
#define PIX_BRIGHT   35     // 0..255
Adafruit_NeoPixel ring(PIX_COUNT, PIX_PIN, NEO_GRB + NEO_KHZ800);

// --- Dusk sensing (pick one) ---
#define LDR_PIN      33     // comment if you use BH1750
#define DUSK_ADC_THR 2400   // ~0..4095 scale; tune for your divider & environment
bool isDusk = false;

// Existing: RELAY_PIN=26, CONTACT_PIN=34, MQTT, etc.

void pixelsOff(){
  ring.clear(); ring.show();
}

void pixelsGlow(uint32_t color, uint8_t maxB=PIX_BRIGHT){
  static uint8_t t=0; t++;
  float s = 0.5f + 0.5f * sinf(t*0.1f);     // soft breathing
  ring.fill(ring.Color((uint8_t)( (color>>16)&0xFF * s ),
                       (uint8_t)( (color>>8 )&0xFF * s ),
                       (uint8_t)( (color    )&0xFF * s )));
  ring.setBrightness(maxB);
  ring.show();
}

void pixelsChevron(uint32_t color){
  static int k=0; k=(k+1)%PIX_COUNT;
  ring.clear();
  for (int i=0;i<PIX_COUNT;i++){
    uint8_t d = (uint8_t)((PIX_COUNT + i - k) % PIX_COUNT);
    uint8_t b = (uint8_t)max(10, 255 - d*22);
    ring.setPixelColor(i, ring.Color((uint8_t)((color>>16)&0xFF * b/255.0),
                                     (uint8_t)((color>>8 )&0xFF * b/255.0),
                                     (uint8_t)((color    )&0xFF * b/255.0)));
  }
  ring.setBrightness(PIX_BRIGHT);
  ring.show();
}

void setup(){
  // ... your existing Wi-Fi/MQTT/relay setup ...
  ring.begin(); ring.setBrightness(PIX_BRIGHT); pixelsOff();
  pinMode(LDR_PIN, INPUT);
}

void loop(){
  // ... your existing MQTT state machine (IDLE / LANDED / CHARGING) ...

  // Dusk detection (simple LDR). If using BH1750, set isDusk = (lux < threshold)
  int adc = analogRead(LDR_PIN);
  isDusk = (adc > DUSK_ADC_THR);

  // Lighting policy:
  //  IDLE daytime  -> off
  //  IDLE dusk     -> slow glow (warm white) to guide approach
  //  LANDED/CHARGING -> chevron chase (cyan/green)
  if (state == IDLE){
    if (isDusk) pixelsGlow(ring.Color(255, 120, 40));   // warm amber glow
    else pixelsOff();
  } else if (state == LANDED || state == CHARGING){
    pixelsChevron(ring.Color(60, 255, 180));            // cyan/green chase
  }

  // Remember to keep publishing status over MQTT as before.
}


Tip: put a 330 Ω resistor inline on the NeoPixel Din and a 1000 µF cap across the ring’s 5 V/GND to keep LEDs stable when the relay/charger kicks in.

5) ESP32-CAM — snapshot on touchdown (MQTT-triggered)

Let the pad controller publish dronepad/status = "charging" after the relay turns on.
Have the ESP32-CAM subscribe to that topic; when it sees "charging", it captures a JPEG and POSTs to your server (or directly to Home Assistant via a webhook/automation).

Libraries: core WiFi.h, PubSubClient, HTTPClient, esp_camera.h.

esp32cam_snap_on_charge.ino
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <HTTPClient.h>
#include "esp_camera.h"

#define WIFI_SSID "YOUR_WIFI"
#define WIFI_PASS "YOUR_PASS"
#define MQTT_HOST "192.168.1.10"
#define MQTT_PORT 1883
#define MQTT_USER "mqtt_user"
#define MQTT_PASS "mqtt_pass"
#define SUB_TOPIC "dronepad/status"       // published by the pad controller
#define POST_URL  "http://YOUR_SERVER_IP:8000/dronepad/snapshot"
#define DEVICE_ID "dronepad_cam_1"

// AI-Thinker pin map
#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27
#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22

WiFiClient net; PubSubClient mqtt(net);

bool initCam(){
  camera_config_t c;
  c.ledc_channel=LEDC_CHANNEL_0; c.ledc_timer=LEDC_TIMER_0;
  c.pin_d0=Y2_GPIO_NUM; c.pin_d1=Y3_GPIO_NUM; c.pin_d2=Y4_GPIO_NUM; c.pin_d3=Y5_GPIO_NUM;
  c.pin_d4=Y6_GPIO_NUM; c.pin_d5=Y7_GPIO_NUM; c.pin_d6=Y8_GPIO_NUM; c.pin_d7=Y9_GPIO_NUM;
  c.pin_xclk=XCLK_GPIO_NUM; c.pin_pclk=PCLK_GPIO_NUM; c.pin_vsync=VSYNC_GPIO_NUM;
  c.pin_href=HREF_GPIO_NUM; c.pin_sscb_sda=SIOD_GPIO_NUM; c.pin_sscb_scl=SIOC_GPIO_NUM;
  c.pin_pwdn=PWDN_GPIO_NUM; c.pin_reset=RESET_GPIO_NUM;
  c.xclk_freq_hz=20000000; c.pixel_format=PIXFORMAT_JPEG;
  c.frame_size=FRAMESIZE_SVGA; c.jpeg_quality=12; c.fb_count=1; c.fb_location=CAMERA_FB_IN_PSRAM;
  return esp_camera_init(&c)==ESP_OK;
}

void wifiUp(){
  WiFi.mode(WIFI_STA); WiFi.begin(WIFI_SSID, WIFI_PASS);
  for (int i=0;i<60 && WiFi.status()!=WL_CONNECTED;i++) delay(250);
}
void mqttUp(){
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  while (!mqtt.connected()){
    if (MQTT_USER[0]) { mqtt.connect(DEVICE_ID, MQTT_USER, MQTT_PASS); }
    else { mqtt.connect(DEVICE_ID); }
    delay(500);
  }
  mqtt.subscribe(SUB_TOPIC);
}

bool postImage(const uint8_t* buf, size_t len){
  HTTPClient http; if(!http.begin(POST_URL)) return false;
  http.addHeader("Content-Type","application/octet-stream");
  http.addHeader("X-Device-Id", DEVICE_ID);
  int code = http.POST(buf, len);
  http.end();
  return code>=200 && code<300;
}

void onMsg(char* topic, byte* payload, unsigned int len){
  String msg; for (unsigned i=0;i<len;i++) msg += (char)payload[i];
  msg.trim();
  if (msg == "charging"){               // touchdown confirmed
    camera_fb_t* fb = esp_camera_fb_get();
    if (fb){ postImage(fb->buf, fb->len); esp_camera_fb_return(fb); }
  }
}

void setup(){
  Serial.begin(115200);
  wifiUp();
  if (!initCam()) { Serial.println("cam init fail"); }
  mqtt.setCallback(onMsg);
  mqttUp();
}

void loop(){
  if (!mqtt.connected()) mqttUp();
  mqtt.loop();
  delay(10);
}


Server (optional FastAPI receiver) — drop into your existing server:

# dronepad_server.py (snippet)
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from pathlib import Path
from PIL import Image
import io, time, uuid

app = FastAPI()
SNAPS = Path("./dronepad_snaps"); SNAPS.mkdir(exist_ok=True)

@app.post("/dronepad/snapshot")
async def snapshot(request: Request):
  raw = await request.body()
  dev = request.headers.get("X-Device-Id","padcam")
  try:
    img = Image.open(io.BytesIO(raw)).convert("RGB")
  except Exception:
    return JSONResponse({"error":"bad image"}, status_code=400)
  name = f"{int(time.time())}_{uuid.uuid4().hex[:8]}_{dev}.jpg"
  img.save(SNAPS/name, quality=90)
  return {"ok": True, "file": name}

6) Behavior summary

Dusk: NeoPixel ring does a soft amber glow (guidance without glare).

Touchdown (contacts/weight): ring flips to moving chevrons; relay ON; status → "charging".

ESP32-CAM (listening on MQTT): receives "charging" → captures & uploads snapshot.

Home Assistant can show the last image (from your server folder) and push “charging started” with a photo.

7) Safety & power notes (important)

Keep LED 5 V supply separate but common-grounded with logic; size it for the ring (60 mA per white LED at full blast; you’re running dim ~35/255).

Add a blade fuse on the charger output to the pad contacts.

Never feed raw supply straight to the drone battery; always go through the drone’s supported charge port or a smart charger matched to the pack chemistry.

Weatherproof the pad; gold-plate contacts if possible.

## Wiring
                ┌─────────────────────┐
                │   Smart Charger /   │
                │   DC Supply (5–24V) │
                └─────────┬───────────┘
                          │ +V in
                          ▼
                   ┌──────────────┐
                   │  Relay Module│◄──── GPIO26 (ESP32)
                   └───────┬──────┘
                           │ Switched +V
                           ▼
                 ┌───────────────────────┐
                 │  Drone Pad Contacts   │
                 │ (pogo pins / plates + │
                 │  QR/AprilTag marker)  │
                 └─────────┬────────────┘
                           │
                         GND───────────────┐
                                           │
    ┌──────────────────────┐               │
    │       ESP32          │               │
    │   DevKitC (Main)     │               │
    │                      │               │
    │   GPIO18 ────────────┼──► NeoPixel Ring (guidance LEDs)
    │   GPIO33 ────────────┼──► LDR / Light Sensor (dusk detect)
    │   GPIO26 ────────────┼──► Relay Control
    │   GPIO34 ────────────┼──► Pad Contact Sense (landing detect)
    │                      │
    └──────────────────────┘
                          │
                          ▼
                    Wi-Fi / MQTT
                          │
             ┌──────────────────────┐
             │   ESP32-CAM Module   │
             │ (snapshot on landing)│
             └──────────────────────┘

Flow: Charger → Relay → Pad contacts.
🔹 ESP32: handles relay, dusk detection, LEDs, and landing detection.
🔹 ESP32-CAM: listens for "charging" MQTT state, snaps a picture, and uploads.
🔹 NeoPixel Ring: lights up at dusk or when charging.
🔹 LDR: triggers dusk detection (or replace with BH1750 I²C sensor).