import shutil
import subprocess
from pathlib import Path


def main():
    # 설치 경로 읽기
    l4d2_dir = Path(Path("L4D2_설치경로.ini").read_text(encoding="utf-8").strip())
    assert (l4d2_dir / "left4dead2.exe").exists(), "잘못된 L4D2 설치 경로입니다."

    sourcemod_scripting_dir = l4d2_dir / "left4dead2/addons/sourcemod/scripting"
    sourcemod_compiled_dir = l4d2_dir / "left4dead2/addons/sourcemod/scripting/compiled"
    sourcemod_plugins_dir = l4d2_dir / "left4dead2/addons/sourcemod/plugins"

    # 리포지토리의 Plugin 디렉토리에서 .sp 파일 목록 수집 후 컴파일
    repo_plugin_dir = Path(__file__).parent / "Plugin"
    compile_queue = sorted([i.name for i in repo_plugin_dir.rglob("scripting/*.sp")])
    subprocess.run(
        f"compile.exe {' '.join(compile_queue)}",
        cwd=sourcemod_scripting_dir,
        shell=True,
        check=True,
    )

    # 컴파일된 플러그인 이동
    shutil.copytree(
        sourcemod_compiled_dir,
        sourcemod_plugins_dir,
        dirs_exist_ok=True,
    )
    shutil.rmtree(sourcemod_compiled_dir)

    print("컴파일 및 적용 완료.")


if __name__ == "__main__":
    main()
