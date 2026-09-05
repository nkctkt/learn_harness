# EXERCISE: Phase 1 静的ゲートの検出確認。各行がどの層(Ruff / basedpyright)で止まるかを見る。
import os
import subprocess


def run(cmd: str) -> int:
    return subprocess.call(cmd, shell=True)  # (1) shell=True → Ruff S602(bandit 相当)


def parse_port(raw: str) -> int:
    port: int = raw  # (2) 型エラー → basedpyright。Ruff は通す
    return port


def risky() -> None:
    try:
        open("/nonexistent").read()  # (3) close 漏れ → Ruff SIM115
    except:  # (4) bare except → Ruff E722
        pass


def silenced(x) -> str:  # (5) 型注釈なし引数 → basedpyright strict
    return x.upper()  # type: ignore  # (6) 理由なし ignore → Ruff PGH003
