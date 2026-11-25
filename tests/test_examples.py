"""离线自检：示例工作流的结构、模型文件名、音频参数与文档约定一致。

不需要 ComfyUI 或模型，纯标准库，CI 里会跑：

  python -m unittest discover -s tests -v
"""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "examples"

REQUIRED_NODES = {
    "MiniMaxMusic3TextEncode",
    "EmptyMiniMaxMusic3LatentAudio",
    "UNETLoader",
    "CLIPLoader",
    "VAELoader",
    "KSampler",
    "VAEDecodeAudioTiled",
    "SaveAudioAdvanced",
}

MODEL_ENUMS = {
    "UNETLoader": (
        "unet_name",
        {"minimax_music3_dit_fp16.safetensors", "minimax_music3_dit_int8_convrot.safetensors"},
    ),
    "CLIPLoader": (
        "clip_name",
        {"minimax_music3_text_encoder_pruned_int8_convrot.safetensors"},
    ),
    "VAELoader": ("vae_name", {"minimax_music3_dav.safetensors"}),
}

SECTION_TAGS = ("[Intro]", "[Verse", "[Chorus]", "[Bridge]", "[Outro]")


def workflows():
    return sorted(EXAMPLES.glob("*/*.json"))


def node_refs(workflow):
    def walk(obj):
        if isinstance(obj, dict):
            for value in obj.values():
                yield from walk(value)
        elif isinstance(obj, list):
            if len(obj) == 2 and isinstance(obj[0], str) and isinstance(obj[1], int):
                yield obj[0]
            for value in obj:
                yield from walk(value)

    for node in workflow.values():
        yield from walk(node.get("inputs", {}))


class ExampleWorkflowTests(unittest.TestCase):
    def test_example_workflows_exist(self):
        self.assertGreaterEqual(len(workflows()), 3)

    def test_node_links_point_to_existing_nodes(self):
        for path in workflows():
            workflow = json.loads(path.read_text(encoding="utf-8"))
            self.assertIsInstance(workflow, dict)
            self.assertTrue(workflow, f"{path.name} 为空")
            for ref in node_refs(workflow):
                self.assertIn(ref, workflow, f"{path.relative_to(ROOT)} 引用了不存在的节点 {ref}")

    def test_required_nodes_present(self):
        for path in workflows():
            workflow = json.loads(path.read_text(encoding="utf-8"))
            types = {node["class_type"] for node in workflow.values()}
            missing = REQUIRED_NODES - types
            self.assertFalse(missing, f"{path.relative_to(ROOT)} 缺节点: {missing}")

    def test_model_filenames_follow_docs(self):
        for path in workflows():
            workflow = json.loads(path.read_text(encoding="utf-8"))
            for node in workflow.values():
                mapping = MODEL_ENUMS.get(node["class_type"])
                if mapping is None:
                    continue
                field, allowed = mapping
                name = node["inputs"][field]
                self.assertIn(name, allowed, f"{path.relative_to(ROOT)}: 模型 {name} 不在文档列出的清单里")

    def test_save_audio_uses_flat_quality_key(self):
        # SaveAudioAdvanced 的动态下拉参数在 API 里是平铺键（format + format.quality），
        # 写成嵌套对象会报 Required input is missing: quality。
        for path in workflows():
            workflow = json.loads(path.read_text(encoding="utf-8"))
            save = [n for n in workflow.values() if n["class_type"] == "SaveAudioAdvanced"]
            self.assertTrue(save, f"{path.relative_to(ROOT)} 缺 SaveAudioAdvanced")
            inputs = save[0]["inputs"]
            self.assertEqual(inputs.get("format"), "mp3")
            self.assertEqual(inputs.get("format.quality"), "V0")

    def test_duration_within_model_limit(self):
        for path in workflows():
            workflow = json.loads(path.read_text(encoding="utf-8"))
            encode = [n for n in workflow.values() if n["class_type"] == "MiniMaxMusic3TextEncode"]
            self.assertTrue(encode, f"{path.relative_to(ROOT)} 缺 MiniMaxMusic3TextEncode")
            duration = float(encode[0]["inputs"]["max_duration"])
            self.assertGreaterEqual(duration, 20, f"{path.relative_to(ROOT)}: max_duration 太短")
            self.assertLessEqual(duration, 300, f"{path.relative_to(ROOT)}: max_duration 超过模型上限")

    def test_lyrics_and_caption_are_usable(self):
        for path in workflows():
            workflow = json.loads(path.read_text(encoding="utf-8"))
            encode = [n for n in workflow.values() if n["class_type"] == "MiniMaxMusic3TextEncode"][0]
            lyrics = encode["inputs"]["lyrics"]
            caption = encode["inputs"]["caption"]
            self.assertTrue(any(tag in lyrics for tag in SECTION_TAGS), f"{path.relative_to(ROOT)} 歌词没有段落标签")
            self.assertGreaterEqual(len(caption), 80, f"{path.relative_to(ROOT)} caption 太短")

    def test_each_example_has_required_files(self):
        for folder in sorted(p for p in EXAMPLES.iterdir() if p.is_dir()):
            for name in ("歌词.txt", "caption.txt", "prompt.json", "说明.md"):
                self.assertTrue((folder / name).exists(), f"{folder.name} 缺 {name}")


if __name__ == "__main__":
    unittest.main()
