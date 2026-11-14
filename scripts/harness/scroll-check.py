#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from pathlib import Path

HARNESS = Path(__file__).resolve().parent / "harness.sh"
PROFILE = sys.argv[1] if len(sys.argv) > 1 else "default"
ROW_HEIGHT = 73
failures = []


def cli(*arguments):
    result = subprocess.run([str(HARNESS), "cli", "-p", PROFILE, *arguments], capture_output=True, text=True)
    return result.stdout + result.stderr


def state():
    return json.loads(cli("page", "--all", "--json"))


def check(condition, message):
    print(("ok    " if condition else "FAIL  ") + message)
    if not condition:
        failures.append(message)


def status():
    lines = cli("source").strip().splitlines()
    html = Path(lines[-1]).read_text() if lines else ""
    return re.search(r'<p id="status">Pressed (.+?), probe (?:Release (\d+) top (-?\d+)|none)', html)


def row_center(model, number):
    for element in model["elements"]:
        if element["visible"] and re.match(rf"Release {number}(\D|$)", element["label"]):
            return element["center"]["y"]
    return None


def button(model, label):
    return next((element for element in model["elements"] if element["role"] == "button" and element["label"] == label), None)


def check_positions(context):
    model = state()
    height = model["page"]["viewport"]["height"]
    check(model["page"]["placed"], f"{context}: positions are known")
    probe = status()
    check(probe is not None and probe.group(2) is not None, f"{context}: the page reports the row under its probe ({probe.group(0) if probe else 'missing'})")
    if probe is None or probe.group(2) is None:
        return model
    number, top = int(probe.group(2)), int(probe.group(3))
    center = row_center(model, number)
    check(center is not None and top <= center <= top + ROW_HEIGHT, f"{context}: Release {number} is placed at y {center}, on screen it spans {top}…{top + ROW_HEIGHT}")
    bar = next((element for element in model["elements"] if element["visible"] and "probe" in element["label"]), None)
    check(bar is not None and bar["center"]["y"] > height - 60, f"{context}: the fixed status bar is listed at the bottom (y {bar and bar['center']['y']} of {height})")
    texts = [(element["label"], element["center"]["y"]) for element in model["elements"] if element["visible"] and element["role"] == "text"]
    check(len(texts) == len(set(texts)), f"{context}: every visible text is listed once ({len(texts) - len(set(texts))} repeated)")
    if number > 5:
        sticky = [element["center"]["y"] for element in model["elements"] if element["visible"] and element["label"] == "Sticky release header"]
        check(bool(sticky) and min(sticky) < 40, f"{context}: the sticky header is at the top (y {sticky})")
    visible = [element for element in model["elements"] if element["visible"]]
    check(all(element["frame"]["y"] < height and element["frame"]["y"] + element["frame"]["height"] > 0 for element in visible), f"{context}: every visible element is at least partly inside the viewport")
    return model


def pressed(label, context):
    probe = status()
    check(probe is not None and probe.group(1) == label, f"{context}: the page reports “Pressed {label}” ({probe.group(0) if probe else 'no status'})")


def ids(model):
    return {(element["id"], element["role"], element["label"]) for element in model["elements"] if element["visible"]}


BASE = subprocess.run([str(HARNESS), "url"], capture_output=True, text=True).stdout.strip()


def page_text(pattern):
    lines = cli("source").strip().splitlines()
    match = re.search(pattern, Path(lines[-1]).read_text()) if lines else None
    return match.group(1) if match else None


if f"{PROFILE}  (open" not in subprocess.run([str(HARNESS), "cli", "status"], capture_output=True, text=True).stdout:
    cli("open", BASE + "heavy.html")
cli("go", BASE + "heavy.html")
first = check_positions("top")
reply = cli("tap", button(first, "Do nothing")["id"]).strip()
check("no visible change" in reply, f"tap Do nothing: reports no visible change ({reply.splitlines()[-1] if reply else 'no reply'})")
for amount, context in [(1500, "down 1500"), (7000, "down 7000 more"), (40000, "down 40000 more"), (400000, "to the bottom"), (-3000, "up 3000"), (-400000, "back to the top"), (2500, "down 2500")]:
    cli("scroll", "400", "400", "0", str(amount), "--quiet")
    model = check_positions(context)
    if context == "back to the top":
        check(ids(model) == ids(first), f"{context}: every element keeps its id ({len(ids(model) ^ ids(first))} differ)")

visible = [element for element in model["elements"] if element["visible"] and element["role"] == "button" and element["label"].startswith("Edit ")]
target = visible[len(visible) // 2]
cli("tap", target["id"])
pressed(target["label"], f"tap {target['id']} {target['label']} on screen")

for label in ["Edit 1", "Edit 900"]:
    element = button(state(), label)
    check(element is not None and not element["visible"], f"{label} starts off screen")
    if element:
        cli("tap", element["id"])
        pressed(label, f"tap {element['id']} {label} off screen")
        check_positions(f"after pressing {label}")

reply = cli("show", "Release 1234")
check(reply.startswith("found"), f"show Release 1234: {reply.splitlines()[0] if reply else 'no reply'}")
model = check_positions("after show")
check(row_center(model, 1234) is not None, "Release 1234 is visible after show")
mentioned = button(model, "Edit 900")
check(mentioned is not None and not mentioned["visible"], f"Edit 900 is off screen, not placed on the status text that mentions it ({mentioned and mentioned['center']})")
check(any(element["visible"] and element["label"].startswith("Pressed Edit 900, probe") for element in model["elements"]), "the status text that mentions Edit 900 is listed whole")

cli("scroll", "400", "400", "0", "-400000", "--quiet")
point = button(state(), "Edit 3")
cli("click", str(point["center"]["x"]), str(point["center"]["y"]))
pressed("Edit 3", "click x y at the position page --all reports for Edit 3")

cli("go", BASE + "index.html")
before = button(state(), "Load report")
cli("scroll", "400", "400", "0", "500", "--quiet")
after = button(state(), "Load report")
check(before and after and before["center"] == after["center"], f"short page: scrolling does not move Load report ({before and before['center']} → {after and after['center']})")

cli("go", BASE + "inner.html")
cli("scroll", "300", "400", "0", "900", "--quiet")
model = state()
items = [element for element in model["elements"] if element["visible"] and element["role"] == "button" and element["label"].startswith("Item ")]
check(bool(items) and items[0]["label"] != "Item 1", f"inner area: scrolled items are placed ({[item['label'] for item in items[:3]]})")
if items:
    item = items[len(items) // 2]
    cli("tap", item["id"])
    picked = page_text(r'<p id="status">Picked number (\d+)')
    check(picked == item["label"].split()[1], f"inner area: tap {item['id']} {item['label']} picks it (page: {picked})")
reply = cli("show", "Item 58")
check(reply.startswith("found"), f"inner area: show Item 58: {reply.splitlines()[0] if reply else 'no reply'}")
far = button(state(), "Item 58")
check(far is not None and far["visible"], f"inner area: Item 58 is visible after show ({far and far['center']})")
if far and far["visible"]:
    cli("tap", far["id"])
    check(page_text(r'<p id="status">Picked number (\d+)') == "58", "inner area: pressing Item 58 picks it")

cli("go", BASE + "long.html")
cli("scroll", "400", "400", "0", "30000", "--quiet")
model = state()
footer = next((element for element in model["elements"] if element["visible"] and element["label"] == "Footer status pinned"), None)
check(footer is not None and footer["center"]["y"] > model["page"]["viewport"]["height"] - 60, f"long page: the fixed footer is listed at the bottom ({footer and footer['center']})")
lines = [element["label"] for element in model["elements"] if element["visible"] and element["label"].startswith("Line ")]
check(bool(lines), f"long page: the scrolled lines are listed ({lines[:2]})")

print(f"\n{PROFILE}: {len(failures)} failure(s)")
sys.exit(1 if failures else 0)
