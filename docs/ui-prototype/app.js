/* ============================================================
   阅读器界面原型 — 交互
   - 内置壁纸 / 导入自定义图片
   - 模糊、压暗、面板通透度
   - 书架 / 阅读页、玻璃 / 纸感 两套风格
   状态保存在 localStorage，刷新后沿用。
   ============================================================ */

const PRESETS = [
  {
    id: "aurora",
    name: "极光夜空",
    tone: "dark",
    css: `radial-gradient(80% 60% at 12% 8%, #1b3a6b 0%, transparent 60%),
          radial-gradient(66% 52% at 82% 18%, #4b2a6b 0%, transparent 58%),
          radial-gradient(70% 60% at 55% 96%, #0f5f6b 0%, transparent 62%),
          linear-gradient(160deg, #070b14, #101a2b)`,
  },
  {
    id: "mist",
    name: "晨雾山间",
    tone: "light",
    css: `radial-gradient(60% 42% at 28% 18%, #dfe8f2 0%, transparent 70%),
          radial-gradient(52% 40% at 76% 34%, #f3e9e2 0%, transparent 70%),
          linear-gradient(170deg, #c9d6e4, #eef2f7)`,
  },
  {
    id: "ink",
    name: "墨色书斋",
    tone: "dark",
    css: `radial-gradient(72% 52% at 50% -6%, #232a36 0%, transparent 70%),
          repeating-linear-gradient(90deg, rgba(255,255,255,0.026) 0 2px, transparent 2px 7px),
          linear-gradient(180deg, #0b0d11, #191d24)`,
  },
  {
    id: "sun",
    name: "暖阳琥珀",
    tone: "light",
    css: `radial-gradient(62% 46% at 18% 12%, #ffd9a8 0%, transparent 66%),
          radial-gradient(56% 44% at 82% 26%, #ffb9a0 0%, transparent 62%),
          linear-gradient(166deg, #f7e6cf, #f2d6bd)`,
  },
  {
    id: "bamboo",
    name: "青竹雨林",
    tone: "dark",
    css: `radial-gradient(62% 50% at 18% 8%, #1f4d3a 0%, transparent 62%),
          radial-gradient(54% 42% at 86% 78%, #2f6b52 0%, transparent 64%),
          linear-gradient(160deg, #091410, #123326)`,
  },
  {
    id: "ocean",
    name: "海盐蓝调",
    tone: "dark",
    css: `radial-gradient(70% 52% at 22% 16%, #1d4560 0%, transparent 62%),
          radial-gradient(60% 46% at 82% 72%, #0e6272 0%, transparent 66%),
          linear-gradient(170deg, #08131b, #0e2b3a)`,
  },
  {
    id: "snow",
    name: "雪原清晨",
    tone: "light",
    css: `radial-gradient(60% 46% at 28% 14%, #ffffff 0%, transparent 72%),
          radial-gradient(52% 42% at 76% 62%, #e6eef7 0%, transparent 70%),
          linear-gradient(166deg, #eef3f9, #dde7f2)`,
  },
  {
    id: "paperwall",
    name: "旧纸纹理",
    tone: "light",
    css: `radial-gradient(72% 52% at 18% 8%, #f7efdf 0%, transparent 72%),
          linear-gradient(162deg, #efe6d4, #e3d7c1)`,
  },
];

const STORAGE_KEY = "reader-ui-proto-v1";

const state = {
  screen: "library",
  variant: "glass",
  wallpaper: "aurora",
  custom: null,
  customTone: "dark",
  blur: 6,
  dim: 24,
  panel: 55,
};

const root = document.documentElement;
const body = document.body;
const wallImage = document.getElementById("wallImage");
const wallGrid = document.getElementById("wallGrid");
const drawer = document.getElementById("drawer");
const scrim = document.getElementById("scrim");

/* ---------------- 状态 ---------------- */

function load() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    Object.assign(state, saved);
  } catch (_) {
    /* 忽略损坏的存档 */
  }
}

function save() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch (_) {
    /* 图片太大导致超限时，退化为不保存图片 */
    const { custom, ...rest } = state;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(rest));
    } catch (_) {}
  }
}

function presetById(id) {
  return PRESETS.find((p) => p.id === id) || PRESETS[0];
}

function apply() {
  body.dataset.variant = state.variant;
  body.dataset.screen = state.screen;

  root.style.setProperty("--wall-blur", `${state.blur}px`);
  root.style.setProperty("--wall-dim", String(state.dim / 100));
  root.style.setProperty("--panel-alpha", String(state.panel / 100));

  if (state.custom) {
    wallImage.style.backgroundImage = `url("${state.custom}")`;
    body.dataset.tone = state.customTone;
  } else {
    const preset = presetById(state.wallpaper);
    wallImage.style.backgroundImage = preset.css;
    body.dataset.tone = preset.tone;
  }

  syncControls();
}

function syncControls() {
  document.querySelectorAll("#screenSeg .seg__btn").forEach((btn) => {
    btn.classList.toggle("is-active", btn.dataset.screen === state.screen);
  });
  document.querySelectorAll("#styleGrid .style-card").forEach((card) => {
    card.classList.toggle("is-active", card.dataset.variant === state.variant);
  });
  document.querySelectorAll(".screen").forEach((section) => {
    section.hidden = section.dataset.screen !== state.screen;
  });
  wallGrid.querySelectorAll(".wall-item").forEach((item) => {
    const active =
      !state.custom && item.dataset.id === state.wallpaper;
    item.classList.toggle("is-active", active);
  });
  document.getElementById("blurRange").value = state.blur;
  document.getElementById("dimRange").value = state.dim;
  document.getElementById("panelRange").value = state.panel;
  document.getElementById("blurOut").textContent = state.blur;
  document.getElementById("dimOut").textContent = state.dim;
  document.getElementById("panelOut").textContent = state.panel;
}

/* ---------------- 壁纸面板 ---------------- */

function buildWallGrid() {
  wallGrid.innerHTML = "";
  PRESETS.forEach((preset) => {
    const btn = document.createElement("button");
    btn.className = "wall-item";
    btn.dataset.id = preset.id;
    btn.title = preset.name;
    btn.innerHTML = `
      <span class="wall-item__swatch" style="background-image:${preset.css.replace(/\n\s*/g, " ")}"></span>
      <span class="wall-item__name">${preset.name}</span>`;
    btn.addEventListener("click", () => {
      state.wallpaper = preset.id;
      state.custom = null;
      apply();
      save();
    });
    wallGrid.appendChild(btn);
  });
}

/* ---------------- 自定义图片 ---------------- */

function averageTone(image) {
  const size = 48;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(image, 0, 0, size, size);
  const { data } = ctx.getImageData(0, 0, size, size);
  let sum = 0;
  for (let i = 0; i < data.length; i += 4) {
    sum += 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
  }
  const luminance = sum / (data.length / 4) / 255;
  return luminance > 0.55 ? "light" : "dark";
}

function downscaleImage(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = reject;
    reader.onload = () => {
      const img = new Image();
      img.onerror = reject;
      img.onload = () => {
        const max = 1600;
        const scale = Math.min(1, max / Math.max(img.width, img.height));
        const canvas = document.createElement("canvas");
        canvas.width = Math.round(img.width * scale);
        canvas.height = Math.round(img.height * scale);
        canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
        resolve({
          dataUrl: canvas.toDataURL("image/jpeg", 0.85),
          tone: averageTone(img),
        });
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

document.getElementById("wallFile").addEventListener("change", async (event) => {
  const file = event.target.files && event.target.files[0];
  if (!file) return;
  try {
    const { dataUrl, tone } = await downscaleImage(file);
    state.custom = dataUrl;
    state.customTone = tone;
    apply();
    save();
  } catch (_) {
    alert("这张图片读取失败，换一张试试？");
  } finally {
    event.target.value = "";
  }
});

/* ---------------- 抽屉 ---------------- */

function openDrawer() {
  drawer.hidden = false;
  scrim.hidden = false;
}

function closeDrawer() {
  drawer.hidden = true;
  scrim.hidden = true;
}

document.getElementById("openDrawer").addEventListener("click", openDrawer);
document.getElementById("openDrawer2").addEventListener("click", openDrawer);
document.getElementById("openDrawer3").addEventListener("click", openDrawer);
document.getElementById("closeDrawer").addEventListener("click", closeDrawer);
scrim.addEventListener("click", closeDrawer);
window.addEventListener("keydown", (e) => {
  if (e.key === "Escape") closeDrawer();
});

/* ---------------- 顶部分段控件 ---------------- */

document.querySelectorAll("#screenSeg .seg__btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    state.screen = btn.dataset.screen;
    apply();
    save();
  });
});

document.querySelectorAll("#styleGrid .style-card").forEach((card) => {
  card.addEventListener("click", () => {
    state.variant = card.dataset.variant;
    apply();
    save();
  });
});

/* ---------------- 滑杆 ---------------- */

[
  ["blurRange", "blur", "blurOut"],
  ["dimRange", "dim", "dimOut"],
  ["panelRange", "panel", "panelOut"],
].forEach(([rangeId, key, outId]) => {
  const range = document.getElementById(rangeId);
  range.addEventListener("input", () => {
    state[key] = Number(range.value);
    document.getElementById(outId).textContent = range.value;
    root.style.setProperty(
      key === "blur" ? "--wall-blur" : key === "dim" ? "--wall-dim" : "--panel-alpha",
      key === "blur" ? `${state.blur}px` : String(state[key] / 100)
    );
    save();
  });
});

/* ---------------- 启动 ---------------- */

load();

// 便于分享/截图：?screen=reader&variant=paper&wallpaper=ink&drawer=1
const params = new URLSearchParams(location.search);
["screen", "variant", "wallpaper"].forEach((key) => {
  if (params.has(key)) state[key] = params.get(key);
});

buildWallGrid();
apply();

// ?clean=1 隐藏原型工具条，方便截图或给别人看成品效果
body.dataset.clean = params.get("clean") === "1" ? "1" : "0";

if (params.get("drawer") === "1") openDrawer();
