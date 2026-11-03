import os
import re
from pathlib import Path
from io import BytesIO
import requests
from PIL import Image
from dotenv import load_dotenv

# ========== 加载环境配置 ==========
env_path = Path(__file__).parent / ".env"
load_dotenv(dotenv_path=env_path)

ARK_API_KEY = os.getenv("ARK_API_KEY")
LLM_MODEL_NAME = os.getenv("LLM_MODEL_NAME")
SEEDREAM_MODEL_NAME = os.getenv("SEEDREAM_MODEL_NAME")
BASE_URL = os.getenv("BASE_URL")

# 校验配置
if not ARK_API_KEY:
    raise RuntimeError("❌ 未读取到 ARK_API_KEY，请检查 .env 文件")
if not all([LLM_MODEL_NAME, SEEDREAM_MODEL_NAME, BASE_URL]):
    raise RuntimeError("❌ .env 里面模型名称或者BASE_URL缺失")

# 输出文件夹
OUTPUT_DIR = Path(__file__).parent / "output"
OUTPUT_DIR.mkdir(exist_ok=True)


def call_llm(text: str) -> str:
    """调用Seed大模型，分析文本，输出插画提示词方案"""
    headers = {
        "Authorization": f"Bearer {ARK_API_KEY}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": LLM_MODEL_NAME,
        "messages": [
            {
                "role": "system",
                "content": """你是一位顶级的小说插画艺术指导。你的任务不是机械地翻译文字，而是像一位真正的画师那样，去**理解**文字背后的心理状态、文化背景和情感意境，并据此制定一套**整体性**的视觉方案。
**核心工作原则：**
1. **意境优先，拒绝堆砌**：不要试图把段落里的每一个细节都画出来。先问自己：这段文字的核心情绪是什么？是“浪漫而痛苦的压抑”，还是“清冷而疏离的孤独”？整个画面的构图、色彩、光影，都必须服务于这个核心情绪。
2. **整体色彩心理映射**：色彩不是对景物的简单还原，而是对心理的总体性隐喻。如果人物内心是“热烈而隐忍”的，那么天空、大地、衣物、甚至阴影的颜色，都应该是这个心理基调的外化。例如，热烈的痛苦，可以是低明度的暗红与灰蓝的碰撞；宁静的疏离，可以是蒙着一层灰的青绿与米白。
3. **文化基因识别**：如果有把握，判断文本的文化底色。否则这一点请忽略。
比如用户有说明这是什么书，知道文段的背景，或者能读到文段两边更多的上下文。
   - 如果文本是**东方文学**（如含蓄、留白、物哀、禅意），风格应倾向于**东方绘画美学**（如中国水墨的“气韵生动”、日本浮世绘的平面装饰感），色彩内敛，注重意境与留白。
   - 如果文本是**西方文学**（如浓烈、直白、戏剧冲突、浪漫主义），风格应倾向于**西方油画传统**（如古典油画的明暗对照法Chiaroscuro、印象派的光色瞬间感），色彩饱满，注重体积与光影。
4. 不要有说明图片是AI生成的水印。不要随便加入人物。记住，你在画一幅画，而不是拍一张照片，你又不是监控，一幅画不可能那么复杂，一定是有主次的。
5. **去AI化的手绘质感**：画面必须具有“人”的痕迹。根据上述判断，选择【水粉/版画/厚涂油画/水彩】作为媒介，并强制要求“可见笔触（visible brushstrokes）”、“粗糙边缘（rough edges）”、“纸张或画布纹理（canvas texture）”。绝对禁止光滑、完美的塑料感。
输出严格遵守下面标记，只输出内容，不要多余闲聊：
*   **【构图线稿 prompt】**：`[Subject and Micro-Action], [Environment & Architecture], [Camera Angle & Composition], [Artistic Style & Rendering Medium], clean line art, monochrome`
*   **【上色质感 prompt】**：`[Lighting Dynamics & Atmosphere], [Overall Color Palette based on psychology], [Specific Medium Keywords e.g. gouache, impasto, woodblock print], visible brushstrokes, rough edges, canvas texture, masterpiece, best quality`
"""
            },
            {"role": "user", "content": text}
        ],
        "temperature": 0.7
    }
    resp = requests.post(
        f"{BASE_URL}/chat/completions",
        headers=headers,
        json=payload,
        proxies={"http": None, "https": None},
        timeout=180
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


def parse_plan(raw_text: str) -> dict:
    """【提示词不动，重写正则：兼容星号、空格、换行、有无反引号】"""
    result = {
        "sketch": "",
        "color": ""
    }
    # 匹配【构图线稿 prompt】，捕获后面` `内部内容；没有反引号也能捕获
    pat_sketch = re.compile(
        r"【构图线稿 prompt】\s*[:：]?\s*`?\s*(.*?)\s*`?(?=\*?\s*【|$)",
        re.S
    )
    # 匹配【上色质感 prompt】
    pat_color = re.compile(
        r"【上色质感 prompt】\s*[:：]?\s*`?\s*(.*?)\s*`?(?=\*?\s*【|$)",
        re.S
    )

    m_sketch = pat_sketch.search(raw_text)
    m_color = pat_color.search(raw_text)

    if m_sketch:
        result["sketch"] = m_sketch.group(1).strip().replace("\n","").replace("\r","")
    if m_color:
        result["color"] = m_color.group(1).strip().replace("\n","").replace("\r","")

    # DEBUG输出
    print(f"\nDEBUG sketch={repr(result['sketch'])}")
    print(f"DEBUG color={repr(result['color'])}")
    return result


def call_text2img(prompt: str, save_filename: str) -> str:
    """调用Seedream绘图，下载图片，保存到output目录"""
    headers = {
        "Authorization": f"Bearer {ARK_API_KEY}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": SEEDREAM_MODEL_NAME,
        "prompt": prompt,
        "size": "1024x1024"
    }
    resp = requests.post(
        f"{BASE_URL}/images/generations",
        headers=headers,
        json=payload,
        proxies={"http": None, "https": None},
        timeout=180
    )
    resp.raise_for_status()
    img_url = resp.json()["data"][0]["url"]
    # 下载图片
    r = requests.get(img_url, proxies={"http": None, "https": None}, timeout=180)
    r.raise_for_status()
    save_path = OUTPUT_DIR / save_filename
    img = Image.open(BytesIO(r.content))
    img.save(save_path)
    absolute_path = str(save_path.resolve())
    return absolute_path


def main():
    print("======= 阅读器配套AI插画生成工具 ======")
    print("输入小说段落，自动生成配套插画，图片保存在 ./output 目录\n")
    user_text = input("请粘贴小说段落：\n")
    print("\n>>> 正在分析文本，生成插画方案...")
    plan_raw = call_llm(user_text)
    print("\n=== 模型原始输出 ===")
    print(plan_raw)
    plan = parse_plan(plan_raw)
    if not plan["sketch"] or not plan["color"]:
        print("\n❌ 解析失败！模型输出格式不对！")
        return
    print("\n>>> 开始绘制草图线稿...")
    sketch_path = call_text2img(plan["sketch"], "sketch.png")
    print(f"✅ 草图保存成功：{sketch_path}")
    print("\n>>> 开始绘制上色成品图...")
    final_path = call_text2img(plan["color"], "final.png")
    print(f"✅ 成品图保存成功：{final_path}")
    print("\n🎉 全部完成！")


if __name__ == "__main__":
    try:
        main()
    except requests.HTTPError as e:
        print(f"\n❌ API请求错误: {e.response.status_code}, 响应内容: {e.response.text}")
    except requests.exceptions.ReadTimeout:
        print("\n❌ 请求超时！优先切换手机热点，关闭代理/VPN再试！")
    except Exception as e:
        print(f"\n❌ 程序异常：{type(e).__name__}: {e}")
