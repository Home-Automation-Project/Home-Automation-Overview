step-by-step ESP32 Car HUD that shows big, legible speed (GPS) plus heading and time, with auto-brightness and an option to reflect on the windshield or run as a direct-view dash display.

1) Recommended hardware (proven parts)

Core

ESP32 DevKit (ESP32-WROOM-32, USB-C or micro-USB).

High-brightness TFT (SPI):

Best: 3.5″ IPS 480×320 ILI9488 (8-LED backlight, ≥500 nits) or

2.8″ ILI9341 320×240 (works, a bit dimmer).

Prefer a board with a separate LED/backlight pin.

GPS: u-blox NEO-M8N (or NEO-6M) with active antenna; 3.3 V logic.

Ambient light sensor: BH1750 (I²C).

Power (automotive-safe)

12 V → 5 V buck rated 9–36 V in, 3 A out, with surge protection (automotive grade).
(Avoid bare LM2596 boards in cars; choose a hardwire USB or buck that mentions load-dump/ISO 7637.)

Inline fuse (1–2 A) and an add-a-fuse tap for an ACC circuit.

(Optional but nice) TVS diode (e.g., SMBJ36A) across 12 V input and a 100 µF + 0.1 µF filter near the ESP32.

Mounting

Low-glare screen visor or a small HUD reflective film for the windshield.

3D-printed or aluminum angle bracket + VHB tape / screws.

2) Wiring

Power

Car ACC 12 V → fuse tap (1–2 A) → buck VIN.

Buck GND → chassis ground.

Buck 5 V out → ESP32 5V (or USB input). Share GND.

Display (SPI)

ESP32 SCK 18 → TFT SCK

ESP32 MOSI 23 → TFT MOSI

ESP32 MISO 19 → TFT MISO (if present; many TFTs don’t use it)

ESP32 CS 5 → TFT CS

ESP32 DC 27 → TFT D/C

ESP32 RST 33 → TFT RST

(Optional dimming) ESP32 GPIO32 (PWM) → transistor/MOSFET → TFT LED (backlight).
If LED pin must be tied to 3V3, you can still do coarse day/night themes in software.

GPS (UART2)

ESP32 RX2 16 ← GPS TX

ESP32 TX2 17 → GPS RX (optional; not required for basic NMEA)

GPS VCC 3.3–5 V (check your module), GND → GND

Light sensor (I²C)

ESP32 SDA 21 → BH1750 SDA

ESP32 SCL 22 → BH1750 SCL

3V3 and GND shared

Avoid boot-strap pins 0/2/15 for CS/DC if your display board pulls them; the mapping above is safe on typical DevKits.

## display options
✅ Recommended TFT Models for ESP32 HUD
🔹 Best all-round choice

3.5″ ILI9488 IPS (480×320)

Brightness: typically 500–800 nits (many boards advertise “high brightness”).

Good viewing angles (IPS panel).

Resolution: 480×320 → crisp speed digits.

Driver: ILI9488 (well-supported in TFT_eSPI and other libs).

Cost: ~$12–15.
👉 Great balance of size, brightness, and support.

🔹 Smaller but easier to drive

2.8″ ILI9341 (320×240)

Brightness: ~300–400 nits (OK, but may wash out in bright sun unless under visor).

Resolution: 320×240 → simpler, faster refresh.

Driver: ILI9341 (rock-solid support, tons of examples).

Cost: ~$8–10.
👉 Good starter option, but for reflection HUD it may look a little dim.

🔹 Premium choice

4.0″ or 5.0″ ILI9488/ILI9486 IPS

Brightness: many are 800+ nits.

Larger digits, easy to see reflected.

Needs more dashboard space + slightly higher ESP32 load to refresh.

Cost: ~$18–25.
👉 Best if you want a “real HUD” look without squinting.

3) Bench test checklist (5–10 min)

Power the ESP32 from USB on your desk first.

Wire only the TFT and flash the sketch below → verify graphics.

Add GPS → check live speed/heading (walk outside or near a window).

Add BH1750 → cover/uncover sensor and watch theme/brightness change.

Move to the car and power from the buck (fused), not raw 12 V.

4) Arduino libraries to install

Adafruit GFX + your display driver (Adafruit_ILI9341 or TFT_eSPI / ILI9488 lib).
(Below sample uses Adafruit_ILI9341; for ILI9488 use a matching library or TFT_eSPI.)

TinyGPSPlus (GPS parsing)

BH1750 (by claws/Bogdan Necula or similar)

Adafruit BusIO (dependency)

5) Sketch (speed, heading, time, auto-brightness, HUD reflect mode)

Works out-of-the-box on ILI9341 (320×240). For ILI9488, swap the driver include/constructor and set width/height.
```
// ===== ESP32 Car HUD (GPS speed + heading + auto-brightness) =====
// Display: ILI9341 SPI (320x240). For ILI9488, use its driver instead.
// GPS: NEO-6M/M8N on UART2 (GPIO16 RX, GPIO17 TX)
// Light: BH1750 I2C (SDA21/SCL22)

#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>
#include <Wire.h>
#include <BH1750.h>
#include <TinyGPSPlus.h>

// ---------- Pins ----------
#define TFT_CS   5
#define TFT_DC   27
#define TFT_RST  33
#define TFT_SCK  18
#define TFT_MOSI 23
#define TFT_MISO 19  // may be unused on some boards

// Backlight (optional PWM via a MOSFET/transistor)
#define TFT_BL   32     // set to -1 if you tie LED to 3V3
#define BL_PWM_CHANNEL 0

// GPS (UART2)
#define GPS_RX 16  // ESP32 RX2 (to GPS TX)
#define GPS_TX 17  // ESP32 TX2 (optional)

// ---------- Display ----------
Adafruit_ILI9341 tft(TFT_CS, TFT_DC, TFT_RST);
const int W = 320, H = 240;

// HUD reflection mode: draw large symmetric 7-seg digits so mirror looks correct
const bool HUD_REFLECT = true;   // true = reflect on windshield; false = direct-view

// ---------- Sensors ----------
HardwareSerial GPSSerial(2);
TinyGPSPlus gps;
BH1750 lux;

// ---------- Units ----------
bool useMPH = true;   // toggle to false for km/h

// ---------- Smoothing ----------
double emaSpeed = 0.0;
const double alpha = 0.25; // EMA smoothing

// ---------- Colors ----------
uint16_t COL_BG_DARK  = ILI9341_BLACK;
uint16_t COL_FG_DARK  = ILI9341_CYAN;
uint16_t COL_BG_LIGHT = ILI9341_WHITE;
uint16_t COL_FG_LIGHT = ILI9341_BLACK;

// ---------- Helpers ----------
float gpsSpeedKmh() {
  if (gps.speed.isValid()) return gps.speed.kmph();
  return 0.0;
}
float toMPH(float kmh){ return kmh * 0.621371f; }

String headingText() {
  if (!gps.course.isValid()) return "--";
  double deg = gps.course.deg();
  const char* dirs[]={"N","NNE","NE","ENE","E","ESE","SE","SSE",
                      "S","SSW","SW","WSW","W","WNW","NW","NNW"};
  int idx = (int)((deg+11.25)/22.5) & 15;
  return String(dirs[idx]);
}

// draw a fat “7-segment” digit (symmetric for mirror HUD)
void segDigit(int x, int y, int w, int h, int thick, int num, uint16_t col) {
  // 7 segments: a,b,c,d,e,f,g
  // layout in a 3x5 grid
  bool seg[10][7] = {
    {1,1,1,1,1,1,0}, //0
    {0,1,1,0,0,0,0}, //1
    {1,1,0,1,1,0,1}, //2
    {1,1,1,1,0,0,1}, //3
    {0,1,1,0,0,1,1}, //4
    {1,0,1,1,0,1,1}, //5
    {1,0,1,1,1,1,1}, //6
    {1,1,1,0,0,0,0}, //7
    {1,1,1,1,1,1,1}, //8
    {1,1,1,1,0,1,1}  //9
  };
  // segment rectangles
  auto HBAR=[&](int cx,int cy,int cw,int ch){ tft.fillRoundRect(cx,cy,cw,ch,thick/2,col); };
  auto VBAR=[&](int cx,int cy,int cw,int ch){ tft.fillRoundRect(cx,cy,cw,ch,thick/2,col); };
  int gap = thick/2;
  // positions
  // a (top)
  if(seg[num][0]) HBAR(x+gap,         y,        w-2*gap, thick);
  // b (upper-right)
  if(seg[num][1]) VBAR(x+w-thick,     y+gap,    thick,   h/2-gap*2);
  // c (lower-right)
  if(seg[num][2]) VBAR(x+w-thick,     y+h/2+gap,thick,   h/2-gap*2);
  // d (bottom)
  if(seg[num][3]) HBAR(x+gap,         y+h-thick,w-2*gap, thick);
  // e (lower-left)
  if(seg[num][4]) VBAR(x,             y+h/2+gap,thick,   h/2-gap*2);
  // f (upper-left)
  if(seg[num][5]) VBAR(x,             y+gap,    thick,   h/2-gap*2);
  // g (middle)
  if(seg[num][6]) HBAR(x+gap,         y+h/2-thick/2, w-2*gap, thick);
}

void drawBigSpeed(int speedInt, uint16_t fg, uint16_t bg) {
  // Clear main area
  tft.fillRect(0, 20, W, 160, bg);

  // Layout three large digits (or two)
  int digits[3] = { (speedInt/100)%10, (speedInt/10)%10, speedInt%10 };
  int n = (speedInt >= 100) ? 3 : (speedInt >= 10) ? 2 : 1;

  int totalW = (n==3? W-16 : (n==2? W-16 : W-16));
  int segW = (n==3? 90 : (n==2? 120 : 140));
  int segH = 140;
  int thick = 18;
  int startX = (W - (n*segW + (n-1)*8)) / 2;
  int y = 30;

  for (int i=0;i<n;i++) {
    tft.fillRect(startX + i*(segW+8), y, segW, segH, bg);
    segDigit(startX + i*(segW+8), y, segW, segH, thick, digits[3-n+i], fg);
  }

  // Units
  tft.setTextSize(2);
  tft.setTextColor(fg, bg);
  String units = useMPH ? "MPH" : "KM/H";
  int16_t bx, by; uint16_t bw, bh;
  tft.getTextBounds(units, 0,0, &bx,&by,&bw,&bh);
  tft.setCursor(W-bw-8, H-28);
  tft.print(units);
}

void applyTheme(float luxVal){
  bool day = luxVal > 120.0; // adjust to taste
  uint16_t bg = day ? COL_BG_LIGHT : COL_BG_DARK;
  uint16_t fg = day ? COL_FG_LIGHT : COL_FG_DARK;
  tft.fillScreen(bg);

  // Title/status bar
  tft.setTextSize(2);
  tft.setTextColor(fg, bg);
  tft.setCursor(8, 4);
  tft.print("HUD");

  // Backlight PWM if wired
  #if (TFT_BL >= 0)
    int duty = day ? 255 : 80; // simple two-level scheme
    ledcWrite(BL_PWM_CHANNEL, duty);
  #endif
}

void setup() {
  // Serial for debug
  Serial.begin(115200);

  // TFT
  SPI.begin(TFT_SCK, TFT_MISO, TFT_MOSI);
  tft.begin();
  tft.setRotation(HUD_REFLECT ? 0 : 1);  // 0=portrait, 1=landscape; reflection often prefers portrait
  #if (TFT_BL >= 0)
    ledcSetup(BL_PWM_CHANNEL, 5000, 8);
    ledcAttachPin(TFT_BL, BL_PWM_CHANNEL);
    ledcWrite(BL_PWM_CHANNEL, 180);
  #endif

  // I2C + light
  Wire.begin(21,22);
  lux.begin(BH1750::CONTINUOUS_HIGH_RES_MODE);

  // GPS
  GPSSerial.begin(9600, SERIAL_8N1, GPS_RX, GPS_TX);

  // Initial theme
  applyTheme(50);
}

unsigned long lastDraw=0, lastTheme=0;
void loop() {
  // Feed GPS
  while (GPSSerial.available()) {
    gps.encode(GPSSerial.read());
  }

  // Update theme every ~2s
  if (millis()-lastTheme > 2000) {
    float lx = lux.readLightLevel();
    if (isnan(lx)) lx = 50;
    applyTheme(lx);
    lastTheme = millis();
  }

  // Compute speed
  float kmh = gpsSpeedKmh();
  float disp = useMPH ? toMPH(kmh) : kmh;
  // EMA smoothing
  if (emaSpeed <= 0.01) emaSpeed = disp;
  emaSpeed = alpha*disp + (1.0 - alpha)*emaSpeed;
  int speedInt = (int)round(emaSpeed);

  // Draw main HUD every 200 ms
  if (millis()-lastDraw > 200) {
    // Colors based on current background (re-read a pixel)
    uint16_t bg = tft.readPixel(0,0);
    bool bgIsLight = (bg == COL_BG_LIGHT);
    uint16_t fg = bgIsLight ? COL_FG_LIGHT : COL_FG_DARK;

    drawBigSpeed(speedInt, fg, bg);

    // Bottom info line: heading + time (GPS)
    tft.fillRect(0, H-24, W, 24, bg);
    tft.setTextSize(2);
    tft.setTextColor(fg, bg);
    tft.setCursor(8, H-20);
    tft.print(headingText());
    tft.setCursor(W/2, H-20);
    if (gps.time.isValid()) {
      char buf[12];
      snprintf(buf, sizeof(buf), "%02d:%02d:%02d",
               gps.time.hour(), gps.time.minute(), gps.time.second());
      tft.print(buf);
    } else {
      tft.print("--:--:--");
    }
    lastDraw = millis();
  }
}
```

Notes

The 7-segment digits are mirror-friendly, so you don’t need per-pixel mirroring for windshield reflection. If you run direct-view, set HUD_REFLECT=false and rotate as desired.

For an ILI9488 screen, switch to a compatible library (e.g., TFT_eSPI) and update the constructor + setRotation.

6) Mounting & setup

Choose mode

Reflection: Stick a HUD reflective film where you want the image. Lay the TFT flat on the dash, angle until digits are sharp.

Direct-view: Mount the TFT upright behind a small visor to cut glare.

Route power: Hard-wire the buck to an ACC circuit with the fuse tap; ground to chassis. Put the ESP32 and buck in a small enclosure.

Cable management: GPS antenna near windshield (under dash top works well). Keep SPI/GPS wires short.

Test drive: Compare HUD speed to the car’s speedometer and a phone GPS; adjust smoothing (alpha) if it feels jumpy.

7) Nice add-ons

OBD-II speed/RPM: Add MCP2515+SN65HVD230 (for CAN vehicles) and pick speed from the bus (smoother than GPS in tunnels).

Overspeed alert: flash digits or beep a piezo at a threshold.

Compass magnetometer (QMC5883L) for heading when GPS is stationary.

Navigation arrows: pair phone↔ESP32 via BLE and send minimal turn prompts from a companion app.

8) Safety & legal

Keep the display below sightline and non-distracting; obey local HUD/reflector laws.

Always fuse your feed; never run the ESP32 from raw 12 V.

Avoid tying into safety-critical wiring.

1) Hardware I recommend (premium tier)

ESP32 DevKit (WROOM-32).

4.0–5.0″ IPS TFT, SPI interface, 480×320, driver ILI9488 (preferred) or ILI9486.

Make sure it is SPI, not “RGB/parallel” (those are for STM32/RPi).

Prefer a board exposing: VCC, GND, SCK, MOSI, MISO, CS, DC, RST, LED(backlight).

GPS: u-blox NEO-M8N (or NEO-6M) with active antenna.

Ambient light sensor: BH1750 (I²C).

Automotive power: Buck converter 12–36 V → 5 V/3 A, fused (1–2 A).

Optional backlight dimming: small N-MOSFET + resistor to PWM the display’s LED pin (or use the TFT’s onboard dim pin if present).

HUD reflective film for the windshield (for reflection mode), or a small visor (for direct-view).

2) Wiring (SPI TFT + GPS + BH1750)
Power

Car ACC 12 V → fuse tap (1–2 A) → buck VIN; buck GND → chassis.

Buck 5 V → ESP32 5V/USB; share GND with all modules.

TFT (SPI)

ESP32 GPIO18 (SCK) → TFT SCK

ESP32 GPIO23 (MOSI) → TFT MOSI

ESP32 GPIO19 (MISO) → TFT MISO (if TFT supports reads; okay to leave if not used)

ESP32 GPIO5 (CS) → TFT CS

ESP32 GPIO27 (DC) → TFT DC

ESP32 GPIO33 (RST) → TFT RST

Backlight:

If TFT exposes LED pin: ESP32 GPIO32 (PWM) → small N-MOSFET gate → LED pin to 3.3/5 V via board (or per TFT docs).

If no LED pin, you can do day/night color themes only.

GPS (UART2)

ESP32 RX2 GPIO16 ← GPS TX

ESP32 TX2 GPIO17 → GPS RX (optional)

GPS VCC 3.3–5 V (check board), GND to GND.

BH1750 (I²C)

ESP32 SDA GPIO21 → BH1750 SDA

ESP32 SCL GPIO22 → BH1750 SCL

3V3 & GND shared.

Avoid boot-strap pins (GPIO0/2/15) for CS/DC. The above map is ESP32-safe.

3) Install & configure TFT_eSPI (important)

Install library “TFT_eSPI” in Arduino IDE.

Open File → Examples → TFT_eSPI → Setup (to locate config files).

Edit User_Setup_Select.h and comment out all default setups.

Add this line near the top (custom inline setup):

#define USER_SETUP_LOADED

// ==== ESP32 SPI pins ====
#define TFT_MOSI 23
#define TFT_MISO 19
#define TFT_SCLK 18
#define TFT_CS    5   // Chip select
#define TFT_DC   27   // Data/command
#define TFT_RST  33   // Reset

// ==== Driver ====
#define ILI9488_DRIVER        // For ILI9488
// If your board is ILI9486 instead, comment the above and use:
// #define ILI9486_DRIVER

// SPI speed (ILI9488 likes 40 MHz; some clones prefer 26-27 MHz)
#define SPI_FREQUENCY 40000000

// Optional: read support (if MISO wired and TFT supports it)
#define TFT_READ_ILI9488

// Fonts (enable what you need)
#define LOAD_GLCD
#define LOAD_FONT2
#define LOAD_FONT4
#define SMOOTH_FONT

// Color order
#define SPI_TOUCH_FREQUENCY 2500000


If your specific board insists on lower SPI frequency (tearing or flicker), try #define SPI_FREQUENCY 27000000.

4) Ready-to-flash HUD sketch (TFT_eSPI + TinyGPSPlus + BH1750)

Big 7-segment digits, mirror-friendly (for reflection).

Auto theme/brightness from BH1750.

MPH/KMH toggle.

// ===== Premium ESP32 Car HUD (ILI9488/ILI9486 + TFT_eSPI) =====
// Pins & driver set in TFT_eSPI's User_Setup_Select.h (see section above)

#include <TFT_eSPI.h>
#include <SPI.h>
#include <Wire.h>
#include <BH1750.h>
#include <TinyGPSPlus.h>

// ---------- Pins not set in TFT_eSPI ----------
#define TFT_BL   32        // Backlight PWM pin (if you wired a MOSFET). Set -1 to disable.
#define BL_CH    0

// ---------- GPS on UART2 ----------
#define GPS_RX   16        // ESP32 RX2 <- GPS TX
#define GPS_TX   17        // ESP32 TX2 -> GPS RX (optional)
HardwareSerial GPSSerial(2);
TinyGPSPlus gps;

// ---------- Display ----------
TFT_eSPI tft = TFT_eSPI();
const int W = 480, H = 320;   // ILI9488/ILI9486 480x320

// HUD reflection mode
bool HUD_REFLECT = true;      // true = reflect on windshield; false = direct view
bool useMPH = true;

// Light sensor
BH1750 lux;

// Smoothing
double emaSpeed = 0.0;
const double alpha = 0.25;

// Theme colors
uint16_t BG_DARK = TFT_BLACK;
uint16_t FG_DARK = TFT_CYAN;
uint16_t BG_LIGHT = TFT_WHITE;
uint16_t FG_LIGHT = TFT_BLACK;

float gpsSpeedKmh() {
  if (gps.speed.isValid()) return gps.speed.kmph();
  return 0.0;
}
float toMPH(float kmh){ return kmh * 0.621371f; }

String headingText() {
  if (!gps.course.isValid()) return "--";
  double deg = gps.course.deg();
  const char* dirs[]={"N","NNE","NE","ENE","E","ESE","SE","SSE",
                      "S","SSW","SW","WSW","W","WNW","NW","NNW"};
  int idx = (int)((deg+11.25)/22.5) & 15;
  return String(dirs[idx]);
}

// Basic 7-seg renderer; symmetric for mirror HUD
void segDigit(int x, int y, int w, int h, int thick, int num, uint16_t col, uint16_t bg) {
  bool seg[10][7] = {
    {1,1,1,1,1,1,0}, {0,1,1,0,0,0,0}, {1,1,0,1,1,0,1},
    {1,1,1,1,0,0,1}, {0,1,1,0,0,1,1}, {1,0,1,1,0,1,1},
    {1,0,1,1,1,1,1}, {1,1,1,0,0,0,0}, {1,1,1,1,1,1,1}, {1,1,1,1,0,1,1}
  };
  auto HBAR=[&](int cx,int cy,int cw,int ch){ tft.fillRoundRect(cx,cy,cw,ch, thick/2, col); };
  auto VBAR=[&](int cx,int cy,int cw,int ch){ tft.fillRoundRect(cx,cy,cw,ch, thick/2, col); };
  int gap = thick/2;
  tft.fillRect(x, y, w, h, bg);
  if(seg[num][0]) HBAR(x+gap,        y,         w-2*gap, thick);              // a
  if(seg[num][1]) VBAR(x+w-thick,    y+gap,     thick,   h/2-gap*2);          // b
  if(seg[num][2]) VBAR(x+w-thick,    y+h/2+gap, thick,   h/2-gap*2);          // c
  if(seg[num][3]) HBAR(x+gap,        y+h-thick, w-2*gap, thick);              // d
  if(seg[num][4]) VBAR(x,            y+h/2+gap, thick,   h/2-gap*2);          // e
  if(seg[num][5]) VBAR(x,            y+gap,     thick,   h/2-gap*2);          // f
  if(seg[num][6]) HBAR(x+gap,        y+h/2-thick/2, w-2*gap, thick);          // g
}

void drawSpeed(int spd, uint16_t fg, uint16_t bg) {
  int n = (spd >= 100) ? 3 : (spd >= 10) ? 2 : 1;
  int segW = (n==3? 130 : (n==2? 160 : 200));
  int segH = 200;
  int thick = 24;
  int gapX = 10;
  int startX = (W - (n*segW + (n-1)*gapX)) / 2;
  int y = 40;

  int d[3] = { (spd/100)%10, (spd/10)%10, spd%10 };
  for (int i=0;i<n;i++) {
    segDigit(startX + i*(segW+gapX), y, segW, segH, thick, d[3-n+i], fg, bg);
  }

  // Units
  tft.setTextColor(fg, bg);
  tft.setTextSize(2);
  String u = useMPH ? "MPH" : "KM/H";
  tft.setCursor(W-8 - tft.textWidth(u), H-28);
  tft.print(u);
}

void applyTheme(float lx){
  bool day = lx > 120.0f;
  uint16_t bg = day ? BG_LIGHT : BG_DARK;
  uint16_t fg = day ? FG_LIGHT : FG_DARK;
  tft.fillScreen(bg);

  tft.setTextColor(fg, bg);
  tft.setTextSize(2);
  tft.setCursor(8, 6);
  tft.print("HUD");

#if (TFT_BL >= 0)
  int duty = day ? 255 : 80; // tweak for your panel
  ledcWrite(BL_CH, duty);
#endif
}

void setup(){
  Serial.begin(115200);

  // Display init
  tft.init();
  tft.setRotation(HUD_REFLECT ? 0 : 1);  // Many HUDs use portrait for taller digits
#if (TFT_BL >= 0)
  ledcSetup(BL_CH, 5000, 8);
  ledcAttachPin(TFT_BL, BL_CH);
  ledcWrite(BL_CH, 180);
#endif

  // I2C + light
  Wire.begin(21,22);
  lux.begin(BH1750::CONTINUOUS_HIGH_RES_MODE);

  // GPS
  GPSSerial.begin(9600, SERIAL_8N1, GPS_RX, GPS_TX);

  applyTheme(60);
}

unsigned long lastDraw=0, lastTheme=0;
void loop(){
  // GPS feed
  while (GPSSerial.available()) gps.encode(GPSSerial.read());

  // Theme update
  if (millis()-lastTheme > 2000) {
    float lx = lux.readLightLevel();
    if (isnan(lx)) lx = 60;
    applyTheme(lx);
    lastTheme = millis();
  }

  // Speed calc + smoothing
  float kmh = gps.speed.isValid() ? gps.speed.kmph() : 0.0f;
  float disp = useMPH ? (kmh * 0.621371f) : kmh;
  if (emaSpeed < 0.01) emaSpeed = disp;
  emaSpeed = alpha*disp + (1.0 - alpha)*emaSpeed;
  int spd = (int)round(emaSpeed);
  if (spd < 0) spd = 0; if (spd > 199) spd = 199; // keep digits fitting

  // Draw ~5 fps
  if (millis() - lastDraw > 200) {
    uint16_t bg = tft.readPixel(0,0);
    bool light = (bg == BG_LIGHT);
    uint16_t fg = light ? FG_LIGHT : FG_DARK;

    // Main area
    tft.fillRect(0, 28, W, H-56, bg);
    drawSpeed(spd, fg, bg);

    // Footer: heading + time
    tft.fillRect(0, H-26, W, 26, bg);
    tft.setTextColor(fg, bg);
    tft.setTextSize(2);
    tft.setCursor(8, H-22);
    tft.print(headingText());

    tft.setCursor(W/2, H-22);
    if (gps.time.isValid()) {
      char buf[12];
      snprintf(buf, sizeof(buf), "%02d:%02d:%02d",
              gps.time.hour(), gps.time.minute(), gps.time.second());
      tft.print(buf);
    } else tft.print("--:--:--");

    lastDraw = millis();
  }
}


Notes

If your module is ILI9486, change the driver define in the TFT_eSPI setup section.

If your TFT board doesn’t wire MISO, TFT reads are disabled automatically; no problem.

If the screen shows reversed colors or weird orientation, try tft.setRotation(1..3) to suit your mount.

5) Mounting & use

Reflection HUD: apply HUD film, lay TFT flat, tilt until digits are sharp and single-image (film prevents double reflections).

Direct-view: mount upright with a small visor; use day/night themes + PWM dimming.

Route GPS antenna to dash top or near windshield. Keep SPI wires short.

6) Upgrades (when you’re ready)

OBD-II speed (CAN) for tunnels/parking lots; blend with GPS.

Overspeed/beep (piezo on a GPIO).

BLE link from phone for simple turn arrows.

Magnetometer (QMC5883L) for heading when stopped.

🔧 Core Board
ESP32 DevKit V1 (ESP-WROOM-32, 30-pin or 38-pin)

Well-supported, cheap, and stable.

USB programming and OTA supported.

Good library compatibility (TinyGPS++, TFT_eSPI, BH1750).

Avoid ultra-mini variants (like ESP32-CAM) — they’re less stable for continuous HUD use.

👉 Example: DOIT ESP32 DevKit V1 (30-pin) from Amazon/eBay.

🖥️ Display (TFT HUD screen)
4.0″–5.0″ ILI9488 IPS, SPI

Driver: ILI9488 (sometimes ILI9486).

Resolution: 480×320.

Brightness: look for ≥500 nits (“high brightness” or “sunlight readable”).

Interface: Must say SPI (4-wire), not “parallel RGB.”

Backlight pin (LED): lets you dim with ESP32 PWM.

👉 Recommended module:

3.5″/4.0″/5.0″ ILI9488 SPI TFT with touch (optional), ~12–20 USD on AliExpress/Amazon.

For max readability, choose IPS + “high brightness” model.

📡 GPS
u-blox NEO-M8N (with external active antenna)

Why not NEO-6M? Works, but M8N is faster (10 Hz updates), more satellites (GPS+GLONASS+Galileo), better accuracy under trees/urban canyons.

Voltage: 3.3–5 V compatible.

Output: NMEA UART @9600 baud (works with TinyGPS++).

Active antenna: magnetic puck → place under windshield.

👉 Module: GY-NEO-M8N with antenna (~$20–25).

☀️ Ambient Light Sensor (for auto-brightness)
BH1750 (I²C)

Cheap, accurate, very low power.

Range: 1–65,000 lux → perfect for car interior (dark night → bright day).

Directly supported by Arduino BH1750 library.

Mount on dash near windshield (not shaded).

👉 Module: BH1750 breakout board (~$3).

⚡ Power (automotive safe)

DC-DC Buck Converter (Automotive Grade):

Input: 9–36 V

Output: 5 V, ≥3 A

With surge/load-dump protection.

Inline fuse: 1–2 A mini blade fuse.

(Optional but recommended) TVS diode (36 V) across input.

👉 Examples:

DROK 12V→5V buck hardwire USB (Amazon).

LM2596-based board works, but automotive surges can kill them if not protected.

🛠️ Optional Upgrades

Piezo buzzer (speed warnings).

QMC5883L magnetometer (heading when GPS is still).

OBD-II CAN module (MCP2515 + SN65HVD230) to add RPM/speed from car bus.

HUD reflective film (Amazon ~$8) → eliminates double reflection.

✅ Summary Shopping List

ESP32 DevKit V1 (30-pin)

4.0–5.0″ ILI9488 IPS SPI TFT, ≥500 nits brightness

u-blox NEO-M8N GPS module + active antenna

BH1750 light sensor (I²C breakout)

Automotive buck converter (12→5 V, 3 A, surge protected)

Mini blade fuse tap + 2 A fuse

(Optional) HUD reflective film, piezo buzzer, CAN module

[wiring diagram](./hud.png)