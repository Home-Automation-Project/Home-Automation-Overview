# Backyard Bird Feeder Monitor with species recognition 
Uses an ESP32-CAM at the feeder and a local classifier server (Python) that does the heavy lifting. It logs every visit, pushes MQTT events (for Home Assistant), and can notify you (email/Telegram)

1) Hardware (recommended BOM)

ESP32-CAM (AI-Thinker) + FTDI USB-TTL for flashing

Mini PIR sensor (HC-SR501 mini or AM312) for motion trigger (optional but great)

5V power: USB wall adapter (≥1A) + weatherproof cable

Camera shelter: Small 3D-printed/DIY hood to keep rain off lens & board

Bird feeder with a fixed perch in camera frame

(Optional) IR LED board 850 nm for dusk/dawn (ESP32-CAM has no IR filter)

(Optional) Raspberry Pi 4 / small PC to run the classifier server 24/7

Mounting tips

Put the ESP32-CAM 20–40 cm from the perch, slightly above and angled down.

Keep the background simple (flat board or backdrop) → better classification.

Add a focus shim if your ESP32-CAM lens needs refocus (twist ring, glue when done).

2) Wiring (ESP32-CAM quick map)

5V → 5V, GND → GND

PIR OUT → GPIO 13 (pulled up internally)

Keep the on-board flash LED disabled; add external IR board to 5V if needed.

3) Software overview (two pieces)

ESP32-CAM firmware: waits for PIR or interval → takes a JPEG → HTTP POST to server.

Classifier server (Python/FastAPI): receives image → detects/crops bird → classifies species → saves to disk/SQLite → publishes MQTT event.

If you built my “plant monitor + vision server,” you’ll recognize the structure—this just swaps in bird logic.

4) Flash the ESP32-CAM (Arduino IDE)

Libraries: none beyond core (uses WiFi.h, HTTPClient.h, esp_camera.h).

Sketch: esp32_cam_bird.ino

#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include "esp_camera.h"

// ---------- CONFIG ----------
#define WIFI_SSID     "YOUR_WIFI"
#define WIFI_PASS     "YOUR_PASS"
#define SERVER_URL    "http://YOUR_SERVER_IP:8000/birds/predict"
#define DEVICE_NAME   "feeder_cam_1"
#define PIR_PIN       13          // AM312/HC-SR501 mini -> 13
#define CAPTURE_EVERY_SEC  0      // set >0 to also do periodic captures
#define CAM_FRAME_SIZE     FRAMESIZE_SVGA
#define CAM_JPEG_QUALITY   12
// ----------------------------

// AI Thinker ESP32-CAM pin map
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

static void wifiUp(){
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long t=millis();
  while (WiFi.status()!=WL_CONNECTED && millis()-t<20000) delay(200);
}

static bool camInit(){
  camera_config_t c;
  c.ledc_channel = LEDC_CHANNEL_0; c.ledc_timer = LEDC_TIMER_0;
  c.pin_d0=Y2_GPIO_NUM; c.pin_d1=Y3_GPIO_NUM; c.pin_d2=Y4_GPIO_NUM; c.pin_d3=Y5_GPIO_NUM;
  c.pin_d4=Y6_GPIO_NUM; c.pin_d5=Y7_GPIO_NUM; c.pin_d6=Y8_GPIO_NUM; c.pin_d7=Y9_GPIO_NUM;
  c.pin_xclk=XCLK_GPIO_NUM; c.pin_pclk=PCLK_GPIO_NUM; c.pin_vsync=VSYNC_GPIO_NUM;
  c.pin_href=HREF_GPIO_NUM; c.pin_sscb_sda=SIOD_GPIO_NUM; c.pin_sscb_scl=SIOC_GPIO_NUM;
  c.pin_pwdn=PWDN_GPIO_NUM; c.pin_reset=RESET_GPIO_NUM;
  c.xclk_freq_hz=20000000; c.frame_size=CAM_FRAME_SIZE; c.pixel_format=PIXFORMAT_JPEG;
  c.fb_location=CAMERA_FB_IN_PSRAM; c.jpeg_quality=CAM_JPEG_QUALITY; c.fb_count=1;
  return esp_camera_init(&c)==ESP_OK;
}

static bool postJpeg(const uint8_t* buf, size_t len){
  HTTPClient http; if(!http.begin(SERVER_URL)) return false;
  http.addHeader("Content-Type","application/octet-stream");
  http.addHeader("X-Device-Id", DEVICE_NAME);
  int code = http.POST(buf, len);
  bool ok = (code>=200 && code<300);
  http.end(); return ok;
}

static void captureAndSend(){
  camera_fb_t* fb = esp_camera_fb_get();
  if(!fb) return;
  postJpeg(fb->buf, fb->len);
  esp_camera_fb_return(fb);
}

void setup(){
  pinMode(PIR_PIN, INPUT);
  wifiUp();
  if(!camInit()) { delay(5000); ESP.restart(); }
}

void loop(){
  static unsigned long last = 0;
  bool trigger = digitalRead(PIR_PIN)==HIGH;
  bool periodic = (CAPTURE_EVERY_SEC>0 && (millis()-last)>CAPTURE_EVERY_SEC*1000UL);

  if(trigger || periodic){
    captureAndSend();
    last = millis();
    delay(1500); // debounce PIR / avoid bursts
  }
  delay(50);
}

5) Classifier server (Python/FastAPI + ONNXRuntime)

What it does

Receives JPEG → decodes with Pillow/OpenCV

(Optional) Runs a bird detector to crop the feeder perch (else uses center crop)

Runs a species classifier (ONNX/TFLite) → top-K species

Saves snapshot + JSON to disk/SQLite

Publishes MQTT event: home/birds/<device>/event

You can start with classifier-only (no detector) if the frame is clean (single bird close to center). If you want robustness with multiple objects, add a lightweight detector (e.g., MobileNet-SSD or YOLO-n) and then classify the crop.

Install

python -m venv .venv
source .venv/bin/activate
pip install fastapi uvicorn[standard] pillow onnxruntime opencv-python paho-mqtt sqlite-utils


server_birds.py

import io, os, time, json, sqlite3, uuid
from pathlib import Path
from typing import List
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from PIL import Image
import numpy as np
import cv2
import onnxruntime as ort
import paho.mqtt.client as mqtt

# ---- Paths & settings ----
DATA_DIR = Path("./bird_events"); DATA_DIR.mkdir(exist_ok=True)
DB_PATH = DATA_DIR/"events.sqlite"
MODEL_PATH = Path("./models/bird_classifier.onnx")   # put your ONNX classifier here
LABELS_PATH = Path("./models/labels.txt")            # one species name per line
IMG_SIZE = 224                                       # match your model input
TOPK = 3

# MQTT optional
MQTT_ENABLE = True
MQTT_HOST = "192.168.1.10"; MQTT_PORT = 1883
MQTT_USER = "mqtt_user"; MQTT_PASS = "mqtt_pass"
MQTT_BASE = "home/birds"

# ---- Load model & labels ----
labels: List[str] = LABELS_PATH.read_text(encoding="utf-8").splitlines()
sess = ort.InferenceSession(str(MODEL_PATH), providers=["CPUExecutionProvider"])
inp_name = sess.get_inputs()[0].name
out_name = sess.get_outputs()[0].name

def ensure_db():
    con = sqlite3.connect(DB_PATH); cur = con.cursor()
    cur.execute("""CREATE TABLE IF NOT EXISTS events(
        id TEXT PRIMARY KEY, ts REAL, device TEXT, top_json TEXT, img_path TEXT
    )""")
    con.commit(); con.close()
ensure_db()

def preprocess_pil(img: Image.Image) -> np.ndarray:
    # center square crop -> resize -> normalize 0..1 -> NCHW
    w,h = img.size
    side = min(w,h); x=(w-side)//2; y=(h-side)//2
    img = img.crop((x,y,x+side,y+side)).resize((IMG_SIZE, IMG_SIZE))
    x = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    # optional mean/std normalize for your model
    x = x.transpose(2,0,1)[None, ...]  # NCHW
    return x

def infer_species(img: Image.Image):
    x = preprocess_pil(img)
    logits = sess.run([out_name], {inp_name: x})[0][0]  # [C]
    probs = np.exp(logits - logits.max())
    probs /= probs.sum()
    idx = probs.argsort()[::-1][:TOPK]
    top = [{"species": labels[i], "prob": float(probs[i])} for i in idx]
    return top

# MQTT client
mqtt_client = None
if MQTT_ENABLE:
    try:
        mqtt_client = mqtt.Client()
        if MQTT_USER: mqtt_client.username_pw_set(MQTT_USER, MQTT_PASS)
        mqtt_client.connect(MQTT_HOST, MQTT_PORT, 60)
    except Exception as e:
        print("MQTT connect failed:", e); mqtt_client = None

app = FastAPI(title="Bird Feeder Species Classifier")

@app.post("/birds/predict")
async def birds_predict(request: Request):
    raw = await request.body()
    if not raw: return JSONResponse({"error":"no image"}, status_code=400)
    device = request.headers.get("X-Device-Id","unknown_cam")
    try:
        img = Image.open(io.BytesIO(raw))
    except Exception:
        return JSONResponse({"error":"bad image"}, status_code=400)

    # (Optional) detector step could go here to crop the bird region
    top = infer_species(img)
    ts = time.time()
    eid = str(uuid.uuid4())
    img_path = DATA_DIR / f"{int(ts)}_{eid}.jpg"
    img.save(img_path, quality=90)

    # persist
    con = sqlite3.connect(DB_PATH); cur = con.cursor()
    cur.execute("INSERT INTO events(id,ts,device,top_json,img_path) VALUES(?,?,?,?,?)",
                (eid, ts, device, json.dumps(top), str(img_path)))
    con.commit(); con.close()

    # mqtt
    if mqtt_client:
        payload = {"device":device, "ts":ts, "top":top, "img": img_path.name}
        try:
            mqtt_client.publish(f"{MQTT_BASE}/{device}/event", json.dumps(payload), retain=False)
        except Exception as e:
            print("mqtt publish failed:", e)

    return JSONResponse({"id":eid,"top":top,"saved":img_path.name})

@app.get("/birds/healthz")
async def healthz(): return {"ok":True}


Model & labels: Put an ONNX image classifier trained on your local species list in ./models/bird_classifier.onnx and a matching labels.txt (one species per line in the same output order). To start fast, you can fine-tune any MobileNet/EfficientNet on ~20–50 common backyard species (transfer learning).

Run

uvicorn server_birds:app --host 0.0.0.0 --port 8000

6) Home Assistant (MQTT)

Add an MQTT sensor (or use an MQTT “text” helper) to show the last species:

sensor:
  - name: "Last Bird Species"
    unique_id: last_bird_species
    state_topic: "home/birds/feeder_cam_1/event"
    value_template: "{{ value_json.top[0].species }}"


You can also template a confidence sensor, or trigger an automation when species in ["American Goldfinch","House Finch"].

7) Notifications (optional)

Telegram: Have your server script subprocess.run a curl to Telegram Bot API on each event.

Email: Use smtplib or a webhook service.

Rate-limit to 1 notification per X minutes per species to avoid spam.

8) Field tuning checklist

Frame cleanliness: single perch, plain backdrop, consistent distance.

Lighting: avoid strong backlight; add small diffuser over perch if harsh sun.

Focus: twist lens to crisp detail at perch distance; dab glue to lock.

PIR sensitivity: tune to trigger only when something lands at perch.

Night: IR LED at 850 nm placed off-axis to reduce eye-shine glare.

9) Improving recognition

Start with a small label set (e.g., top 20 species you see).

Collect & label your own feeder images for fine-tuning.

Add a detector (e.g., MobileNet-SSD/YOLO “bird” class) → crop → classify (best accuracy).

Train-time augmentations: random crop, brightness, slight rotation → improves robustness.

10) Maintenance & data

All images saved under ./bird_events.

SQLite log at ./bird_events/events.sqlite (id, timestamp, device, top-K, image file).

Periodically archive (.zip) older months to NAS/Dropbox.

# training detection
Path A — “Fastest way”: fine-tune a small model on your own photos (10–20 species)

This is the most reliable path for backyard feeders because you’ll match your camera angle, distance, lighting, and local species. It’s a 1–2 hour evening project if you already have ~50–150 photos per species.

1) Make a tiny dataset

Create a folder tree like this (one folder per species you want recognized):

birds_ds/
  train/
    american_goldfinch/
    house_finch/
    black_capped_chickadee/
    northern_cardinal/
    ...
  val/
    american_goldfinch/
    house_finch/
    black_capped_chickadee/
    northern_cardinal/
    ...


Put 60–90% of images in train/, the rest in val/.

If you have only a handful for some species, oversample or add light augmentations (flip, small rotations).

2) Install deps
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install torch torchvision onnx onnxruntime opencv-python pillow tqdm

3) Train (transfer learning) + export to ONNX

Paste this as train_birds_to_onnx.py and run it. It uses MobileNetV3-Small, quick and accurate for small edge tasks.

# train_birds_to_onnx.py
import os, json, time, numpy as np, torch
from pathlib import Path
from torch import nn, optim
from torch.utils.data import DataLoader
from torchvision import datasets, transforms, models
from tqdm import tqdm

DATA_DIR = Path("birds_ds")      # your dataset root with train/ and val/
MODEL_OUT = Path("models"); MODEL_OUT.mkdir(exist_ok=True, parents=True)
ONNX_PATH = MODEL_OUT/"bird_classifier.onnx"
LABELS_PATH = MODEL_OUT/"labels.txt"
IMG_SIZE = 224
BATCH = 32
EPOCHS = 8
LR = 3e-4
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
MEAN = (0.485, 0.456, 0.406)   # torchvision ImageNet mean/std
STD  = (0.229, 0.224, 0.225)

# 1) Datasets & loaders
train_tf = transforms.Compose([
    transforms.RandomResizedCrop(IMG_SIZE, scale=(0.7, 1.0)),
    transforms.RandomHorizontalFlip(),
    transforms.ColorJitter(0.2,0.2,0.2,0.05),
    transforms.ToTensor(),
    transforms.Normalize(MEAN, STD),
])
val_tf = transforms.Compose([
    transforms.Resize(int(IMG_SIZE*1.14)),
    transforms.CenterCrop(IMG_SIZE),
    transforms.ToTensor(),
    transforms.Normalize(MEAN, STD),
])

train_ds = datasets.ImageFolder(DATA_DIR/"train", transform=train_tf)
val_ds   = datasets.ImageFolder(DATA_DIR/"val",   transform(val_tf))
train_loader = DataLoader(train_ds, batch_size=BATCH, shuffle=True, num_workers=2, pin_memory=True)
val_loader   = DataLoader(val_ds, batch_size=BATCH, shuffle=False, num_workers=2, pin_memory=True)

# Save labels file in class index order
classes = train_ds.classes
with open(LABELS_PATH, "w", encoding="utf-8") as f:
    f.write("\n".join(classes))

# 2) Model: MobileNetV3-Small pretrained → replace classifier
m = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.DEFAULT)
in_feats = m.classifier[3].in_features
m.classifier[3] = nn.Linear(in_feats, len(classes))
m.to(DEVICE)

criterion = nn.CrossEntropyLoss()
optimizer = optim.AdamW(m.parameters(), lr=LR)
scaler = torch.cuda.amp.GradScaler(enabled=(DEVICE=="cuda"))

def evaluate():
    m.eval(); correct=0; total=0; loss_sum=0.0
    with torch.no_grad():
        for x,y in val_loader:
            x,y = x.to(DEVICE), y.to(DEVICE)
            with torch.cuda.amp.autocast(enabled=(DEVICE=="cuda")):
                logits = m(x)
                loss = criterion(logits, y)
            loss_sum += loss.item()*x.size(0)
            pred = logits.argmax(1)
            correct += (pred==y).sum().item()
            total += x.size(0)
    return loss_sum/total, correct/total

best_acc = 0.0
for epoch in range(1, EPOCHS+1):
    m.train()
    pbar = tqdm(train_loader, desc=f"Epoch {epoch}/{EPOCHS}")
    for x,y in pbar:
        x,y = x.to(DEVICE), y.to(DEVICE)
        optimizer.zero_grad()
        with torch.cuda.amp.autocast(enabled=(DEVICE=="cuda")):
            logits = m(x)
            loss = criterion(logits, y)
        scaler.scale(loss).backward()
        scaler.step(optimizer)
        scaler.update()
        pbar.set_postfix(loss=float(loss.item()))
    val_loss, val_acc = evaluate()
    print(f"Val: loss={val_loss:.4f}, acc={val_acc:.3f}")
    if val_acc > best_acc:
        best_acc = val_acc
        torch.save(m.state_dict(), MODEL_OUT/"best.pt")

# Reload best and export to ONNX
m.load_state_dict(torch.load(MODEL_OUT/"best.pt", map_location=DEVICE))
m.eval()
dummy = torch.zeros(1,3,IMG_SIZE,IMG_SIZE, device=DEVICE)
torch.onnx.export(
    m, dummy, ONNX_PATH,
    input_names=["input"], output_names=["logits"],
    dynamic_axes={"input":{0:"batch"}, "logits":{0:"batch"}},
    opset_version=13
)
print("Exported:", ONNX_PATH)
print("Labels:", LABELS_PATH)

4) Verify the ONNX with onnxruntime
# sanity_check_onnx.py
import numpy as np, onnxruntime as ort
from PIL import Image
from pathlib import Path

IMG = "some_test_bird.jpg"
MODEL = "models/bird_classifier.onnx"
LABELS = [l.strip() for l in open("models/labels.txt", "r", encoding="utf-8")]
IMG_SIZE = 224
MEAN = (0.485,0.456,0.406); STD=(0.229,0.224,0.225)

def preprocess(pil):
    pil = pil.convert("RGB").resize((IMG_SIZE,IMG_SIZE))
    x = (np.asarray(pil)/255.0).astype("float32")
    x = (x - MEAN)/STD
    x = x.transpose(2,0,1)[None, ...]
    return x

sess = ort.InferenceSession(MODEL, providers=["CPUExecutionProvider"])
inp, out = sess.get_inputs()[0].name, sess.get_outputs()[0].name
x = preprocess(Image.open(IMG))
logits = sess.run([out], {inp:x})[0][0]
probs = np.exp(logits - logits.max()); probs /= probs.sum()
top = probs.argsort()[::-1][:3]
for i in top:
    print(LABELS[i], float(probs[i]))


Copy bird_classifier.onnx and labels.txt into your server’s models/ folder and make sure the server’s preprocessing matches the MEAN/STD above.

Path B — “Zero-training now, train later”: use a generic image embedder + nearest-neighbors

If you don’t have labeled data yet, you can still get useful species guesses by:

Using a pretrained image embedding model (e.g., a torchvision backbone or CLIP) exported to ONNX,

Storing a gallery of a few exemplar images per species,

Classifying new images by cosine similarity to the gallery.

Steps

Collect 10–20 exemplar images per species you care about (handpicked, good quality).

Use a backbone (e.g., resnet50) to produce 2048-D embeddings.

Save each species’ centroid vector; at inference time compute the embedding for the incoming frame and pick the nearest centroid.

Pros: no training, quick start.
Cons: lower accuracy on tough angles/lighting; you’ll eventually want fine-tuning.

Sketch (Python, concept):

# build_gallery.py
import numpy as np, torch, onnx, onnxruntime as ort
from torchvision import models, transforms
from PIL import Image
from pathlib import Path
import json

IMG_SIZE=224
MEAN=(0.485,0.456,0.406); STD=(0.229,0.224,0.225)
tf = transforms.Compose([
  transforms.Resize(int(IMG_SIZE*1.14)),
  transforms.CenterCrop(IMG_SIZE),
  transforms.ToTensor(),
  transforms.Normalize(MEAN,STD)
])

# 1) Export a feature extractor to ONNX
m = models.resnet50(weights=models.ResNet50_Weights.DEFAULT)
m.fc = torch.nn.Identity()
m.eval()
dummy = torch.zeros(1,3,IMG_SIZE,IMG_SIZE)
torch.onnx.export(m, dummy, "models/resnet50_feats.onnx",
                  input_names=["input"], output_names=["feat"],
                  dynamic_axes={"input":{0:"batch"}, "feat":{0:"batch"}},
                  opset_version=13)

# 2) Build species centroids
sess = ort.InferenceSession("models/resnet50_feats.onnx", providers=["CPUExecutionProvider"])
inp, out = sess.get_inputs()[0].name, sess.get_outputs()[0].name
GALLERY = Path("gallery")  # gallery/species_name/*.jpg
centroids={}
for sp_dir in GALLERY.iterdir():
    if not sp_dir.is_dir(): continue
    vecs=[]
    for imgp in sp_dir.glob("*.jpg"):
        x = tf(Image.open(imgp).convert("RGB")).unsqueeze(0).numpy()
        feat = sess.run([out], {"input": x})[0]   # [1,2048]
        v = feat[0]/(np.linalg.norm(feat[0])+1e-8)
        vecs.append(v)
    if vecs:
        centroids[sp_dir.name] = (np.stack(vecs,0).mean(0)).tolist()
Path("models/centroids.json").write_text(json.dumps(centroids))
print("Built:", len(centroids), "species centroids")


Then at inference time, compute the feature for the incoming image and choose the nearest centroid by cosine similarity. You can later replace this with the trained classifier from Path A by just swapping the model + labels and keeping your API the same.

Which path should you pick?

If you have (or can quickly gather) 50–150 images/species: do Path A now. You’ll get strong accuracy and a clean .onnx you can deploy.

If you want something working today with zero labels: do Path B now and plan a weekend to fine-tune (Path A) later.

Plugging into your feeder server

Whichever path you choose, make sure your FastAPI server:

Uses the same preprocessing (resize/center-crop/MEAN/STD) as the training/export.

Loads models/bird_classifier.onnx (Path A) or models/resnet50_feats.onnx + centroids.json (Path B).

Reads labels.txt for species names (Path A), or keys from centroids.json (Path B).

Returns top-K results as you already saw in the /birds/predict endpoint structure.

## REST API
FastAPI server that supports both backends:

Path A (Classifier): bird_classifier.onnx + labels.txt

Path B (Embedder + Nearest-Centroid): resnet50_feats.onnx + centroids.json

It also:

saves each snapshot to disk,

logs events to SQLite,

(optionally) publishes MQTT events for Home Assistant.

📁 Folder layout (make this)
bird-feeder-server/
├─ server.py
├─ requirements.txt
├─ models/
│  ├─ bird_classifier.onnx        # (Path A) optional now
│  ├─ labels.txt                  # (Path A) optional now
│  ├─ resnet50_feats.onnx         # (Path B) optional now
│  └─ centroids.json              # (Path B) optional now
└─ data/
   └─ bird_events/                # auto-created

📦 requirements.txt
fastapi
uvicorn[standard]
pillow
numpy
opencv-python
onnxruntime
paho-mqtt
sqlite-utils
python-dotenv

🚀 server.py (copy all of this)
import io, os, json, time, uuid, sqlite3
from pathlib import Path
from typing import List, Dict, Tuple, Optional

import numpy as np
from PIL import Image
import onnxruntime as ort
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import paho.mqtt.client as mqtt

# ----------------------------
# Configuration (env or defaults)
# ----------------------------
# Backend mode: "classifier" (Path A) or "embedder" (Path B)
BACKEND_MODE = os.getenv("BF_BACKEND_MODE", "classifier").lower()

# Model files
MODEL_DIR     = Path(os.getenv("BF_MODEL_DIR", "models"))
CLASSIFIER_ONNX = MODEL_DIR / os.getenv("BF_CLASSIFIER_ONNX", "bird_classifier.onnx")
LABELS_TXT      = MODEL_DIR / os.getenv("BF_LABELS_TXT", "labels.txt")
EMBEDDER_ONNX   = MODEL_DIR / os.getenv("BF_EMBEDDER_ONNX", "resnet50_feats.onnx")
CENTROIDS_JSON  = MODEL_DIR / os.getenv("BF_CENTROIDS_JSON", "centroids.json")

# Preprocessing
IMG_SIZE = int(os.getenv("BF_IMG_SIZE", "224"))
MEAN = tuple(map(float, os.getenv("BF_MEAN", "0.485,0.456,0.406").split(",")))
STD  = tuple(map(float, os.getenv("BF_STD",  "0.229,0.224,0.225").split(",")))

# Output top-K
TOPK = int(os.getenv("BF_TOPK", "3"))

# Storage
DATA_DIR = Path(os.getenv("BF_DATA_DIR", "data/bird_events"))
DATA_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA_DIR / "events.sqlite"

# MQTT
MQTT_ENABLE = os.getenv("BF_MQTT_ENABLE", "false").lower() in ("1", "true", "yes")
MQTT_HOST   = os.getenv("BF_MQTT_HOST", "192.168.1.10")
MQTT_PORT   = int(os.getenv("BF_MQTT_PORT", "1883"))
MQTT_USER   = os.getenv("BF_MQTT_USER", "mqtt_user")
MQTT_PASS   = os.getenv("BF_MQTT_PASS", "mqtt_pass")
MQTT_BASE   = os.getenv("BF_MQTT_BASE", "home/birds")

# ----------------------------
# Utilities
# ----------------------------
def ensure_db():
    con = sqlite3.connect(DB_PATH); cur = con.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS events(
            id TEXT PRIMARY KEY,
            ts REAL,
            device TEXT,
            mode TEXT,
            top_json TEXT,
            img_path TEXT
        )
    """)
    con.commit(); con.close()
ensure_db()

def preprocess_pil(pil: Image.Image) -> np.ndarray:
    """Resize -> center-crop to IMG_SIZE, normalize (MEAN/STD), NCHW float32 in [batch=1]."""
    pil = pil.convert("RGB")
    # Simple center-crop after resize-within
    w, h = pil.size
    scale = IMG_SIZE / min(w, h)
    new_w, new_h = int(round(w * scale)), int(round(h * scale))
    pil = pil.resize((new_w, new_h), Image.BICUBIC)
    # center crop
    x0 = (new_w - IMG_SIZE) // 2
    y0 = (new_h - IMG_SIZE) // 2
    pil = pil.crop((x0, y0, x0 + IMG_SIZE, y0 + IMG_SIZE))

    x = np.asarray(pil).astype("float32") / 255.0
    x = (x - MEAN) / STD
    x = x.transpose(2, 0, 1)[None, ...]  # NCHW
    return x

def softmax(logits: np.ndarray) -> np.ndarray:
    a = logits - logits.max()
    exp = np.exp(a)
    return exp / exp.sum()

# ----------------------------
# Backends
# ----------------------------
class ClassifierBackend:
    """Path A: ONNX classifier with labels.txt"""
    def __init__(self, model_path: Path, labels_path: Path):
        if not model_path.exists():
            raise FileNotFoundError(f"Classifier ONNX not found: {model_path}")
        if not labels_path.exists():
            raise FileNotFoundError(f"labels.txt not found: {labels_path}")
        self.sess = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        self.inp = self.sess.get_inputs()[0].name
        self.out = self.sess.get_outputs()[0].name
        self.labels = labels_path.read_text(encoding="utf-8").splitlines()

    def predict_topk(self, pil: Image.Image, k: int) -> List[Dict]:
        x = preprocess_pil(pil)
        logits = self.sess.run([self.out], {self.inp: x})[0][0]  # (C,)
        probs = softmax(logits)
        idx = probs.argsort()[::-1][:k]
        return [{"species": self.labels[i], "prob": float(probs[i])} for i in idx]

class EmbedderBackend:
    """Path B: ONNX feature extractor + nearest-centroid from centroids.json"""
    def __init__(self, model_path: Path, centroids_json: Path):
        if not model_path.exists():
            raise FileNotFoundError(f"Embedder ONNX not found: {model_path}")
        if not centroids_json.exists():
            raise FileNotFoundError(f"centroids.json not found: {centroids_json}")
        self.sess = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        self.inp = self.sess.get_inputs()[0].name
        self.out = self.sess.get_outputs()[0].name

        # centroids.json can be either {species: [float,...]} or {species: [[...], ...]} -> we take mean
        raw = json.loads(centroids_json.read_text(encoding="utf-8"))
        labels = []
        vecs = []
        for sp, v in raw.items():
            arr = np.array(v, dtype="float32")
            if arr.ndim == 2:   # list of vectors
                c = arr.mean(axis=0)
            else:
                c = arr
            n = np.linalg.norm(c) + 1e-8
            labels.append(sp)
            vecs.append(c / n)
        self.labels = labels
        self.centroids = np.stack(vecs, axis=0)  # (S, D)

    def _embed(self, pil: Image.Image) -> np.ndarray:
        # Use same preprocess as classifier (mean/std, size)
        x = preprocess_pil(pil)  # (1,3,H,W)
        feat = self.sess.run([self.out], {self.inp: x})[0][0]  # (D,)
        feat = feat.astype("float32")
        feat = feat / (np.linalg.norm(feat) + 1e-8)
        return feat

    def predict_topk(self, pil: Image.Image, k: int) -> List[Dict]:
        f = self._embed(pil)  # (D,)
        # cosine similarity = dot for normalized vectors
        sims = self.centroids @ f  # (S,)
        idx = sims.argsort()[::-1][:k]
        # convert similarity to [0..1]-ish confidence
        sims_clipped = np.clip((sims[idx] + 1) / 2.0, 0.0, 1.0)
        return [{"species": self.labels[i], "prob": float(sims_clipped[j])}
                for j, i in enumerate(idx)]

# ----------------------------
# App init
# ----------------------------
app = FastAPI(title="Bird Feeder Species Server")

backend = None
mode_loaded = None
mqtt_client = None

def init_backend():
    global backend, mode_loaded
    if BACKEND_MODE == "classifier":
        backend = ClassifierBackend(CLASSIFIER_ONNX, LABELS_TXT)
        mode_loaded = "classifier"
    elif BACKEND_MODE == "embedder":
        backend = EmbedderBackend(EMBEDDER_ONNX, CENTROIDS_JSON)
        mode_loaded = "embedder"
    else:
        raise ValueError("BF_BACKEND_MODE must be 'classifier' or 'embedder'")

def init_mqtt():
    global mqtt_client
    if not MQTT_ENABLE:
        mqtt_client = None
        return
    try:
        mqtt_client = mqtt.Client()
        if MQTT_USER:
            mqtt_client.username_pw_set(MQTT_USER, MQTT_PASS)
        mqtt_client.connect(MQTT_HOST, MQTT_PORT, 60)
    except Exception as e:
        print("MQTT connect failed:", e)
        mqtt_client = None

init_backend()
init_mqtt()

# ----------------------------
# Routes
# ----------------------------
@app.get("/healthz")
async def healthz():
    return {
        "ok": True,
        "mode": mode_loaded,
        "backend_mode_env": BACKEND_MODE,
        "mqtt": bool(mqtt_client),
        "model_dir": str(MODEL_DIR),
        "data_dir": str(DATA_DIR),
    }

@app.get("/config")
async def config():
    return {
        "BACKEND_MODE": BACKEND_MODE,
        "IMG_SIZE": IMG_SIZE,
        "MEAN": MEAN,
        "STD": STD,
        "TOPK": TOPK,
        "MQTT_ENABLE": MQTT_ENABLE,
        "MQTT_BASE": MQTT_BASE,
    }

@app.post("/birds/predict")
async def birds_predict(request: Request):
    raw = await request.body()
    if not raw:
        return JSONResponse({"error": "no image bytes"}, status_code=400)

    device = request.headers.get("X-Device-Id", "unknown_cam")
    try:
        pil = Image.open(io.BytesIO(raw))
    except Exception:
        return JSONResponse({"error": "invalid image"}, status_code=400)

    # infer
    top = backend.predict_topk(pil, TOPK)

    # save image
    ts = time.time()
    eid = str(uuid.uuid4())
    img_name = f"{int(ts)}_{eid}.jpg"
    img_path = DATA_DIR / img_name
    try:
        pil.save(img_path, quality=90)
    except Exception:
        # if Pillow fails on some mode, convert to RGB
        pil.convert("RGB").save(img_path, quality=90)

    # persist to sqlite
    con = sqlite3.connect(DB_PATH); cur = con.cursor()
    cur.execute("INSERT INTO events(id, ts, device, mode, top_json, img_path) VALUES(?,?,?,?,?,?)",
                (eid, ts, device, mode_loaded, json.dumps(top), str(img_path)))
    con.commit(); con.close()

    # mqtt notify
    if mqtt_client:
        payload = {"device": device, "ts": ts, "mode": mode_loaded, "top": top, "img": img_name}
        try:
            mqtt_client.publish(f"{MQTT_BASE}/{device}/event", json.dumps(payload), retain=False)
        except Exception as e:
            print("mqtt publish failed:", e)

    return JSONResponse({"id": eid, "top": top, "saved": img_name})

# Simple listing endpoint (debug)
@app.get("/birds/recent")
async def birds_recent(limit: int = 20):
    con = sqlite3.connect(DB_PATH); cur = con.cursor()
    cur.execute("SELECT id, ts, device, mode, top_json, img_path FROM events ORDER BY ts DESC LIMIT ?", (limit,))
    rows = cur.fetchall(); con.close()
    out = []
    for r in rows:
        out.append({
            "id": r[0], "ts": r[1], "device": r[2], "mode": r[3],
            "top": json.loads(r[4]), "img": Path(r[5]).name
        })
    return out

▶️ Run it
cd bird-feeder-server
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Choose a backend via env:
# 1) Classifier (Path A)
export BF_BACKEND_MODE=classifier
# and place models/bird_classifier.onnx + labels.txt

# 2) Embedder (Path B)
# export BF_BACKEND_MODE=embedder
# and place models/resnet50_feats.onnx + centroids.json

# Optional MQTT
export BF_MQTT_ENABLE=true
export BF_MQTT_HOST=192.168.1.10
export BF_MQTT_USER=mqtt_user
export BF_MQTT_PASS=mqtt_pass

uvicorn server:app --host 0.0.0.0 --port 8000


Health check: GET http://<server_ip>:8000/healthz

Predict: POST http://<server_ip>:8000/birds/predict

Headers: X-Device-Id: feeder_cam_1

Body: raw JPEG bytes

Notes & tips

Keep preprocessing in sync with your training/export (IMG_SIZE, MEAN, STD).

For Path B centroids, build them like I showed earlier; you can start with just a few species and add more later.

To rate-limit notifications, do it in Home Assistant automations or add simple cooldown logic in this server.