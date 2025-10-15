import shutil
from pathlib import Path


def main():
    # 설치 경로 읽기
    l4d2_dir = Path(Path("L4D2_설치경로.ini").read_text(encoding="utf-8").strip())
    assert (l4d2_dir / "left4dead2.exe").exists(), "잘못된 L4D2 설치 경로입니다."

    l4d2_api_dir = l4d2_dir / "left4dead2"
    l4d2_plugin_dir = l4d2_dir / "left4dead2/addons/sourcemod"

    src_api_dir = Path(__file__).parent / "API"
    src_plugin_dir = Path(__file__).parent / "Plugin"

    # API 설치
    src_api_items = sorted([i for i in src_api_dir.iterdir() if i.is_dir()])
    for item in src_api_items:
        shutil.copytree(item, l4d2_api_dir, dirs_exist_ok=True)

    # Plugin 설치
    src_plugin_items = sorted([i for i in src_plugin_dir.iterdir() if i.is_dir()])
    for item in src_plugin_items:
        shutil.copytree(item, l4d2_plugin_dir, dirs_exist_ok=True)

    print(f"'{l4d2_dir}'에서 설치 완료.")


if __name__ == "__main__":
    main()
