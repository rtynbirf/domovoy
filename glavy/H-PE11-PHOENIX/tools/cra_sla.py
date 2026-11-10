#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CRA-SLA контур роя H-PE11-PHOENIX (Э-2.3, волна ×5 «Реестр-добой»).

EU Cyber Resilience Act: reporting obligations с 11.09.2026 — активно
эксплуатируемые уязвимости и тяжёлые инциденты репортятся в ENISA за 24 часа.
У роя есть SEALS.jsonl (append-only хеш-цепь пломб) — CRA превращаем в метрику,
а не в бюрократию: уязвимостное событие старше 24 ч без пломбы-реакции = 🔴.

Вход:
  --events PATH  журнал событий (по умолчанию reports/cra-events.jsonl);
                 файла может не быть — это «событий нет», не ошибка;
                 событие = {"date": "YYYY-MM-DD", "source": "...", "summary": "..."}
  --seals PATH   цепь пломб (по умолчанию SEALS.jsonl в корне репо)

Правило (дневная гранулярность дат): время суток события неизвестно, поэтому
инцидентом честно считается только событие, которому 24 ч уже не могло хватить:
дата события <= сегодня-2 (UTC). Событие младше — ⏳ «в сроке», без тревоги.
Пломба-реакция — запись SEALS.jsonl с датой >= даты события; дата пломбы
берётся толерантно из первого известного поля даты записи (date/ts/sealed_at/
timestamp/time) — формат летописи не перекраиваем, поле sbom_ctx добавляется
аддитивно (см. CRA-SBOM-CONTOUR.md).

Выходы: таблица событий + вердикт 🟢/🔴; exit 0 при 🟢, exit 1 при 🔴 (гейт:
инцидент или дата события не читается — fail-closed), exit 2 при ошибке данных
(битая JSON-строка журнала). Только stdlib.

Самотест: python3 tools/cra_sla.py --selftest — синтетические зелёный и красный
сценарии в tempfile, прогон обоих через CLI (зелёный rc=0, красный rc=1).
"""
import argparse
import json
import re
import subprocess
import sys
import tempfile
from datetime import date, timedelta
from pathlib import Path

DATE_PREFIX = re.compile(r"^\d{4}-\d{2}-\d{2}")
SEAL_DATE_KEYS = ("date", "ts", "sealed_at", "timestamp", "time")


def load_jsonl(path: Path) -> list:
    """Читает JSONL: пустые строки и '#' -комментарии пропускаются.

    Отсутствующий файл -> пустой список (событий нет / пломб нет). Битая JSON-
    строка -> ошибка данных (exit 2 у вызывающего), молчать о ней — нечестно.
    """
    if not path.exists():
        return []
    records = []
    for num, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        text = raw.strip()
        if not text or text.startswith("#"):
            continue
        try:
            rec = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError("%s строка %d не JSON (%s)" % (path, num, exc))
        if not isinstance(rec, dict):
            raise ValueError("%s строка %d — не объект" % (path, num))
        records.append(rec)
    return records


def parse_date(value: str):
    """'YYYY-MM-DD...' -> date; без даты — None (не выдумываем дату)."""
    if not isinstance(value, str):
        return None
    match = DATE_PREFIX.match(value.strip())
    if not match:
        return None
    try:
        return date.fromisoformat(match.group(0))
    except ValueError:
        return None


def event_date_of(rec: dict):
    return parse_date(rec.get("date", ""))


def seal_date_of(rec: dict):
    """Дата пломбы: толерантно к формату летописи (первое известное поле даты)."""
    for key in SEAL_DATE_KEYS:
        parsed = parse_date(rec.get(key, ""))
        if parsed is not None:
            return parsed
    return None


def evaluate(events: list, seals: list, today: date):
    """(таблица-строки, инциденты). Инцидент: дата <= сегодня-2 и нет пломбы
    с датой >= даты события."""
    seal_dates = [d for d in (seal_date_of(r) for r in seals) if d is not None]
    unreadable_seals = sum(1 for r in seals if seal_date_of(r) is None)
    breach_edge = today - timedelta(days=2)  # старше этого — 24 ч точно вышли
    rows, incidents = [], []
    for ev in sorted(events, key=lambda r: str(r.get("date", ""))):
        edate = event_date_of(ev)
        if edate is None:
            rows.append((str(ev.get("date", "?")), str(ev.get("source", "?")),
                         str(ev.get("summary", "?")), "⚠️ дата не читается — починить журнал"))
            incidents.append(ev)
            continue
        reaction = next((d for d in seal_dates if d >= edate), None)
        if edate <= breach_edge and reaction is None:
            status = "🔴 инцидент: 24 ч вышли, пломбы-реакции нет"
            incidents.append(ev)
        elif reaction is not None:
            status = "🟢 пломба-реакция %s" % reaction.isoformat()
        else:
            status = "⏳ в сроке (24 ч не вышли), пломбы пока нет"
        rows.append((edate.isoformat(), str(ev.get("source", "?")),
                     str(ev.get("summary", "?")), status))
    return rows, incidents, unreadable_seals


def render(rows: list, n_events: int, n_seals: int, unreadable_seals: int) -> str:
    out = ["CRA-SLA · событий: %d · записей SEALS: %d" % (n_events, n_seals)]
    if unreadable_seals:
        out.append("внимание: записей SEALS без читаемой даты: %d (в реакции не участвуют)"
                   % unreadable_seals)
    out.append("")
    out.append("дата       | источник              | суть                          | реакция")
    out.append("-----------+-----------------------+-------------------------------+--------")
    for edate, source, summary, status in rows:
        out.append("%-10s | %-21s | %-29s | %s" % (edate[:10], source[:21], summary[:29], status))
    return "\n".join(out)


def run(events_path: Path, seals_path: Path) -> int:
    try:
        events = load_jsonl(events_path)
        seals = load_jsonl(seals_path)
    except ValueError as exc:
        print("ОТКАЗ: %s" % exc)
        return 2
    if not events_path.exists():
        print("журнал %s отсутствует — событий нет (появится с первым инцидентом)"
              % events_path)
    rows, incidents, unreadable = evaluate(events, seals, date.today())
    print(render(rows, len(events), len(seals), unreadable))
    print("")
    if incidents:
        print("ВЕРДИКТ: 🔴 CRA-SLA инцидент(ы): %d — событие старше 24 ч без пломбы-реакции "
              "в SEALS.jsonl" % len(incidents))
        print("лечение: отреагировать и запломбировать (запись SEALS.jsonl, при желании "
              "с полем sbom_ctx — см. CRA-SBOM-CONTOUR.md)")
        return 1
    print("ВЕРДИКТ: 🟢 CRA-SLA чист: инцидентов «старше 24 ч без пломбы» нет")
    return 0


SELF = Path(__file__).resolve()


def selftest() -> int:
    """Синтетика в tempfile: зелёный сценарий (rc=0) и красный (rc=1) через CLI."""
    today = date.today()
    old_breach = (today - timedelta(days=5)).isoformat()
    fresh = today.isoformat()
    edge = (today - timedelta(days=2)).isoformat()
    with tempfile.TemporaryDirectory(prefix="cra-sla-selftest-") as tmp:
        root = Path(tmp)

        # Зелёный: старое событие закрыто пломбой ПОЗЖЕ события; свежее — в сроке.
        green = root / "green-events.jsonl"
        green.write_text(
            json.dumps({"date": edge, "source": "vulnerability-alert",
                        "summary": "синтетика: событие закрыто пломбой"}, ensure_ascii=False) + "\n" +
            json.dumps({"date": fresh, "source": "osv-sverka",
                        "summary": "синтетика: свежее событие, 24 ч не вышли"}, ensure_ascii=False) + "\n",
            encoding="utf-8")
        green_seals = root / "green-SEALS.jsonl"
        green_seals.write_text(
            json.dumps({"ts": (today - timedelta(days=1)).isoformat() + "T12:00:00Z",
                        "note": "пломба-реакция"}, ensure_ascii=False) + "\n",
            encoding="utf-8")

        # Красный: событие старше 24 ч без реакции; пломба ДО события не считается.
        red = root / "red-events.jsonl"
        red.write_text(
            json.dumps({"date": old_breach, "source": "vulnerability-alert",
                        "summary": "синтетика: инцидент без реакции"}, ensure_ascii=False) + "\n" +
            json.dumps({"date": fresh, "source": "vulnerability-alert",
                        "summary": "синтетика: свежее, в сроке"}, ensure_ascii=False) + "\n",
            encoding="utf-8")
        red_seals = root / "red-SEALS.jsonl"
        red_seals.write_text(
            json.dumps({"ts": (today - timedelta(days=6)).isoformat() + "T09:00:00Z",
                        "note": "пломба ДО события — реакцией не является"}, ensure_ascii=False) + "\n",
            encoding="utf-8")

        for path, seals, want_rc, label in ((green, green_seals, 0, "зелёный"),
                                            (red, red_seals, 1, "красный")):
            proc = subprocess.run(
                [sys.executable, str(SELF), "--events", str(path), "--seals", str(seals)],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            if proc.returncode != want_rc:
                print("САМОТЕСТ: сценарий %s дал rc=%d (ожидался %d)" % (label, proc.returncode, want_rc))
                print(proc.stdout)
                return 1
            print("сценарий %s: rc=%d как ожидалось" % (label, proc.returncode))
        # Прямая проверка evaluate: в зелёном инцидентов нет, в красном — ровно 1
        # (свежее событие красного сценария — ещё в сроке, пломба ДО события не реакция).
        _, green_inc, _ = evaluate(load_jsonl(green), load_jsonl(green_seals), today)
        _, red_inc, _ = evaluate(load_jsonl(red), load_jsonl(red_seals), today)
        if green_inc or len(red_inc) != 1:
            print("САМОТЕСТ: логика инцидентов разошлась с ожиданием (%d/%d)"
                  % (len(green_inc), len(red_inc)))
            return 1
    print("SELFTEST OK")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="CRA 24-ч SLA: уязвимостное событие старше 24 ч без пломбы-реакции = 🔴")
    parser.add_argument("--events", default="reports/cra-events.jsonl",
                        help="журнал событий (по умолчанию reports/cra-events.jsonl)")
    parser.add_argument("--seals", default="SEALS.jsonl",
                        help="цепь пломб (по умолчанию SEALS.jsonl)")
    parser.add_argument("--selftest", action="store_true",
                        help="самотест: зелёный и красный сценарии в tempfile")
    args = parser.parse_args()

    if args.selftest:
        return selftest()
    return run(Path(args.events), Path(args.seals))


if __name__ == "__main__":
    sys.exit(main())
