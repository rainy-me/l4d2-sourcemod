import os
import shutil
from pathlib import Path


def main():
    # 설치 경로 읽기
    l4d2_dir = Path(Path("L4D2_설치경로.ini").read_text(encoding="utf-8").strip())
    assert (l4d2_dir / "left4dead2.exe").exists(), "잘못된 L4D2 설치 경로입니다."

    # addons 폴더 내 모든 항목 삭제 (workshop, readme.txt 제외)
    l4d2_addons_dir = l4d2_dir / "left4dead2/addons"
    for i in l4d2_addons_dir.iterdir():
        if i.name != "workshop" and i.name != "readme.txt":
            if i.is_dir():
                shutil.rmtree(i)
            elif i.is_file():
                os.remove(i)
            else:
                raise ValueError("알 수 없는 파일 형식입니다.")

    # cfg 폴더 내 sourcemod 폴더 삭제
    shutil.rmtree(l4d2_dir / "left4dead2/cfg/sourcemod", ignore_errors=True)

    print(f"'{l4d2_dir}'에서 삭제 완료.")


if __name__ == "__main__":
    main()
