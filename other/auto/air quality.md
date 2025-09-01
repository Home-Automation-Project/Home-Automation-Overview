here’s a complete, step-by-step build for a Car Cabin Comfort Monitor with an ESP32. It tracks CO₂, temp, humidity, pressure, and PM2.5/PM10, shows live values on a small OLED, auto-dims at night, and gives beeps + color warnings. It can run offline in the car, and (optionally) publish to MQTT when you park within home Wi-Fi.

1) What you’ll build

* Sensors: CO₂ (SCD41), Temp/Humidity/Pressure + VOC proxy (BME680), Particulates PM1.0/2.5/10 (PMSA003/PMS5003)
* UI: 0.96–1.3″ SSD1306 OLED (I²C) + buzzer + RGB status LED
* Logic: traffic-light warnings (CO₂ & PM thresholds), night auto-dimming, optional MQTT publishing when Wi-Fi is available.

2) Bill of materials (premium picks + a budget alternative)

Core
* ESP32 DevKit V1 (ESP-WROOM-32, 30-pin)

Sensors
* CO₂: Sensirion SCD41 (I²C, 3.3 V–5 V) — fast, accurate NDIR (best choice)
(Budget: SCD30/SCD40 also work.)

T/H/P + VOC proxy: BME680 (I²C, 3.3 V)
(For true TVOC/eCO₂ you can later switch to BSEC library.)

PM: Plantower PMSA003 or PMS5003 (UART, 5 V)
(Premium alternative: Sensirion SPS30 if you want I²C and superb long-term stability.)

UI + bits

SSD1306 128×64 OLED (I²C, 3.3 V)

Mini piezo buzzer (3.3 V via GPIO)

RGB LED (common cathode) or a small tri-color LED module

Automotive buck 12 → 5 V (3 A, surge-rated), inline fuse 1–2 A, optional TVS 36 V

Small enclosure, nylon standoffs, VHB tape, short silicone tubing (PM sensor intake guard)

3) Wiring (suggested pins)

All grounds common.

Power

Car ACC 12 V → fuse tap (1–2 A) → buck VIN → 5 V out → ESP32 5V (or USB input)

PMS sensor needs 5 V; BME680/SCD41/OLED use 3V3

I²C bus (3V3)

ESP32 SDA GPIO21 → BME680 SDA, SCD41 SDA, SSD1306 SDA

ESP32 SCL GPIO22 → BME680 SCL, SCD41 SCL, SSD1306 SCL

PMSA003 / PMS5003 (UART)

ESP32 RX2 GPIO16 ← PMS TX

ESP32 TX2 GPIO17 → PMS RX (optional; needed only for sleep/wake cmd)

PMS 5V → buck 5 V, GND → common

Alerts

Buzzer: GPIO26 → buzzer (+), buzzer (–) → GND

RGB LED: e.g., GPIO27→R (through 220 Ω), GPIO25→G, GPIO33→B

Avoid boot-strap pins (0/2/15) for peripherals. Keep PMS intake away from direct vents to avoid “fake” spikes.

4) Sensor placement (important)

SCD41 (CO₂): shaded airflow near center console or seat level (not in sun, not in direct vent blast).

BME680: a few cm away from ESP32 voltage regulator to avoid heat bias.

PMSA003: mount flat with inlet/outlet unobstructed; add a short dust mesh; avoid condensation (don’t place by defroster outlet).

5) Thresholds (defaults you can tweak)

CO₂ (ppm): 800 = caution, 1200 = bad (ventilate), 2000 = critical

PM2.5 (µg/m³): 12 = good, 35 = caution, 55 = bad

Temp/Humidity: comfort 20–24 °C, 30–60 % RH

6) Firmware (Arduino) — ready to flash

Install libraries: Adafruit BME680, SparkFun_SCD4x, Adafruit SSD1306 (and Adafruit GFX), optionally PubSubClient for MQTT.
```
// ==== Car Cabin Comfort Monitor (ESP32) ====
// Sensors: SCD41 (CO2, I2C), BME680 (T/H/P + gas, I2C), PMSA003/PMS5003 (PM, UART)
// OLED: SSD1306 128x64 (I2C)
// Optional MQTT if Wi-Fi present (set USE_MQTT true)

#include <Wire.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_BME680.h>
#include <SparkFun_SCD4x_Arduino_Library.h>
#include <HardwareSerial.h>

#define USE_MQTT false
#if USE_MQTT
  #include <WiFi.h>
  #include <PubSubClient.h>
  const char* WIFI_SSID="YOUR_WIFI";
  const char* WIFI_PASS="YOUR_PASS";
  const char* MQTT_HOST="192.168.1.10";
  const uint16_t MQTT_PORT=1883;
  WiFiClient wcli; PubSubClient mqtt(wcli);
#endif

// ----- Pins -----
#define I2C_SDA 21
#define I2C_SCL 22
#define PMS_RX  16   // ESP32 RX2 <- PMS TX
#define PMS_TX  17   // optional
#define BUZZ_PIN 26
#define LED_R 27
#define LED_G 25
#define LED_B 33

// ----- Globals -----
Adafruit_SSD1306 oled(128, 64, &Wire);
Adafruit_BME680 bme;     // 0x76/0x77
SCD4x scd41;             // 0x62
HardwareSerial PMSSerial(2);

struct PMData {uint16_t pm1=0, pm25=0, pm10=0; bool valid=false;} pm;
unsigned long lastOLED=0, lastPub=0;

void led(uint8_t r,uint8_t g,uint8_t b){ analogWrite(LED_R,r); analogWrite(LED_G,g); analogWrite(LED_B,b); }
void beep(uint16_t ms){ tone(BUZZ_PIN, 2200); delay(ms); noTone(BUZZ_PIN); }

bool readPMS() {
  // PMS frame: 0x42 0x4D + 30 bytes
  while (PMSSerial.available() >= 32) {
    if (PMSSerial.read()!=0x42) continue;
    if (PMSSerial.read()!=0x4D) continue;
    uint8_t buf[30]; if (PMSSerial.readBytes(buf,30)!=30) return false;
    uint16_t sum=0x42+0x4D; for(int i=0;i<28;i++) sum+=buf[i];
    uint16_t cs=(buf[28]<<8)|buf[29]; if (sum!=cs) return false;
    pm.pm1  = (buf[4]<<8)|buf[5];
    pm.pm25 = (buf[6]<<8)|buf[7];
    pm.pm10 = (buf[8]<<8)|buf[9];
    pm.valid=true;
    return true;
  }
  return false;
}

#if USE_MQTT
void ensureWiFi(){
  if(WiFi.status()==WL_CONNECTED) return;
  WiFi.mode(WIFI_STA); WiFi.begin(WIFI_SSID, WIFI_PASS);
  for(int i=0;i<30 && WiFi.status()!=WL_CONNECTED;i++) delay(200);
}
void ensureMQTT(const String& availTopic){
  while(!mqtt.connected()){
    String cid="car-cabin-"+String((uint32_t)ESP.getEfuseMac(), HEX);
    if(mqtt.connect(cid.c_str(), NULL, NULL, availTopic.c_str(), 0, true, "offline")){
      mqtt.publish(availTopic.c_str(),"online",true);
      break;
    } else delay(800);
  }
}
#endif

void setup(){
  pinMode(BUZZ_PIN, OUTPUT);
  ledcAttachPin(LED_R, 1); ledcSetup(1, 2000, 8);
  ledcAttachPin(LED_G, 2); ledcSetup(2, 2000, 8);
  ledcAttachPin(LED_B, 3); ledcSetup(3, 2000, 8);

  Serial.begin(115200);
  Wire.begin(I2C_SDA, I2C_SCL);

  // OLED
  oled.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  oled.clearDisplay(); oled.setTextSize(1); oled.setTextColor(SSD1306_WHITE);
  oled.setCursor(0,0); oled.println("Cabin Monitor"); oled.display();

  // BME680
  if(!bme.begin(0x76) && !bme.begin(0x77)){
    oled.println("BME680 not found"); oled.display();
  } else {
    bme.setTemperatureOversampling(BME680_OS_8X);
    bme.setHumidityOversampling(BME680_OS_2X);
    bme.setPressureOversampling(BME680_OS_4X);
    bme.setGasHeater(320, 150);
  }

  // SCD41
  if(scd41.begin()){
    scd41.startPeriodicMeasurement();
  } else {
    oled.println("SCD41 not found"); oled.display();
  }

  // PMS
  PMSSerial.begin(9600, SERIAL_8N1, PMS_RX, PMS_TX);

#if USE_MQTT
  WiFi.mode(WIFI_STA);
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
#endif

  beep(120);
}

void loop(){
  // Read sensors
  float tempC=NAN, rh=NAN, hPa=NAN; uint32_t gas=0;
  if (bme.performReading()){
    tempC=bme.temperature; rh=bme.humidity; hPa=bme.pressure/100.0; gas=bme.gas_resistance;
  }

  static uint16_t co2=0; static float t2=NAN, rh2=NAN;
  uint16_t co2Raw; float tRaw, rhRaw;
  if (scd41.readMeasurement(co2Raw, tRaw, rhRaw)) {
    if (co2Raw != 0xFFFF){ co2=co2Raw; t2=tRaw; rh2=rhRaw; }
  }

  readPMS();

  // Warn levels
  bool warnCO2 = (co2 >= 1200);
  bool badCO2  = (co2 >= 2000);
  bool warnPM  = pm.valid && (pm.pm25 >= 35);
  bool badPM   = pm.valid && (pm.pm25 >= 55);

  // LED: green ok, yellow warn, red bad
  if (badCO2 || badPM) { led(255,0,0); }
  else if (warnCO2 || warnPM) { led(255,120,0); }
  else { led(0,180,0); }

  // Beep on first entry to bad state
  static bool lastBad=false; bool nowBad = (badCO2||badPM);
  if (nowBad && !lastBad) beep(200);
  lastBad = nowBad;

  // OLED refresh ~2/s
  if (millis()-lastOLED > 500){
    oled.clearDisplay(); oled.setCursor(0,0);
    oled.printf("CO2: %4u ppm\n", co2);
    oled.printf("PM2.5:%3u ug/m3\n", pm.valid? pm.pm25:0);
    oled.printf("Temp: %.1f C\n", isnan(tempC)? t2: tempC);
    oled.printf("Hum : %.0f %%\n", isnan(rh)?  rh2: rh);
    oled.printf("Pres: %.1f hPa\n", hPa);
    oled.display();
    lastOLED = millis();
  }

#if USE_MQTT
  static String base, avail, state;
  if(base==""){
    char id[13]; snprintf(id,sizeof(id),"%012llX", ESP.getEfuseMac());
    base = String("car/cabin/")+id; avail=base+"/availability"; state=base+"/state";
  }
  if (WiFi.status()==WL_CONNECTED){ ensureMQTT(avail); }
  else ensureWiFi();

  if (mqtt.connected() && millis()-lastPub>10000){
    lastPub=millis();
    String j="{";
    j += "\"co2\":" + String(co2) + ",";
    j += "\"pm25\":" + String(pm.valid? pm.pm25:0) + ",";
    j += "\"pm10\":" + String(pm.valid? pm.pm10:0) + ",";
    j += "\"temp_c\":" + String(isnan(tempC)? t2: tempC,1) + ",";
    j += "\"humidity\":" + String(isnan(rh)? rh2: rh,0) + ",";
    j += "\"pressure_hpa\":" + String(hPa,1);
    j += "}";
    mqtt.publish(state.c_str(), j.c_str(), false);
  }
  mqtt.loop();
#endif
}
```

How it behaves

Shows CO₂, PM2.5, Temp, RH, Pressure on the OLED.

LED = green (ok), amber (caution), red (bad).

Buzzer chirps when entering a “bad” condition (CO₂ ≥ 2000 ppm or PM2.5 ≥ 55 µg/m³).

If you enable USE_MQTT, it will try to publish every 10 s when your home Wi-Fi is in range.

7) Calibration & sanity checks

SCD41: leave in the car with windows open for 5–10 min occasionally; its automatic baseline (ABC) will anchor ~420 ppm.

BME680: allow 12–48 h burn-in; gas resistance trends are informative even without BSEC IAQ.

PMSA003: avoid humidity fog; dust spikes from vents during defrost are normal. Optionally command sleep between reads to extend fan life.

8) Install & mounting

Place the unit out of direct sun, with the PMS intake away from vents.

Use drip loops and secure the buck + ESP32 enclosure.

Tap an ACC circuit so it powers only with ignition; always fuse the line.

For night driving, you can further dim the OLED (reduce refresh / invert colors) if it’s too bright.

9) Nice upgrades (when you want more)

Auto window-vent alert: if CO₂ > 1500 ppm for 2+ minutes while speed < 10 mph → beep + on-screen hint.

BLE broadcast: push CO₂/PM to your phone widget via BLE advertisements.

SPS30 PM sensor**:** rock-solid long-run PM values via I²C (swap code path).

GPS merge: correlate air quality with location and speed; log to microSD and upload at home via Wi-Fi.

[Wiring schema](./cabin%20aq%20monitor.png)
