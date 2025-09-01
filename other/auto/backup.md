rear (or front) Parking Assistant with an ESP32 that beeps faster as you approach an obstacle and (optionally) shows left/right guidance. This design uses water-resistant ultrasonics and is wired to your car’s reverse circuit so it only powers when backing up.

1) What you’ll build

1–2 waterproof ultrasonic sensors in the bumper (center only, or left + right).

ESP32 reads distance(s), filters noise, and drives a piezo buzzer (and optional RGB LED).

Powers from the reverse-lamp 12 V (or ACC) via a protected buck converter.

2) Recommended parts

Core

ESP32 DevKit V1 (ESP-WROOM-32).

Ultrasonics (pick one style)

JSN-SR04T-2.0 (water-resistant, 5 V, TRIG/ECHO).

Needs a voltage divider on ECHO → ESP32 (3.3 V max).

OR A02YYUW (URM09) UART ultrasonic (IP67, 3.3–5.5 V, 9600 baud).

Native 3.3 V logic → no level shifting (cleanest option).

You can add a second unit for left/right.

Power & protection

Automotive buck 12–36 V → 5 V/2–3 A, surge/EMI-hardened.

Inline fuse 1–2 A (use an add-a-fuse at the reverse-lamp circuit).

(Nice) TVS diode (SMBJ36A) across 12 V near the buck.

Alerts / UI

Piezo buzzer (3.3 V) → simple and loud.

(Optional) RGB LED (common cathode) with 3×220 Ω resistors, or a tiny OLED.

Hardware

Heat-shrink, epoxy or silicone for sensor backs, VHB tape or bracket, cable glands.

3) Wiring (two-sensor JSN-SR04T version)

Power (reverse-activated)

Reverse-lamp +12 V → fuse → buck VIN; buck GND → chassis.

Buck 5 V → ESP32 5V (or USB-5V pin). GND common.

Sensors (use short, shielded runs if possible)

Left sensor: TRIG → GPIO14, ECHO → GPIO34 (input-only).

Voltage divider on ECHO: 18 kΩ (top) from ECHO → node; 33 kΩ (bottom) node → GND; node → GPIO34. (5 V → ≈3.2 V)

Right sensor: TRIG → GPIO27, ECHO → GPIO35 (with the same divider).

Buzzer & LED

Buzzer + → GPIO26, buzzer − → GND.

(Optional) LED R→GPIO25, G→GPIO32, B→GPIO33 (each through 220 Ω to the LED).

Notes
• Most JSN-SR04T modules accept 3.3 V TRIG just fine.
• If you choose A02YYUW (UART) instead, wire each sensor TX → ESP32 RX (e.g., GPIO16/17 using Serial2 or a second SoftwareSerial), Vcc 5 V, GND common—no dividers needed.

4) Install & aiming

Mount height: ~40–55 cm (16–22″) from ground.

Angle: tilt the sensor 2–5° downward so it sees curbs yet doesn’t lock on the ground.

Locations: rear bumper (center only) or left + right spaced near the corners for guidance.

Seal: keep the transducer face exposed; seal the cable entry; avoid pointing straight at the exhaust tip.

Power tap: the reverse-lamp +12 V in the tail-light housing is ideal—module only runs in reverse.

5) Distance → alerts (defaults)
Range (cm)	LED (opt.)	Beep pattern
> 150	green	silent
150–80	green	slow beep (800 ms period)
80–40	yellow	medium (400 ms)
40–25	orange	fast (200 ms)
< 25	red	continuous tone

Left/right hint: if the left sensor is much closer than the right (e.g., Δ≥15 cm), play a double-chirp, and vice-versa for right.

6) Firmware (Arduino, JSN-SR04T ×2)

No external libraries required.

Uses median filtering, timeout handling, and a simple beeper state machine.

// ===== ESP32 Parking Assistant: 2x JSN-SR04T + Buzzer (+optional RGB) =====
#include <Arduino.h>

// ---- Pins ----
const int TRIG_L = 14, ECHO_L = 34;   // left sensor (echo via divider!)
const int TRIG_R = 27, ECHO_R = 35;   // right sensor (echo via divider!)
const int BUZZ   = 26;
const int LED_R  = 25, LED_G = 32, LED_B = 33;   // optional RGB

// ---- Settings ----
const uint32_t PULSE_TIMEOUT_US = 25000;  // ~4.3 m
const uint32_t INTER_PING_MS    = 60;     // JSN-SR04T spec ~60ms between pings
const int MEDIAN_SAMPLES = 3;

struct Dist {int cm; bool ok;};
unsigned long lastPingMs = 0;

// Tone via LEDC (hardware PWM)
const int BUZZ_CH = 0;
void toneOn(int hz){ ledcWriteTone(BUZZ_CH, hz); }
void toneOff(){ ledcWrite(BUZZ_CH, 0); }

// Optional RGB helper
void setRGB(uint8_t r,uint8_t g,uint8_t b){
  ledcWrite(1, r); ledcWrite(2, g); ledcWrite(3, b);
}

// Trigger one ultrasonic measurement (blocking ~ up to timeout)
Dist measureCm(int trig, int echo){
  // Ensure low
  digitalWrite(trig, LOW); delayMicroseconds(2);
  // 10us trigger
  digitalWrite(trig, HIGH); delayMicroseconds(10);
  digitalWrite(trig, LOW);
  // read echo pulse
  unsigned long us = pulseIn(echo, HIGH, PULSE_TIMEOUT_US);
  if (us == 0) return {9999,false};
  // JSN/HC-SR04 -> cm = us/58.0
  int cm = (int)round(us / 58.0);
  // sanity clamp
  if (cm<2 || cm>400) return {9999,false};
  return {cm,true};
}

int median3(int a,int b,int c){
  if (a>b) swap(a,b); if (b>c) swap(b,c); if (a>b) swap(a,b);
  return b;
}

int filteredDistance(int trig, int echo){
  int a=9999,b=9999,c=9999; bool okA=false,okB=false,okC=false;
  Dist d;
  d=measureCm(trig,echo); a=d.cm; okA=d.ok; delay(5);
  d=measureCm(trig,echo); b=d.cm; okB=d.ok; delay(5);
  d=measureCm(trig,echo); c=d.cm; okC=d.ok;
  int m = median3(a,b,c);
  if (!(okA||okB||okC)) return 9999;
  return m;
}

// Beeper state machine
unsigned long nextBeepToggle=0;
bool buzzing=false;
void beepLogic(int nearest, bool leftCloser, bool rightCloser){
  // LED color
  if      (nearest < 25) setRGB(255,0,0);
  else if (nearest < 40) setRGB(255,80,0);
  else if (nearest < 80) setRGB(255,150,0);
  else if (nearest <150) setRGB(0,180,0);
  else                   setRGB(0,60,0);

  // Period selection
  int periodMs=0;  int toneHz = 2500;
  if      (nearest < 25) { toneOn(toneHz); buzzing=true; return; }  // solid
  else if (nearest < 40) periodMs = 200;
  else if (nearest < 80) periodMs = 400;
  else if (nearest <150) periodMs = 800;
  else { toneOff(); buzzing=false; return; }

  // Left/right prompt: quick double chirp at start of each new band
  static int lastBand=-1;
  int band = (nearest<40)?3:(nearest<80)?2:(nearest<150)?1:0;
  static unsigned long bandStamp=0;
  if (band!=lastBand){
    lastBand=band; bandStamp=millis();
    if (leftCloser){ toneOn(2200); delay(60); toneOff(); delay(60); toneOn(2200); delay(90); toneOff(); }
    else if (rightCloser){ toneOn(2800); delay(60); toneOff(); delay(60); toneOn(2800); delay(90); toneOff(); }
  }

  if (millis() >= nextBeepToggle){
    if (buzzing){ toneOff(); buzzing=false; nextBeepToggle = millis() + periodMs; }
    else        { toneOn(toneHz); buzzing=true; nextBeepToggle = millis() + 60; } // 60ms beep
  }
}

void setup(){
  Serial.begin(115200);

  pinMode(TRIG_L, OUTPUT); pinMode(ECHO_L, INPUT);
  pinMode(TRIG_R, OUTPUT); pinMode(ECHO_R, INPUT);

  pinMode(BUZZ, OUTPUT);
  ledcSetup(BUZZ_CH, 4000, 12);
  ledcAttachPin(BUZZ, BUZZ_CH);

  // RGB channels (optional)
  ledcSetup(1, 2000, 8); ledcAttachPin(LED_R, 1);
  ledcSetup(2, 2000, 8); ledcAttachPin(LED_G, 2);
  ledcSetup(3, 2000, 8); ledcAttachPin(LED_B, 3);
  setRGB(0,0,0);
}

void loop(){
  // Leave at least ~60ms between each sensor to avoid cross-talk
  int dL = filteredDistance(TRIG_L, ECHO_L); delay(10);
  int dR = filteredDistance(TRIG_R, ECHO_R);

  // Choose nearest valid cm
  int nL = (dL>=9999? 9999 : dL);
  int nR = (dR>=9999? 9999 : dR);
  int nearest = min(nL, nR);
  bool leftCloser  = (nL + 15 < nR);   // ≥15cm difference → hint left
  bool rightCloser = (nR + 15 < nL);

  beepLogic(nearest, leftCloser, rightCloser);

  // debug
  static unsigned long lastPrint=0;
  if (millis()-lastPrint>300){
    Serial.printf("L:%4d  R:%4d  -> nearest:%4d\n", dL, dR, nearest);
    lastPrint=millis();
  }

  delay(20);
}


If you picked A02YYUW (UART) sensors instead: read each sensor’s 4-byte frame (0xFF, 0x02, HIGH, LOW) at 9600 baud and convert to cm; you can drop it into filteredDistance() and skip the pulseIn() logic (no cross-talk).

7) Test & calibrate (10–15 minutes)

Bench-power at 5 V; watch Serial. Distances should track a flat board moved in front of the sensor.

In the car, place cones/boxes at 150, 80, 40, 25 cm and verify the beep bands change at those points.

If all readings run short/long, tilt the sensor or shift its height a little.

If you get random 0/9999 spikes, increase MEDIAN_SAMPLES to 5 or add a simple moving average over the last 5 results.

If cross-talk occurs (rare with JSN), increase INTER_PING_MS to 80–100 ms.

8) Nice upgrades

Front sensors that auto-enable <10 mph using a speed signal (e.g., from GPS or OBD).

OLED or LED bargraph on the dash.

CAN/OBD-II integration to mute music / beep via speakers.

BLE phone notification (useful when guiding a trailer).

Waterproof enclosure with a drain hole and conformal coating on the ESP32.

## wiring
Power

12 V reverse lamp → fuse (1–2 A) → buck converter

Buck 5 V → ESP32 5V pin + sensors VCC

All grounds common

📡 Ultrasonic Sensors (JSN-SR04T ×2)

Left Sensor

TRIG → GPIO14

ECHO → GPIO34 (⚠ through a voltage divider 18kΩ / 33kΩ)

VCC → 5 V from buck

GND → GND

Right Sensor

TRIG → GPIO27

ECHO → GPIO35 (⚠ voltage divider)

VCC → 5 V

GND → GND

🔊 Alerts

Piezo buzzer

→ GPIO26

– → GND

RGB LED (with 220 Ω resistors)

R → GPIO25

G → GPIO32

B → GPIO33

Common cathode → GND

[wiring diagram](./parking%20assistant.png)
