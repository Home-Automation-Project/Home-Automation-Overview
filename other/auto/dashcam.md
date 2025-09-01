step-by-step build for an ESP32 Dashcam Companion / Event Logger. It continuously buffers JPEG frames in RAM, and when an event (bump/brake/impact) is detected it saves a clip with a few seconds before and after the event to microSD, along with GPS and g-force metadata. It’s designed to be simple, robust, and automotive-safe.

1) What you’ll build

Always-on ring buffer of low/medium-res JPEG frames (in PSRAM).

Event triggers: accelerometer threshold (bump/impact) & optional manual button.

Clip saving: writes pre-trigger and post-trigger frames to a folder on microSD, with a JSON sidecar (time, location, g-peak).

Power-safe: runs from ACC 12 V via a buck; optional supercap/UPS for graceful shutdown.

Optionals: quick beeper + status LED; Wi-Fi sync at home.

2) Recommended hardware (two good paths)
A) Widely available, easiest parts

ESP32-CAM AI-Thinker (OV2640 camera, PSRAM, on-board microSD slot)

Accelerometer: LIS3DH (I²C, has interrupt pin) or MPU-6050

GPS: u-blox NEO-M8N (+ active antenna)

Automotive buck 12→5 V (≥2 A, surge-tolerant) + 1–2 A fuse (+ optional 36 V TVS)

High-endurance microSD (32–128 GB, “Endurance” class)

Momentary button (manual clip), buzzer (event chirp), LED (status)

Pros: cheap, tons of examples.
Caveat: ESP32-CAM has few spare GPIOs; we’ll map around that.

B) Premium & roomier (if you can source it)

ESP32-S3-CAM (S3 + OV2640/OV5640) with microSD slot (SPI) and 8 MB PSRAM

Same sensors (LIS3DH, NEO-M8N), same power stack

Pros: more GPIO, more RAM, cleaner wiring. If you have this, tell me the exact board and I’ll tailor pin maps.

go ESP32-S3-CAM if you can find a board with PSRAM + microSD built in. It’s roomier, more stable, and far less pin-constrained—perfect for buffering frames, logging to SD, and hanging GPS + accelerometer without weird pin gymnastics.

Why S3-CAM (recommended)

More RAM / faster core → bigger ring buffer, smoother saves.

More free GPIOs → clean I²C (accel), UART (GPS), button, buzzer/LED.

Often has native USB for easy flashing/logging.

Some variants include OV5640 (better optics); OV2640 also fine.

Look for: ESP32-S3-CAM with 8 MB PSRAM + microSD (SPI), OV2640/OV5640, exposed 3V3/5V, and a decent regulator.

When ESP32-CAM (AI-Thinker) still makes sense

Cheapest / easiest to source and you’re okay with:

Very few spare pins (tight mapping).

Sharing buses and being careful about boot pins.

Sticking to OV2640 and the onboard SD_MMC slot.

It works; you’ll just live with stricter constraints and slightly smaller buffers.

Parts pick (my go-to)

Board: ESP32-S3-CAM (8 MB PSRAM + microSD).

Accel: LIS3DH (I²C, INT pin).

GPS: u-blox NEO-M8N + active antenna.

Storage: 64–128 GB high-endurance microSD.

Power: Automotive buck 12→5 V (surge-rated) + 1–2 A fuse (+ optional 36 V TVS).

UI: Momentary button, buzzer, status LED.

3) Power & mounting

Tap ACC 12 V in the fuse box → add-a-fuse (1–2 A) → buck converter → 5 V to ESP32 5V (or USB-5V).

Ground to chassis; keep wiring short; add a 36 V TVS at buck input if you have one.

Mount camera behind the rear-view mirror (discreet) with lens peeking under the tint band.

Keep the ESP32 module inside a small vented enclosure; don’t block airflow around the camera module.

4) Wiring (ESP32-CAM version)

ESP32-CAM already uses specific pins for camera and SD; we’ll keep the rest simple.

LIS3DH (I²C):

SDA → GPIO 13, SCL → GPIO 14 (works alongside SD on ESP32-CAM if you don’t use 4-bit SD; we use the on-board SDMMC, so keep I²C clock modest)

VCC → 3V3, GND → GND

INT1 → GPIO 12 (interrupt/wake)

GPS (UART1/2):

GPS TX → GPIO 2 (U2RXD) (GPIO2 is also flash LED on some boards—if your board’s LED is on GPIO4, using GPIO2 for RX is OK)

GPS RX → GPIO 15 (U2TXD) (optional; not required)

VCC 3.3–5 V (check module), GND → GND

Button (manual clip): GPIO 0 to GND via button (hold HIGH with 10 k pull-up)

Buzzer (optional): GPIO 16 → buzzer +, buzzer − → GND

LED (optional): GPIO 4 (ESP32-CAM flash LED) for brief status blips at low duty

Pin reality: ESP32-CAM is cramped. If any conflict appears on your specific board revision, we can remap (or shift to the S3-CAM mapping).

5) Capture model & clip sizing (sane defaults)

Frame size: 800×600 (SVGA) or 640×480 (VGA) JPEG; quality ~10–12 (≈40–70 KB/frame).

Ring buffer: ~3–4 MB in PSRAM → ~50–80 frames (~5–8 s @ 10 fps).

Clip: 5 s pre-trigger + 10 s post-trigger (≈15 s total) → ~10–50 MB depending on fps/quality.

File layout:

/EVENTS/2025-08-30_15-42-07Z_BUMP/
    frame_0001.jpg
    ...
    meta.json   # time, gps, g_peak, frames, averages

6) Arduino libraries

esp32-camera (bundled with ESP32 core examples)

SD_MMC (ESP32-CAM built-in slot) or SD (SPI on S3-CAM)

Adafruit LIS3DH (or Jeff Rowberg’s MPU6050 if you choose MPU)

TinyGPSPlus (GPS)

ArduinoJson (for meta.json) – optional; we can hand-roll JSON too

7) Firmware (ESP32-CAM; ring buffer + event clip)

Paste this; then set the #define CAMERA_MODEL_AI_THINKER and adjust the pin block if your board differs. This sketch:
• runs a ring buffer in PSRAM,
• watches LIS3DH INT,
• on trigger saves pre+post frames to SD, and
• logs a meta.json with GPS and g-peak.
```
// ===== ESP32 Dashcam Event Logger (ESP32-CAM AI-Thinker) =====
// - Ring buffer of JPEG frames in PSRAM
// - Trigger via LIS3DH INT (bump) or button
// - Save pre+post frames to microSD with metadata (GPS + g-peak)

#include "esp_camera.h"
#include "FS.h"
#include "SD_MMC.h"
#include <Wire.h>
#include <Adafruit_LIS3DH.h>
#include <Adafruit_Sensor.h>
#include <TinyGPSPlus.h>

// ---------- Camera model ----------
#define CAMERA_MODEL_AI_THINKER
#include "camera_pins.h"   // use the standard header from ESP32 examples

// ---------- Pins (ESP32-CAM) ----------
#define I2C_SDA   13
#define I2C_SCL   14
#define LIS_INT   12
#define BTN_PIN    0      // manual clip
#define BUZZ_PIN  16      // optional buzzer
#define LED_FLASH  4      // on-board LED; brief status blinks only

// ---------- GPS (UART2) ----------
HardwareSerial GPSSerial(2);
#define GPS_RX   2   // U2RXD  <- GPS TX
#define GPS_TX  15   // U2TXD  -> GPS RX (optional)
TinyGPSPlus gps;

// ---------- Globals ----------
Adafruit_LIS3DH lis = Adafruit_LIS3DH();
volatile bool eventFlag = false;
volatile bool buttonFlag = false;

struct JpegBuf {
  uint8_t* data = nullptr;
  size_t   len  = 0;
  uint64_t us   = 0;   // microseconds since boot
};
#include <deque>
std::deque<JpegBuf> ring;
size_t ringBytes = 0;
const size_t RING_BYTES_MAX = 4 * 1024 * 1024; // ~4MB

// Capture config
const framesize_t FRAME_SIZE = FRAMESIZE_SVGA; // 800x600
const int JPEG_QUALITY = 12;                   // 10-14 = decent
const int FPS_TARGET = 10;

// Clip config
const uint32_t PRE_MS  = 5000;  // pre-trigger window
const uint32_t POST_MS = 10000; // post-trigger window
float g_peak = 0.0;

// Utils
uint64_t nowUs(){ return (uint64_t)esp_timer_get_time(); }

void IRAM_ATTR isrLIS(){ eventFlag = true; }
void IRAM_ATTR isrBTN(){ buttonFlag = true; }

void beep(int ms=80){ 
#ifdef BUZZ_PIN
  ledcWriteTone(0, 2400); delay(ms); ledcWrite(0, 0);
#endif
}

void statusBlink(int ms=50){
#ifdef LED_FLASH
  digitalWrite(LED_FLASH, HIGH); delay(ms);
  digitalWrite(LED_FLASH, LOW);
#endif
}

void mountSD(){
  if(!SD_MMC.begin("/sdcard", true)) { // 1-bit mode for stability
    // try again after a moment
    delay(300);
    SD_MMC.begin("/sdcard", true);
  }
}

bool initCamera(){
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;   config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;   config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;   config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;   config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn  = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAME_SIZE;
  config.jpeg_quality = JPEG_QUALITY;
  config.fb_count = 1;        // single fb, we copy into our ring
  config.grab_mode = CAMERA_GRAB_LATEST;

  if (psramFound()) config.fb_location = CAMERA_FB_IN_PSRAM;
  else config.fb_location = CAMERA_FB_IN_DRAM;

  esp_err_t err = esp_camera_init(&config);
  return (err == ESP_OK);
}

void pushFrameToRing(){
  camera_fb_t* fb = esp_camera_fb_get();
  if(!fb) return;

  // copy JPEG into PSRAM buffer
  uint8_t* buf = (uint8_t*)heap_caps_malloc(fb->len, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
  if(buf){
    memcpy(buf, fb->buf, fb->len);
    JpegBuf jb; jb.data = buf; jb.len = fb->len; jb.us = nowUs();
    ring.push_back(jb);
    ringBytes += jb.len;

    // drop oldest until under limit and keep only PRE_MS window
    while (ringBytes > RING_BYTES_MAX) {
      auto &old = ring.front(); ringBytes -= old.len;
      heap_caps_free(old.data); ring.pop_front();
    }
    // window trim by time
    uint64_t cutoff = nowUs() - (uint64_t)PRE_MS * 1000ULL;
    while (!ring.empty() && ring.front().us < cutoff) {
      auto &old = ring.front(); ringBytes -= old.len;
      heap_caps_free(old.data); ring.pop_front();
    }
  }
  esp_camera_fb_return(fb);
}

String tsFileSafe(){ // rough UTC from GPS if present, else uptime
  char buf[40];
  if (gps.time.isValid() && gps.date.isValid()) {
    snprintf(buf,sizeof(buf), "%04d-%02d-%02d_%02d-%02d-%02dZ",
      gps.date.year(), gps.date.month(), gps.date.day(),
      gps.time.hour(), gps.time.minute(), gps.time.second());
  } else {
    uint32_t s = millis()/1000;
    snprintf(buf,sizeof(buf), "UP_%06u", s);
  }
  return String(buf);
}

void writeMetaJSON(const String& folder, int framesBefore, int framesAfter){
  File f = SD_MMC.open(folder + "/meta.json", FILE_WRITE);
  if(!f) return;
  // basic JSON (no ArduinoJson needed)
  f.print("{");
  f.print("\"time\":\""); f.print(tsFileSafe()); f.print("\",");
  f.print("\"g_peak\":"); f.print(g_peak,2); f.print(",");
  if (gps.location.isValid()){
    f.print("\"lat\":"); f.print(gps.location.lat(),6); f.print(",");
    f.print("\"lon\":"); f.print(gps.location.lng(),6); f.print(",");
  }
  f.print("\"frames_before\":"); f.print(framesBefore); f.print(",");
  f.print("\"frames_after\":"); f.print(framesAfter);
  f.print("}");
  f.close();
}

// Save current ring + collect more frames for POST_MS
void saveEventClip(){
  statusBlink(120);
  beep(100);

  String folder = "/EVENTS/" + tsFileSafe() + "_BUMP";
  SD_MMC.mkdir(folder);

  // 1) Save PRE frames (everything in ring)
  int idx=1;
  int framesBefore = ring.size();
  for (auto &jb : ring){
    char name[32]; snprintf(name,sizeof(name), "/frame_%04d.jpg", idx++);
    File f = SD_MMC.open(folder + String(name), FILE_WRITE);
    if(f){ f.write(jb.data, jb.len); f.close(); }
  }

  // 2) Collect & save POST frames for POST_MS
  uint64_t endUs = nowUs() + (uint64_t)POST_MS*1000ULL;
  int framesAfter = 0;
  while (nowUs() < endUs){
    camera_fb_t* fb = esp_camera_fb_get();
    if (fb){
      char name[32]; snprintf(name,sizeof(name), "/frame_%04d.jpg", idx++);
      File f = SD_MMC.open(folder + String(name), FILE_WRITE);
      if(f){ f.write(fb->buf, fb->len); f.close(); framesAfter++; }
      esp_camera_fb_return(fb);
    }
    // read some GPS and LIS acceleration while saving
    while (GPSSerial.available()) gps.encode(GPSSerial.read());
    sensors_event_t a, t, p; lis.getEvent(&a, &t, &p);
    float g = sqrtf(a.acceleration.x*a.acceleration.x +
                    a.acceleration.y*a.acceleration.y +
                    a.acceleration.z*a.acceleration.z) / 9.80665f;
    if (g > g_peak) g_peak = g;
    delay(1000 / FPS_TARGET);
  }

  writeMetaJSON(folder, framesBefore, framesAfter);

  // 3) Clear the ring after saving
  while(!ring.empty()){
    auto &jb = ring.front(); ringBytes -= jb.len;
    heap_caps_free(jb.data); ring.pop_front();
  }

  // small done chirp
  beep(60); delay(60); beep(60);
}

void setup(){
  pinMode(BTN_PIN, INPUT_PULLUP);
  pinMode(LED_FLASH, OUTPUT); digitalWrite(LED_FLASH, LOW);

#ifdef BUZZ_PIN
  ledcSetup(0, 4000, 10); ledcAttachPin(BUZZ_PIN, 0);
#endif

  Serial.begin(115200);
  Wire.begin(I2C_SDA, I2C_SCL);

  // Accelerometer
  if (!lis.begin(0x18) && !lis.begin(0x19)) {
    Serial.println("LIS3DH not found");
  } else {
    lis.setRange(LIS3DH_RANGE_4_G);
    lis.setDataRate(LIS3DH_DATARATE_100_HZ);
    pinMode(LIS_INT, INPUT);
    // Simple high-accel interrupt ~0.6g; adjust for your car
    lis.setClick(1, 80); // single click sensitivity (datasheet scaled)
    attachInterrupt(digitalPinToInterrupt(LIS_INT), isrLIS, RISING);
  }

  // GPS
  GPSSerial.begin(9600, SERIAL_8N1, GPS_RX, GPS_TX);

  // Camera & SD
  if (!initCamera()){
    Serial.println("Camera init failed");
    while(1){ statusBlink(700); delay(300); }
  }
  mountSD();
  SD_MMC.mkdir("/EVENTS");

  // Button interrupt
  attachInterrupt(digitalPinToInterrupt(BTN_PIN), isrBTN, FALLING);

  Serial.println("Ready");
  beep(80);
}

void loop(){
  // feed GPS
  while (GPSSerial.available()) gps.encode(GPSSerial.read());

  // capture into ring
  pushFrameToRing();

  // track peak g in background (approx)
  sensors_event_t a, t, p; lis.getEvent(&a, &t, &p);
  float g = sqrtf(a.acceleration.x*a.acceleration.x +
                  a.acceleration.y*a.acceleration.y +
                  a.acceleration.z*a.acceleration.z) / 9.80665f;
  if (g > g_peak) g_peak = g;

  // triggers
  if (eventFlag || buttonFlag){
    noInterrupts(); eventFlag = false; buttonFlag = false; interrupts();
    saveEventClip();
    g_peak = 0.0;                  // reset for next clip
    statusBlink(80);
  }

  // modest frame pacing
  delay(1000 / FPS_TARGET);
}
```

Tuning notes

If SD writes stutter, drop to VGA (FRAMESIZE_VGA) and/or JPEG_QUALITY=14.

If LIS3DH “click” is too sensitive/insensitive, tune lis.setClick(1, N) (larger N = less sensitive) or switch to high-pass + INT1 thresholds; I can wire that up too.

On some ESP32-CAMs GPIO2 is tied to the onboard LED; if GPS RX on GPIO2 causes boot issues, move GPS to U0RXD/U0TXD and program OTA after first flash, or we can remap.

8) Testing (10–15 minutes)

Bench: aim the camera, insert microSD (FAT32), power via USB 5 V. You should see /EVENTS created.

Tap the button → a new event folder with frames + meta.json should appear.

Gently knock the enclosure: confirm LIS3DH triggers and records a clip.

Put GPS near a window; verify meta.json has lat/lon after a fix.

In car: wire to ACC; verify it starts/stops with ignition.

9) “Parking mode” (optional)

Keep the ESP32 on a tiny UPS / supercap after ACC goes off and enter light sleep with LIS3DH INT as wake.

On wake (impact), grab a short high-FPS clip and power down again.

Add a voltage monitor (divider to an ADC) so you never run the car battery low; exit if voltage < 12.0 V.

10) Nice upgrades

Audio blip: add an I²S mic and record a 1–2 s WAV along with the clip.

Wi-Fi sync: when home SSID is seen, start a tiny HTTP server or push to an SMB/FTP endpoint.

Timekeeping: write GPS time to RTC (DS3231) so events are timestamped even without a fix.

Overlay: draw time/speed onto frames (MJPEG) if you later move to an S3 board + display pipeline.

## Wiring
🔌 Wiring Plan (ESP32-S3-CAM)
Power

Car ACC 12 V → 1–2 A fuse → automotive buck converter (12→5 V).

Buck 5 V → ESP32-S3-CAM 5V pin (or USB input).

GNDs common.

(Optional) TVS diode across 12 V input for surge protection.

GPS (NEO-M8N)

GPS TX → ESP32 GPIO16 (U2RXD).

GPS RX → ESP32 GPIO17 (U2TXD, optional).

GPS VCC → 3.3–5 V (depending on module).

GPS GND → common ground.

Accelerometer (LIS3DH, I²C + INT)

SDA → GPIO21.

SCL → GPIO22.

INT1 → GPIO19.

VCC → 3.3 V.

GND → common ground.

Button (manual clip trigger)

One side → GPIO18.

Other side → GND.

Use ESP32’s INPUT_PULLUP.

Buzzer (event chirp)

GPIO26 → buzzer (+).

Buzzer (–) → GND.

(PWM tone-capable).

Status LED (RGB optional)

R → GPIO25 through 220 Ω.

G → GPIO32 through 220 Ω.

B → GPIO33 through 220 Ω.

Cathode → GND.

microSD (SPI)

Uses board’s dedicated SD slot pins (usually GPIOs 13, 11, 12, 10, depending on your S3-CAM variant). We’ll label them as “on-board SD.”

[wiring diagram](./dashcam.png)