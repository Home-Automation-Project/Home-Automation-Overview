# Plant Monitor
monitor soil and environment while also snapping photos of leaves for disease detection.

🌿 Project Overview

Plant Monitor Node (ESP32 + E-Ink)

Sensors: SHT31 (temp/humidity), BH1750 (light), capacitive soil moisture (analog), optional pH (analog).

Waveshare 2.9" e-Paper display.

Sends data via MQTT with Home Assistant auto-discovery.

Sleeps between measurements to save power.

Vision Node (ESP32-CAM)

Takes a leaf photo every X minutes.

Uploads JPEG to your FastAPI server.

Runs on AI Thinker ESP32-CAM module.

Classifier Server (FastAPI, Python)

Receives JPEGs, runs a simple heuristic (green vs yellow/brown pixels).

Returns “healthy” or “possible_disease” JSON.

Can publish results back to MQTT.

🛠️ Hardware Needed

ESP32 DevKitC (or similar)

AI Thinker ESP32-CAM module

SHT31 sensor (I²C)

BH1750 light sensor (I²C)

Capacitive soil moisture sensor (analog, 3.3V compatible)

(Optional) pH probe + analog board (3.3V version)

Waveshare 2.9" e-Paper (SPI, GxEPD2 supported)

Power: USB or 5V solar/battery

Small Linux box / Pi / PC to run the FastAPI classifier server

🔌 Wiring (Plant Monitor Node)

ESP32 DevKitC pins:

I²C: SDA → GPIO21, SCL → GPIO22

E-Ink: CS=5, DC=17, RST=16, BUSY=4, SCLK=18, MOSI=23, MISO=19

Soil moisture: AOUT → GPIO34

pH probe: AOUT → GPIO35 (optional)

📲 Step-by-Step Build
1. Prepare Plant Monitor Node

Install Arduino IDE + ESP32 board package.

Install required libraries:

GxEPD2, Adafruit SHT31, BH1750, PubSubClient, ArduinoJson.

Open plant_monitor/plant_monitor.ino.

Edit config.h:

Wi-Fi SSID + password.

MQTT host/port/user/pass.

Sleep interval (e.g., 10 minutes).

Soil calibration values (AIR_CAL, WATER_CAL).

Upload sketch to ESP32.

Verify that E-Ink updates and publishes data to MQTT/Home Assistant.

2. Prepare Vision Node (ESP32-CAM)

In Arduino IDE, select AI Thinker ESP32-CAM.

Open esp32_cam_vision/esp32_cam_vision.ino.

Edit config.h:

Wi-Fi SSID + password.

Server URL (your classifier PC IP, e.g. http://192.168.1.50:8000/predict).

Capture interval (minutes).

Flash to ESP32-CAM.

Power it with 5V, it will start uploading JPEGs every interval.

3. Run the Classifier Server

On your PC or Raspberry Pi:

cd server
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python classifier_server.py


Server listens at http://0.0.0.0:8000/predict.

Health check: http://<server_ip>:8000/healthz.

4. Integration

Plant monitor sends metrics like temperature, humidity, lux, soil moisture via MQTT.

ESP32-CAM sends images → server → classifier → optional MQTT topic:
home/plant/<device>/vision/result.

Home Assistant auto-discovers the metrics.

## Code
📂 Project: esp32-plant-health-monitor
1. Root
README.md
# ESP32 Plant Health Monitor (E-Ink + Leaf Disease Detection)

Two ESP32 nodes + optional FastAPI classifier:

1) **Plant Monitor Node (ESP32 + E-Ink)**:  
   - Sensors: SHT31 (temp/humidity), BH1750 (light), Capacitive Soil Moisture (ADC), optional pH (ADC).  
   - Sends MQTT (Home Assistant auto-discovery).  
   - Shows data on Waveshare 2.9" e-paper.  

2) **Vision Node (ESP32-CAM)**:  
   - Captures leaf photos and POSTs JPEG to the classifier server.  

3) **Classifier Server (FastAPI, Python)**:  
   - Receives images, runs a heuristic (green vs yellow/brown pixels).  
   - Returns “healthy” or “possible_disease” JSON.  
   - Optionally publishes results to MQTT.  

See `plant_monitor/README_PLANT.md` and `server/README_SERVER.md` for details.

2. Folder: plant_monitor
LIBRARIES.md
# Arduino Libraries (Plant Monitor)

Install via Arduino Library Manager:

- GxEPD2 (Jean-Marc Zingg)
- Adafruit SHT31 Library
- BH1750 (Christopher Laws)
- PubSubClient (Nick O'Leary)
- ArduinoJson (Benoit Blanchon)

config.h
#pragma once
#define WIFI_SSID        "YOUR_WIFI_SSID"
#define WIFI_PASS        "YOUR_WIFI_PASSWORD"

#define MQTT_HOST        "192.168.1.10"
#define MQTT_PORT        1883
#define MQTT_USER        "mqtt_user"
#define MQTT_PASS        "mqtt_pass"

#define DEVICE_NAME      "plant1"
#define FRIENDLY_NAME    "Backyard Basil"
#define HA_DISCOVERY_PREFIX "homeassistant"

#define SLEEP_MINUTES    10

#define I2C_SDA          21
#define I2C_SCL          22

#define EPD_CS           5
#define EPD_DC           17
#define EPD_RST          16
#define EPD_BUSY         4
#define EPD_SCLK         18
#define EPD_MOSI         23
#define EPD_MISO         19

#define PIN_SOIL_ADC     34
#define PIN_PH_ADC       35

#define AIR_CAL          2800
#define WATER_CAL        1200

#define PH4_ADC          2400
#define PH7_ADC          1700

#define DISPLAY_ROTATION 1
#define ENABLE_PH        0
#define MQTT_RETAIN      false

plant_monitor.ino
#include <Arduino.h>
#include "config.h"
#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <Adafruit_SHT31.h>
#include <BH1750.h>
#include <ArduinoJson.h>
#include <GxEPD2_BW.h>
#include <Fonts/FreeMonoBold9pt7b.h>
#include <Fonts/FreeSans9pt7b.h>
#include <Fonts/FreeSansBold12pt7b.h>

GxEPD2_BW<GxEPD2_290, GxEPD2_290::HEIGHT> display(GxEPD2_290(EPD_CS, EPD_DC, EPD_RST, EPD_BUSY));
Adafruit_SHT31 sht31 = Adafruit_SHT31();
BH1750 lightMeter;
WiFiClient espClient;
PubSubClient mqtt(espClient);

char baseTopic[64];
char statTopic[96];
char availTopic[96];

void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) delay(250);
}

void connectMQTT() {
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  String clientId = String("plant-") + DEVICE_NAME + "-" + String((uint32_t)ESP.getEfuseMac(), HEX);
  while (!mqtt.connected()) {
    if (MQTT_USER[0]) {
      if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS, availTopic, 1, true, "offline")) break;
    } else {
      if (mqtt.connect(clientId.c_str(), nullptr, nullptr, availTopic, 1, true, "offline")) break;
    }
    delay(1000);
  }
  mqtt.publish(availTopic, "online", true);
}

float adcToMoisturePct(int raw) {
  float pct = 100.0f * (float)(AIR_CAL - raw) / (float)(AIR_CAL - WATER_CAL);
  if (pct < 0) pct = 0; if (pct > 100) pct = 100;
  return pct;
}

float adcToPH(int raw) {
  float slope = (7.0f - 4.0f) / (float)(PH7_ADC - PH4_ADC);
  return 7.0f + slope * (raw - PH7_ADC);
}

void drawScreen(float t, float h, float lux, float soilPct, float ph, bool ok) {
  display.setRotation(DISPLAY_ROTATION);
  display.setTextColor(GxEPD_BLACK);
  display.setFont(&FreeSansBold12pt7b);

  display.firstPage();
  do {
    display.fillScreen(GxEPD_WHITE);
    display.setCursor(4, 20);
    display.print(String(FRIENDLY_NAME));

    display.setFont(&FreeSans9pt7b);
    display.setCursor(4, 45);
    display.printf("Temp: %.1f C   Hum: %.0f%%", t, h);
    display.setCursor(4, 70);
    display.printf("Light: %.0f lx", lux);
    display.setCursor(4, 95);
    display.printf("Soil:  %.0f%%", soilPct);
    #if ENABLE_PH
      display.setCursor(4, 120);
      display.printf("pH:    %.2f", ph);
    #endif

    display.setFont(&FreeMonoBold9pt7b);
    display.setCursor(220, 20);
    display.print(ok ? "[OK]" : "[!]");
  } while (display.nextPage());
}

void deepSleepMinutes(uint32_t minutes) {
  esp_sleep_enable_timer_wakeup((uint64_t)minutes * 60ULL * 1000000ULL);
  esp_deep_sleep_start();
}

void setup() {
  pinMode(PIN_SOIL_ADC, INPUT);
  #if ENABLE_PH
  pinMode(PIN_PH_ADC, INPUT);
  #endif

  Wire.begin(I2C_SDA, I2C_SCL);
  SPI.begin(EPD_SCLK, EPD_MISO, EPD_MOSI);
  display.init(115200);

  sht31.begin(0x44);
  lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE);

  snprintf(baseTopic, sizeof(baseTopic), "home/plant/%s", DEVICE_NAME);
  snprintf(statTopic, sizeof(statTopic), "%s/state", baseTopic);
  snprintf(availTopic, sizeof(availTopic), "%s/availability", baseTopic);

  connectWiFi();
  connectMQTT();

  float t = sht31.readTemperature();
  float h = sht31.readHumidity();
  if (isnan(t) || isnan(h)) { t = NAN; h = NAN; }

  float lux = lightMeter.readLightLevel();

  analogSetWidth(12);
  analogSetAttenuation(ADC_11db);
  int soilRaw = analogRead(PIN_SOIL_ADC);
  float soilPct = adcToMoisturePct(soilRaw);

  float ph = NAN;
  #if ENABLE_PH
    int phRaw = analogRead(PIN_PH_ADC);
    ph = adcToPH(phRaw);
  #endif

  StaticJsonDocument<256> st;
  st["temperature_c"] = t;
  st["humidity_pct"] = h;
  st["illuminance_lux"] = lux;
  st["soil_moisture_pct"] = soilPct;
  #if ENABLE_PH
    st["ph"] = ph;
  #endif
  char payload[256];
  serializeJson(st, payload, sizeof(payload));
  mqtt.publish(statTopic, payload, MQTT_RETAIN);

  bool ok = soilPct >= 20 && soilPct <= 60 && !isnan(h) && h >= 20 && h <= 90;
  drawScreen(t, h, lux, soilPct, ph, ok);

  mqtt.publish(availTopic, "offline", true);
  delay(50);
  deepSleepMinutes(SLEEP_MINUTES);
}

void loop() {}

README_PLANT.md
# Plant Monitor Tips

- If E-Ink is blank: verify BUSY/DC/CS pins and SPI wiring.  
- If SHT31 reads NaN: try address 0x45 and recheck SDA=21/SCL=22.  
- Calibrate soil moisture: log raw ADC in air and saturated soil, update AIR_CAL/WATER_CAL.  
- For pH, do 2-point calibration with pH 4 and 7 buffers and update PH4_ADC/PH7_ADC.  

3. Folder: esp32_cam_vision
config.h
#pragma once
#define WIFI_SSID    "YOUR_WIFI_SSID"
#define WIFI_PASS    "YOUR_WIFI_PASSWORD"
#define SERVER_URL   "http://192.168.1.50:8000/predict"
#define DEVICE_NAME  "plant1_cam"
#define CAPTURE_EVERY_MIN   30
#define CAM_FRAME_SIZE  FRAMESIZE_SVGA
#define CAM_JPEG_QUALITY 12

esp32_cam_vision.ino
#include <Arduino.h>
#include "config.h"
#include "esp_camera.h"
#include <WiFi.h>
#include <HTTPClient.h>

#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) delay(250);
}

bool initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.frame_size = CAM_FRAME_SIZE;
  config.pixel_format = PIXFORMAT_JPEG;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = CAM_JPEG_QUALITY;
  config.fb_count = 1;
  return esp_camera_init(&config) == ESP_OK;
}

void sleepMinutes(uint32_t minutes) {
  esp_sleep_enable_timer_wakeup((uint64_t)minutes * 60ULL * 1000000ULL);
  esp_deep_sleep_start();
}

bool postImage(const uint8_t* data, size_t len) {
  HTTPClient http;
  if (!http.begin(SERVER_URL)) return false;
  http.addHeader("Content-Type", "application/octet-stream");
  http.addHeader("X-Device-Id", DEVICE_NAME);
  int code = http.POST(data, len);
  bool ok = (code >= 200 && code < 300);
  http.end();
  return ok;
}

void setup() {
  connectWiFi();
  if (!initCamera()) sleepMinutes(CAPTURE_EVERY_MIN);

  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) sleepMinutes(CAPTURE_EVERY_MIN);

  postImage(fb->buf, fb->len);
  esp_camera_fb_return(fb);
  sleepMinutes(CAPTURE_EVERY_MIN);
}

void loop() {}

4. Folder: server
requirements.txt
fastapi
uvicorn[standard]
pillow
paho-mqtt

README_SERVER.md
# Classifier Server (FastAPI)

Receives JPEGs via POST `/predict`, runs a simple color-based heuristic (for demo),
and returns JSON. Optionally publishes to MQTT.

## Run
```bash
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python classifier_server.py


Listens on 0.0.0.0:8000.


### `classifier_server.py`
```python
import io, json
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from PIL import Image
import paho.mqtt.client as mqtt

MQTT_ENABLE = True
MQTT_HOST = "192.168.1.10"
MQTT_PORT = 1883
MQTT_USER = "mqtt_user"
MQTT_PASS = "mqtt_pass"
MQTT_BASE = "home/plant"

mqtt_client = None
if MQTT_ENABLE:
    try:
        mqtt_client = mqtt.Client()
        if MQTT_USER:
            mqtt_client.username_pw_set(MQTT_USER, MQTT_PASS)
        mqtt_client.connect(MQTT_HOST, MQTT_PORT, 60)
    except Exception as e:
        print("MQTT connect failed:", e)
        mqtt_client = None

app = FastAPI(title="Plant Leaf Classifier (Demo)")

def color_heuristic(img: Image.Image) -> dict:
    img = img.convert("RGB").resize((256, 256))
    pixels = img.load()
    total = 0; greenish = 0; yellow_brown = 0
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = pixels[x, y]
            total += 1
            if g > r + 20 and g > b + 20: greenish += 1
            if (r > 100 and g > 80 and b < 80) or (r > 80 and g > 60 and b < 60):
                yellow_brown += 1
    pct_green = (greenish / total) * 100.0
    pct_yb = (yellow_brown / total) * 100.0
    disease_score = min(1.0, max(0.0, (pct_yb - 5.0) / 25.0))
    label = "healthy" if disease_score < 0.35 else "possible_disease"
    confidence = (1.0 - disease_score) if label == "healthy" else disease_score
    return {"label": label,"confidence": round(confidence, 3),
            "pct_green": round(pct_green, 1),"pct_yellow_brown": round(pct_yb, 1)}

@app.post("/predict")
async def predict(request: Request):
    raw = await request.body()
    if not raw: return JSONResponse({"error": "no image bytes"}, status_code=400)
    device_id = request.headers.get("X-Device-Id", "unknown_cam")
    try: img = Image.open(io.BytesIO(raw))
    except Exception: return JSONResponse({"error": "invalid image"}, status_code=400)
    result = color_heuristic(img)
    if mqtt_client:
        topic = f"{MQTT_BASE}/{device_id}/vision/result"
        try: mqtt_client.publish(topic, json.dumps(result), retain=False)
        except Exception as e: print("MQTT publish failed:", e)
    return JSONResponse(result)

@app.get("/healthz")
async def healthz(): return {"ok": True}