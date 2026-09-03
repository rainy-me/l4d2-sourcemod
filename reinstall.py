import re
import shutil
import subprocess
import winreg
from collections.abc import Iterator
from pathlib import Path

REPO = Path(__file__).parent
STEAM_KEYS = (
    (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam"),
    (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam"),
)


def is_l4d2_dir(path: Path) -> bool:
    return (path / "left4dead2.exe").exists()


def steam_libraries() -> Iterator[Path]:
    """Steam 레지스트리 + libraryfolders.vdf 에서 라이브러리 폴더 목록 수집."""
    for hive, key in STEAM_KEYS:
        try:
            with winreg.OpenKey(hive, key) as k:
                root = Path(winreg.QueryValueEx(k, "InstallPath")[0])
        except OSError:
            continue
        yield root
        vdf = root / "steamapps/libraryfolders.vdf"
        if vdf.exists():
            for p in re.findall(r'"path"\s*"([^"]+)"', vdf.read_text(encoding="utf-8")):
                yield Path(p.replace("\\\\", "\\"))


def find_l4d2_dir() -> Path | None:
    for lib in dict.fromkeys(steam_libraries()):
        game = lib / "steamapps/common/Left 4 Dead 2"
        if is_l4d2_dir(game):
            return game
    return None


def ask_l4d2_dir() -> Path:
    print("Left 4 Dead 2 설치 폴더를 자동으로 찾지 못했습니다.")
    while True:
        raw = input("left4dead2.exe가 있는 폴더 경로 (Enter 시 취소): ").strip('" ')
        if not raw:
            raise SystemExit(1)
        path = Path(raw)
        if is_l4d2_dir(path):
            return path
        print("  그 폴더에 left4dead2.exe가 없습니다.")


def uninstall(game_dir: Path) -> None:
    """addons 폴더 내 모든 항목 삭제 (workshop, readme.txt 제외) 및 cfg/sourcemod 삭제."""
    for item in (game_dir / "addons").iterdir():
        if item.name in ("workshop", "readme.txt"):
            continue
        if item.is_dir():
            shutil.rmtree(item)
        else:
            item.unlink()
    shutil.rmtree(game_dir / "cfg/sourcemod", ignore_errors=True)
    print("삭제 완료.")


def install(game_dir: Path) -> None:
    for src, dst in (
        (REPO / "API", game_dir),
        (REPO / "Plugin", game_dir / "addons/sourcemod"),
        (REPO / "Plugin_metamod", game_dir),
    ):
        for item in sorted(i for i in src.iterdir() if i.is_dir()):
            shutil.copytree(item, dst, dirs_exist_ok=True)
    print("설치 완료.")


def compile_plugins(game_dir: Path) -> None:
    """리포지토리의 Plugin 디렉토리에 있는 .sp 파일을 컴파일해 plugins 폴더로 이동."""
    scripting_dir = game_dir / "addons/sourcemod/scripting"
    compiled_dir = scripting_dir / "compiled"
    plugins_dir = game_dir / "addons/sourcemod/plugins"

    queue = sorted(i.name for i in (REPO / "Plugin").rglob("scripting/*.sp"))
    subprocess.run([scripting_dir / "compile.exe", *queue], cwd=scripting_dir, check=True)

    shutil.copytree(compiled_dir, plugins_dir, dirs_exist_ok=True)
    shutil.rmtree(compiled_dir)
    print("컴파일 및 적용 완료.")


def main() -> None:
    l4d2_dir = find_l4d2_dir() or ask_l4d2_dir()
    print(f"게임 경로: {l4d2_dir}")
    game_dir = l4d2_dir / "left4dead2"
    uninstall(game_dir)
    install(game_dir)
    compile_plugins(game_dir)


if __name__ == "__main__":
    main()
