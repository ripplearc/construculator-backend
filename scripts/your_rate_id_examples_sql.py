#!/usr/bin/env python3
"""Keeps the examples in supabase/tests/database/your_rate_id_test.sql equal to
the app's test/libraries/powersync/units/models/your_rate_id_examples.json.

The JSON file in the app repository is the one source. Run

    scripts/your_rate_id_examples_sql.py --write <path to the JSON file>

after changing it, and

    scripts/your_rate_id_examples_sql.py --check <path to the JSON file>

to fail when the SQL list differs (exit code 1).
"""
import json
import pathlib
import sys

SQL = pathlib.Path(__file__).resolve().parent.parent / "supabase/tests/database/your_rate_id_test.sql"
BEGIN = "-- BEGIN GENERATED EXAMPLES (scripts/your_rate_id_examples_sql.py)\n"
END = "-- END GENERATED EXAMPLES\n"


def literal(value):
    if value is None:
        return "NULL"
    if not any(ord(c) > 126 or c in "\t\n" for c in value):
        return "'" + value.replace("'", "''") + "'"
    out = "U&'"
    for c in value:
        if c == "'":
            out += "''"
        elif c == "\\":
            out += "\\\\"
        elif ord(c) > 126 or c in "\t\n":
            out += "\\%04x" % ord(c) if ord(c) <= 0xFFFF else "\\+%06x" % ord(c)
        else:
            out += c
    return out + "'"


def block(examples):
    rows = [
        "  (%s, %s::uuid, %s::cost_item_type_enum, %s, %s::equipment_pricing_method_enum, %s, %s::uuid)"
        % (
            literal(e["case"]),
            literal(e["companyId"]),
            literal(e["category"]),
            literal(e["itemName"]),
            literal(e["equipmentMethod"]),
            literal(e.get("entryLabel")),
            literal(e["id"]),
        )
        for e in examples
    ]
    return BEGIN + ",\n".join(rows) + "\n" + END


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("--write", "--check"):
        sys.exit(__doc__)
    mode, json_path = sys.argv[1], sys.argv[2]
    examples = json.load(open(json_path, encoding="utf-8"))
    text = SQL.read_text(encoding="utf-8")
    start = text.index(BEGIN)
    end = text.index(END) + len(END)
    wanted = block(examples)
    if mode == "--check":
        if text[start:end] != wanted:
            sys.exit("your_rate_id_test.sql differs from " + json_path + ". Run --write.")
        print("your_rate_id_test.sql matches %d examples" % len(examples))
        return
    SQL.write_text(text[:start] + wanted + text[end:], encoding="utf-8")
    print("wrote %d examples" % len(examples))


main()
