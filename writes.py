"""Everything that changes the database. Each function runs in one transaction."""
from __future__ import annotations

from sqlalchemy import text


def get_or_create_financier(conn, name: str, ftype: str | None = None) -> int | None:
    name = (name or "").strip()
    if not name:
        return None
    row = conn.execute(text("SELECT financier_id FROM installments.financiers WHERE lower(name) = lower(:n)"),
                       {"n": name}).first()
    if row:
        return row[0]
    return conn.execute(text("INSERT INTO installments.financiers (name, short_name, financier_type) "
                             "VALUES (:n, :n, :t) RETURNING financier_id"), {"n": name, "t": ftype}).scalar_one()


def add_offer(eng, o: dict, status: str = "pending", entry_source: str = "web") -> int:
    """o: sector_id, item, merchant, financier, financier_type, cash_price, down_payment, upfront_fees,
    months, monthly_installment, source_name, source_url, notes, submitted_by"""
    with eng.begin() as conn:
        fid = get_or_create_financier(conn, o.get("financier"), o.get("financier_type"))
        return conn.execute(text("""
            INSERT INTO installments.offers (sector_id, sub_category, item, merchant, financier_id, data_type, cash_price,
                down_payment, upfront_fees, months, monthly_installment, notes, source_name, source_url,
                status, entry_source, submitted_by)
            VALUES (:sector_id, :sub, :item, :merchant, :fid, :dtype, :cash, :down, :fee, :months, :monthly,
                    :notes, :src, :url, :status, :es, :by)
            RETURNING offer_id"""), {
            "sector_id": int(o["sector_id"]), "sub": o.get("sub_category"), "item": o["item"].strip(),
            "merchant": (o.get("merchant") or "").strip() or None, "fid": fid,
            "dtype": "عرض من الموقع" if entry_source == "web" else "عرض حقيقي منشور",
            "cash": o.get("cash_price") or None, "down": o.get("down_payment") or 0, "fee": o.get("upfront_fees") or 0,
            "months": int(o["months"]), "monthly": float(o["monthly_installment"]), "notes": o.get("notes"),
            "src": o.get("source_name"), "url": o.get("source_url"), "status": status, "es": entry_source,
            "by": o.get("submitted_by")}).scalar_one()


def set_status(eng, ids: list[int], status: str) -> int:
    if not ids:
        return 0
    with eng.begin() as conn:
        return conn.execute(text("UPDATE installments.offers SET status = :s WHERE offer_id = ANY(:ids)"),
                            {"s": status, "ids": [int(i) for i in ids]}).rowcount


def update_offers(eng, changes: list[dict]) -> int:
    """changes: [{offer_id, cash_price, monthly_installment, months, is_active}]"""
    if not changes:
        return 0
    with eng.begin() as conn:
        conn.execute(text("""UPDATE installments.offers
                             SET cash_price = :cash, monthly_installment = :m, months = :n, is_active = :a
                             WHERE offer_id = :id"""),
                     [{"cash": None if c["cash_price"] in (None, 0) else float(c["cash_price"]),
                       "m": float(c["monthly_installment"]), "n": int(c["months"]),
                       "a": bool(c["is_active"]), "id": int(c["offer_id"])} for c in changes])
    return len(changes)


def update_plans(eng, changes: list[dict]) -> int:
    """changes: [{plan_id, flat_annual_rate, min_months, max_months, is_active}]"""
    if not changes:
        return 0
    with eng.begin() as conn:
        conn.execute(text("""UPDATE installments.calc_plans
                             SET flat_annual_rate = :r, min_months = :lo, max_months = :hi, is_active = :a
                             WHERE plan_id = :id"""),
                     [{"r": float(c["flat_annual_rate"]), "lo": int(c["min_months"]), "hi": int(c["max_months"]),
                       "a": bool(c["is_active"]), "id": int(c["plan_id"])} for c in changes])
    return len(changes)


def update_benchmarks(eng, changes: list[dict]) -> int:
    if not changes:
        return 0
    with eng.begin() as conn:
        conn.execute(text("UPDATE installments.benchmarks SET value = :v, updated_at = now() WHERE code = :c"),
                     [{"v": float(c["value"]), "c": c["code"]} for c in changes])
    return len(changes)
